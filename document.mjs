// Three-way document transactions. Unchanged fields always come from the
// server, never from a stale client snapshot. Destructive conflicts are atomic.
import { isDeepStrictEqual as equal } from 'node:util';

export class DocumentConflict extends Error {}
const conflict = () => { throw new DocumentConflict('Diese Änderung überschneidet sich mit neueren Beiträgen. Deine lokale Fassung bleibt erhalten.'); };
const clone = value => value === undefined ? undefined : structuredClone(value);

function merge(before, after, current) {
  if (equal(before, after)) return clone(current);
  if (before === undefined) { if (current !== undefined) conflict(); return clone(after); }
  if (after === undefined) { if (!equal(before, current)) conflict(); return undefined; }
  if (before && after && current && !Array.isArray(before) && typeof before === 'object' && typeof after === 'object') {
    const result = {};
    for (const key of new Set([...Object.keys(before), ...Object.keys(after), ...Object.keys(current)])) {
      const value = merge(before[key], after[key], current[key]);
      if (value !== undefined) result[key] = value;
    }
    return result;
  }
  if (!equal(before, current)) conflict();
  return clone(after);
}

export function documentState(s) {
  const layers = Object.fromEntries(s.layers.map(l => [l.id, { ...l, parent: l.parent ? s.layers[l.parent - 1].id : null }]));
  const frames = Object.fromEntries(s.frameIds.map((id, i) => [id, s.frames[i]]));
  const cells = {};
  for (const c of s.cels) cells[`${s.layers[c.layer - 1].id}:${s.frameIds[c.frame - 1]}`] = {
    runs: c.runs, opacity: c.opacity, z: c.z, link: c.link || null,
  };
  const tags = Object.fromEntries((s.tags || []).map(t => [t.id, { ...t, from: s.frameIds[t.from - 1], to: s.frameIds[t.to - 1] }]));
  return { width: s.width, height: s.height, layers, frames, cells, tags,
    layerOrder: s.layers.map(l => l.id), frameOrder: s.frameIds, palette: s.palette };
}

export function mergeDocument(before, after, current) {
  const a = documentState(before), b = documentState(after), c = documentState(current);
  // Canvas transformations use a different coordinate system. Even an edit to
  // an otherwise untouched cell must not silently change meaning under resize.
  if ((a.width !== b.width || a.height !== b.height) && !equal(a, c)) conflict();
  const result = merge(a, b, c);
  const li = new Map(result.layerOrder.map((id, i) => [id, i + 1]));
  const fi = new Map(result.frameOrder.map((id, i) => [id, i + 1]));
  if (li.size !== Object.keys(result.layers).length || fi.size !== Object.keys(result.frames).length) conflict();
  const layers = result.layerOrder.map(id => {
    const l = result.layers[id];
    if (!l || (l.parent && !li.has(l.parent))) conflict();
    return { ...l, parent: l.parent ? li.get(l.parent) : 0 };
  });
  const cels = Object.entries(result.cells).map(([key, cel]) => {
    const [layerId, frameId] = key.split(':');
    if (!li.has(layerId) || !fi.has(frameId)) conflict();
    return { ...cel, layer: li.get(layerId), frame: fi.get(frameId) };
  });
  const tags = Object.values(result.tags).map(t => {
    if (!fi.has(t.from) || !fi.has(t.to)) conflict();
    return { ...t, from: fi.get(t.from), to: fi.get(t.to) };
  });
  return { ...current, width: result.width, height: result.height, layers,
    frameIds: result.frameOrder, frames: result.frameOrder.map(id => result.frames[id]),
    cels, tags, palette: result.palette };
}

export { equal as documentEqual };
export function changedPaths(a,b,prefix='') {
  if (equal(a,b)) return [];
  if (a && b && typeof a==='object' && typeof b==='object' && !Array.isArray(a) && !Array.isArray(b))
    return [...new Set([...Object.keys(a),...Object.keys(b)])].flatMap(k=>changedPaths(a[k],b[k],`${prefix}/${k}`));
  return [prefix];
}
