// Shared ideas, deliberately separate from the pixel contribution history.
import { randomBytes } from 'node:crypto';
import { isDeepStrictEqual } from 'node:util';
export const NOTE_LIMITS = { cards: 128, title: 120, text: 2048, bytes: 524288, history: 32, historyBytes: 4 * 1024 * 1024, trash: 20, depth: 24 };
export const FIELDS = ['title', 'text', 'parent', 'x', 'y', 'color', 'status'];
export class NoteRejected extends Error {}
const reject = text => { throw new NoteRejected(text); };
const clone = value => structuredClone(value);
const idOK = id => typeof id === 'string' && /^[a-f0-9]{32}$/.test(id);
const int = (v, min, max) => Number.isSafeInteger(v) && v >= min && v <= max;
const same = isDeepStrictEqual;
export function emptyNotes() { return { format: 1, revision: 0, cards: [], trash: [] }; }
function fieldOK(field, v) {
  if (field === 'title' || field === 'text') return typeof v === 'string' && Buffer.byteLength(v) <= NOTE_LIMITS[field] && !/[\x00-\x08\x0b-\x1f]/.test(v);
  if (field === 'parent') return v === '' || idOK(v);
  if (field === 'x' || field === 'y') return int(v, -10000, 10000);
  if (field === 'color') return typeof v === 'string' && /^(|#[0-9A-Fa-f]{6})$/.test(v);
  if (field === 'status') return ['idea', 'decided', 'done'].includes(v);
  return false;
}
function card(input, revision) {
  if (!input || !idOK(input.id)) reject('Ungültige Notizkennung.');
  const c = { id: input.id, versions: {} };
  for (const f of FIELDS) {
    if (!fieldOK(f, input[f]) || !int(input.versions?.[f], 0, revision)) reject('Ungültige Notizfelder oder Versionen.');
    c[f] = input[f]; c.versions[f] = input.versions[f];
  }
  return c;
}
export function validateNotes(input) {
  if (input == null) return emptyNotes();
  if (input.format !== 1 || !int(input.revision, 0, 1e12) || !Array.isArray(input.cards) || input.cards.length > NOTE_LIMITS.cards ||
      !Array.isArray(input.trash) || input.trash.length > NOTE_LIMITS.trash) reject('Notizformat oder Größenlimit stimmt nicht.');
  const output = { format: 1, revision: input.revision, cards: input.cards.map(c => card(c, input.revision)), trash: [] };
  const map = new Map(output.cards.map(c => [c.id, c]));
  if (map.size !== output.cards.length) reject('Doppelte Notizkennung.');
  for (const c of output.cards) {
    let current = c, depth = 0;
    const seen = new Set();
    while (current) {
      if (seen.has(current.id) || ++depth > NOTE_LIMITS.depth) reject('Notizverbindung bildet einen Kreis oder zu viele Unterkarten.');
      seen.add(current.id);
      if (current.parent && !map.has(current.parent)) reject('Übergeordnete Karte fehlt.');
      current = map.get(current.parent);
    }
  }
  const trashIds = new Set();
  for (const t of input.trash) {
    if (!t || !idOK(t.id) || trashIds.has(t.id) || !Array.isArray(t.cards) || !t.cards.length || t.cards.length > NOTE_LIMITS.cards) reject('Ungültiger Notizpapierkorb.');
    trashIds.add(t.id);
    const cards = t.cards.map(c => card(c, input.revision));
    if (new Set(cards.map(c => c.id)).size !== cards.length) reject('Doppelte gelöschte Karte.');
    output.trash.push({ id: t.id, cards });
  }
  if (Buffer.byteLength(JSON.stringify(output)) > NOTE_LIMITS.bytes) reject('Notizwand ist voll (512 KiB).');
  return output;
}
export class Notes {
  constructor(input) { this.data = validateNotes(input); this.users = new Map(); this.locks = new Map(); }
  snapshot() { return clone(this.data); }
  user(author) {
    if (!this.users.has(author)) this.users.set(author, { seq: 0, undo: [], redo: [] });
    return this.users.get(author);
  }
  history(author) { const u = this.user(author); return { undo: u.undo.length, redo: u.redo.length, seq: u.seq }; }
  expire(now = Date.now()) { for (const [k, l] of this.locks) if (l.until <= now) this.locks.delete(k); }
  unlock(author) { for (const [k, l] of this.locks) if (l.author === author) this.locks.delete(k); }
  prune(authors) { for (const id of this.users.keys()) if (!authors.includes(id)) { this.users.delete(id); this.unlock(id); } }
  lock(author, name, id, field, release = false) {
    this.expire();
    if (!idOK(id) || !FIELDS.includes(field) || !this.data.cards.some(c => c.id === id)) reject('Karte nicht mehr vorhanden.');
    const key = id + ':' + field, old = this.locks.get(key);
    if (old && old.author !== author) reject('Dieses Feld wird gerade bearbeitet.');
    if (release) this.locks.delete(key);
    else this.locks.set(key, { id, field, author, name, until: Date.now() + 15000 });
  }
  presence() { this.expire(); return [...this.locks.values()].map(({ until, ...l }) => l); }
  checkLock(author, id, field) {
    this.expire();
    for (const l of this.locks.values()) if (l.id === id && (!field || l.field === field) && l.author !== author)
      reject('Karte wird gerade bearbeitet. Bitte kurz warten.');
  }
  // Atomic field patches. History carries revisions, not just equal strings:
  // another person's edit-away-and-back must not be undone by an old action.
  commit(author, patches) {
    const next = this.snapshot(), map = new Map(next.cards.map(c => [c.id, c])), inverse = [];
    if (!patches.length || patches.length > NOTE_LIMITS.cards * FIELDS.length) reject('Keine gültige Notizänderung.');
    const touched = new Set(), revision = next.revision + 1;
    for (const p of patches) {
      if (!p || !idOK(p.id)) reject('Ungültige Notizänderung.');
      const key = p.id + ':' + (p.field || '*');
      if (touched.has(key) || touched.has(p.id + ':*') || (!p.field && [...touched].some(k => k.startsWith(p.id + ':')))) reject('Doppelte Notizänderung.');
      touched.add(key); this.checkLock(author, p.id, p.field);
      const old = map.get(p.id);
      if (p.field) {
        if (!old || !FIELDS.includes(p.field) || old.versions[p.field] !== p.expected || !fieldOK(p.field, p.value)) reject('Karte wurde geändert. Dein Entwurf bleibt erhalten; bitte vergleichen.');
        inverse.push({ id: p.id, field: p.field, expected: revision, value: old[p.field], restoreVersion: old.versions[p.field] });
        old[p.field] = p.value; old.versions[p.field] = revision;
      } else {
        if (!same(old || false, p.expected || false)) reject('Karte wurde inzwischen geändert.');
        let value = false;
        if (p.value) {
          value = card(p.value, revision);
          if (value.id !== p.id) reject('Notizkennung stimmt nicht.');
          for (const f of FIELDS) value.versions[f] = revision;
          map.set(p.id, value);
        } else map.delete(p.id);
        inverse.push({ id: p.id, expected: value, value: old || false });
      }
    }
    next.cards = [...map.values()]; next.revision = revision;
    this.data = validateNotes(next);
    return inverse.reverse();
  }
  execute(author, message) {
    const u = this.user(author);
    if (!int(message.seq, 1, 1e12)) reject('Ungültige Notizsequenz.');
    if (message.seq === u.seq) return clone(u.reply); // one outstanding action per client
    if (message.seq !== u.seq + 1) reject('Notizsequenz unterbrochen.');
    let reply;
    try {
      const action = message.action;
      let inverse;
      if (action === 'undo' || action === 'redo') {
        const from = action === 'undo' ? u.undo : u.redo, to = action === 'undo' ? u.redo : u.undo;
        if (!from.length) reject('Keine eigene Notizänderung im Verlauf.');
        const applied = from.at(-1);
        inverse = this.commit(author, applied); from.pop();
        // Our own reversal restores a previous field state at a new revision.
        // Rebase only our retained expectations for precisely that old state.
        for (const p of applied) {
          const restored = p.field ? { [p.field]: p.restoreVersion } : p.value?.versions;
          for (const [field, version] of Object.entries(restored || {})) for (const entry of [...u.undo, ...u.redo]) for (const q of entry) {
            if (q.id !== p.id) continue;
            if (q.field === field && q.expected === version) q.expected = this.data.revision;
            if (!q.field && q.expected?.versions?.[field] === version) q.expected.versions[field] = this.data.revision;
          }
        }
        to.push(inverse);
      } else if (action === 'patch') {
        if (!Array.isArray(message.patches)) reject('Notizänderungen fehlen.');
        inverse = this.commit(author, message.patches);
      } else if (action === 'delete') {
        const target = this.data.cards.find(c => c.id === message.id);
        if (!target || !same(target.versions, message.versions)) reject('Karte wurde inzwischen geändert.');
        const ids = new Set([target.id]);
        if (message.children === true) {
          let added = true;
          while (added) { added = false; for (const c of this.data.cards) if (ids.has(c.parent) && !ids.has(c.id)) { ids.add(c.id); added = true; } }
        }
        const removed = this.data.cards.filter(c => ids.has(c.id));
        // Require the board revision for subtree deletion: no unseen child edits.
        if (message.revision !== this.data.revision) reject('Die Wand wurde geändert. Löschung bitte erneut prüfen.');
        const patches = removed.map(c => ({ id: c.id, expected: c, value: null }));
        for (const c of this.data.cards) if (!ids.has(c.id) && ids.has(c.parent)) patches.push({ id: c.id, field: 'parent', expected: c.versions.parent, value: target.parent });
        const saved = this.snapshot();
        inverse = this.commit(author, patches);
        this.data.trash.push({ id: randomBytes(16).toString('hex'), cards: clone(removed) });
        while (this.data.trash.length > NOTE_LIMITS.trash || Buffer.byteLength(JSON.stringify(this.data)) > NOTE_LIMITS.bytes) this.data.trash.shift();
        try { this.data = validateNotes(this.data); } catch (e) { this.data = saved; throw e; }
      } else if (action === 'restore') {
        const t = this.data.trash.find(t => t.id === message.id);
        if (!t) reject('Gelöschte Karten nicht mehr vorhanden.');
        const ids = new Set([...this.data.cards, ...t.cards].map(c => c.id));
        const patches = t.cards.map(c => ({ id: c.id, expected: null, value: { ...c, parent: ids.has(c.parent) ? c.parent : '' } }));
        inverse = this.commit(author, patches);
        this.data.trash = this.data.trash.filter(item => item.id !== t.id);
      } else reject('Unbekannte Notizaktion.');
      if (!['undo', 'redo'].includes(action)) { u.undo.push(inverse); if (u.undo.length > NOTE_LIMITS.history) u.undo.shift(); u.redo = []; }
      while (Buffer.byteLength(JSON.stringify([u.undo, u.redo])) > NOTE_LIMITS.historyBytes) {
        if (u.undo.length) u.undo.shift(); else u.redo.shift();
      }
      reply = { ok: true, seq: message.seq };
    } catch (error) {
      if (!(error instanceof NoteRejected)) throw error;
      reply = { ok: false, seq: message.seq, message: error.message };
    }
    u.seq = message.seq; u.reply = reply;
    return clone(reply);
  }
}
