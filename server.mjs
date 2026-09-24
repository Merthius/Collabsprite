import http from 'node:http';
import dgram from 'node:dgram';
import { WebSocketServer, WebSocket } from 'ws';
import { randomBytes, timingSafeEqual, createHash } from 'node:crypto';
import { allowedPeer, addresses, invite, replyAddress } from './network.mjs';
import { mkdir, readdir, readFile, writeFile, rename } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Room } from './core.mjs';

const hash = value => createHash('sha256').update(String(value)).digest('hex');
const isLocal = address => ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(address);
export async function startServer({ port = 8766, host = '0.0.0.0', dataDir = resolve(dirname(fileURLToPath(import.meta.url)), 'data'), log = console.log } = {}) {
  const localOnly = host === '127.0.0.1' || host === '::1';
  const rooms = new Map();
  if (dataDir) {
    await mkdir(dataDir, { recursive: true });
    for (const file of (await readdir(dataDir)).filter(f => /^[A-F0-9]{8}\.json$/.test(f)).slice(0, 8)) {
      try {
        const saved = JSON.parse(await readFile(resolve(dataDir, file), 'utf8'));
        if (!/^[a-f0-9]{64}$/.test(saved.tokenHash)) continue;
        rooms.set(file.slice(0, -5), { core: new Room(saved.snapshot), tokenHash: saved.tokenHash, clients: new Set(), dirty: false, restored: true });
      } catch (error) { log(`Backup ${file} konnte nicht geladen werden: ${error.message}`); }
    }
  }
  const server = http.createServer((req, res) => {
    if (req.url === '/status' && allowedPeer(req.socket.remoteAddress, localOnly)) {
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(JSON.stringify({ app: 'Collabsprite', protocol: 3, localOnly, port: server.address()?.port }));
      return;
    }
    if (!allowedPeer(req.socket.remoteAddress, localOnly)) { res.writeHead(403); res.end(); return; }
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end('Collabsprite ist bereit. In Aseprite Ansicht > Collabsprite waehlen.\n');
  });
  const wss = new WebSocketServer({ server, maxPayload: 64 * 1024 * 1024, perMessageDeflate: { threshold: 1024 }, clientTracking: true });
  const send = (socket, data) => {
    if (socket.readyState !== WebSocket.OPEN) return;
    if (socket.bufferedAmount > 64 * 1024 * 1024) return socket.close(1013, 'Empfaenger zu langsam');
    socket.send(JSON.stringify(data));
  };
  const broadcast = (room, event) => { for (const client of room.clients) send(client, event); };
  const histories = room => { for (const client of room.clients) send(client, { type: 'history', ...room.core.history(client.author) }); };
  const presence = room => broadcast(room, { type: 'presence', members: [...room.clients].map(c => ({ name: c.name, author: c.author })) });
  wss.on('connection', (socket, request) => {
    const address = String(request.socket.remoteAddress || '').replace(/^::ffff:/, '');
    if (!allowedPeer(address, localOnly))
      return socket.close(1008, 'Nur lokales Netzwerk oder Radmin VPN');
    socket._socket?.setNoDelay(true);
    socket.lastSeen = Date.now();
    socket.on('pong', () => { socket.lastSeen = Date.now(); });
    // Aseprite's native client sends its ws:// URL as Origin. Browser pages
    // send http(s):// (or null); reject those, including localhost drive-by hosts.
    if (request.headers.origin && request.headers.origin !== `ws://${request.headers.host}`)
      return socket.close(1008, 'Nur native Aseprite-Verbindungen');
    if (wss.clients.size > 24) return socket.close(1013, 'Server voll');
    const greetingTimeout = setTimeout(() => { if (!socket.room) socket.close(1008, 'Keine Anmeldung'); }, 15000);
    greetingTimeout.unref();
    socket.on('message', (data, binary) => {
      try {
        socket.lastSeen = Date.now();
        if (binary) throw new Error('Nur JSON-Nachrichten erlaubt');
        const message = JSON.parse(data.toString());
        if (!socket.room) {
          if (message.type !== 'hello' || message.protocol !== 3) throw new Error('Unpassende Erweiterungsversion');
          socket.name = String(message.name || 'Kuenstler').replace(/[\x00-\x1f]/g, '').slice(0, 30);
          socket.author = randomBytes(16).toString('hex');
          let room, code, token;
          if (message.mode === 'host') {
            if (!isLocal(request.socket.remoteAddress)) throw new Error('Sitzungen bitte auf dem Host-PC starten (127.0.0.1)');
            if (rooms.size >= 8) throw new Error('Maximal 8 gespeicherte Sitzungen; alte Backups im data-Ordner archivieren');
            const core = new Room(message.snapshot);
            code = randomBytes(4).toString('hex').toUpperCase();
            token = randomBytes(16).toString('hex');
            room = { core, tokenHash: hash(token), discoveryToken: token, hostName: socket.name,
              clients: new Set(), dirty: true, restored: false, hostAuthor: socket.author };
            rooms.set(code, room);
          } else if (message.mode === 'join') {
            code = String(message.room || '').toUpperCase(); room = rooms.get(code);
            const submitted = Buffer.from(hash(message.token), 'hex');
            if (!room || !timingSafeEqual(Buffer.from(room.tokenHash, 'hex'), submitted)) throw new Error('Sitzung oder Einladungscode stimmt nicht');
            if (room.clients.size >= 8) throw new Error('Maximal 8 Personen pro Sitzung');
            // A restored room becomes discoverable again after a legitimate join.
            room.discoveryToken = String(message.token);
            if (!room.hostName) room.hostName = socket.name;
            // Local host can reclaim host controls after a restart using the saved invitation.
            if (!room.clients.size && isLocal(request.socket.remoteAddress)) room.hostAuthor = socket.author;
          } else throw new Error('Unbekannter Verbindungsmodus');
          clearTimeout(greetingTimeout);
          socket.room = room; socket.code = code; room.clients.add(socket); room.core.user(socket.author);
          const actualPort = server.address().port;
          send(socket, { type: 'welcome', protocol: 3, author: socket.author, room: code, host: room.hostAuthor === socket.author, revision: room.core.revision, structure: room.core.structure,
            invite: token ? invite(localOnly ? [] : addresses(), actualPort, code, token) : undefined,
            localOnly, restored: room.restored, snapshot: room.core.snapshot() });
          histories(room); presence(room);
          log(`Sitzung ${code}: ${room.clients.size} Person(en) verbunden.`);
          return;
        }
        const room = socket.room;
        let event;
        if (message.type === 'paint') event = room.core.paint(socket.author, message.seq, message.patches, message.structure);
        else if (message.type === 'undo' || message.type === 'redo') event = room.core.undoRedo(socket.author, message.type === 'redo');
        else if (message.type === 'append') {
          if (message.structure !== room.core.structure) throw new Error('Dokumentstruktur hat sich geaendert; bitte neu verbinden');
          event = room.core.append(message.kind, message.name, message.source);
        } else if (message.type === 'delete') {
          if (message.structure !== room.core.structure) throw new Error('Dokumentstruktur hat sich geaendert; bitte neu verbinden');
          event = room.core.delete(message.kind, message.index);
        } else if (message.type === 'deleteMany') {
          if (message.structure !== room.core.structure) throw new Error('Dokumentstruktur hat sich geaendert; bitte neu verbinden');
          const events = room.core.deleteMany(message.kind, message.indices);
          for (const deletion of events) broadcast(room, deletion);
          room.dirty = true; histories(room);
          return;
        } else if (message.type === 'property') {
          if (message.structure !== room.core.structure) throw new Error('Dokumentstruktur hat sich geaendert; bitte neu verbinden');
          event = room.core.setProperty(message.kind, message.index, message.field, message.value);
        } else if (message.type === 'celProperty') {
          if (message.structure !== room.core.structure) throw new Error('Dokumentstruktur hat sich geaendert; bitte neu verbinden');
          event = room.core.setCelProperty(message.layer, message.frame, message.field, message.value);
        } else if (message.type === 'palette') {
          event = room.core.setPalette(message.colors);
        } else if (message.type === 'invite' && room.hostAuthor === socket.author) {
          send(socket, { type: 'invite', invite: invite(localOnly ? [] : addresses(), server.address().port, socket.code, room.discoveryToken) }); return;
        } else if (message.type === 'ping') { send(socket, { type: 'pong', nonce: message.nonce }); return; }
        else throw new Error('Unbekannte Nachricht');
        if (event) {
          broadcast(room, event); room.dirty = true;
        }
        histories(room);
      } catch (error) {
        send(socket, { type: 'error', message: error.message });
        socket.close(1008, 'Sitzung wegen ungueltiger Nachricht beendet');
      }
    });
    socket.on('close', () => {
      clearTimeout(greetingTimeout);
      if (socket.room) { socket.room.clients.delete(socket); presence(socket.room); }
    });
    socket.on('error', () => {});
  });
  async function save() {
    if (!dataDir) return;
    for (const [code, room] of rooms) {
      if (!room.dirty || room.saving) continue;
      room.saving = true; room.dirty = false;
      try {
        const temporary = resolve(dataDir, `${code}.tmp`);
        await writeFile(temporary, JSON.stringify({ tokenHash: room.tokenHash, snapshot: room.core.snapshot() }));
        await rename(temporary, resolve(dataDir, `${code}.json`));
      } catch (error) { room.dirty = true; log(`Backup fehlgeschlagen: ${error.message}`); }
      finally { room.saving = false; }
    }
  }
  const saveTimer = setInterval(() => void save(), 2000); saveTimer.unref();
  const heartbeat = setInterval(() => {
    for (const socket of wss.clients) {
      // The native Aseprite client may not expose Pong. Its explicit JSON
      // heartbeat is the authority; a single missed protocol Pong is not fatal.
      if (Date.now() - socket.lastSeen > 60000) { socket.terminate(); continue; }
      if (socket.readyState === WebSocket.OPEN) socket.ping();
    }
  }, 15000); heartbeat.unref();
  await new Promise((accept, reject) => { server.once('error', reject); server.listen(port, host, accept); });
  const discovery = dgram.createSocket('udp4');
  discovery.on('message', (data, peer) => {
    if (data.toString() !== 'COLLABSPRITE_DISCOVER_V3') return;
    if (!allowedPeer(peer.address, localOnly)) return;
    const address = replyAddress(peer.address, localOnly);
    if (!address) return;
    const visible = [];
    for (const [code, room] of rooms) {
      if (!room.clients.size || !room.discoveryToken) continue;
      visible.push({ name: room.hostName || 'Kuenstler', image: room.core.meta.name,
        invite: invite([address], server.address().port, code, room.discoveryToken) });
    }
    const response = Buffer.from(JSON.stringify({ protocol: 3, rooms: visible }));
    if (response.length <= 1200) discovery.send(response, peer.port, peer.address);
  });
  discovery.on('error', error => log(`Sitzungssuche: ${error.message}`));
  let discoveryPort = null;
  try {
    await new Promise((accept, reject) => {
      discovery.once('error', reject);
      discovery.bind(port === 0 ? 0 : server.address().port, localOnly ? '127.0.0.1' : '0.0.0.0', accept);
    });
    discoveryPort = discovery.address().port;
  } catch (error) {
    discovery.close();
    log(`UDP-Sitzungssuche nicht verfuegbar (${error.message}); Einladungscode funktioniert weiterhin.`);
  }
  log(`Collabsprite | Port ${server.address().port} | ${localOnly ? 'Test: nur dieser PC' : 'LAN und Radmin VPN'}\nHost: Collabsprite in Aseprite oeffnen und Sitzung starten.`);
  return { server, rooms, port: server.address().port, discoveryPort, async close() {
    clearInterval(saveTimer); clearInterval(heartbeat);
    if (discoveryPort) discovery.close();
    for (const socket of wss.clients) socket.terminate();
    await save();
    await new Promise(resolve => wss.close(resolve));
    await new Promise(resolve => server.close(resolve));
  } };
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const mode = process.argv.includes('--local') ? 'local' : 'global';
  const requestedPort = process.argv.find(arg => arg.startsWith('--port='));
  const port = Number(requestedPort?.slice(7) || process.env.COLLABSPRITE_PORT || (mode === 'local' ? 8765 : 8766));
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Ungueltiger Serverport');
  const service = await startServer({ port, host: mode === 'local' ? '127.0.0.1' : '0.0.0.0' });
  let stopping = false;
  const stop = async () => { if (stopping) return; stopping = true; await service.close(); process.exit(0); };
  if (process.argv.includes('--managed')) {
    let idleSince = Date.now();
    const idleTimer = setInterval(() => {
      if ([...service.rooms.values()].some(room => room.clients.size > 0)) idleSince = Date.now();
      else if (Date.now() - idleSince > 120000) void stop();
    }, 30000);
    idleTimer.unref();
  }
  process.on('SIGINT', stop); process.on('SIGTERM', stop);
}
