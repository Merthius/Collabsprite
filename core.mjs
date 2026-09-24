// Ordered pixel contributions. Undo toggles only the requesting author's operation.
// It never applies a whole-image snapshot over another participant's work.
export const LIMITS = { side: 1024, layers: 32, frames: 120, pixels: 4_194_304, changes: 1_048_576, history: 256, historyPixels: 500_000 };
export function integer(value, min, max, label) {
  if (!Number.isSafeInteger(value) || value < min || value > max) throw new Error(`Ungueltig: ${label}`);
  return value;
}
export function encodeRuns(values, sparse = false) {
  const runs = [];
  for (let i = 0; i < values.length;) {
    const value = values[i];
    let end = i + 1;
    while (end < values.length && values[end] === value) end++;
    if (!sparse || value !== 0) runs.push(i, end - i, value);
    i = end;
  }
  return runs;
}
export function validateRuns(runs, size) {
  if (!Array.isArray(runs) || runs.length % 3 || runs.length > size * 3) throw new Error('Ungueltige Pixelbereiche');
  let previousEnd = 0, count = 0;
  for (let i = 0; i < runs.length; i += 3) {
    const start = integer(runs[i], 0, size - 1, 'Pixelposition');
    const length = integer(runs[i + 1], 1, size - start, 'Bereich');
    integer(runs[i + 2], 0, 0xffffffff, 'RGBA');
    if (start < previousEnd) throw new Error('Pixelbereiche ueberlappen oder sind unsortiert');
    previousEnd = start + length;
    count += length;
  }
  return count;
}
export function validateSnapshot(input) {
  if (!input || input.format !== 1) throw new Error('Unbekanntes Sitzungsformat');
  const width = integer(input.width, 1, LIMITS.side, 'Breite');
  const height = integer(input.height, 1, LIMITS.side, 'Hoehe');
  if (!Array.isArray(input.layers) || !input.layers.length || input.layers.length > LIMITS.layers) throw new Error('Maximal 32 Ebenen');
  if (!Array.isArray(input.frames) || !input.frames.length || input.frames.length > LIMITS.frames) throw new Error('Maximal 120 Frames');
  const frames = input.frames.map(ms => integer(ms, 1, 65535, 'Frame-Dauer'));
  const layers = input.layers.map((layer, i) => ({
    name: String(layer.name || `Ebene ${i + 1}`).slice(0, 100),
    group: layer.group === true,
    parent: integer(layer.parent ?? 0, 0, i, 'Elterngruppe'),
    opacity: integer(layer.opacity ?? 255, 0, 255, 'Deckkraft'),
    blend: integer(layer.blend ?? 3, 0, 31, 'Mischmodus'),
    visible: layer.visible !== false,
    editable: layer.editable !== false,
    continuous: layer.continuous === true
  }));
  layers.forEach(layer => { if (layer.parent && !layers[layer.parent - 1].group) throw new Error('Ungueltige Ebenengruppe'); });
  const rasterCount = layers.filter(l => !l.group).length;
  if (!rasterCount || rasterCount * frames.length * width * height > LIMITS.pixels) throw new Error('Sitzung zu gross: maximal 4 Millionen Cel-Pixel');
  if (!Array.isArray(input.cels) || input.cels.length > rasterCount * frames.length) throw new Error('Ungueltige Cels');
  const seen = new Set();
  const cels = input.cels.map(cel => {
    const layer = integer(cel.layer, 1, layers.length, 'Cel-Ebene');
    const frame = integer(cel.frame, 1, frames.length, 'Cel-Frame');
    if (layers[layer - 1].group || seen.has(`${layer}:${frame}`)) throw new Error('Doppeltes oder ungueltiges Cel');
    seen.add(`${layer}:${frame}`);
    validateRuns(cel.runs, width * height);
    return { layer, frame, runs: [...cel.runs], opacity: integer(cel.opacity ?? 255, 0, 255, 'Cel-Deckkraft'), z: integer(cel.z ?? 0, -32768, 32767, 'Cel-Z') };
  });
  const palette = Array.isArray(input.palette) ? input.palette.slice(0, 256).map(v => integer(v, 0, 0xffffffff, 'Palettenfarbe')) : [];
  return { format: 1, name: String(input.name || 'Gemeinsam').slice(0, 100), width, height, layers, frames, cels, palette };
}
export class Room {
  constructor(snapshot, options = {}) {
    this.meta = validateSnapshot(snapshot);
    this.size = this.meta.width * this.meta.height;
    this.cells = new Map();
    this.users = new Map();
    this.operations = [];
    this.historyPixels = 0;
    this.revision = 0;
    this.structure = 0;
    this.historyLimit = options.historyLimit ?? LIMITS.history;
    this.pixelLimit = options.pixelLimit ?? LIMITS.historyPixels;
    for (let l = 1; l <= this.meta.layers.length; l++) {
      if (!this.meta.layers[l - 1].group) for (let f = 1; f <= this.meta.frames.length; f++) this.addCell(l, f);
    }
    for (const cel of this.meta.cels) {
      const cell = this.cells.get(`${cel.layer}:${cel.frame}`);
      cell.opacity = cel.opacity; cell.z = cel.z;
      for (let i = 0; i < cel.runs.length; i += 3) cell.pixels.fill(cel.runs[i + 2], cel.runs[i], cel.runs[i] + cel.runs[i + 1]);
      cell.base.set(cell.pixels);
    }
    this.meta.cels = [];
  }
  addCell(layer, frame) {
    this.cells.set(`${layer}:${frame}`, { layer, frame, opacity: 255, z: 0, pixels: new Uint32Array(this.size), base: new Uint32Array(this.size), stacks: new Map() });
  }
  user(id) {
    if (!this.users.has(id)) this.users.set(id, { undo: [], redo: [], seq: 0 });
    return this.users.get(id);
  }
  history(id) { const u = this.user(id); return { undo: u.undo.length, redo: u.redo.length }; }
  snapshot() {
    return { ...this.meta, cels: [...this.cells.values()].sort((a,b) => a.layer-b.layer || a.frame-b.frame).map(c => ({ layer: c.layer, frame: c.frame, opacity: c.opacity, z: c.z, runs: encodeRuns(c.pixels, true) })) };
  }
  changesToPatches(touched) {
    const patches = [];
    for (const [key, indices] of touched) {
      const cell = this.cells.get(key);
      const runs = [];
      for (const index of [...indices].sort((a, b) => a - b)) {
        const value = cell.pixels[index], n = runs.length;
        if (n && runs[n - 3] + runs[n - 2] === index && runs[n - 1] === value) runs[n - 2]++;
        else runs.push(index, 1, value);
      }
      if (runs.length) patches.push({ layer: cell.layer, frame: cell.frame, runs });
    }
    return patches;
  }
  paint(author, seq, patches, structure) {
    const user = this.user(author);
    if (structure !== this.structure) throw new Error('Dokumentstruktur hat sich geaendert; lokale Kopie speichern und neu verbinden');
    integer(seq, 1, Number.MAX_SAFE_INTEGER, 'Sequenz');
    if (seq !== user.seq + 1) throw new Error('Sequenz stimmt nicht; bitte neu verbinden');
    if (!Array.isArray(patches) || !patches.length || patches.length > this.cells.size) throw new Error('Leere/ungueltige Operation');
    let amount = 0;
    const seen = new Set();
    // Validate every cel first: no partial mutation on malformed messages.
    for (const patch of patches) {
      const key = `${patch.layer}:${patch.frame}`;
      if (!this.cells.has(key) || seen.has(key)) throw new Error('Unbekanntes oder doppeltes Cel');
      seen.add(key);
      amount += validateRuns(patch.runs, this.size);
    }
    if (amount > LIMITS.changes) throw new Error('Aktion zu gross (maximal 1 Million geaenderte Pixel)');
    const op = { author, seq, active: true, patches: structuredClone(patches), amount };
    const touched = new Map();
    for (const patch of op.patches) {
      const key = `${patch.layer}:${patch.frame}`, cell = this.cells.get(key), indices = new Set();
      for (let r = 0; r < patch.runs.length; r += 3) {
        const [start, length, value] = patch.runs.slice(r, r + 3);
        for (let i = start; i < start + length; i++) {
          const stack = cell.stacks.get(i) || [];
          stack.push({ op, value }); cell.stacks.set(i, stack);
          cell.pixels[i] = value; indices.add(i);
        }
      }
      touched.set(key, indices);
    }
    user.seq = seq; user.undo.push(op); user.redo = [];
    this.operations.push(op); this.historyPixels += amount;
    this.compact();
    return { type: 'patch', author, seq, revision: ++this.revision, patches: this.changesToPatches(touched) };
  }
  undoRedo(author, redo = false) {
    const user = this.user(author), from = redo ? user.redo : user.undo, to = redo ? user.undo : user.redo;
    const op = from.pop();
    if (!op) return null;
    op.active = redo; to.push(op);
    const touched = new Map();
    for (const patch of op.patches) {
      const key = `${patch.layer}:${patch.frame}`, cell = this.cells.get(key), indices = new Set();
      for (let r = 0; r < patch.runs.length; r += 3) {
        for (let i = patch.runs[r]; i < patch.runs[r] + patch.runs[r + 1]; i++) {
          const visible = cell.stacks.get(i)?.findLast(node => node.op.active)?.value ?? cell.base[i];
          if (visible !== cell.pixels[i]) { cell.pixels[i] = visible; indices.add(i); }
        }
      }
      touched.set(key, indices);
    }
    return { type: 'patch', author, action: redo ? 'redo' : 'undo', revision: ++this.revision, patches: this.changesToPatches(touched) };
  }
  compact() {
    while (this.operations.length > 1 && (this.operations.length > this.historyLimit || this.historyPixels > this.pixelLimit)) {
      const op = this.operations.shift();
      for (const patch of op.patches) {
        const cell = this.cells.get(`${patch.layer}:${patch.frame}`);
        for (let r = 0; r < patch.runs.length; r += 3) for (let i = patch.runs[r]; i < patch.runs[r] + patch.runs[r + 1]; i++) {
          if (op.active) cell.base[i] = patch.runs[r + 2];
          const stack = cell.stacks.get(i);
          if (stack?.[0]?.op === op) stack.shift();
          if (!stack?.length) cell.stacks.delete(i);
        }
      }
      const user = this.user(op.author);
      user.undo = user.undo.filter(item => item !== op); user.redo = user.redo.filter(item => item !== op);
      this.historyPixels -= op.amount;
    }
  }
  append(kind, name, source) {
    const raster = this.meta.layers.filter(l => !l.group).length;
    const layerCount = this.meta.layers.length, frameCount = this.meta.frames.length;
    if (kind === 'layer') {
      if (layerCount >= LIMITS.layers || (raster + 1) * frameCount * this.size > LIMITS.pixels) throw new Error('Ebenen-/Groessenlimit erreicht');
      const layer = { name: String(name || `Ebene ${layerCount + 1}`).slice(0, 100), group: false, parent: 0, opacity: 255, blend: 3, visible: true, editable: true, continuous: false };
      const copyFrom = source == null ? null : integer(source, 1, layerCount, 'Quellebene');
      if (copyFrom && this.meta.layers[copyFrom - 1].group) throw new Error('Gruppen lassen sich so nicht duplizieren');
      this.meta.layers.push(layer);
      const cels = [];
      for (let f = 1; f <= frameCount; f++) {
        this.addCell(layerCount + 1, f);
        if (copyFrom) {
          const original = this.cells.get(`${copyFrom}:${f}`), copy = this.cells.get(`${layerCount + 1}:${f}`);
          copy.pixels.set(original.pixels); copy.base.set(original.pixels);
          copy.opacity = original.opacity; copy.z = original.z;
          cels.push({ layer: layerCount + 1, frame: f, opacity: copy.opacity, z: copy.z, runs: encodeRuns(copy.pixels, true) });
        }
      }
      return { type: 'append', kind, layer, index: layerCount + 1, cels, structure: ++this.structure, revision: ++this.revision };
    }
    if (kind !== 'frame' || frameCount >= LIMITS.frames || raster * (frameCount + 1) * this.size > LIMITS.pixels) throw new Error('Frame-/Groessenlimit erreicht');
    const copyFrom = source == null ? null : integer(source, 1, frameCount, 'Quellframe');
    this.meta.frames.push(this.meta.frames[copyFrom ? copyFrom - 1 : frameCount - 1]);
    const cels = [];
    this.meta.layers.forEach((l, i) => {
      if (l.group) return;
      this.addCell(i + 1, frameCount + 1);
      if (copyFrom) {
        const original = this.cells.get(`${i + 1}:${copyFrom}`), copy = this.cells.get(`${i + 1}:${frameCount + 1}`);
        copy.pixels.set(original.pixels); copy.base.set(original.pixels);
        copy.opacity = original.opacity; copy.z = original.z;
        cels.push({ layer: i + 1, frame: frameCount + 1, opacity: copy.opacity, z: copy.z, runs: encodeRuns(copy.pixels, true) });
      }
    });
    return { type: 'append', kind, duration: this.meta.frames[frameCount], index: frameCount + 1, cels, structure: ++this.structure, revision: ++this.revision };
  }
  remapStructure(layerMap, frameMap) {
    const cells = new Map();
    for (const cell of this.cells.values()) {
      const layer = layerMap[cell.layer], frame = frameMap[cell.frame];
      if (layer && frame) {
        cell.layer = layer; cell.frame = frame;
        cells.set(`${layer}:${frame}`, cell);
      }
    }
    this.cells = cells;
    const retained = [];
    for (const op of this.operations) {
      op.patches = op.patches.flatMap(p => {
        const layer = layerMap[p.layer], frame = frameMap[p.frame];
        return layer && frame ? [{ ...p, layer, frame }] : [];
      });
      op.amount = op.patches.reduce((sum, p) => sum + p.runs.reduce((n, v, i) => i % 3 === 1 ? n + v : n, 0), 0);
      if (op.patches.length) retained.push(op);
    }
    this.operations = retained;
    this.historyPixels = retained.reduce((sum, op) => sum + op.amount, 0);
    const live = new Set(retained);
    for (const user of this.users.values()) {
      user.undo = user.undo.filter(op => live.has(op));
      user.redo = user.redo.filter(op => live.has(op));
    }
  }
  delete(kind, index) {
    if (kind === 'frame') {
      integer(index, 1, this.meta.frames.length, 'Frame');
      if (this.meta.frames.length < 2) throw new Error('Das letzte Frame kann nicht geloescht werden');
      const frameMap = {};
      for (let f = 1; f <= this.meta.frames.length; f++) if (f !== index) frameMap[f] = f < index ? f : f - 1;
      const layerMap = Object.fromEntries(this.meta.layers.map((_, i) => [i + 1, i + 1]));
      this.meta.frames.splice(index - 1, 1);
      this.remapStructure(layerMap, frameMap);
      return { type: 'delete', kind, index, count: 1, structure: ++this.structure, revision: ++this.revision };
    }
    if (kind !== 'layer') throw new Error('Unbekannter Strukturtyp');
    integer(index, 1, this.meta.layers.length, 'Ebene');
    const removed = new Set([index]);
    for (let i = index + 1; i <= this.meta.layers.length; i++) {
      let parent = this.meta.layers[i - 1].parent;
      while (parent && !removed.has(parent)) parent = this.meta.layers[parent - 1].parent;
      if (parent) removed.add(i);
    }
    const remaining = this.meta.layers.filter((layer, i) => !removed.has(i + 1));
    if (!remaining.some(layer => !layer.group)) throw new Error('Die letzte Rasterebene kann nicht geloescht werden');
    const layerMap = {}, frameMap = {};
    let next = 0;
    for (let i = 1; i <= this.meta.layers.length; i++) if (!removed.has(i)) layerMap[i] = ++next;
    for (let f = 1; f <= this.meta.frames.length; f++) frameMap[f] = f;
    this.meta.layers = remaining.map(layer => ({ ...layer, parent: layer.parent ? layerMap[layer.parent] : 0 }));
    this.remapStructure(layerMap, frameMap);
    return { type: 'delete', kind, index, count: removed.size, layers: structuredClone(this.meta.layers), structure: ++this.structure, revision: ++this.revision };
  }
  deleteMany(kind, indices) {
    const max = kind === 'layer' ? this.meta.layers.length : kind === 'frame' ? this.meta.frames.length : 0;
    if (!max) throw new Error('Unbekannter Strukturtyp');
    if (!Array.isArray(indices) || !indices.length || indices.length > max) throw new Error('Ungueltige Auswahl');
    const ordered = [...new Set(indices.map(index => integer(index, 1, max, 'Auswahl')))].sort((a, b) => b - a);
    // Check the complete batch before changing the live room or its history.
    const trial = new Room(this.snapshot());
    for (const index of ordered) trial.delete(kind, index);
    return ordered.map(index => this.delete(kind, index));
  }
  setProperty(kind, index, field, value) {
    if (kind === 'frame') {
      integer(index, 1, this.meta.frames.length, 'Frame');
      if (field !== 'duration') throw new Error('Unbekannte Frame-Eigenschaft');
      value = integer(value, 1, 65535, 'Frame-Dauer');
      this.meta.frames[index - 1] = value;
    } else if (kind === 'layer') {
      integer(index, 1, this.meta.layers.length, 'Ebene');
      const layer = this.meta.layers[index - 1];
      if (field === 'name') { value = String(value || '').trim().slice(0, 100); if (!value) throw new Error('Ebenenname fehlt'); }
      else if (field === 'opacity') value = integer(value, 0, 255, 'Deckkraft');
      else if (field === 'blend') value = integer(value, 0, 31, 'Mischmodus');
      else if (['visible', 'editable', 'continuous'].includes(field)) { if (typeof value !== 'boolean') throw new Error('Ungueltiger Schalter'); }
      else throw new Error('Unbekannte Ebeneneigenschaft');
      if (layer.group && ['opacity', 'blend', 'continuous'].includes(field)) throw new Error('Fuer Gruppen nicht verfuegbar');
      layer[field] = value;
    } else throw new Error('Unbekannter Eigenschaftstyp');
    return { type: 'property', kind, index, field, value, revision: ++this.revision };
  }
  setCelProperty(layer, frame, field, value) {
    integer(layer, 1, this.meta.layers.length, 'Cel-Ebene');
    integer(frame, 1, this.meta.frames.length, 'Cel-Frame');
    const cell = this.cells.get(`${layer}:${frame}`);
    if (!cell) throw new Error('Unbekanntes Cel');
    if (field === 'opacity') value = integer(value, 0, 255, 'Cel-Deckkraft');
    else if (field === 'z') value = integer(value, -32768, 32767, 'Cel-Z');
    else throw new Error('Unbekannte Cel-Eigenschaft');
    cell[field] = value;
    return { type: 'celProperty', layer, frame, field, value, revision: ++this.revision };
  }
  setPalette(colors) {
    if (!Array.isArray(colors) || colors.length > 256) throw new Error('Ungueltige Palette');
    this.meta.palette = colors.map(color => integer(color, 0, 0xffffffff, 'Palettenfarbe'));
    return { type: 'palette', colors: [...this.meta.palette], revision: ++this.revision };
  }
}
