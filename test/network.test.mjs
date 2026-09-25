import test from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';
import dgram from 'node:dgram';
import { startServer } from '../server.mjs';
import { allowedPeer, addresses, invite, replyAddress } from '../network.mjs';
import { mkdtemp, rm } from 'node:fs/promises';
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
  const send=message=>ws.send(JSON.stringify(message));send({type:'hello',protocol:3,...hello});
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
    socket.send(Buffer.from('COLLABSPRITE_DISCOVER_V3'),port,'127.0.0.1');
    return await reply;
  } finally {socket.close();}
}
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
  assert.deepEqual(await resumed.next('history'),{type:'history',undo:0,redo:0});
});
test('Local-only server advertises loopback and joins without VPN',async t=>{
  const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{}});
  t.after(()=>service.close());
  assert.deepEqual(await (await fetch(`http://127.0.0.1:${service.port}/status`)).json(),
    {app:'Collabsprite',protocol:3,localOnly:true,port:service.port});
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
  host1.ws.close();await once(host1.ws,'close');
  await waitFor(()=>service.rooms.get(room).clients.size===0,'first host disconnect');
  assert.equal(shutdowns,0,'A second active host keeps the server alive');
  const finalHostLeft=once(service.server,'collabsprite:last-host-left');
  host2.ws.close();await once(host2.ws,'close');
  await finalHostLeft;
  assert.equal(shutdowns,1,'The final host leaving stops a managed server');
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
