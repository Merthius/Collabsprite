import test from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';
import dgram from 'node:dgram';
import { startServer } from '../server.mjs';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { existsSync } from 'node:fs';
const execFileAsync=promisify(execFile);
const snapshot=()=>({format:1,name:'Netzwerktest',width:16,height:16,layers:[{name:'Gemeinsam'}],frames:[100],cels:[],palette:[]});
async function connect(port,hello) {
  const ws=new WebSocket(`ws://127.0.0.1:${port}`);
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
  const send=message=>ws.send(JSON.stringify(message));send({type:'hello',protocol:1,...hello});
  return {ws,send,next};
}
async function discover(port) {
  const socket=dgram.createSocket('udp4');
  try {
    await new Promise(resolve=>socket.bind(0,'127.0.0.1',resolve));
    const reply=new Promise((resolve,reject)=>{
      const timeout=setTimeout(()=>reject(Error('Timeout UDP discovery')),2000);
      socket.once('message',data=>{clearTimeout(timeout);resolve(JSON.parse(data.toString()));});
    });
    socket.send(Buffer.from('COLLABSPRITE_DISCOVER_V1'),port,'127.0.0.1');
    return await reply;
  } finally {socket.close();}
}
test('Three real WebSocket clients converge; authorization and restore',async t=>{
  const dataDir=await mkdtemp(join(tmpdir(),'pixelkollab-test-'));
  let service=await startServer({port:0,dataDir,log:()=>{}});
  t.after(async()=>{await service.close();await rm(dataDir,{recursive:true});});
  const a=await connect(service.port,{mode:'host',name:'A',snapshot:snapshot()});
  const welcome=await a.next('welcome');const [,code,token]=welcome.invite.split('/');
  const b=await connect(service.port,{mode:'join',name:'B',room:code,token});await b.next('welcome');
  const c=await connect(service.port,{mode:'join',name:'C',room:code,token});await c.next('welcome');
  a.send({type:'paint',seq:1,patches:[{layer:1,frame:1,runs:[0,2,0xff123456]}]});
  const events=await Promise.all([a,b,c].map(x=>x.next('patch')));
  assert.deepEqual(events[0],events[2]);
  b.send({type:'paint',seq:1,patches:[{layer:1,frame:1,runs:[0,1,0xffabcdef]}]});
  await Promise.all([a,b,c].map(x=>x.next('patch')));
  a.send({type:'undo'});
  const undone=await Promise.all([a,b,c].map(x=>x.next('patch')));
  assert.deepEqual(undone[1].patches[0].runs,[1,1,0]);
  a.send({type:'append',kind:'frame'});await Promise.all([a,b,c].map(x=>x.next('append')));
  const bad=await connect(service.port,{mode:'join',room:code,token:'bad'});
  assert.match((await bad.next('error')).message,/Einladungscode/);
  c.send({type:'append',kind:'layer'});
  const guestLayer=await Promise.all([a,b,c].map(x=>x.next('append')));
  assert.equal(guestLayer[0].index,2);
  assert.deepEqual(guestLayer[0],guestLayer[2]);
  b.send({type:'append',kind:'frame',source:1});
  const guestFrame=await Promise.all([a,b,c].map(x=>x.next('append')));
  assert.equal(guestFrame[0].index,3);
  assert.deepEqual(guestFrame[0],guestFrame[2]);
  const expected=service.rooms.get(code).core.snapshot();
  await service.close();
  service=await startServer({port:0,dataDir,log:()=>{}});
  const resumed=await connect(service.port,{mode:'join',room:code,token});
  const recovered=await resumed.next('welcome');
  assert.deepEqual(recovered.snapshot,expected);assert.equal(recovered.restored,true);
  assert.deepEqual(await resumed.next('history'),{type:'history',undo:0,redo:0});
});
test('Local-only server advertises loopback and joins without VPN',async t=>{
  const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{}});
  t.after(()=>service.close());
  assert.deepEqual(await (await fetch(`http://127.0.0.1:${service.port}/status`)).json(),
    {app:'Collabsprite',protocol:1,localOnly:true,port:service.port});
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
    const {stdout}=await execFileAsync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',probe,String(service.discoveryPort)],{timeout:15000});
    assert.equal(JSON.parse(stdout.trim().split(/\r?\n/)[0]).rooms[0].invite,welcome.invite);
  }
  a.send({type:'paint',seq:1,patches:[{layer:1,frame:1,runs:[0,1,0xff123456]}]});
  await Promise.all([a.next('patch'),b.next('patch')]);
  b.send({type:'paint',seq:1,patches:[{layer:1,frame:1,runs:[1,1,0xff654321]}]});
  await Promise.all([a.next('patch'),b.next('patch')]);
  a.send({type:'undo'});
  const result=await b.next('patch');
  assert.deepEqual(result.patches,[{layer:1,frame:1,runs:[0,1,0]}]);
  assert.equal(service.rooms.get(room).core.cells.get('1:1').pixels[1],0xff654321);
});
