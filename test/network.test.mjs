import test from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';
import dgram from 'node:dgram';
import { startServer } from '../server.mjs';
import { allowedPeer, addresses, invite, replyAddress } from '../network.mjs';
import { mkdtemp, rm, writeFile, utimes, readdir, rename, readFile } from 'node:fs/promises';
import { tmpdir, networkInterfaces } from 'node:os';
import { join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { existsSync } from 'node:fs';
import { once } from 'node:events';
const execFileAsync=promisify(execFile);
const snapshot=()=>({format:1,name:'Netzwerktest',width:16,height:16,layers:[{name:'Gemeinsam'}],frames:[100],cels:[],palette:[]});
async function connect(port,hello,address='127.0.0.1') {
  const ws=new WebSocket(`ws://${address}:${port}`);
  const queue=[],pending=[];
  ws.on('message',data=>{
    const message=JSON.parse(data);
    const index=pending.findIndex(p=>p.type===message.type);
    if(index>=0){const p=pending.splice(index,1)[0];clearTimeout(p.timeout);p.resolve(message);}
    else queue.push(message);
  });
  const next=type=>{
    const index=queue.findIndex(m=>m.type===type);
    if(index>=0)return Promise.resolve(queue.splice(index,1)[0]);
    return new Promise((resolve,reject)=>{const p={type,resolve};p.timeout=setTimeout(()=>reject(Error('Timeout '+type)),4000);pending.push(p);});
  };
  await new Promise((resolve,reject)=>{ws.once('open',resolve);ws.once('error',reject);});
  const send=message=>ws.send(JSON.stringify(message));send({type:'hello',protocol:14,...hello});
  return {ws,send,next};
}
async function waitFor(check,description) {
  const deadline=Date.now()+2000;
  while (!check()) {
    if (Date.now()>deadline) throw new Error(`Timeout ${description}`);
    await new Promise(resolve=>setTimeout(resolve,5));
  }
}
async function discover(port) {
  const socket=dgram.createSocket('udp4');
  try {
    await new Promise(resolve=>socket.bind(0,'127.0.0.1',resolve));
    const reply=new Promise((resolve,reject)=>{
      const timeout=setTimeout(()=>reject(Error('Timeout UDP discovery')),2000);
      socket.once('message',data=>{clearTimeout(timeout);resolve(JSON.parse(data.toString()));});
    });
    socket.send(Buffer.from('COLLABSPRITE_DISCOVER_V7'),port,'127.0.0.1');
    return await reply;
  } finally {socket.close();}
}

test('Document history cannot be bypassed by legacy property or structure messages',async t=>{
  const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{}});t.after(()=>service.close());
  const host=await connect(service.port,{mode:'host',snapshot:snapshot()});const hw=await host.next('welcome');
  const [,room,token]=hw.invite.split('/');const guest=await connect(service.port,{mode:'join',room,token});await guest.next('welcome');
  const before=structuredClone(hw.snapshot),after=structuredClone(before);after.layers[0].name='Protected';
  host.send({type:'document',requestId:'a'.repeat(32),before,after});await host.next('document');await guest.next('document');
  for(const message of [{type:'property',kind:'layer',index:1,field:'name',value:'Bypass'},
    {type:'append',kind:'frame'},{type:'delete',kind:'frame',index:1},{type:'restore',recovery:'a'.repeat(32)},
    {type:'celProperty',layer:1,frame:1,field:'opacity',value:80},{type:'palette',colors:[42]}]) {
    guest.send({...message,structure:1});assert.match((await guest.next('rejected')).message,/normalen Aseprite/);
  }
  assert.equal(service.rooms.get(room).core.meta.layers[0].name,'Protected');
  guest.send({type:'ping',nonce:123});assert.equal((await guest.next('pong')).nonce,123);
  host.send({type:'undo'});assert.equal((await guest.next('document')).snapshot.layers[0].name,before.layers[0].name);
});

test('Shared notes: three peers, leases, late join, lost ack resume, host save and durable guest departure',async t=>{
  const dataDir=await mkdtemp(join(tmpdir(),'collabsprite-notes-'));
  const service=await startServer({port:0,host:'127.0.0.1',dataDir,log:()=>{}});
  t.after(async()=>{await service.close();await rm(dataDir,{recursive:true,force:true});});
  const host=await connect(service.port,{mode:'host',name:'Host',snapshot:snapshot()});const hw=await host.next('welcome');await host.next('notes');
  const [,room,token]=hw.invite.split('/');
  const a=await connect(service.port,{mode:'join',room,token,name:'Gast A'});const aw=await a.next('welcome');await a.next('notes');
  const id='c'.repeat(32),fields=['title','text','parent','x','y','color','status'];
  const card={id,title:'Hexe',text:'',parent:'',x:10,y:20,color:'',status:'idea',versions:Object.fromEntries(fields.map(f=>[f,0]))};
  a.send({type:'note',seq:1,action:'patch',patches:[{id,expected:false,value:card}]});assert.equal((await a.next('noteAck')).ok,true);
  const state=await host.next('notes');assert.equal(state.board.cards[0].title,'Hexe');
  assert.deepEqual(state.board.authors[id],{created:'Gast A',edited:'Gast A'});await a.next('notes');
  const b=await connect(service.port,{mode:'join',room,token,name:'Gast B'});await b.next('welcome');assert.equal((await b.next('notes')).board.cards[0].title,'Hexe');
  a.send({type:'noteLock',id,field:'text'});assert.equal((await b.next('noteLocks')).locks[0].author,aw.author);
  b.send({type:'note',seq:1,action:'patch',patches:[{id,field:'text',expected:1,value:'blocked'}]});assert.equal((await b.next('noteAck')).ok,false);await b.next('notes');
  a.send({type:'note',seq:2,action:'patch',patches:[{id,field:'text',expected:1,value:'Besen leuchtet'}]});
  const edited=await host.next('notes');assert.deepEqual(edited.board.authors[id],{created:'Gast A',edited:'Gast A'}); // Do not consume A's acknowledgement: simulate its loss.
  a.ws.terminate();await once(a.ws,'close');
  const resumed=await connect(service.port,{mode:'resume',room,author:aw.author,resumeToken:aw.resumeToken});const rw=await resumed.next('welcome');
  assert.equal(rw.snapshot.notes.cards[0].text,'Besen leuchtet');const ns=await resumed.next('notes');assert.equal(ns.history.undo,2);
  resumed.send({type:'note',seq:2,action:'patch',patches:[{id,field:'text',expected:1,value:'Besen leuchtet'}]});
  assert.equal((await resumed.next('noteAck')).ok,true);assert.equal((await resumed.next('notes')).board.revision,2);
  host.send({type:'noteSaved',revision:2});assert.equal((await resumed.next('noteSaved')).revision,2);
  resumed.send({type:'leave'});await once(resumed.ws,'close');await service.flush();
  const saved=JSON.parse(await readFile(join(dataDir,room+'.json'),'utf8'));assert.equal(saved.snapshot.notes.cards[0].text,'Besen leuchtet');
  assert.deepEqual(saved.snapshot.notes.authors[id],{created:'Gast A',edited:'Gast A'});
  host.send({type:'undo'});await host.next('history');assert.equal(service.rooms.get(room).core.notes.data.cards[0].text,'Besen leuchtet');
  b.send({type:'noteSaved',revision:2});await b.next('error');
});
test('Magnetic reference image reaches peers, persists, survives late join and personal undo',async t=>{
  const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{}});t.after(()=>service.close());
  const host=await connect(service.port,{mode:'host',snapshot:snapshot()});const hw=await host.next('welcome');await host.next('notes');
  const [,room,token]=hw.invite.split('/');const guest=await connect(service.port,{mode:'join',room,token});await guest.next('welcome');await guest.next('notes');
  const id='d'.repeat(32),fields=['title','text','parent','x','y','color','status','kind','listStyle','checks','image'];
  const ref={id,title:'',text:'',parent:'',x:20,y:30,color:'#D6E4F4',status:'idea',kind:'image',listStyle:'check',checks:'',image:{width:512,height:512,pixels:'1a2b3cff'.repeat(512*512)},versions:Object.fromEntries(fields.map(f=>[f,0]))};
  guest.send({type:'note',seq:1,action:'patch',patches:[{id,expected:false,value:ref}]});assert.equal((await guest.next('noteAck')).ok,true);
  assert.deepEqual((await host.next('notes')).board.cards[0].image,ref.image);await guest.next('notes');
  const late=await connect(service.port,{mode:'join',room,token});await late.next('welcome');assert.deepEqual((await late.next('notes')).board.cards[0].image,ref.image);
  guest.send({type:'note',seq:2,action:'undo'});assert.equal((await guest.next('noteAck')).ok,true);assert.equal((await host.next('notes')).board.cards.length,0);await guest.next('notes');
  guest.send({type:'note',seq:3,action:'redo'});assert.equal((await guest.next('noteAck')).ok,true);assert.deepEqual((await host.next('notes')).board.cards[0].image,ref.image);
  guest.send({type:'leave'});await once(guest.ws,'close');assert.deepEqual(service.rooms.get(room).core.snapshot().notes.cards[0].image,ref.image);
});

test('Full-resolution sketch reaches host, guest and a later joiner',async t=>{
  const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{}});t.after(()=>service.close());
  const host=await connect(service.port,{mode:'host',snapshot:snapshot()});const hw=await host.next('welcome');await host.next('notes');
  const [,room,token]=hw.invite.split('/');const guest=await connect(service.port,{mode:'join',room,token});await guest.next('welcome');await guest.next('notes');
  const image={width:1000,height:1000,encoding:'b64',pixels:Buffer.alloc(1000*1000*4).toString('base64')};
  const fields=['title','text','parent','x','y','color','status','kind','listStyle','checks','image'];
  const paper={id:'f'.repeat(32),title:'',text:'',parent:'',x:20,y:30,color:'',status:'idea',kind:'paper',listStyle:'check',checks:'',image,
    versions:Object.fromEntries(fields.map(f=>[f,0]))};
  guest.send({type:'note',seq:1,action:'patch',patches:[{id:paper.id,expected:false,value:paper}]});
  assert.equal((await guest.next('noteAck')).ok,true);
  assert.deepEqual((await host.next('notes')).board.cards[0].image,image);await guest.next('notes');
  const late=await connect(service.port,{mode:'join',room,token});await late.next('welcome');
  assert.deepEqual((await late.next('notes')).board.cards[0].image,image);
  guest.send({type:'leave'});await once(guest.ws,'close');
  assert.deepEqual(service.rooms.get(room).core.notes.data.cards[0].image,image);
});

test('Three-sided idea links converge for host and guest',async t=>{
  const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{}});t.after(()=>service.close());
  const host=await connect(service.port,{mode:'host',snapshot:snapshot()});const hw=await host.next('welcome');await host.next('notes');
  const [,room,token]=hw.invite.split('/');const guest=await connect(service.port,{mode:'join',room,token});await guest.next('welcome');await guest.next('notes');
  const keys=['title','text','parent','dock','x','y','color','status','kind','listStyle','checks','image'];
  const make=(letter,parent='',dock='below')=>({id:letter.repeat(32),title:letter,text:'',parent,dock,x:20,y:30,color:'',status:'idea',kind:'text',listStyle:'check',checks:'',image:false,versions:Object.fromEntries(keys.map(key=>[key,0]))});
  const root=make('a');host.send({type:'note',seq:1,action:'patch',patches:[{id:root.id,expected:false,value:root}]});assert.equal((await host.next('noteAck')).ok,true);await host.next('notes');await guest.next('notes');
  const left=make('b',root.id,'left');guest.send({type:'note',seq:1,action:'patch',patches:[{id:left.id,expected:false,value:left}]});assert.equal((await guest.next('noteAck')).ok,true);await guest.next('notes');await host.next('notes');
  const right=make('c',root.id,'right');host.send({type:'note',seq:2,action:'patch',patches:[{id:right.id,expected:false,value:right}]});assert.equal((await host.next('noteAck')).ok,true);await host.next('notes');
  const joined=await guest.next('notes');assert.deepEqual(joined.board.cards.map(c=>c.dock),['below','left','right']);
  const duplicate=make('d',root.id,'left');guest.send({type:'note',seq:2,action:'patch',patches:[{id:duplicate.id,expected:false,value:duplicate}]});assert.equal((await guest.next('noteAck')).ok,false);await guest.next('notes');
  assert.equal(service.rooms.get(room).core.notes.data.cards.length,3);
  const animation={...make('e'),kind:'animation',tag:'Hexe läuft',tagStart:1};
  host.send({type:'note',seq:3,action:'patch',patches:[{id:animation.id,expected:false,value:animation}]});
  assert.equal((await host.next('noteAck')).ok,true);const hostBoard=(await host.next('notes')).board;
  assert.equal((await guest.next('notes')).board.cards[3].tag,'Hexe läuft');
  host.send({type:'note',seq:4,action:'patch',patches:[{id:animation.id,field:'frame',expected:hostBoard.cards[3].versions.frame,value:2}]});
  assert.equal((await host.next('noteAck')).ok,true);await host.next('notes');
  assert.equal((await guest.next('notes')).board.cards[3].frame,2);
  const late=await connect(service.port,{mode:'join',room,token});await late.next('welcome');
  const lateBoard=(await late.next('notes')).board;
  assert.equal(lateBoard.cards[3].kind,'animation');assert.equal(lateBoard.cards[3].frame,2);
});

test('Authenticated reconnect retains identity, undo and pending sequence across a locked session',async t=>{
  const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{}});t.after(()=>service.close());
  const host=await connect(service.port,{mode:'host',snapshot:snapshot()});const hw=await host.next('welcome');
  const [,room,token]=hw.invite.split('/');const guest=await connect(service.port,{mode:'join',room,token});const gw=await guest.next('welcome');
  const patch={layer:1,frame:1,layerId:gw.snapshot.layers[0].id,frameId:gw.snapshot.frameIds[0],runs:[0,1,17]};
  guest.send({type:'paint',seq:1,structure:0,patches:[patch]});await host.next('patch');await guest.next('patch');
  guest.ws.terminate();await once(guest.ws,'close');await waitFor(()=>service.rooms.get(room).clients.size===1,'guest loss');
  host.send({type:'admission',open:false});await host.next('admission');
  host.send({type:'paint',seq:1,structure:0,patches:[{layer:1,frame:1,runs:[1,1,29]}]});await host.next('patch');
  const forged=await connect(service.port,{mode:'resume',room,author:gw.author,resumeToken:token});
  assert.match((await forged.next('error')).message,/Wiederverbindung/);
  const resume={mode:'resume',room,author:gw.author,resumeToken:gw.resumeToken};
  const back=await connect(service.port,resume);const bw=await back.next('welcome');
  assert.equal(bw.author,gw.author);assert.equal(bw.confirmedSeq,1);assert.equal(bw.resumed,true);assert.equal((await back.next('history')).undo,1);
  back.send({type:'paint',seq:1,structure:0,patches:[patch]});assert.equal((await back.next('ack')).seq,1);
  assert.equal(service.rooms.get(room).core.revision,2);
  back.send({type:'undo'});await back.next('patch');await host.next('patch');
  assert.deepEqual([...service.rooms.get(room).core.cells.get('1:1').pixels].slice(0,2),[0,29]);
  back.send({type:'leave'});await once(back.ws,'close');
  const denied=await connect(service.port,resume);assert.match((await denied.next('error')).message,/Wiederverbindung/);
});
test('Unexpected host transport loss is leased, resumes once, and expires safely',async t=>{
  const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{},resumeMs:250});t.after(()=>service.close());
  let shutdowns=0;service.server.on('collabsprite:last-host-left',()=>shutdowns++);
  const host=await connect(service.port,{mode:'host',snapshot:snapshot()});const welcome=await host.next('welcome');
  const resume={mode:'resume',room:welcome.room,author:welcome.author,resumeToken:welcome.resumeToken};
  // Replace an apparently active (half-open) socket using its private secret.
  const back=await connect(service.port,resume);const resumed=await back.next('welcome');
  assert.equal(resumed.host,true);assert.equal(resumed.author,welcome.author);
  await waitFor(()=>service.rooms.get(welcome.room).clients.size===1,'half-open replacement');
  back.ws.terminate();await once(back.ws,'close');assert.equal(shutdowns,0);
  await waitFor(()=>shutdowns===1,'lease expiry');
  const denied=await connect(service.port,resume);assert.match((await denied.next('error')).message,/abgelaufen/);
});
test('Recovery is broadcast to all peers, and two stale clicks cannot restore two deletions',async t=>{
  const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{}});t.after(()=>service.close());
  const s=snapshot();s.frames=[100,200,300];
  const host=await connect(service.port,{mode:'host',snapshot:s});const hw=await host.next('welcome');
  const [,room,token]=hw.invite.split('/');const guest=await connect(service.port,{mode:'join',room,token});await guest.next('welcome');
  host.send({type:'delete',kind:'frame',index:3,structure:0});await host.next('delete');await guest.next('delete');
  host.send({type:'delete',kind:'frame',index:2,structure:1});await host.next('delete');await guest.next('delete');
  const id=service.rooms.get(room).core.recoveries.at(-1).id;
  guest.send({type:'restore',recovery:id});const [a,b]=await Promise.all([host.next('restore'),guest.next('restore')]);
  assert.deepEqual(a,b);assert.deepEqual(a.snapshot.frames,[100,200]);
  host.send({type:'restore',recovery:id});assert.match((await host.next('rejected')).message,/geaendert/);
  assert.equal(service.rooms.get(room).core.recoveries.length,1);
});
test('Host admission gate hides discovery, denies new guests and keeps existing peers editing',async t=>{
  const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{}});
  t.after(()=>service.close());
  const host=await connect(service.port,{mode:'host',snapshot:snapshot()});
  const welcome=await host.next('welcome');const [,room,token]=welcome.invite.split('/');
  const guest=await connect(service.port,{mode:'join',room,token});await guest.next('welcome');
  host.send({type:'admission',open:false});
  assert.equal((await host.next('admission')).open,false);await guest.next('admission');
  assert.equal((await discover(service.discoveryPort)).rooms.length,0);
  const blocked=await connect(service.port,{mode:'join',room,token});
  assert.match((await blocked.next('error')).message,/Beitritte gesperrt/);
  guest.send({type:'paint',seq:1,structure:0,patches:[{layer:1,frame:1,runs:[0,1,27]}]});
  await Promise.all([host.next('patch'),guest.next('patch')]);
  guest.send({type:'admission',open:true});assert.match((await guest.next('error')).message,/Nur der Host/);
  assert.equal(service.rooms.get(room).acceptingGuests,false);
  host.send({type:'admission',open:true});await host.next('admission');
  const accepted=await connect(service.port,{mode:'join',room,token});
  assert.equal((await accepted.next('welcome')).host,false);
  assert.equal((await discover(service.discoveryPort)).rooms.length,1);
  assert.equal(service.rooms.get(room).core.cells.get('1:1').pixels[0],27);
});
test('Backup failure is visible, retry recovers, concurrent shutdown keeps the final revision',async t=>{
  const root=await mkdtemp(join(tmpdir(),'collabsprite-backup-safety-'));
  const dataDir=join(root,'data'), moved=join(root,'temporarily-unavailable');
  const service=await startServer({port:0,host:'127.0.0.1',dataDir,log:()=>{}});
  t.after(async()=>{await service.close();await rm(root,{recursive:true,force:true});});
  const host=await connect(service.port,{mode:'host',snapshot:snapshot()});
  const welcome=await host.next('welcome');
  await rename(dataDir,moved);await service.flush();
  assert.equal((await host.next('backup')).state,'error');
  assert.equal(service.rooms.get(welcome.room).dirty,true);
  await rename(moved,dataDir);await service.flush();
  assert.equal((await host.next('backup')).state,'saved');
  host.send({type:'paint',seq:1,structure:0,patches:[{layer:1,frame:1,runs:[0,1,9]}]});
  await host.next('patch');
  const room=service.rooms.get(welcome.room), inflight=service.flush();
  assert.equal(room.saving,true,'Expected an in-flight disk write');
  // Simulate another already accepted ordered edit before that write finishes.
  room.core.paint(welcome.author,2,[{layer:1,frame:1,runs:[1,1,10]}],0);room.dirty=true;
  const closing=service.close();assert.equal(service.close(),closing,'Shutdown is not idempotent');
  await Promise.all([inflight,closing]);
  const saved=JSON.parse(await readFile(join(dataDir,welcome.room+'.json'),'utf8'));
  assert.deepEqual(saved.snapshot.cels[0].runs,[0,1,9,1,1,10]);
});
test('Invalid messages cannot mutate after rejection and do not break other peers',async t=>{
  const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{}});
  t.after(()=>service.close());
  const host=await connect(service.port,{mode:'host',snapshot:snapshot()});
  const welcome=await host.next('welcome');const [,room,token]=welcome.invite.split('/');
  const bad=await connect(service.port,{mode:'join',room,token});await bad.next('welcome');
  bad.send(null);
  bad.send({type:'paint',seq:1,structure:0,patches:[{layer:1,frame:1,runs:[0,1,99]}]});
  assert.match((await bad.next('error')).message,/Ungueltige Nachricht/);
  host.send({type:'ping',nonce:1});await host.next('pong');
  assert.equal(service.rooms.get(room).core.revision,0);
  const flood=await connect(service.port,{mode:'join',room,token});await flood.next('welcome');
  for(let i=0;i<5000;i++) flood.send({type:'ping',nonce:i});
  assert.match((await flood.next('error')).message,/Zu viele Nachrichten/);
  const huge=await connect(service.port,{mode:'join',room,token});await huge.next('welcome');
  huge.send({type:'ping',nonce:'x'.repeat(9000)});
  assert.match((await huge.next('error')).message,/Steuernachricht zu gross/);
  host.send({type:'paint',seq:1,structure:0,patches:[{layer:1,frame:1,runs:[1,1,7]}]});
  assert.equal((await host.next('patch')).revision,1);
});
test('Browser-origin connections are rejected before WebSocket upgrade',async t=>{
  const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{}});
  t.after(()=>service.close());
  const ws=new WebSocket(`ws://127.0.0.1:${service.port}`,{origin:'https://untrusted.example'});
  await new Promise((resolve,reject)=>{
    ws.on('error',err=>{assert.match(err.message,/403/);resolve();});
    ws.on('open',()=>{ws.close();reject(Error('Browser was allowed'));});
  });
  assert.equal(service.rooms.size,0);
});
test('Last-cel and stale structural commands are rejected without disconnecting collaborators',async t=>{
  const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{}});
  t.after(()=>service.close());
  const host=await connect(service.port,{mode:'host',snapshot:snapshot()});
  const welcome=await host.next('welcome');const [,room,token]=welcome.invite.split('/');
  const guest=await connect(service.port,{mode:'join',room,token});await guest.next('welcome');
  guest.send({type:'delete',kind:'frame',index:1,structure:0});
  assert.match((await guest.next('rejected')).message,/letzte Frame/);
  guest.send({type:'delete',kind:'layer',index:1,structure:0});
  assert.match((await guest.next('rejected')).message,/letzte Rasterebene/);
  host.send({type:'append',kind:'frame',structure:0});
  await Promise.all([host.next('append'),guest.next('append')]);
  guest.send({type:'append',kind:'layer',structure:0});
  assert.match((await guest.next('rejected')).message,/erneut ausführen/);
  assert.equal(service.rooms.get(room).core.structure,1);
  guest.send({type:'append',kind:'layer',structure:1});
  assert.equal((await host.next('append')).structure,2);await guest.next('append');
  guest.send({type:'paint',seq:1,structure:2,patches:[{layer:2,frame:2,runs:[0,1,42]}]});
  assert.equal((await host.next('patch')).revision,3);
  assert.equal(guest.ws.readyState,WebSocket.OPEN);
});
test('Three real WebSocket clients converge; authorization and restore',async t=>{
  const dataDir=await mkdtemp(join(tmpdir(),'pixelkollab-test-'));
  let service=await startServer({port:0,dataDir,log:()=>{}});
  t.after(async()=>{await service.close();await rm(dataDir,{recursive:true});});
  const a=await connect(service.port,{mode:'host',name:'A',snapshot:snapshot()});
  const welcome=await a.next('welcome');const [,code,token]=welcome.invite.split('/');
  a.send({type:'invite'});
  assert.equal((await a.next('invite')).invite,welcome.invite);
  const b=await connect(service.port,{mode:'join',name:'B',room:code,token});await b.next('welcome');
  const c=await connect(service.port,{mode:'join',name:'C',room:code,token});await c.next('welcome');
  a.send({type:'paint',seq:1,structure:0,patches:[{layer:1,frame:1,runs:[0,2,0xff123456]}]});
  const events=await Promise.all([a,b,c].map(x=>x.next('patch')));
  assert.deepEqual(events[0],events[2]);
  b.send({type:'paint',seq:1,structure:0,patches:[{layer:1,frame:1,runs:[0,1,0xffabcdef]}]});
  await Promise.all([a,b,c].map(x=>x.next('patch')));
  a.send({type:'undo'});
  const undone=await Promise.all([a,b,c].map(x=>x.next('patch')));
  assert.deepEqual(undone[1].patches[0].runs,[1,1,0]);
  a.send({type:'append',kind:'frame',structure:0});await Promise.all([a,b,c].map(x=>x.next('append')));
  const bad=await connect(service.port,{mode:'join',room:code,token:'bad'});
  assert.match((await bad.next('error')).message,/Einladungscode/);
  c.send({type:'append',kind:'layer',structure:1});
  const guestLayer=await Promise.all([a,b,c].map(x=>x.next('append')));
  assert.equal(guestLayer[0].index,2);
  assert.deepEqual(guestLayer[0],guestLayer[2]);
  b.send({type:'append',kind:'frame',source:1,structure:2});
  const guestFrame=await Promise.all([a,b,c].map(x=>x.next('append')));
  assert.equal(guestFrame[0].index,3);
  assert.deepEqual(guestFrame[0],guestFrame[2]);
  const expected=service.rooms.get(code).core.snapshot();
  await service.close();
  service=await startServer({port:0,dataDir,log:()=>{}});
  const resumed=await connect(service.port,{mode:'join',room:code,token});
  const recovered=await resumed.next('welcome');
  assert.deepEqual(recovered.snapshot,expected);assert.equal(recovered.restored,true);
  assert.deepEqual(await resumed.next('history'),{type:'history',undo:0,redo:0,recoveryCount:0});
});
test('Local-only server advertises loopback and joins without VPN',async t=>{
  const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{}});
  t.after(()=>service.close());
  assert.deepEqual(await (await fetch(`http://127.0.0.1:${service.port}/status`)).json(),
    {app:'Collabsprite',protocol:14,localOnly:true,port:service.port});
  const a=await connect(service.port,{mode:'host',name:'Local A',snapshot:snapshot()});
  const welcome=await a.next('welcome');
  assert.equal(welcome.localOnly,true);
  const [address,room,token]=welcome.invite.split('/');
  assert.equal(address,`127.0.0.1:${service.port}`);
  const b=await connect(service.port,{mode:'join',name:'Local B',room,token});
  const guest=await b.next('welcome');
  assert.equal(guest.localOnly,true);assert.notEqual(guest.author,welcome.author);
  const found=await discover(service.discoveryPort);
  assert.equal(found.rooms.length,1);
  assert.equal(found.rooms[0].name,'Local A');
  assert.equal(found.rooms[0].invite,welcome.invite);
  const probe=join(import.meta.dirname,'..','extension','Probe.ps1');
  if (process.platform==='win32' && existsSync(probe)) {
    // A fresh Windows CI runner can take several seconds to start PowerShell.
    const {stdout}=await execFileAsync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',probe,String(service.discoveryPort),'-LoopbackOnly'],{timeout:15000});
    assert.equal(JSON.parse(stdout.trim().split(/\r?\n/)[0]).rooms[0].invite,welcome.invite);
    // Discovery must also reach Bootstrap's PowerShell success stream. A
    // Console.WriteLine bypassed its @(& Probe.ps1) result collection.
    const bootstrap=join(import.meta.dirname,'..','extension','Bootstrap.ps1');
    const nested=await execFileAsync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',bootstrap,
      '-Action','Search','-Mode','Test','-Port',String(service.discoveryPort)],{timeout:15000});
    assert.ok(nested.stdout.startsWith('SEARCH\r\n')||nested.stdout.startsWith('SEARCH\n'));
    const responses=nested.stdout.trim().split(/\r?\n/).slice(1).filter(Boolean).map(JSON.parse);
    assert.ok(responses.some(r=>r.protocol===14 && r.rooms.some(room=>room.invite===welcome.invite)),'Detached search worker discarded found sessions');
  }
  a.send({type:'paint',seq:1,structure:0,patches:[{layer:1,frame:1,runs:[0,1,0xff123456]}]});
  await Promise.all([a.next('patch'),b.next('patch')]);
  b.send({type:'paint',seq:1,structure:0,patches:[{layer:1,frame:1,runs:[1,1,0xff654321]}]});
  await Promise.all([a.next('patch'),b.next('patch')]);
  a.send({type:'undo'});
  const result=await b.next('patch');
  assert.deepEqual(result.patches,[{layer:1,frame:1,runs:[0,1,0]}]);
  assert.equal(service.rooms.get(room).core.cells.get('1:1').pixels[1],0xff654321);
});
test('A full backup folder never blocks hosting and old backups are preserved',async t=>{
  const dataDir=await mkdtemp(join(tmpdir(),'collabsprite-full-backups-'));
  t.after(()=>rm(dataDir,{recursive:true,force:true}));
  const saved={tokenHash:'a'.repeat(64),snapshot:snapshot()};
  for (let i=1;i<=10;i++) {
    const code=i.toString(16).toUpperCase().padStart(8,'0');
    const path=join(dataDir,`${code}.json`);
    await writeFile(path,JSON.stringify(saved));
    const time=new Date(Date.UTC(2026,0,1,0,0,i));
    await utimes(path,time,time);
  }
  const service=await startServer({port:0,host:'127.0.0.1',dataDir,log:()=>{}});
  t.after(()=>service.close());
  assert.equal(service.rooms.size,8);
  assert.equal(service.rooms.has('00000001'),false,'Only the eight newest backups are restored');
  assert.equal(service.rooms.has('00000003'),true);
  const host=await connect(service.port,{mode:'host',name:'Host',snapshot:snapshot()});
  const welcome=await host.next('welcome');
  assert.equal(service.rooms.size,8,'New hosting reuses an idle in-memory slot');
  assert.equal(service.rooms.has('00000003'),false,'The oldest idle loaded room is evicted first');
  assert.ok(service.rooms.has(welcome.room));
  const files=await readdir(dataDir);
  assert.equal(files.filter(file=>file.endsWith('.json')).length,10,'No saved backup is removed');
  assert.ok(files.includes('00000001.json'),'Even backups outside the restore window remain untouched');
  assert.ok(files.includes('00000003.json'),'Evicting a room never deletes its backup');
});
test('Only the last host leaving requests managed server shutdown',async t=>{
  const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{}});
  t.after(()=>service.close());
  let shutdowns=0;
  service.server.on('collabsprite:last-host-left',()=>{shutdowns++;});
  const host1=await connect(service.port,{mode:'host',name:'Host 1',snapshot:snapshot()});
  const welcome1=await host1.next('welcome');
  const [,room,token]=welcome1.invite.split('/');
  const guest=await connect(service.port,{mode:'join',name:'Guest',room,token});
  await guest.next('welcome');
  const host2=await connect(service.port,{mode:'host',name:'Host 2',snapshot:snapshot()});
  await host2.next('welcome');
  guest.ws.close();await once(guest.ws,'close');
  await waitFor(()=>service.rooms.get(room).clients.size===1,'guest disconnect');
  assert.equal(shutdowns,0,'A guest leaving must not stop the server');
  host1.send({type:'leave'});await once(host1.ws,'close');
  await waitFor(()=>service.rooms.get(room).clients.size===0,'first host disconnect');
  assert.equal(shutdowns,0,'A second active host keeps the server alive');
  const finalHostLeft=once(service.server,'collabsprite:last-host-left');
  host2.send({type:'leave'});await once(host2.ws,'close');
  await finalHostLeft;
  assert.equal(shutdowns,1,'The final host leaving stops a managed server');
});

test('Guest departure retains pixels, host-only undo and durable backup after restart',async t=>{
  const dataDir=await mkdtemp(join(tmpdir(),'collabsprite-departure-'));
  let service=await startServer({port:0,host:'127.0.0.1',dataDir,log:()=>{}});
  t.after(async()=>{await service.close();await rm(dataDir,{recursive:true,force:true});});
  const host=await connect(service.port,{mode:'host',name:'Host',snapshot:snapshot()});
  const welcome=await host.next('welcome');
  const [,room,token]=welcome.invite.split('/');
  const guest=await connect(service.port,{mode:'join',name:'Gast',room,token});
  const guestWelcome=await guest.next('welcome');
  assert.equal(guestWelcome.host,false);
  host.send({type:'paint',seq:1,structure:0,patches:[{layer:1,frame:1,runs:[0,2,0xff112233]}]});
  await Promise.all([host.next('patch'),guest.next('patch')]);
  guest.send({type:'paint',seq:1,structure:0,patches:[{layer:1,frame:1,runs:[1,2,0xffabcdef]}]});
  // This is the client's ordered drain barrier, sent directly after paint.
  guest.send({type:'ping',nonce:'leave:2'});
  assert.equal((await guest.next('pong')).nonce,'leave:2');
  await Promise.all([host.next('patch'),guest.next('patch')]);
  guest.ws.close();await once(guest.ws,'close');
  await waitFor(()=>service.rooms.get(room).clients.size===1,'guest departure');
  assert.deepEqual([...service.rooms.get(room).core.cells.get('1:1').pixels].slice(0,3),
    [0xff112233,0xffabcdef,0xffabcdef]);
  host.send({type:'undo'});await host.next('patch');
  assert.deepEqual([...service.rooms.get(room).core.cells.get('1:1').pixels].slice(0,3),
    [0,0xffabcdef,0xffabcdef],'Host undo erased departed guest contribution');
  const expected=service.rooms.get(room).core.snapshot();
  await service.close();
  service=await startServer({port:0,host:'127.0.0.1',dataDir,log:()=>{}});
  const restored=await connect(service.port,{mode:'join',name:'Host',room,token});
  assert.deepEqual((await restored.next('welcome')).snapshot,expected);
});
test('Peers receive layer/frame deletion, metadata and join presence',async t=>{
  const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{}});
  t.after(()=>service.close());
  const a=await connect(service.port,{mode:'host',name:'Host',snapshot:snapshot()});
  const welcome=await a.next('welcome');
  const [,room,token]=welcome.invite.split('/');
  const b=await connect(service.port,{mode:'join',name:'Freund',room,token});
  const guest=await b.next('welcome');
  await b.next('presence');
  let members;
  do { members=(await a.next('presence')).members; } while (!members.some(member=>member.author===guest.author));
  assert.equal(members.find(member=>member.author===guest.author).name,'Freund');
  b.send({type:'append',kind:'layer',structure:0});
  await Promise.all([a.next('append'),b.next('append')]);
  a.send({type:'append',kind:'frame',structure:1});
  await Promise.all([a.next('append'),b.next('append')]);
  b.send({type:'property',kind:'layer',index:2,field:'name',value:'Figur',structure:2});
  assert.equal((await a.next('property')).value,'Figur');
  await b.next('property');
  a.send({type:'property',kind:'frame',index:2,field:'duration',value:300,structure:2});
  assert.equal((await b.next('property')).value,300);
  b.send({type:'celProperty',layer:2,frame:2,field:'opacity',value:125,structure:2});
  assert.equal((await a.next('celProperty')).value,125);
  a.send({type:'palette',colors:[0xff112233,0xff445566]});
  assert.deepEqual((await b.next('palette')).colors,[0xff112233,0xff445566]);
  b.send({type:'delete',kind:'frame',index:1,structure:2});
  const frameDelete=await a.next('delete');
  await b.next('delete');
  assert.equal(frameDelete.kind,'frame');
  assert.equal(frameDelete.structure,3);
  a.send({type:'delete',kind:'layer',index:1,structure:3});
  const layerDelete=await b.next('delete');
  assert.equal(layerDelete.kind,'layer');
  assert.equal(layerDelete.layers[0].name,'Figur');
  assert.equal(service.rooms.get(room).core.snapshot().cels.length,1);
  b.send({type:'leave'});await once(b.ws,'close');
  const afterLeave=await a.next('presence');
  assert.ok(!afterLeave.members.some(member=>member.author===guest.author),'Departed guest remained in presence');
});
test('A multi-frame deletion reaches peers as ordered, atomic events',async t=>{
  const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{}});
  t.after(()=>service.close());
  const state=snapshot();state.frames=[100,100,100,100];
  const host=await connect(service.port,{mode:'host',name:'Host',snapshot:state});
  const welcome=await host.next('welcome');
  const [,room,token]=welcome.invite.split('/');
  const guest=await connect(service.port,{mode:'join',name:'Gast',room,token});
  await guest.next('welcome');
  host.send({type:'deleteMany',kind:'frame',indices:[1,3],structure:0});
  const events=await Promise.all([guest.next('delete'),guest.next('delete')]);
  assert.deepEqual(events.map(event=>event.index),[3,1]);
  assert.deepEqual(events.map(event=>event.structure),[1,2]);
  assert.equal(service.rooms.get(room).core.meta.frames.length,2);
});
test('LAN subnet and Radmin addresses share one invitation format',()=>{
  const source={lan:[{family:'IPv4',address:'192.168.5.8',netmask:'255.255.255.0',internal:false}],
    vpn:[{family:'IPv4',address:'26.42.7.9',netmask:'255.0.0.0',internal:false}]};
  assert.deepEqual(addresses(source),['192.168.5.8','26.42.7.9']);
  assert.equal(invite(addresses(source),8766,'AABBCCDD','0123456789abcdef0123456789abcdef'),
    '192.168.5.8:8766,26.42.7.9:8766/AABBCCDD/0123456789abcdef0123456789abcdef');
  assert.equal(allowedPeer('192.168.5.99',false,source),true);
  assert.equal(allowedPeer('192.168.6.1',false,source),false);
  assert.equal(allowedPeer('26.9.9.9',false,source),true);
  assert.equal(allowedPeer('8.8.8.8',false,source),false);
  assert.equal(allowedPeer('26.9.9.9',true,source),false);
  assert.equal(replyAddress('192.168.5.99',false,source),'192.168.5.8');
  assert.equal(replyAddress('26.9.9.9',false,source),'26.42.7.9');
});
test('A second client can connect through this PC\'s LAN interface',async t=>{
  const lan=Object.values(networkInterfaces()).flat().find(entry=>entry?.family==='IPv4' &&
    !entry.internal && /^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(entry.address));
  if (!lan) { t.skip('No active private IPv4 interface'); return; }
  const service=await startServer({port:0,dataDir:null,log:()=>{}});
  t.after(()=>service.close());
  const host=await connect(service.port,{mode:'host',name:'Host',snapshot:snapshot()});
  const welcome=await host.next('welcome');
  assert.match(welcome.invite,new RegExp(lan.address.replaceAll('.','\\.')+':'+service.port));
  const [,room,token]=welcome.invite.split('/');
  const guest=await connect(service.port,{mode:'join',name:'LAN-Gast',room,token},lan.address);
  assert.equal((await guest.next('welcome')).room,room);
  host.send({type:'paint',seq:1,structure:0,patches:[{layer:1,frame:1,runs:[0,1,0xff112233]}]});
  assert.deepEqual((await guest.next('patch')).patches,[{layer:1,frame:1,runs:[0,1,0xff112233]}]);
});
test('An available Radmin adapter is advertised and accepts a client',async t=>{
  const vpn=Object.values(networkInterfaces()).flat().find(entry=>entry?.family==='IPv4' &&
    !entry.internal && /^26\./.test(entry.address));
  if (!vpn) { t.skip('No active Radmin-style IPv4 adapter'); return; }
  const service=await startServer({port:0,dataDir:null,log:()=>{}});
  t.after(()=>service.close());
  const host=await connect(service.port,{mode:'host',name:'Host',snapshot:snapshot()});
  const welcome=await host.next('welcome');
  assert.ok(welcome.invite.includes(`${vpn.address}:${service.port}`));
  const [,room,token]=welcome.invite.split('/');
  const guest=await connect(service.port,{mode:'join',name:'VPN-Gast',room,token},vpn.address);
  assert.equal((await guest.next('welcome')).room,room);
});
