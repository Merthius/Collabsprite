-- RGBA cel transport: compact runs on the wire, immutable byte strings locally.
local M = {}
function M.key(layer, frame) return string.format('%d:%d', layer, frame) end
function M.runs(bytes, before)
  local runs, start, count, value = {}, nil, 0, nil
  local function flush()
    if start then
      runs[#runs+1], runs[#runs+2], runs[#runs+3] = start, count, value
      start, count, value = nil, 0, nil
    end
  end
  for offset=1,#bytes,4 do
    local v = string.unpack('<I4', bytes, offset)
    local old = before and string.unpack('<I4', before, offset) or 0
    if v ~= old then
      local index = (offset-1)//4
      if start and start+count == index and value == v then count=count+1
      else flush(); start, count, value = index, 1, v end
    else flush() end
  end
  flush()
  return runs
end
function M.applyRuns(bytes, runs)
  local parts, cursor = {}, 1
  for i=1,#runs,3 do
    local pos, count, value = runs[i]*4+1, runs[i+1], runs[i+2]
    assert(pos >= cursor and count > 0 and pos+count*4 <= #bytes+1, 'Ungueltige Pixelbereiche')
    parts[#parts+1] = bytes:sub(cursor,pos-1)
    parts[#parts+1] = string.rep(string.pack('<I4',value),count)
    cursor = pos+count*4
  end
  parts[#parts+1] = bytes:sub(cursor)
  return table.concat(parts)
end
function M.flatten(sprite)
  local mapping, metadata = {}, {}
  local function visit(layers,parent)
    for _,layer in ipairs(layers) do
      assert(not layer.isTilemap and not layer.isReference, 'Tilemap-/Referenzebenen zuerst in normale Rasterebenen umwandeln.')
      local id=#mapping+1
      mapping[id]=layer
      metadata[id]={name=layer.name, group=layer.isGroup, parent=parent, opacity=layer.opacity or 255,
        blend=layer.blendMode or BlendMode.NORMAL, visible=layer.isVisible,
        editable=layer.isEditable,continuous=not layer.isGroup and layer.isContinuous or false}
      if layer.isGroup then visit(layer.layers,id) end
    end
  end
  visit(sprite.layers,0)
  return mapping, metadata
end
local function celBytes(cel,w,h,blank)
  if not cel then return blank, 'empty' end
  local im, p = cel.image,cel.position
  local signature=table.concat({im.id,im.version,p.x,p.y,im.width,im.height},':')
  local raw=im.bytes
  if p.x==0 and p.y==0 and im.width==w and im.height==h then return raw,signature end
  -- A moved/selected cel may extend beyond the canvas. Sync its visible
  -- intersection instead of terminating the whole multiplayer session.
  local x0,y0=math.max(0,p.x),math.max(0,p.y)
  local x1,y1=math.min(w,p.x+im.width),math.min(h,p.y+im.height)
  if x1<=x0 or y1<=y0 then return blank,signature end
  local rows={string.rep('\0',y0*w*4)}
  local left,right=string.rep('\0',x0*4),string.rep('\0',(w-x1)*4)
  for y=y0,y1-1 do
    local first=((y-p.y)*im.width+x0-p.x)*4+1
    rows[#rows+1]=left..raw:sub(first,first+(x1-x0)*4-1)..right
  end
  rows[#rows+1]=string.rep('\0',(h-y1)*w*4)
  return table.concat(rows),signature
end
function M.scan(sprite,mapping,previous)
  local out,blank={}
  for l,layer in ipairs(mapping) do
    if not layer.isGroup then
      for f=1,#sprite.frames do
        local key=M.key(l,f)
        local cel=layer:cel(f)
        local cached=previous and previous[key]
        local signature='empty'
        if cel then
          local im,p=cel.image,cel.position
          signature=table.concat({im.id,im.version,p.x,p.y,im.width,im.height},':')
        end
        if cached and cached.signature==signature then out[key]=cached
        else
          if not blank then blank=string.rep('\0',sprite.width*sprite.height*4) end
          local bytes,sig=celBytes(cel,sprite.width,sprite.height,blank)
          out[key]={bytes=bytes,signature=sig,layer=l,frame=f}
        end
      end
    end
  end
  return out
end
function M.capture(sprite)
  assert(sprite, 'Bitte zuerst ein Bild in Aseprite oeffnen.')
  assert(sprite.colorMode==ColorMode.RGB, 'Bitte vor der Sitzung Sprite > Farbmodus > RGB waehlen (in einer Kopie).')
  assert(sprite.width<=1024 and sprite.height<=1024, 'Maximale Canvas-Groesse: 1024 x 1024.')
  local mapping,layers=M.flatten(sprite)
  local raster=0
  for _,l in ipairs(layers) do if not l.group then raster=raster+1 end end
  assert(#layers<=32 and #sprite.frames<=120 and raster>0, 'Maximal 32 Ebenen und 120 Frames; mindestens eine Rasterebene.')
  assert(raster*#sprite.frames*sprite.width*sprite.height<=4194304, 'Zu gross: maximal 4 Millionen Cel-Pixel pro Sitzung.')
  local s={format=1,name=app.fs.fileTitle(sprite.filename or '') or 'Gemeinsam',width=sprite.width,height=sprite.height,
    layers=layers,frames={},cels={},palette={}}
  for _,f in ipairs(sprite.frames) do s.frames[#s.frames+1]=math.max(1,math.floor(f.duration*1000+0.5)) end
  local scan=M.scan(sprite,mapping)
  for l,layer in ipairs(mapping) do if not layer.isGroup then
    for f=1,#sprite.frames do
      local cel=layer:cel(f)
      s.cels[#s.cels+1]={layer=l,frame=f,runs=M.runs(scan[M.key(l,f)].bytes),opacity=cel and cel.opacity or 255,z=cel and cel.zIndex or 0}
    end
  end end
  local pal=sprite.palettes[1]
  if pal then for i=0,math.min(#pal,256)-1 do s.palette[#s.palette+1]=pal:getColor(i).rgbaPixel end end
  return s
end
function M.decode(s)
  local cells,blank={},string.rep('\0',s.width*s.height*4)
  for l,layer in ipairs(s.layers) do if not layer.group then
    for f=1,#s.frames do cells[M.key(l,f)]={layer=l,frame=f,bytes=blank,opacity=255,z=0} end
  end end
  for _,cel in ipairs(s.cels) do
    local c=assert(cells[M.key(cel.layer,cel.frame)],'Unbekanntes Cel')
    c.bytes=M.applyRuns(blank,cel.runs); c.opacity=cel.opacity or 255; c.z=cel.z or 0
  end
  return cells
end
function M.writeCel(sprite,layer,frame,bytes,opacity,z)
  local im=Image(sprite.width,sprite.height,ColorMode.RGB)
  im.bytes=bytes
  local cel=layer:cel(frame)
  if cel then cel.image=im; cel.position=Point(0,0)
  else cel=sprite:newCel(layer,frame,im,Point(0,0)) end
  if opacity then cel.opacity=opacity end
  if z then cel.zIndex=z end
end
function M.create(s,cells)
  cells=cells or M.decode(s)
  local sprite=Sprite(s.width,s.height,ColorMode.RGB)
  local initial=sprite.layers[1]
  local mapping={}
  app.transaction('Collabsprite Sitzungskopie',function()
    for f=2,#s.frames do sprite:newEmptyFrame(f) end
    for f,ms in ipairs(s.frames) do sprite.frames[f].duration=ms/1000 end
    for i,meta in ipairs(s.layers) do
      local layer=meta.group and sprite:newGroup() or sprite:newLayer()
      if meta.parent>0 then layer.parent=mapping[meta.parent] end
      -- Each newly created child is explicitly moved to the top of its parent.
      layer.stackIndex=#(meta.parent>0 and mapping[meta.parent].layers or sprite.layers)
      layer.name=meta.name; layer.opacity=meta.opacity; layer.blendMode=meta.blend; layer.isVisible=meta.visible
      layer.isEditable=meta.editable~=false
      if not meta.group then layer.isContinuous=meta.continuous==true end
      mapping[i]=layer
    end
    sprite:deleteLayer(initial)
    for _,c in pairs(cells) do M.writeCel(sprite,mapping[c.layer],c.frame,c.bytes,c.opacity,c.z) end
    if #s.palette>0 then
      local pal=Palette(#s.palette)
      for i,v in ipairs(s.palette) do pal:setColor(i-1,Color{r=v&255,g=(v>>8)&255,b=(v>>16)&255,a=(v>>24)&255}) end
      sprite:setPalette(pal)
    end
  end)
  sprite.filename=(s.name~='' and s.name or 'Gemeinsam')..' - Multiplayer.aseprite'
  for _,layer in ipairs(mapping) do if not layer.isGroup then app.layer=layer; break end end
  return sprite,mapping
end
function M.checkTopology(sprite,mapping,meta)
  assert(sprite.width==meta.width and sprite.height==meta.height and sprite.colorMode==ColorMode.RGB and #sprite.frames==#meta.frames,
    'Dokumentstruktur geaendert: '..sprite.width..'x'..sprite.height..' / '..#sprite.frames..' Frames; erwartet '..meta.width..'x'..meta.height..' / '..#meta.frames..'. Lokale Kopie bleibt erhalten.')
  local actual,layers=M.flatten(sprite)
  assert(#actual==#mapping,'Ebenenstruktur wurde geaendert.')
  for i,layer in ipairs(actual) do
    assert(layer==mapping[i] and layers[i].parent==meta.layers[i].parent,'Ebenenreihenfolge wurde geaendert.')
  end
end
return M
