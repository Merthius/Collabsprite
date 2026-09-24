import test from 'node:test';
import assert from 'node:assert/strict';
import { Room, encodeRuns } from '../core.mjs';
export const snapshot = () => ({ format: 1, name: 'Test', width: 4, height: 4,
  layers: [{ name: 'Gemeinsam' }], frames: [100], cels: [], palette: [] });
const paint = (room, author, seq, runs, layer = 1, frame = 1) => room.paint(author, seq, [{ layer, frame, runs }],room.structure);
const pixels = room => [...room.cells.get('1:1').pixels];
test('Own undo/redo preserves newer overlapping peer pixels', () => {
  const r = new Room(snapshot());
  paint(r, 'A', 1, [0, 2, 10]);
  paint(r, 'B', 1, [0, 1, 20, 2, 1, 20]);
  r.undoRedo('A');
  assert.deepEqual(pixels(r).slice(0, 3), [20, 0, 20]);
  r.undoRedo('A', true);
  assert.deepEqual(pixels(r).slice(0, 3), [20, 10, 20]);
  r.undoRedo('B');
  assert.deepEqual(pixels(r).slice(0, 3), [10, 10, 0]);
  r.undoRedo('A');
  assert.deepEqual(pixels(r).slice(0, 3), [0, 0, 0]);
  r.undoRedo('B', true);
  assert.deepEqual(pixels(r).slice(0, 3), [20, 0, 20]);
});
test('Transparent paint, equal-valued contributions, new edit clears only own redo', () => {
  const r = new Room(snapshot());
  paint(r, 'A', 1, [0, 1, 0xffaabbcc]); paint(r, 'B', 1, [0, 1, 0xffaabbcc]);
  r.undoRedo('A');assert.equal(pixels(r)[0], 0xffaabbcc);
  paint(r, 'B', 2, [0, 1, 0]);assert.equal(pixels(r)[0], 0);
  r.undoRedo('B');assert.equal(pixels(r)[0], 0xffaabbcc);
  paint(r, 'A', 2, [1, 1, 10]);assert.deepEqual(r.history('A'), {undo:1,redo:0});
  assert.equal(r.history('B').redo, 1);
});
test('Whole operation validation is atomic and sequence strict', () => {
  const r = new Room(snapshot());
  assert.throws(() => r.paint('A', 1, [{layer:1,frame:1,runs:[0,1,5]}, {layer:99,frame:1,runs:[0,1,10]}],r.structure));
  assert.equal(pixels(r)[0],0);assert.equal(r.user('A').seq,0);
  assert.throws(() => paint(r,'A',2,[0,1,1]));
  assert.throws(() => paint(r,'A',1,[0,3,1,1,1,2]));
  assert.throws(() => paint(r,'A',1,[0,1,-1]));
});
test('History compaction preserves visible state and immutable base', () => {
  const r=new Room(snapshot(),{historyLimit:2});
  paint(r,'A',1,[0,1,1]);paint(r,'B',1,[0,1,2]);r.undoRedo('A');
  paint(r,'B',2,[1,1,3]);assert.equal(r.history('A').redo,0);
  r.undoRedo('B');r.undoRedo('B');assert.equal(pixels(r)[0],0);
  r.undoRedo('B',true);assert.equal(pixels(r)[0],2);
});
test('Append shared layer/frame keeps existing history and blank cells', () => {
  const r=new Room(snapshot());paint(r,'A',1,[0,1,1]);
  assert.equal(r.append('layer','Zwei').index,2);
  assert.equal(r.append('frame').index,2);
  paint(r,'B',1,[0,1,99],2,2);r.undoRedo('A');
  assert.equal(r.cells.get('2:2').pixels[0],99);
  const restored=new Room(r.snapshot());
  assert.deepEqual(restored.snapshot(),r.snapshot());
});
test('Guests can copy layers and frames without taking over another author’s undo', () => {
  const r=new Room(snapshot());
  paint(r,'A',1,[0,1,0xff112233]);
  const layerEvent=r.append('layer','Kopie',1);
  assert.deepEqual(layerEvent.cels[0].runs,[0,1,0xff112233]);
  const frameEvent=r.append('frame',null,1);
  assert.equal(frameEvent.cels.length,2);
  assert.equal(r.cells.get('2:2').pixels[0],0xff112233);
  paint(r,'B',1,[1,1,0xff556677],2,2);
  r.undoRedo('A');
  assert.equal(r.cells.get('1:1').pixels[0],0);
  assert.equal(r.cells.get('2:2').pixels[0],0xff112233);
  assert.equal(r.cells.get('2:2').pixels[1],0xff556677);
});
test('Compact run encoding is lossless', () => {
  assert.deepEqual(encodeRuns([0,0,5,5,0,9],true),[2,2,5,5,1,9]);
});
test('Deleting a frame reindexes pixels and surviving author history', () => {
  const r = new Room(snapshot());
  r.append('frame');r.append('frame');
  paint(r,'A',1,[0,1,11],1,1);
  paint(r,'A',2,[1,1,22],1,2);
  paint(r,'B',1,[2,1,33],1,3);
  assert.equal(r.delete('frame',2).structure,3);
  assert.equal(r.meta.frames.length,2);
  assert.equal(r.cells.get('1:2').pixels[2],33);
  assert.deepEqual(r.history('A'),{undo:1,redo:0});
  r.undoRedo('A');
  assert.equal(r.cells.get('1:1').pixels[0],0);
  r.undoRedo('B');
  assert.equal(r.cells.get('1:2').pixels[2],0);
  assert.throws(()=>r.delete('frame',2) && r.delete('frame',1),/letzte Frame/);
});
test('Stale paint cannot land on a shifted cel after deletion', () => {
  const r=new Room(snapshot());
  r.append('frame');
  const oldStructure=r.structure;
  r.delete('frame',1);
  assert.throws(()=>r.paint('A',1,[{layer:1,frame:1,runs:[0,1,0xff123456]}],oldStructure),/struktur/i);
  assert.equal(r.cells.get('1:1').pixels[0],0);
  assert.equal(r.user('A').seq,0);
});
test('Deleting a layer prunes its undo and shifts surviving cels', () => {
  const r = new Room(snapshot());
  r.append('layer','Mitte');r.append('layer','Oben');
  paint(r,'A',1,[0,1,10],2);
  paint(r,'B',1,[1,1,20],3);
  assert.equal(r.delete('layer',2).count,1);
  assert.equal(r.meta.layers[1].name,'Oben');
  assert.equal(r.cells.get('2:1').pixels[1],20);
  assert.deepEqual(r.history('A'),{undo:0,redo:0});
  r.undoRedo('B');
  assert.equal(r.cells.get('2:1').pixels[1],0);
  assert.throws(()=>r.delete('layer',2) && r.delete('layer',1),/letzte Rasterebene/);
});
test('Deleting a group removes descendants and remaps surviving parent links', () => {
  const state=snapshot();
  state.layers=[
    {name:'Basis'},
    {name:'Gruppe',group:true},
    {name:'Kind',parent:2},
    {name:'Enkelgruppe',group:true,parent:2},
    {name:'Enkel',parent:4},
    {name:'Oberste'}
  ];
  const r=new Room(state);
  paint(r,'A',1,[0,1,11],3);
  paint(r,'B',1,[1,1,22],6);
  const event=r.delete('layer',2);
  assert.equal(event.count,4);
  assert.deepEqual(r.meta.layers.map(l=>l.name),['Basis','Oberste']);
  assert.equal(r.cells.get('2:1').pixels[1],22);
  assert.deepEqual(r.history('A'),{undo:0,redo:0});
  r.undoRedo('B');
  assert.equal(r.cells.get('2:1').pixels[1],0);
});
test('Multi-delete is atomic, descending and keeps surviving history', () => {
  const r=new Room(snapshot());
  r.append('frame');r.append('frame');r.append('frame');
  paint(r,'A',1,[0,1,11],1,2);
  paint(r,'B',1,[1,1,22],1,4);
  assert.throws(()=>r.deleteMany('frame',[1,2,3,4]),/letzte Frame/);
  assert.equal(r.meta.frames.length,4);
  assert.deepEqual(r.history('A'),{undo:1,redo:0});
  const events=r.deleteMany('frame',[3,1]);
  assert.deepEqual(events.map(event=>event.index),[3,1]);
  assert.equal(r.meta.frames.length,2);
  assert.equal(r.cells.get('1:1').pixels[0],11);
  assert.equal(r.cells.get('1:2').pixels[1],22);
  r.undoRedo('A');r.undoRedo('B');
  assert.equal(r.cells.get('1:1').pixels[0],0);
  assert.equal(r.cells.get('1:2').pixels[1],0);
});
test('Validated property edits preserve snapshot and reject malformed fields', () => {
  const r=new Room(snapshot());
  assert.equal(r.setProperty('layer',1,'name','  Figur  ').value,'Figur');
  r.setProperty('layer',1,'visible',false);
  r.setProperty('layer',1,'editable',false);
  r.setProperty('frame',1,'duration',250);
  assert.equal(r.snapshot().layers[0].name,'Figur');
  assert.equal(r.snapshot().layers[0].editable,false);
  assert.equal(r.snapshot().frames[0],250);
  assert.throws(()=>r.setProperty('layer',1,'opacity',999));
  assert.throws(()=>r.setProperty('layer',1,'name','   '));
});
