import test from 'node:test';
import assert from 'node:assert/strict';
import { Room, encodeRuns } from '../core.mjs';
export const snapshot = () => ({ format: 1, name: 'Test', width: 4, height: 4,
  layers: [{ name: 'Gemeinsam' }], frames: [100], cels: [], palette: [] });
const paint = (room, author, seq, runs, layer = 1, frame = 1) => room.paint(author, seq, [{ layer, frame, runs }]);
const pixels = room => [...room.cells.get('1:1').pixels];
test('Own undo/redo preserves newer overlapping peer pixels', () => {
  const r = new Room(snapshot());
  paint(r, 'A', 1, [0, 2, 10]);
  paint(r, 'B', 1, [0, 1, 20, 2, 1, 20]);
  r.undoRedo('A');
  assert.deepEqual(pixels(r).slice(0, 3), [20, 0, 20]);
  r.undoRedo('A', true);
  assert.deepEqual(pixels(r).slice(0, 3), [20, 10, 20]);
  r.undoRedo('B');
  assert.deepEqual(pixels(r).slice(0, 3), [10, 10, 0]);
  r.undoRedo('A');
  assert.deepEqual(pixels(r).slice(0, 3), [0, 0, 0]);
  r.undoRedo('B', true);
  assert.deepEqual(pixels(r).slice(0, 3), [20, 0, 20]);
});
test('Transparent paint, equal-valued contributions, new edit clears only own redo', () => {
  const r = new Room(snapshot());
  paint(r, 'A', 1, [0, 1, 0xffaabbcc]); paint(r, 'B', 1, [0, 1, 0xffaabbcc]);
  r.undoRedo('A');assert.equal(pixels(r)[0], 0xffaabbcc);
  paint(r, 'B', 2, [0, 1, 0]);assert.equal(pixels(r)[0], 0);
  r.undoRedo('B');assert.equal(pixels(r)[0], 0xffaabbcc);
  paint(r, 'A', 2, [1, 1, 10]);assert.deepEqual(r.history('A'), {undo:1,redo:0});
  assert.equal(r.history('B').redo, 1);
});
test('Whole operation validation is atomic and sequence strict', () => {
  const r = new Room(snapshot());
  assert.throws(() => r.paint('A', 1, [{layer:1,frame:1,runs:[0,1,5]}, {layer:99,frame:1,runs:[0,1,10]}]));
  assert.equal(pixels(r)[0],0);assert.equal(r.user('A').seq,0);
  assert.throws(() => paint(r,'A',2,[0,1,1]));
  assert.throws(() => paint(r,'A',1,[0,3,1,1,1,2]));
  assert.throws(() => paint(r,'A',1,[0,1,-1]));
});
test('History compaction preserves visible state and immutable base', () => {
  const r=new Room(snapshot(),{historyLimit:2});
  paint(r,'A',1,[0,1,1]);paint(r,'B',1,[0,1,2]);r.undoRedo('A');
  paint(r,'B',2,[1,1,3]);assert.equal(r.history('A').redo,0);
  r.undoRedo('B');r.undoRedo('B');assert.equal(pixels(r)[0],0);
  r.undoRedo('B',true);assert.equal(pixels(r)[0],2);
});
test('Append shared layer/frame keeps existing history and blank cells', () => {
  const r=new Room(snapshot());paint(r,'A',1,[0,1,1]);
  assert.equal(r.append('layer','Zwei').index,2);
  assert.equal(r.append('frame').index,2);
  paint(r,'B',1,[0,1,99],2,2);r.undoRedo('A');
  assert.equal(r.cells.get('2:2').pixels[0],99);
  const restored=new Room(r.snapshot());
  assert.deepEqual(restored.snapshot(),r.snapshot());
});
test('Guests can copy layers and frames without taking over another author’s undo', () => {
  const r=new Room(snapshot());
  paint(r,'A',1,[0,1,0xff112233]);
  const layerEvent=r.append('layer','Kopie',1);
  assert.deepEqual(layerEvent.cels[0].runs,[0,1,0xff112233]);
  const frameEvent=r.append('frame',null,1);
  assert.equal(frameEvent.cels.length,2);
  assert.equal(r.cells.get('2:2').pixels[0],0xff112233);
  paint(r,'B',1,[1,1,0xff556677],2,2);
  r.undoRedo('A');
  assert.equal(r.cells.get('1:1').pixels[0],0);
  assert.equal(r.cells.get('2:2').pixels[0],0xff112233);
  assert.equal(r.cells.get('2:2').pixels[1],0xff556677);
});
test('Compact run encoding is lossless', () => {
  assert.deepEqual(encodeRuns([0,0,5,5,0,9],true),[2,2,5,5,1,9]);
});
