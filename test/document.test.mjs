import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {Room,validateSnapshot} from '../core.mjs';
const id=()=>randomBytes(16).toString('hex');
const room=()=>new Room({format:1,width:4,height:4,name:'Coop',layers:[{name:'A'},{name:'B'}],frames:[100,200,300],cels:[],palette:[]});
const clone=structuredClone;
const paint=(r,who,seq,l,f,runs)=>r.paint(who,seq,[{layer:l,frame:f,runs}],r.structure);
const edit=(r,who,change)=>{const b=r.snapshot(),a=clone(b);change(a);return r.document(who,b,a,id());};
const reorder=(s,layers,frames)=>{
  const old=clone(s);s.layers=layers.map(i=>old.layers[i]);s.frameIds=frames.map(i=>old.frameIds[i]);s.frames=frames.map(i=>old.frames[i]);
  s.cels=old.cels.map(c=>({...c,layer:layers.indexOf(c.layer-1)+1,frame:frames.indexOf(c.frame-1)+1}));
};

test('Document reordering rebases simultaneous pixels and preserves personal pixel undo',()=>{
  const r=room(),before=r.snapshot(),after=clone(before);
  reorder(after,[1,0],[2,0,1]);
  paint(r,'B',1,1,1,[0,1,42]);
  r.document('A',before,after,id());
  assert.equal(r.cells.get('2:2').pixels[0],42);
  r.undoRedo('B');assert.equal(r.cells.get('2:2').pixels[0],0);
  r.undoRedo('A');assert.deepEqual(r.meta.frameIds,before.frameIds);
  r.undoRedo('B',true);assert.equal(r.cells.get('1:1').pixels[0],42);
  r.undoRedo('A',true);assert.equal(r.cells.get('2:2').pixels[0],42);
});
test('Nested groups and middle frame insertion undo without changing unrelated work',()=>{
  const r=room();
  edit(r,'A',s=>{
    s.layers.unshift({id:id(),name:'Figur',group:true,parent:0,opacity:255,blend:3,visible:true,editable:true});
    s.layers[1].parent=1;for(const c of s.cels)c.layer++;
    s.frames.splice(1,0,150);s.frameIds.splice(1,0,id());
    for(const c of s.cels)if(c.frame>=2)c.frame++;
    for(const l of [2,3])s.cels.push({layer:l,frame:2,runs:[],opacity:255,z:0});
  });
  paint(r,'B',1,3,4,[0,1,22]);r.undoRedo('A');
  assert.equal(r.meta.layers.length,2);assert.equal(r.meta.frames.length,3);assert.equal(r.cells.get('2:3').pixels[0],22);
  r.undoRedo('A',true);assert.equal(r.cells.get('3:4').pixels[0],22);
});
test('Deleting and restoring own structure keeps old personal pixel history',()=>{
  const r=room();paint(r,'A',1,1,2,[0,1,11]);
  edit(r,'A',s=>{s.layers.splice(0,1);s.cels=s.cels.filter(c=>c.layer!==1).map(c=>({...c,layer:1}));});
  paint(r,'B',1,1,1,[3,1,44]);r.undoRedo('A');
  assert.equal(r.cells.get('1:2').pixels[0],11);assert.equal(r.cells.get('2:1').pixels[3],44);
  r.undoRedo('A');assert.equal(r.cells.get('1:2').pixels[0],0);assert.equal(r.cells.get('2:1').pixels[3],44);
});
test('Structural undo never deletes another participant’s content in an added frame',()=>{
  const r=room();edit(r,'A',s=>{s.frames.push(100);s.frameIds.push(id());for(const l of [1,2])s.cels.push({layer:l,frame:4,runs:[],opacity:255,z:0});});
  paint(r,'B',1,1,4,[0,1,55]);const before=r.snapshot(),hist=r.history('A');
  assert.throws(()=>r.undoRedo('A'),/neuere/);
  assert.deepEqual(r.snapshot(),before);assert.deepEqual(r.history('A'),hist);
});
test('Field-wise property undo preserves unrelated metadata and prevents foreign ABA',()=>{
  const r=room();edit(r,'A',s=>s.layers[0].name='Hair');
  edit(r,'B',s=>s.layers[0].opacity=100);r.undoRedo('A');
  assert.equal(r.meta.layers[0].name,'A');assert.equal(r.meta.layers[0].opacity,100);
  r.undoRedo('A',true);edit(r,'B',s=>s.layers[0].name='Hat');edit(r,'B',s=>s.layers[0].name='Hair');
  assert.throws(()=>r.undoRedo('A'),/neuere/);assert.equal(r.meta.layers[0].name,'Hair');
});
test('Linked cels share strokes and personal undo, retain links after roundtrip',()=>{
  const r=room();edit(r,'A',s=>{for(const c of s.cels)if(c.layer===1)c.link=s.frameIds[0];});
  paint(r,'A',1,1,2,[0,2,10]);paint(r,'B',1,1,3,[0,1,20]);r.undoRedo('A');
  for(const f of [1,2,3])assert.deepEqual([...r.cells.get(`1:${f}`).pixels].slice(0,2),[20,0]);
  r.undoRedo('B');r.undoRedo('A',true);
  for(const f of [1,2,3])assert.deepEqual([...r.cells.get(`1:${f}`).pixels].slice(0,2),[10,10]);
  assert.deepEqual(new Room(r.snapshot()).snapshot(),r.snapshot());
});
test('Unlink can be undone and conflicting linked data is rejected before mutation',()=>{
  const r=room();edit(r,'A',s=>{for(const c of s.cels)if(c.layer===1)c.link=s.frameIds[0];});
  edit(r,'A',s=>{for(const c of s.cels)delete c.link;});r.undoRedo('A');
  assert(r.cells.get('1:1').link);
  const s=r.snapshot();s.cels[0].runs=[0,1,42];assert.throws(()=>validateSnapshot(s),/dieselben Pixel/);
  const opacity=r.snapshot();opacity.cels[0].opacity=80;assert.throws(()=>validateSnapshot(opacity),/dieselbe Deckkraft/);
  assert.throws(()=>paint(r,'B',1,1,1,[0,1,-1]));
});
test('Tags synchronize names, ranges, direction, repeats and independent undo',()=>{
  const r=room();edit(r,'A',s=>s.tags.push({id:id(),name:'Idle',from:1,to:2,direction:2,repeats:3,color:0xff123456}));
  edit(r,'B',s=>s.layers[0].visible=false);r.undoRedo('A');assert.equal(r.meta.tags.length,0);assert.equal(r.meta.layers[0].visible,false);
  r.undoRedo('A',true);assert.equal(r.meta.tags[0].name,'Idle');assert.equal(r.meta.tags[0].repeats,3);
  const s=r.snapshot();s.tags[0].to=99;assert.throws(()=>validateSnapshot(s));
});
test('Resize/crop is atomic, keeps notes and restores prior pixel undo',()=>{
  const r=room();paint(r,'A',1,1,1,[0,1,44]);const original=r.snapshot();
  edit(r,'A',s=>{s.width=8;s.height=8;});
  assert.equal(r.meta.width,8);r.undoRedo('A');assert.equal(r.meta.width,4);r.undoRedo('A');assert.equal(r.cells.get('1:1').pixels[0],0);
  const after=clone(original);after.width=8;after.height=8;paint(r,'B',1,2,3,[0,1,7]);
  assert.throws(()=>r.document('A',original,after,id()),/überschneidet/);assert.equal(r.meta.width,4);
});
test('Merge keeps a reversible fragment, refuses to undo over newer merged pixels',()=>{
  const r=room();paint(r,'A',1,1,1,[0,1,11]);paint(r,'B',1,2,1,[1,1,22]);
  edit(r,'A',s=>{s.layers.pop();s.cels=s.cels.filter(c=>c.layer===1);s.cels[0].runs=[0,1,11,1,1,22];});
  r.undoRedo('A');assert.equal(r.cells.get('2:1').pixels[1],22);r.undoRedo('A',true);
  paint(r,'B',2,1,1,[2,1,33]);assert.throws(()=>r.undoRedo('A'),/neuere/);assert.equal(r.cells.get('1:1').pixels[2],33);
});
test('History compaction bounds structural snapshots without losing current pixels',()=>{
  const r=room();r.historyLimit=3;
  for(let i=0;i<30;i++)edit(r,'A',s=>s.layers[0].name='Version '+i);
  assert.equal(r.operations.length,3);assert.equal(r.history('A').undo,3);
  r.undoRedo('A');r.undoRedo('A');r.undoRedo('A');assert.equal(r.meta.layers[0].name,'Version 26');
});
test('Document transactions never roll back concurrent shared notes',()=>{
  const r=room(),before=r.snapshot(),after=clone(before);after.layers[0].name='Changed';
  const card={id:id(),parent:'',title:'Keep',text:'idea',x:0,y:0,color:'',status:'idea',versions:Object.fromEntries(['title','text','parent','x','y','color','status'].map(f=>[f,0]))};
  assert(r.notes.execute('B',{seq:1,action:'patch',patches:[{id:card.id,expected:false,value:card}]}).ok);
  const notes=clone(r.notes.snapshot());r.document('A',before,after,id());
  assert.deepEqual(r.notes.snapshot(),notes);r.undoRedo('A');assert.deepEqual(r.notes.snapshot(),notes);
});
