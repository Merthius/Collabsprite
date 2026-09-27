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
  assert.equal(set(b, 'a', 1, 'text', 'a'.repeat(4097)).ok, false);
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

test('Magnetic boxes: bounded RGBA references, list styles, stack uniqueness and legacy migration', () => {
  const original={format:1,revision:0,cards:[card(1),card(2,id(1)),card(3,id(1))],trash:[]};
  const migrated=validateNotes(original);
  assert.equal(migrated.format,2);assert.equal(migrated.cards[2].parent,id(2));assert.equal(original.cards[2].parent,id(1));
  assert.equal(migrated.cards[2].title,'Hexe');
  const b=new Notes(migrated);
  assert.equal(create(b,'guest',card(4,id(1))).ok,false,'A box cannot have two magnetic children');
  assert.equal(set(b,'guest',1,'parent',id(3)).ok,false,'Cycle accepted');
  const picture={...card(4),kind:'image',image:{width:512,height:512,pixels:'abcdef12'.repeat(512*512)}};
  assert.ok(create(b,'guest',picture).ok);assert.deepEqual(new Notes(b.snapshot()).data.cards[3].image,picture.image);
  assert.equal(set(b,'guest',4,'image',{width:513,height:1,pixels:'00000000'.repeat(513)}).ok,false);
  assert.equal(set(b,'guest',4,'image',{width:1,height:1,pixels:'000000zz'}).ok,false);
  assert.equal(set(b,'guest',4,'image',{width:1,height:1,pixels:'00000000',path:'private.png'}).ok,false);
  assert.equal(set(b,'guest',4,'image',false).ok,false);
  const list={...card(5),kind:'list',listStyle:'number',text:'Farbe\nBlau',checks:'01'};
  assert.ok(create(b,'guest',list).ok);assert.equal(set(b,'guest',5,'checks','maybe').ok,false);
  assert.equal(set(b,'guest',5,'text','x\n'.repeat(128)).ok,false);
  assert.ok(run(b,'guest',{action:'undo'}).ok);assert.ok(run(b,'guest',{action:'redo'}).ok);
});

test('Marquee multi-edit stays atomic on the server and keeps foreign text during own undo', () => {
  const b = new Notes();
  for (const c of [card(1), card(2, id(1)), card(3)]) assert.ok(create(b, 'host', c).ok);
  const first = b.data.cards.find(c => c.id === id(1));
  const third = b.data.cards.find(c => c.id === id(3));
  assert.ok(run(b, 'guest', { action: 'patch', patches: [
    { id: id(1), field: 'x', expected: first.versions.x, value: 90 },
    { id: id(3), field: 'x', expected: third.versions.x, value: 150 },
  ] }).ok);
  assert.ok(set(b, 'host', 3, 'text', 'Fremde Idee').ok);
  assert.ok(run(b, 'guest', { action: 'undo' }).ok);
  assert.equal(b.data.cards.find(c => c.id === id(1)).x, 30);
  assert.equal(b.data.cards.find(c => c.id === id(3)).x, 30);
  assert.equal(b.data.cards.find(c => c.id === id(3)).text, 'Fremde Idee');
  const cloned = [card(4), card(5, id(4))];
  assert.ok(run(b, 'guest', { action: 'patch', patches: cloned.map(c => ({ id: c.id, expected: false, value: c })) }).ok);
  assert.ok(run(b, 'guest', { action: 'undo' }).ok);
  assert.equal(b.data.cards.length, 3);
  const before=b.snapshot();
  assert.equal(run(b, 'guest', { action: 'patch', patches: [
    { id: id(1), expected: before.cards[0], value: false },
    { id: id(3), expected: before.cards[2], value: false },
    { id: id(2), field: 'parent', expected: before.cards[1].versions.parent, value: '' },
    { id: id(2), field: 'x', expected: before.cards[1].versions.x, value: 100000 },
  ] }).ok, false);
  assert.deepEqual(b.snapshot(), before, 'A rejected group must not partly delete elements');
  assert.ok(run(b, 'guest', { action: 'patch', patches: [
    { id: id(1), expected: before.cards[0], value: false },
    { id: id(3), expected: before.cards[2], value: false },
    { id: id(2), field: 'parent', expected: before.cards[1].versions.parent, value: '' },
  ] }).ok);
  assert.equal(b.data.cards.length, 1);
  assert.equal(b.data.cards[0].parent, '');
  assert.ok(run(b, 'guest', { action: 'undo' }).ok);
  assert.equal(b.data.cards.length, 3);
  assert.equal(b.data.cards.find(c => c.id === id(2)).parent, id(1));
  assert.equal(b.data.cards.find(c => c.id === id(3)).text, 'Fremde Idee');
});
