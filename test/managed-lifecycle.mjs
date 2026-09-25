import assert from 'node:assert/strict';
import { once } from 'node:events';
import { WebSocket } from 'ws';

const port = Number(process.argv[2]);
assert.ok(Number.isInteger(port) && port > 0 && port < 65536);
const url = `ws://127.0.0.1:${port}`;
const snapshot = { format: 1, name: 'Lifecycle test', width: 4, height: 4,
  layers: [{ name: 'Shared' }], frames: [100], cels: [], palette: [] };

async function connect(hello) {
  const socket = new WebSocket(url);
  const welcome = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('Welcome timeout')), 3000);
    socket.on('message', data => {
      const message = JSON.parse(data);
      if (message.type === 'welcome') { clearTimeout(timeout); resolve(message); }
      else if (message.type === 'error') { clearTimeout(timeout); reject(new Error(message.message)); }
    });
  });
  await once(socket, 'open');
  socket.send(JSON.stringify({ type: 'hello', protocol: 3, ...hello }));
  return { socket, welcome: await welcome };
}

const host = await connect({ mode: 'host', name: 'Host', snapshot });
const [,room,token] = host.welcome.invite.split('/');
const guest = await connect({ mode: 'join', name: 'Guest', room, token });
assert.equal(guest.welcome.room, room);
guest.socket.close();
await once(guest.socket, 'close');
assert.equal((await fetch(`http://127.0.0.1:${port}/status`)).status, 200,
  'A guest leaving must not stop the server');
host.socket.close();
await once(host.socket, 'close');

const deadline = Date.now() + 6000;
let stopped = false;
while (Date.now() < deadline) {
  try { await fetch(`http://127.0.0.1:${port}/status`, { signal: AbortSignal.timeout(300) }); }
  catch { stopped = true; break; }
  await new Promise(resolve => setTimeout(resolve, 50));
}
assert.equal(stopped, true, 'The managed host server must release its port promptly');
console.log('PASS: Guest leaves, host leaves, server stops and releases its port.');
