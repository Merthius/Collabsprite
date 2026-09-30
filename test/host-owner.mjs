import assert from 'node:assert/strict';
import {spawn,execFileSync} from 'node:child_process';
import {existsSync,readFileSync,writeFileSync,unlinkSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {randomUUID} from 'node:crypto';
import {once} from 'node:events';
import net from 'node:net';
import dgram from 'node:dgram';
import {WebSocket} from 'ws';

const root=resolve(process.argv[2]),port=Number(process.argv[3]);
const exe=process.env.ASEPRITE_EXE||'C:/Program Files (x86)/Steam/steamapps/common/Aseprite/aseprite.exe';
if (!existsSync(exe)) {console.log('SKIP: native owner test requires Aseprite.');process.exit(0);}
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function until(check,label) {
  const deadline=Date.now()+18000;
  while(Date.now()<deadline) {if(await check())return;await delay(80);}
  throw Error('Timeout: '+label);
}
for(const forced of [false,true]) {
  const id=randomUUID().replaceAll('-',''),result=join(process.env.TEMP,`Collabsprite-start-${id}.status`),stop=join(root,`stop-${id}`);
  let child,ws,ownerServerPid;
  try {
    child=spawn(exe,['--batch','--script-param',`root=${root.replaceAll('\\','/')}`,
      '--script-param',`result=${result.replaceAll('\\','/')}`,'--script-param',`stop=${stop.replaceAll('\\','/')}`,
      '--script-param',`port=${port}`,'--script',resolve('test/host-owner.lua')],{windowsHide:true});
    let output='';child.stdout.on('data',d=>output+=d);child.stderr.on('data',d=>output+=d);
    await until(()=>output.includes('OWNER_READY'),'Aseprite launcher');
    await until(()=>existsSync(result)&&readFileSync(result,'utf8').startsWith(`READY ${port}`),'host ready');
    const proc=JSON.parse(execFileSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',
      `$p=Get-NetTCPConnection -LocalPort ${port} -State Listen | Select-Object -First 1; Get-CimInstance Win32_Process -Filter ('ProcessId='+$p.OwningProcess) | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress`],{encoding:'utf8',windowsHide:true}));
    assert.ok(proc.CommandLine.includes(root));ownerServerPid=proc.ProcessId;
    assert.ok(proc.CommandLine.includes(`--owner-pid=${child.pid}`),'Launcher did not bind the real Aseprite ancestor');
    ws=new WebSocket(`ws://127.0.0.1:${port}`);
    const welcomed=new Promise((yes,no)=>ws.on('message',d=>{const m=JSON.parse(d);if(m.type==='welcome')yes(m);if(m.type==='error')no(Error(m.message));}));
    await once(ws,'open');ws.send(JSON.stringify({type:'hello',protocol:13,mode:'host',name:'Owner test',snapshot:{format:1,name:'Owner test',width:4,height:4,layers:[{name:'Shared'}],frames:[100],cels:[],palette:[]}}));
    const welcome=await welcomed;
    const exit=once(child,'exit');
    if(forced)child.kill();else writeFileSync(stop,'exit');
    await exit;
    await until(async()=>{try{await fetch(`http://127.0.0.1:${port}/status`,{signal:AbortSignal.timeout(200)});return false;}catch{return true;}},'server released TCP port');
    await until(()=>existsSync(join(root,'data',`${welcome.room}.json`)),'final backup');
    const tcp=net.createServer();tcp.listen(port,'127.0.0.1');await once(tcp,'listening');await new Promise(r=>tcp.close(r));
    const udp=dgram.createSocket('udp4');udp.bind(port,'127.0.0.1');await once(udp,'listening');udp.close();
    console.log(`PASS: real Aseprite ${forced?'forced termination':'normal exit'} stops host; backup retained; TCP/UDP reusable.`);
  } finally {
    ws?.terminate();if(child?.exitCode===null&&!child?.signalCode)child.kill();
    if(ownerServerPid) {
      // Only the process whose executable command line was verified above.
      execFileSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',
        `$p=Get-CimInstance Win32_Process -Filter 'ProcessId=${ownerServerPid}' -ErrorAction SilentlyContinue; if($p -and $p.Name -eq 'node.exe' -and $p.CommandLine.Contains('${root.replaceAll("'","''")}')){Stop-Process -Id ${ownerServerPid} -Force -ErrorAction SilentlyContinue}`],{windowsHide:true});
    }
    if(existsSync(result))unlinkSync(result);if(existsSync(stop))unlinkSync(stop);
  }
}
