import http from 'node:http';
import dgram from 'node:dgram';
import { WebSocketServer, WebSocket } from 'ws';
import { randomBytes, timingSafeEqual, createHash } from 'node:crypto';
import { allowedPeer, addresses, invite, replyAddress } from './network.mjs';
import { mkdir, readdir, readFile, writeFile, rename, stat } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Room, OperationRejected } from './core.mjs';
import { NoteRejected } from './notes.mjs';

const hash = value => createHash('sha256').update(String(value)).digest('hex');
const isLocal = address => ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(address);
const MAX_ROOMS = 8;
const MiB = 1024 * 1024;
// Token buckets permit normal bursts (including initial large sprites) while
// bounding sustained work. Limits concern decompressed application bytes.
function budget(capacity, perSecond) {
  let tokens = capacity, updated = performance.now();
  return amount => {
    const now = performance.now();
    tokens = Math.min(capacity, tokens + (now - updated) * perSecond / 1000); updated = now;
    if (amount > tokens) return false;
    tokens -= amount; return true;
  };
}
export async function startServer({ port = 8766, host = '0.0.0.0', dataDir = resolve(dirname(fileURLToPath(import.meta.url)), 'data'), log = console.log, resumeMs = 120000 } = {}) {
  if (!Number.isSafeInteger(resumeMs) || resumeMs < 50 || resumeMs > 120000) throw new Error('Ungueltiges Wiederverbindungsfenster');
  const localOnly = host === '127.0.0.1' || host === '::1';
  const rooms = new Map();
  let stopping = false, closePromise;
  if (dataDir) {
    await mkdir(dataDir, { recursive: true });
    const backups = await Promise.all((await readdir(dataDir))
      .filter(file => /^[A-F0-9]{8}\.json$/.test(file))
      .map(async file => {
        try {
          const info = await stat(resolve(dataDir, file));
          return info.isFile() ? { file, savedAt: info.mtimeMs } : null;
        } catch { return null; }
      }));
    // Restore the most recently used eight sessions. Older backup files stay
    // on disk untouched, but must not prevent a new room from being created.
    let restoredCount = 0;
    for (const backup of backups.filter(Boolean).sort((a, b) => b.savedAt - a.savedAt)) {
      if (restoredCount >= MAX_ROOMS) break;
      const { file, savedAt } = backup;
      try {
        const saved = JSON.parse(await readFile(resolve(dataDir, file), 'utf8'));
        if (!/^[a-f0-9]{64}$/.test(saved.tokenHash)) continue;
        rooms.set(file.slice(0, -5), { core: new Room(saved.snapshot), tokenHash: saved.tokenHash, clients: new Set(), leases: new Map(), dirty: false, restored: true, persisted: true, savedAt, acceptingGuests: false, savedRevision: 0 });
        restoredCount++;
      } catch (error) { log(`Backup ${file} konnte nicht geladen werden: ${error.message}`); }
    }
  }
  function makeRoomSlot() {
    if (rooms.size < MAX_ROOMS) return;
    const stale = [...rooms.entries()]
      .filter(([, room]) => room.persisted && !room.dirty && !room.saving && room.clients.size === 0 && room.leases.size === 0)
      .sort((a, b) => a[1].savedAt - b[1].savedAt)[0];
    if (!stale) throw new Error(`Alle ${MAX_ROOMS} Sitzungsplätze sind belegt. Eine aktive Sitzung schließen und erneut versuchen.`);
    // The durable JSON backup is deliberately retained. Only its in-memory
    // room slot is recycled; a later server start can restore recent files.
    rooms.delete(stale[0]);
  }
  const server = http.createServer((req, res) => {
    if (req.url === '/status' && allowedPeer(req.socket.remoteAddress, localOnly)) {
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(JSON.stringify({ app: 'Collabsprite', protocol: 5, localOnly, port: server.address()?.port }));
      return;
    }
    if (!allowedPeer(req.socket.remoteAddress, localOnly)) { res.writeHead(403); res.end(); return; }
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end('Collabsprite ist bereit. In Aseprite Ansicht > Collabsprite waehlen.\n');
  });
  const wss = new WebSocketServer({ noServer: true, maxPayload: 64 * MiB,
    perMessageDeflate: { threshold: 1024, serverNoContextTakeover: true, clientNoContextTakeover: true, concurrencyLimit: 4 }, clientTracking: true });
  const upgradeBudget = budget(48, 8);
  server.on('upgrade', (request, socket, head) => {
    const address = request.socket.remoteAddress;
    const reject = () => { socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n'); };
    if (stopping || !allowedPeer(address, localOnly) || !upgradeBudget(1) || wss.clients.size >= 24 ||
        (request.headers.origin && request.headers.origin !== `ws://${request.headers.host}`)) { reject(); return; }
    // Refuse before allocating a WebSocket/decompression context.
    wss.handleUpgrade(request, socket, head, ws => wss.emit('connection', ws, request));
  });
  const send = (socket, data) => {
    if (socket.readyState !== WebSocket.OPEN) return;
    if (socket.bufferedAmount > 64 * 1024 * 1024) return socket.close(1013, 'Empfaenger zu langsam');
    socket.send(JSON.stringify(data));
  };
  const broadcast = (room, event) => { for (const client of room.clients) send(client, event); };
  const histories = room => { for (const client of room.clients) send(client, { type: 'history', ...room.core.history(client.author), recovery: room.core.recoveries.at(-1)?.id, recoveryCount: room.core.recoveries.length }); };
  const pruneUsers = room => room.core.pruneUsers([...room.leases.keys(), ...[...room.clients].map(client => client.author)]);
  const backupStatus = room => {
    for (const client of room.clients) if (client.author === room.hostAuthor)
      send(client, { type: 'backup', state: room.backupError ? 'error' : 'saved', revision: room.savedRevision ?? 0 });
  };
  const presence = room => broadcast(room, { type: 'presence', members: [...room.clients].map(c => ({ name: c.name, author: c.author })) });
  const noteState = (room, target) => {
    for (const peer of target ? [target] : room.clients) send(peer, { type: 'notes', board: room.core.notes.snapshot(),
      history: room.core.notes.history(peer.author), locks: room.core.notes.presence(), saved: room.notesSaved ?? -1 });
  };
  const hasConnectedHost = () => [...rooms.values()].some(room =>
    [...room.clients].some(client => client.author === room.hostAuthor));
  const hasHostLease = () => [...rooms.values()].some(room => room.leases.has(room.hostAuthor));
  function expireLeases() {
    let lostHost = false;
    for (const room of rooms.values()) {
      for (const [author, lease] of room.leases) if (lease.expires <= Date.now()) {
        room.leases.delete(author); if (author === room.hostAuthor) lostHost = true;
      }
      pruneUsers(room);
      room.core.notes.prune([...room.leases.keys(), ...[...room.clients].map(c => c.author)]);
    }
    if (lostHost && !hasConnectedHost() && !hasHostLease()) server.emit('collabsprite:last-host-left');
  }
  wss.on('connection', (socket, request) => {
    const address = String(request.socket.remoteAddress || '').replace(/^::ffff:/, '');
    if (!allowedPeer(address, localOnly))
      return socket.close(1008, 'Nur lokales Netzwerk oder Radmin VPN');
    socket._socket?.setNoDelay(true);
    const messageBudget = budget(2048, 256), byteBudget = budget(128 * MiB, 16 * MiB);
    const noteBudget = budget(64, 24);
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
      if (stopping || socket.rejected || socket.readyState !== WebSocket.OPEN) return;
      try {
        socket.lastSeen = Date.now();
        if (binary) throw new Error('Nur JSON-Nachrichten erlaubt');
        if (!messageBudget(1) || !byteBudget(data.length)) throw new Error('Zu viele Nachrichten; lokale Kopie bleibt erhalten.');
        if (!socket.room && !isLocal(request.socket.remoteAddress) && data.length > 8192) throw new Error('Anmeldung zu gross');
        const message = JSON.parse(data.toString());
        if (!message || typeof message !== 'object' || Array.isArray(message) || typeof message.type !== 'string') throw new Error('Ungueltige Nachricht');
        if (socket.room && message.type !== 'paint' && data.length > (message.type === 'note' ? 128 * 1024 : 8192)) throw new Error('Steuernachricht zu gross');
        if (!socket.room) {
          if (message.type !== 'hello' || message.protocol !== 5) throw new Error('Unpassende Erweiterungsversion');
          socket.name = String(message.name || 'Kuenstler').replace(/[\x00-\x1f]/g, '').slice(0, 30);
          socket.author = randomBytes(16).toString('hex');
          let room, code, token, resumeToken = randomBytes(32).toString('hex');
          expireLeases();
          if (message.mode === 'host') {
            if (!isLocal(request.socket.remoteAddress)) throw new Error('Sitzungen bitte auf dem Host-PC starten (127.0.0.1)');
            makeRoomSlot();
            const core = new Room(message.snapshot);
            do { code = randomBytes(4).toString('hex').toUpperCase(); } while (rooms.has(code));
            token = randomBytes(16).toString('hex');
            room = { core, tokenHash: hash(token), discoveryToken: token, hostName: socket.name,
              clients: new Set(), leases: new Map(), dirty: true, restored: false, persisted: false, savedAt: Date.now(), hostAuthor: socket.author, acceptingGuests: true };
            rooms.set(code, room);
          } else if (message.mode === 'join') {
            code = String(message.room || '').toUpperCase(); room = rooms.get(code);
            const submitted = Buffer.from(hash(message.token), 'hex');
            if (!room || !timingSafeEqual(Buffer.from(room.tokenHash, 'hex'), submitted)) throw new Error('Sitzung oder Einladungscode stimmt nicht');
            const reclaim = !room.clients.size && !room.leases.size && isLocal(request.socket.remoteAddress);
            if (!reclaim && ![...room.clients].some(client => client.author === room.hostAuthor)) throw new Error('Host ist nicht verbunden');
            if (!reclaim && room.acceptingGuests === false) throw new Error('Host hat weitere Beitritte gesperrt');
            if (room.leases.size >= 8) throw new Error('Maximal 8 Personen pro Sitzung (einschliesslich kurzer Wiederverbindungen)');
            // A restored room becomes discoverable again after a legitimate join.
            room.discoveryToken = String(message.token);
            if (!room.hostName) room.hostName = socket.name;
            // Local host can reclaim host controls after a restart using the saved invitation.
            if (reclaim) room.hostAuthor = socket.author;
          } else if (message.mode === 'resume') {
            code = String(message.room || '').toUpperCase(); room = rooms.get(code);
            const lease = room?.leases.get(message.author);
            if (!lease || typeof message.resumeToken !== 'string' || message.resumeToken.length !== 64 ||
                !timingSafeEqual(Buffer.from(lease.tokenHash, 'hex'), Buffer.from(hash(message.resumeToken), 'hex')))
              throw new Error('Wiederverbindung abgelaufen oder Server neu gestartet. Lokale Ansicht bleibt erhalten.');
            socket.author = message.author; socket.name = lease.name; resumeToken = message.resumeToken;
            // A valid private resume secret replaces a half-open transport,
            // never another user's identity obtained from the public invite.
            if (lease.socket) { lease.socket.superseded = true; room.clients.delete(lease.socket); lease.socket.close(1000, 'Verbindung ersetzt'); }
          } else throw new Error('Unbekannter Verbindungsmodus');
          clearTimeout(greetingTimeout);
          socket.room = room; socket.code = code; room.clients.add(socket); room.core.user(socket.author);
          room.leases.set(socket.author, { tokenHash: hash(resumeToken), name: socket.name, socket, expires: Infinity });
          const actualPort = server.address().port;
          send(socket, { type: 'welcome', protocol: 5, author: socket.author, room: code, host: room.hostAuthor === socket.author, revision: room.core.revision, structure: room.core.structure,
            invite: token ? invite(localOnly ? [] : addresses(), actualPort, code, token) : undefined,
            localOnly, restored: room.restored, acceptingGuests: room.acceptingGuests !== false, snapshot: room.core.snapshot(),
            resumed: message.mode === 'resume', resumeToken, resumeMs, confirmedSeq: room.core.user(socket.author).seq });
          histories(room); presence(room); noteState(room, socket);
          log(`Sitzung ${code}: ${room.clients.size} Person(en) verbunden.`);
          return;
        }
        const room = socket.room;
        if (['note','noteLock','noteSaved'].includes(message.type) && !noteBudget(1)) throw new Error('Zu viele Notizaktionen. Bitte langsamer bearbeiten.');
        if (['append', 'delete', 'deleteMany'].includes(message.type) && message.structure !== room.core.structure)
          throw new OperationRejected('Ebenen/Frames wurden inzwischen geändert. Bitte die Aktion erneut ausführen.');
        let event;
        if (message.type === 'note') {
          const revision = room.core.notes.data.revision;
          const result = room.core.notes.execute(socket.author, message);
          send(socket, { type: 'noteAck', ...result });
          if (room.core.notes.data.revision !== revision) { room.dirty = true; noteState(room); }
          else noteState(room, socket);
          return;
        } else if (message.type === 'noteLock') {
          try { room.core.notes.lock(socket.author, socket.name, message.id, message.field, message.release === true); }
          catch (error) { if (!(error instanceof NoteRejected)) throw error; }
          broadcast(room, { type: 'noteLocks', locks: room.core.notes.presence() }); return;
        } else if (message.type === 'noteSaved') {
          if (socket.author !== room.hostAuthor || !Number.isSafeInteger(message.revision) || message.revision < 0 || message.revision > room.core.notes.data.revision) throw new Error('Ungültige Notizspeicherbestätigung');
          room.notesSaved = message.revision;
          broadcast(room, { type: 'noteSaved', revision: room.notesSaved }); return;
        } else if (message.type === 'paint') event = room.core.paint(socket.author, message.seq, message.patches, message.structure);
        else if (message.type === 'undo' || message.type === 'redo') event = room.core.undoRedo(socket.author, message.type === 'redo');
        else if (message.type === 'append') {
          if (message.structure !== room.core.structure) throw new Error('Dokumentstruktur hat sich geaendert; bitte neu verbinden');
          event = room.core.append(message.kind, message.name, message.source);
        } else if (message.type === 'delete' || message.type === 'deleteMany') {
          if (message.structure !== room.core.structure) throw new Error('Dokumentstruktur hat sich geaendert; bitte neu verbinden');
          const events = room.core.deleteRecoverable(socket.author, message.kind, message.type === 'delete' ? [message.index] : message.indices);
          for (const deletion of events) broadcast(room, deletion);
          room.dirty = true; pruneUsers(room); histories(room);
          return;
        } else if (message.type === 'restore') {
          event = room.core.restoreDeletion(message.recovery);
        } else if (message.type === 'property') {
          if (message.structure !== room.core.structure) throw new Error('Dokumentstruktur hat sich geaendert; bitte neu verbinden');
          event = room.core.setProperty(message.kind, message.index, message.field, message.value);
        } else if (message.type === 'celProperty') {
          if (message.structure !== room.core.structure) throw new Error('Dokumentstruktur hat sich geaendert; bitte neu verbinden');
          event = room.core.setCelProperty(message.layer, message.frame, message.field, message.value);
        } else if (message.type === 'palette') {
          event = room.core.setPalette(message.colors);
        } else if (message.type === 'admission') {
          if (room.hostAuthor !== socket.author || typeof message.open !== 'boolean') throw new Error('Nur der Host darf Beitritte steuern');
          room.acceptingGuests = message.open;
          broadcast(room, { type: 'admission', open: room.acceptingGuests }); return;
        } else if (message.type === 'invite' && room.hostAuthor === socket.author) {
          send(socket, { type: 'invite', invite: invite(localOnly ? [] : addresses(), server.address().port, socket.code, room.discoveryToken) }); return;
        } else if (message.type === 'leave') {
          socket.intentionalLeave = true; socket.rejected = true;
          room.leases.delete(socket.author);
          if (room.hostAuthor === socket.author) for (const peer of room.clients) if (peer !== socket)
            send(peer, { type: 'ended', message: 'Host hat die Sitzung beendet. Bestätigte Beiträge bleiben beim Host.' });
          socket.close(1000, 'Sitzung verlassen'); return;
        } else if (message.type === 'ping') {
          if (message.nonce != null && !(Number.isSafeInteger(message.nonce) || (typeof message.nonce === 'string' && message.nonce.length <= 80))) throw new Error('Ungueltige Bestaetigung');
          send(socket, { type: 'pong', nonce: message.nonce }); return;
        }
        else throw new Error('Unbekannte Nachricht');
        if (event?.type === 'ack') send(socket, event);
        else if (event) {
          broadcast(room, event); room.dirty = true;
        }
        pruneUsers(room); histories(room);
      } catch (error) {
        if (error instanceof OperationRejected && socket.room) {
          send(socket, { type: 'rejected', message: error.message }); return;
        }
        // Ignore already queued messages after the first failure; close() is
        // asynchronous and otherwise further edits could still be applied.
        socket.rejected = true;
        send(socket, { type: 'error', message: error.message });
        socket.close(1008, 'Sitzung wegen ungueltiger Nachricht beendet');
      }
    });
    socket.on('close', () => {
      clearTimeout(greetingTimeout);
      if (socket.room && !socket.superseded) {
        const room = socket.room;
        room.clients.delete(socket);
        room.core.notes.unlock(socket.author);
        broadcast(room, { type: 'noteLocks', locks: room.core.notes.presence() });
        const lease = room.leases.get(socket.author);
        if (socket.intentionalLeave || socket.rejected || stopping) room.leases.delete(socket.author);
        else if (lease?.socket === socket) { lease.socket = null; lease.expires = Date.now() + resumeMs; }
        pruneUsers(room);
        // Membership is ephemeral; pixel contributions and the author's
        // ordered history are part of the document and must survive leaving.
        // Also persist immediately instead of relying only on the 2s timer.
        void save();
        presence(room);
        // Only a managed host process listens for this event. A guest leaving
        // must never stop the server; another active host can keep it alive.
        if (!stopping && socket.author === room.hostAuthor && !hasConnectedHost() && !hasHostLease())
          server.emit('collabsprite:last-host-left');
      }
    });
    socket.on('error', () => {});
  });
  let saving;
  function save() {
    if (!dataDir) return Promise.resolve();
    if (saving) return saving;
    // Serialize the periodic backup and shutdown backup. Otherwise a shutdown
    // can skip a room whose earlier write is still in progress.
    saving = (async () => {
      for (const [code, room] of rooms) {
        if (!room.dirty) continue;
        room.dirty = false; room.saving = true;
        const revision = room.core.revision;
        try {
          const temporary = resolve(dataDir, `${code}.tmp`);
          await writeFile(temporary, JSON.stringify({ tokenHash: room.tokenHash, snapshot: room.core.snapshot() }), { flush: true });
          await rename(temporary, resolve(dataDir, `${code}.json`));
          room.persisted = true;
          room.savedAt = Date.now(); room.savedRevision = revision; room.backupError = false;
          backupStatus(room);
        } catch (error) {
          room.dirty = true;
          if (!room.backupError) { room.backupError = true; backupStatus(room); }
          log(`Backup fehlgeschlagen: ${error.message}`);
        } finally { room.saving = false; }
      }
    })().finally(() => { saving = null; });
    return saving;
  }
  const saveTimer = setInterval(() => void save(), 2000); saveTimer.unref();
  const leaseTimer = setInterval(expireLeases, Math.min(1000, resumeMs)); leaseTimer.unref();
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
  const discoveryBudget = budget(40, 20);
  discovery.on('message', (data, peer) => {
    if (stopping || !discoveryBudget(1)) return;
    if (data.toString() !== 'COLLABSPRITE_DISCOVER_V5') return;
    if (!allowedPeer(peer.address, localOnly)) return;
    const address = replyAddress(peer.address, localOnly);
    if (!address) return;
    const visible = [];
    for (const [code, room] of rooms) {
      if (!room.clients.size || !room.discoveryToken || room.acceptingGuests === false ||
          ![...room.clients].some(client => client.author === room.hostAuthor)) continue;
      visible.push({ name: room.hostName || 'Kuenstler', image: room.core.meta.name,
        invite: invite([address], server.address().port, code, room.discoveryToken) });
    }
    const response = Buffer.from(JSON.stringify({ protocol: 5, rooms: visible }));
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
  return { server, rooms, port: server.address().port, discoveryPort, flush: save, close() {
    if (closePromise) return closePromise;
    stopping = true;
    closePromise = (async () => {
    clearInterval(saveTimer); clearInterval(heartbeat); clearInterval(leaseTimer);
    if (discoveryPort) discovery.close();
    for (const socket of wss.clients) socket.terminate();
    // If an older snapshot was already writing, wait for it and flush the
    // final dirty revision once more after preventing all new mutations.
    if (saving) await saving;
    await save();
    await new Promise(resolve => wss.close(resolve));
    await new Promise(resolve => server.close(resolve));
    })();
    return closePromise;
  } };
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const mode = process.argv.includes('--local') ? 'local' : 'global';
  const requestedPort = process.argv.find(arg => arg.startsWith('--port='));
  const port = Number(requestedPort?.slice(7) || process.env.COLLABSPRITE_PORT || (mode === 'local' ? 8765 : 8766));
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Ungueltiger Serverport');
  const service = await startServer({ port, host: mode === 'local' ? '127.0.0.1' : '0.0.0.0' });
  let stopping = false;
  const stop = async () => { if (stopping) return; stopping = true; await service.close(); };
  if (process.argv.includes('--managed')) {
    service.server.on('collabsprite:last-host-left', () => void stop());
    let idleSince = Date.now();
    const idleTimer = setInterval(() => {
      if ([...service.rooms.values()].some(room => room.clients.size > 0 || room.leases.size > 0)) idleSince = Date.now();
      else if (Date.now() - idleSince > 30000) void stop();
    }, 1000);
    idleTimer.unref();
  }
  process.on('SIGINT', stop); process.on('SIGTERM', stop);
}
