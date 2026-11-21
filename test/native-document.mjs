// Two real native documents/controllers, production WebSocket server. Batch
// Aseprite has no GUI socket pump: use a private mailbox, not one new curl
// process per exchange (which makes this test measure Windows process startup).
import {startServer} from '../server.mjs';
import {WebSocket} from 'ws';
import {randomBytes} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {resolve,join,dirname,basename} from 'node:path';
import {tmpdir} from 'node:os';
import {mkdtemp,readFile,writeFile,rename,unlink,rm} from 'node:fs/promises';
const token=randomBytes(16).toString('hex'), peers=new Map();
const mailbox=await mkdtemp(join(tmpdir(),'Collabsprite-native-document-'));
const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{}});
let processing=false,stopping=false,pollJob;
async function pumpMailbox(){
  if(processing||stopping)return;
  processing=true;
  let p;
  try {
    let body;
    try{body=await readFile(join(mailbox,'request.json'),'utf8');}
    catch(error){if(error.code==='ENOENT')return;throw error;}
    await unlink(join(mailbox,'request.json'));
    if(body.length>16*1024*1024)throw Error('Too large');
    p=JSON.parse(body);if(p.token!==token||!['A','B'].includes(p.peer))throw Error('Forbidden');
    let peer=peers.get(p.peer);
    if(!peer){
      const ws=new WebSocket(`ws://127.0.0.1:${service.port}`);peer={ws,queue:[]};peers.set(p.peer,peer);
      ws.on('message',data=>peer.queue.push(JSON.parse(data)));
      await new Promise((yes,no)=>{ws.once('open',yes);ws.once('error',no);});
    }
    if(p.action==='send'){
      peer.ws.send(p.data);
      await new Promise(yes=>setTimeout(yes,5));
      await reply({seq:p.seq,ok:true,value:{}});
    }else if(p.action==='poll'){
      await new Promise(yes=>setTimeout(yes,5));
      await reply({seq:p.seq,ok:true,value:peer.queue.splice(0)});
    }else throw Error('Unknown action');
  }catch(e){await reply({seq:p?.seq,ok:false,error:e.message});}
  finally{processing=false;}
}
async function reply(value){
  await writeFile(join(mailbox,'response.tmp'),JSON.stringify(value));
  await rename(join(mailbox,'response.tmp'),join(mailbox,'response.json'));
}
const timer=setInterval(()=>{
  if(!processing&&!stopping)pollJob=pumpMailbox().catch(error=>{console.error(error.message);process.exitCode=1;});
},5);
try{
  const exe=process.env.ASEPRITE_EXE||'C:/Program Files (x86)/Steam/steamapps/common/Aseprite/aseprite.exe';
  const pending=promisify(execFile)(exe,['--batch','--script-param',`root=${resolve('.')}`,'--script-param',`mailbox=${mailbox.replaceAll('\\','/')}`,'--script-param',`token=${token}`,'--script',resolve('test/native-document.lua')],{windowsHide:true,timeout:180000,maxBuffer:4*1024*1024,
    env:{...process.env,ASEPRITE_USER_FOLDER:join(mailbox,'profile')}});
  pending.child.stdout.on('data',data=>process.stdout.write(data));
  const result=await pending;if(result.stderr)console.error(result.stderr);
  if(!result.stdout.includes('PASS: native cooperative document transactions'))throw Error('Native PASS missing');
}catch(error){
  // Do not dump argv/test capability token on a failed child invocation.
  console.error(error.stdout||`Native test failed (${error.killed?'timeout':error.code})`);process.exitCode=1;
}finally{
  stopping=true;clearInterval(timer);await pollJob;
  for(const p of peers.values())p.ws.terminate();
  await service.close();
  if(dirname(resolve(mailbox))!==resolve(tmpdir())||!basename(mailbox).startsWith('Collabsprite-native-document-'))throw Error('Unexpected test directory');
  await rm(mailbox,{recursive:true,force:true});
}
