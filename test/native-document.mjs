// Two real native documents/controllers, production WebSocket server. A tiny
// loopback bridge pumps sockets because --batch has no native GUI event loop.
import {startServer} from '../server.mjs';
import {WebSocket} from 'ws';
import http from 'node:http';
import {randomBytes} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {resolve} from 'node:path';
const token=randomBytes(16).toString('hex'), peers=new Map();
const service=await startServer({port:0,host:'127.0.0.1',dataDir:null,log:()=>{}});
const bridge=http.createServer(async(req,res)=>{
  try {
    if(req.method!=='POST'||req.headers.origin)throw Error('Forbidden');
    let body='';for await(const part of req){body+=part;if(body.length>16*1024*1024)throw Error('Too large');}
    const p=JSON.parse(body);if(p.token!==token||!['A','B'].includes(p.peer))throw Error('Forbidden');
    let peer=peers.get(p.peer);
    if(!peer){
      const ws=new WebSocket(`ws://127.0.0.1:${service.port}`);peer={ws,queue:[]};peers.set(p.peer,peer);
      ws.on('message',data=>peer.queue.push(JSON.parse(data)));
      await new Promise((yes,no)=>{ws.once('open',yes);ws.once('error',no);});
    }
    if(p.action==='send'){
      peer.ws.send(p.data);
      await new Promise(yes=>setTimeout(yes,5));
      res.end('{}');
    }else{
      await new Promise(yes=>setTimeout(yes,5));
      res.end(JSON.stringify(peer.queue.splice(0)));
    }
  }catch(e){res.writeHead(400);res.end(JSON.stringify({error:e.message}));}
});
await new Promise(yes=>bridge.listen(0,'127.0.0.1',yes));
try{
  const exe=process.env.ASEPRITE_EXE||'C:/Program Files (x86)/Steam/steamapps/common/Aseprite/aseprite.exe';
  // Windows starts a separate curl process for every deterministic bridge
  // exchange. Leave headroom for slower machines without an unbounded test.
  const pending=promisify(execFile)(exe,['--batch','--script-param',`root=${resolve('.')}`,'--script-param',`bridge=${bridge.address().port}`,'--script-param',`token=${token}`,'--script',resolve('test/native-document.lua')],{windowsHide:true,timeout:180000,maxBuffer:4*1024*1024});
  pending.child.stdout.on('data',data=>process.stdout.write(data));
  const result=await pending;if(result.stderr)console.error(result.stderr);
  if(!result.stdout.includes('PASS: native cooperative document transactions'))throw Error('Native PASS missing');
}catch(error){
  // Do not dump argv/test capability token on a failed child invocation.
  console.error(error.stdout||`Native test failed (${error.killed?'timeout':error.code})`);process.exitCode=1;
}finally{
  for(const p of peers.values())p.ws.terminate();
  await new Promise(yes=>bridge.close(yes));await service.close();
}
