import test from 'node:test';
import assert from 'node:assert/strict';
import { Notes, emptyNotes, validateNotes, FIELDS } from '../notes.mjs';
import { Room } from '../core.mjs';
const id = n => n.toString(16).padStart(32, '0');
const card = (n, parent = '') => ({ id: id(n), parent, title: 'Hexe', text: '', color: '', status: 'idea', x: 30, y: 30, versions: Object.fromEntries(FIELDS.map(f => [f, 0])) });
const run = (b, author, op) => b.execute(author, { seq: b.user(author).seq + 1, ...op });
const create = (b, author, c) => run(b, author, { action: 'patch', patches: [{ id: c.id, expected: false, value: c }] });
const set = (b, author, n, field, value) => run(b, author, { action: 'patch', patches: [{ id: id(n), field, value, expected: b.data.cards.find(c => c.id === id(n)).versions[field] }] });
test('Notes: field revisions, personal undo and foreign ABA conflict protection', () => {
  const b = new Notes();assert.ok(create(b, 'host', card(1)).ok);
  assert.ok(set(b, 'a', 1, 'title', 'Hexe A').ok);
  assert.ok(set(b, 'b', 1, 'text', 'Kleid violett').ok);
  assert.ok(run(b, 'a', { action: 'undo' }).ok);
  assert.equal(b.data.cards[0].title, 'Hexe');assert.equal(b.data.cards[0].text, 'Kleid violett');
  assert.ok(run(b, 'a', { action: 'redo' }).ok);
  set(b, 'b', 1, 'title', 'Fremd');set(b, 'b', 1, 'title', 'Hexe A');
  assert.equal(run(b, 'a', { action: 'undo' }).ok, false);
});
test('Notes: atomic validation, cycle and size protection', () => {
  const b = new Notes();create(b, 'a', card(1));create(b, 'a', card(2, id(1)));
  const before = b.snapshot();assert.equal(set(b, 'a', 1, 'parent', id(2)).ok, false);assert.deepEqual(b.snapshot(), before);
  assert.equal(set(b, 'a', 1, 'text', 'a'.repeat(2049)).ok, false);
  assert.throws(() => validateNotes({ ...emptyNotes(), cards: [card(1), card(1)] }));
  assert.throws(() => validateNotes({ ...emptyNotes(), cards: [card(1, id(9))] }));
  const result = run(b, 'a', { action: 'patch', patches: [
    { id: id(1), field: 'title', expected: b.data.cards[0].versions.title, value: 'good' },
    { id: id(2), field: 'x', expected: 0, value: 1e10 }] });
  assert.equal(result.ok, false);assert.deepEqual(b.snapshot(), before);
});
test('Notes: multiple own undos/redos traverse the history without invalidating it', () => {
  const b=new Notes();create(b,'a',card(1));set(b,'a',1,'title','Two');set(b,'a',1,'title','Three');
  assert.ok(run(b,'a',{action:'undo'}).ok);assert.ok(run(b,'a',{action:'undo'}).ok);
  assert.equal(b.data.cards[0].title,'Hexe');assert.ok(run(b,'a',{action:'undo'}).ok);assert.equal(b.data.cards.length,0);
  assert.ok(run(b,'a',{action:'redo'}).ok);assert.ok(run(b,'a',{action:'redo'}).ok);assert.ok(run(b,'a',{action:'redo'}).ok);
  assert.equal(b.data.cards[0].title,'Three');
});
test('Notes: text lease, expiry, disconnect and idempotent lost acknowledgement', () => {
  const b = new Notes();create(b, 'a', card(1));b.lock('a', 'Host', id(1), 'text');
  assert.equal(set(b, 'b', 1, 'text', 'no').ok, false);assert.ok(set(b, 'b', 1, 'color', '#aabbcc').ok);
  b.expire(Date.now() + 16000);assert.ok(set(b, 'b', 1, 'text', 'yes').ok);
  const snapshot = b.snapshot(),seq = b.user('b').seq;
  assert.deepEqual(b.execute('b', { seq, action: 'undo' }), { ok: true, seq });assert.deepEqual(b.snapshot(), snapshot);
  b.lock('b', 'Gast', id(1), 'text');b.unlock('b');assert.deepEqual(b.presence(), []);
});
test('Notes: deletion/restore preserves unrelated peer edits, tree links and durable trash', () => {
  const b = new Notes();create(b, 'a', card(1));create(b, 'a', card(2, id(1)));create(b, 'b', card(3));
  const target=b.data.cards[0];assert.ok(run(b, 'a', { action: 'delete', id: target.id, versions: target.versions, revision: b.data.revision, children: true }).ok);
  set(b, 'b', 3, 'text', 'Still here');const persisted = new Notes(b.snapshot());
  assert.ok(run(persisted, 'b', { action: 'restore', id: persisted.data.trash[0].id }).ok);
  assert.equal(persisted.data.cards.find(c=>c.id===id(2)).parent,id(1));assert.equal(persisted.data.cards.find(c=>c.id===id(3)).text,'Still here');
});
test('Notes: keep children on deletion, restore limits and stale subtree refusal', () => {
  const b=new Notes();create(b,'a',card(1));create(b,'a',card(2,id(1)));
  const c=b.data.cards[0],revision=b.data.revision;set(b,'b',2,'text','new child edit');
  assert.equal(run(b,'a',{action:'delete',id:c.id,versions:c.versions,revision,children:true}).ok,false);
  assert.ok(run(b,'a',{action:'delete',id:c.id,versions:c.versions,revision:b.data.revision,children:false}).ok);
  assert.equal(b.data.cards[0].parent,'');assert.ok(run(b,'a',{action:'undo'}).ok);assert.equal(b.data.cards.find(c=>c.id===id(2)).parent,id(1));
});
test('Notes: pixel undo and structural restore never roll back the board', () => {
  const room=new Room({format:1,width:2,height:2,layers:[{name:'A'},{name:'B'}],frames:[100],cels:[],palette:[]});
  create(room.notes,'guest',card(1));room.paint('host',1,[{layer:1,frame:1,runs:[0,1,123]}],0);
  room.deleteRecoverable('host','layer',[2]);set(room.notes,'guest',1,'text','After deletion');
  room.restoreDeletion(room.recoveries.at(-1).id);room.undoRedo('host',false);
  assert.equal(room.snapshot().notes.cards[0].text,'After deletion');
});
