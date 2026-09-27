-- Native frame wrappers are positional, not stable identities. Track surviving
-- Cel objects instead: inserting/moving a frame moves those actual objects.
local M={}
local function id() return tostring(Uuid()):gsub('-',''):lower() end
M.id=id
function M.track(sprite,mapping,meta,anchorEmptyFrames)
  local out={layers={},frames={},tags={}}
  for i,l in ipairs(mapping) do out.layers[#out.layers+1]={object=l,id=meta.layers[i].id} end
  for f,frameId in ipairs(meta.frameIds or {}) do
    local refs={};for _,l in ipairs(mapping) do if not l.isGroup and l:cel(f) then refs[#refs+1]=l:cel(f) end end
    -- An erased frame still needs a native object that follows insert/reorder.
    -- A transparent 1px cel changes no rendered pixels and adds no hidden layer.
    -- Only the live client opts in, after a completed edit, inside its guard.
    if anchorEmptyFrames and #refs==0 then
      for _,l in ipairs(mapping) do if not l.isGroup then
        refs[1]=sprite:newCel(l,f,Image(1,1,ColorMode.RGB),Point(0,0));break
      end end
    end
    out.frames[f]={id=frameId,refs=refs}
  end
  local used={}
  for _,t in ipairs(sprite.tags) do
    for i,v in ipairs(meta.tags or {}) do
      if not used[i] and v.name==t.name and v.from==t.fromFrame.frameNumber and v.to==t.toFrame.frameNumber and v.direction==t.aniDir and v.repeats==t.repeats and v.color==t.color.rgbaPixel then
        used[i]=true;out.tags[#out.tags+1]={object=t,id=v.id};break
      end
    end
  end
  return out
end
function M.describe(sprite,mapping,layers,known)
  known=known or {layers={},frames={},tags={}}
  for i,l in ipairs(mapping) do
    for _,entry in ipairs(known.layers) do if entry.object==l then layers[i].id=entry.id;break end end
    layers[i].id=layers[i].id or id()
  end
  local frameIds,candidates={},{}
  for old,entry in ipairs(known.frames) do
    local candidate,ambiguous
    for _,cel in ipairs(entry.refs) do
      local ok,f=pcall(function() return cel.frameNumber end)
      if ok then if candidate and candidate~=f then ambiguous=true else candidate=f end end
    end
    if candidate and not ambiguous and candidate<=#sprite.frames then
      if candidates[candidate]~=nil then candidates[candidate]=false else candidates[candidate]={old=old,id=entry.id} end
    end
  end
  -- A partial cel move is NOT a whole-frame reorder. Only accept a complete
  -- bijection for same-length permutations; otherwise retain positional IDs.
  local matched=0;for _,entry in pairs(candidates) do if entry then matched=matched+1 end end
  if #sprite.frames==#known.frames and matched<#known.frames then
    for f,entry in ipairs(known.frames) do frameIds[f]=entry.id end
  else
    for f,entry in pairs(candidates) do if entry then frameIds[f]=entry.id end end
  end
  for f=1,#sprite.frames do frameIds[f]=frameIds[f] or id() end
  local tags={}
  for _,t in ipairs(sprite.tags) do
    local identity
    for _,entry in ipairs(known.tags) do if entry.object==t then identity=entry.id;break end end
    tags[#tags+1]={id=identity or id(),name=t.name,from=t.fromFrame.frameNumber,to=t.toFrame.frameNumber,
      direction=t.aniDir,repeats=t.repeats,color=t.color.rgbaPixel}
  end
  table.sort(tags,function(a,b) return a.id<b.id end)
  local cels={}
  for l,layer in ipairs(mapping) do if not layer.isGroup then
    local groups={}
    for f=1,#sprite.frames do
      local cel=layer:cel(f)
      local c={layer=l,frame=f,opacity=cel and cel.opacity or 255,z=cel and cel.zIndex or 0}
      cels[#cels+1]=c
      if cel then
        local key=cel.image.id
        groups[key]=groups[key] or {};groups[key][#groups[key]+1]={meta=c,position=cel.position}
      end
    end
    for _,group in pairs(groups) do if #group>1 then
      local ids={};for _,entry in ipairs(group) do ids[#ids+1]=frameIds[entry.meta.frame] end;table.sort(ids)
      for _,entry in ipairs(group) do
        assert(entry.position==group[1].position,'Verknüpfte Cels mit verschiedenen Positionen: bitte zunächst Verknüpfung lösen. Lokale Fassung bleibt erhalten.')
        entry.meta.link=ids[1]
      end
    end end
  end end
  return frameIds,tags,cels
end
function M.apply(sprite,mapping,s)
  -- LinkCels is the public native API for establishing actual shared images.
  local previous,layer,frame=app.sprite,app.layer,app.frame
  app.sprite=sprite
  local groups={}
  for _,c in ipairs(s.cels) do if c.link then
    local key=c.layer..':'..c.link
    groups[key]=groups[key] or {layer=c.layer,frames={}}
    table.insert(groups[key].frames,c.frame)
  end end
  for _,g in pairs(groups) do if #g.frames>1 then
    app.range:clear();app.layer=mapping[g.layer];app.frame=sprite.frames[g.frames[1]]
    app.range.layers={mapping[g.layer]};app.range.frames=g.frames
    assert(app.command.LinkCels(),'Verknüpfte Cels konnten nicht angelegt werden')
  end end
  app.range:clear()
  -- Restore metadata after linking. Native linked cels share opacity, whereas
  -- stacking offsets remain per cel; validation enforces shared opacity.
  for _,c in ipairs(s.cels) do
    local cel=mapping[c.layer]:cel(c.frame)
    if cel then cel.opacity=c.opacity or 255;cel.zIndex=c.z or 0 end
  end
  local oldTags={};for _,t in ipairs(sprite.tags) do oldTags[#oldTags+1]=t end
  for _,t in ipairs(oldTags) do sprite:deleteTag(t) end
  for _,t in ipairs(s.tags or {}) do
    local tag=sprite:newTag(t.from,t.to);tag.name=t.name;tag.aniDir=t.direction;tag.repeats=t.repeats
    local v=t.color;tag.color=Color{r=v&255,g=(v>>8)&255,b=(v>>16)&255,a=(v>>24)&255}
  end
  app.sprite=previous
  if previous and previous~=sprite then if layer then app.layer=layer end;if frame then app.frame=frame end end
end
return M
