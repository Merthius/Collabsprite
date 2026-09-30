-- A compact board surface with an island toolbar, marquee selection and boxes.
local dir=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local N=dofile(app.fs.joinPath(dir,'notes.lua'))
local T=dofile(app.fs.joinPath(dir,'notes-input.lua'))
local S=dofile(app.fs.joinPath(dir,'notes-stack.lua'))
local B=dofile(app.fs.joinPath(dir,'notes-board.lua'))
local F=dofile(app.fs.joinPath(dir,'notes-style.lua'))
local I=dofile(app.fs.joinPath(dir,'notes-image.lua'))
local P=dofile(app.fs.joinPath(dir,'notes-paper.lua'))
local V=dofile(app.fs.joinPath(dir,'notes-paper-view.lua'))
local A=dofile(app.fs.joinPath(dir,'notes-animation.lua'))
local L=dofile(app.fs.joinPath(dir,'ui-layout.lua'))
local UI={};UI.__index=UI
local function inside(r,x,y) return x>=r.x and y>=r.y and x<r.x+r.w and y<r.y+r.h end
local function rect(x,y,w,h) return {x=x,y=y,w=w,h=h} end
local function clamp(v) return math.floor(math.max(-10000,math.min(10000,v))) end
function UI.new(getSession,guestGuard,safe,getName,promote,files)
  return setmetatable({states={},getSession=getSession,guestGuard=guestGuard,safe=safe,getName=getName or function() return 'Künstler' end,promote=promote,files=files},UI)
end
function UI:state(sprite)
  if not self.states[sprite.id] then
    local s={sprite=sprite,board=N.read(sprite),history={undo={},redo={}},zoom=1,ox=24,oy=90,drafts={},paperDrafts={},seen=false,images={},animationThumbs={},selection={},slow={},windowToken=N.uid()}
    s.changeListener=sprite.events:on('change',function() s.animationDirty=true end)
    self.states[sprite.id]=s
  end
  return self.states[sprite.id]
end
function UI:session(s) local c=self.getSession();return c and c.sprite==s.sprite and (c.connected or c.connecting or c.reconnecting) and c or nil end
function UI:editable(s)
  local c=self:session(s);if c then return c.connected and not c.leaving end
  return not self.guestGuard(s.sprite)
end
function UI:run(fn) self.safe(fn) end
function UI:action(s,op,callback)
  assert(s.sprite.isValid and self:editable(s),'Notizen sind derzeit nur lesbar. Verbindung prüfen.')
  local c=self:session(s)
  if c then assert(not s.ack,'Eine Notizänderung wird noch bestätigt');c:noteAction(op);s.ack=callback or function() end
  else
    local history=N.copy(s.history);local next=N.localAction(s.board,history,op,self.getName())
    local previous,layer,frame=app.sprite,app.layer,app.frame;app.sprite=s.sprite
    local ok,err=pcall(function() app.transaction('Collabsprite: Ideenwand',function() N.write(s.sprite,next) end) end)
    app.sprite=previous;if previous then app.layer=layer;app.frame=frame end
    if not ok then error(err) end
    s.board=next;s.history=history;if callback then callback(true) end
  end
  self:refresh(s)
end
function UI:attach(c)
  if not c.sprite then return end
  local s=self:state(c.sprite)
  c.onNotes=function(message)
    if message.type=='notes' then
      s.board=N.copy(c.meta.notes)
      -- ACK precedes state: chain edits only after the authoritative revision.
      if s.ackResult then local fn,result=s.ack,s.ackResult;s.ack=nil;s.ackResult=nil;if fn then fn(result.ok,result.message) end end
    elseif message.type=='noteAck' then s.ackResult=message end
    self:refresh(s)
  end
  c.notesCanLeave=function() return self:canLeave(s) end
end
function UI:canLeave(s)
  if s.inline and s.inline.dirty and not s.inline.error then self:finishInline(s) end
  for id,draft in pairs(s.paperDrafts) do if draft.dirty then
    app.tip('Skizzenblatt noch nicht gespeichert. Bitte öffnen und fertigstellen.',5)
    self:paperPreview(s,id);return false
  end end
  for _,d in pairs(s.drafts) do if d.dirty then
    app.tip('Notizentwurf noch offen. Rechtsklick auf das Element zum Vergleichen.',6)
    self:show(s.sprite);self:edit(s,d.id);return false
  end end
  local c=self:session(s)
  if c and c.notePending then app.tip('Notizänderung wird noch bestätigt. Bitte kurz warten.',4);return false end
  return true
end
function UI:refresh(s)
  if s.inline and s.inline.error and s.inline.error~=s.lastError then s.lastError=s.inline.error;app.tip(s.inline.error,5) end
  if not s.inline or not s.inline.error then s.lastError=nil end
  if s.cachedBoard~=s.board then
    local images={}
    for id in pairs(s.selection) do if not N.card(s.board,id) then s.selection[id]=nil end end
    if s.selected and not N.card(s.board,s.selected) then s.selected=next(s.selection) end
    if s.sheet and not N.card(s.board,s.sheet.id) then s.sheet=nil end
    if s.playing and not N.card(s.board,s.playing.id) then s.playing=nil end
    for _,c in ipairs(s.board.cards) do if c.kind=='image' or c.kind=='paper' then
      local old=s.images[c.id];images[c.id]=old and N.equal(old.data,c.image) and old or
        {data=N.copy(c.image),image=c.kind~='paper' and I.unpack(c.image) or nil,previews={}}
    end end
    s.images=images;s.cachedBoard=s.board
    for id,draft in pairs(s.paperDrafts) do
      local current=N.card(s.board,id)
      if not current then s.paperDrafts[id]=nil
      elseif not draft.dirty and not draft.sending and current.versions.image~=draft.baseVersion then
        draft.image=P.unpack(current.image);draft.baseVersion=current.versions.image
        draft.undo={};draft.redo={};draft.previewRevision=(draft.previewRevision or 0)+1
      end
    end
  end
  if s.dialog then s.dialog:repaint() end
end
function UI:paperThumbnail(s,card,size)
  local cached=s.images[card.id];if not cached then return end
  local draft=s.paperDrafts[card.id]
  local source=draft and draft.image or false
  local revision=draft and draft.previewRevision or -1
  if cached.previewSource~=source or cached.previewRevision~=revision then
    cached.previews={};cached.previewSource=source;cached.previewRevision=revision
  end
  if not cached.previews[size] then
    local small=P.thumbnail(source or P.unpack(card.image),size)
    local white=Image(size,size,ColorMode.RGB)
    white:clear(app.pixelColor.rgba(255,255,255,255));white:drawImage(small)
    cached.previews[size]=white
  end
  return cached.previews[size]
end
function UI:layout(s)
  if s.drag and s.drag.group and s.drag.moved then
    local board=N.copy(s.drag.board)
    for _,patch in ipairs(B.move(s.drag.board,s.drag.selection,s.drag.dx,s.drag.dy).patches) do
      N.card(board,patch.id)[patch.field]=N.copy(patch.value)
    end
    return S.layout(board,s.inline)
  end
  return S.layout(s.board,s.inline,s.drag)
end
function UI:prepare(s) F.load();self:refresh(s) end
function UI:fit(s)
  -- Native font and cards stay at 100%; only the viewport is recentered.
  s.zoom=1
  local boxes=S.layout(s.board)
  if #boxes==0 then s.ox,s.oy=16,84
  else
    local minx,miny,maxx,maxy=1e6,1e6,-1e6,-1e6
    for _,b in ipairs(boxes) do
      minx=math.min(minx,b.x);miny=math.min(miny,b.y)
      maxx=math.max(maxx,b.x+b.w);maxy=math.max(maxy,b.y+b.h)
    end
    local w,h=s.width or 420,s.height or 260
    s.ox=(maxx-minx<=w-24) and math.floor((w-minx-maxx)/2) or 16-boxes[1].x
    s.oy=(maxy-miny<=h-100) and math.floor((h+72-miny-maxy)/2) or 84-boxes[1].y
  end
  self:refresh(s)
end
function UI:reveal(s,id,caret)
  local _,map=B.display(self:layout(s),s.zoom,s.ox,s.oy);local v=map[id];if not v then return end
  local b=v.box;local x,y=v.x,v.y
  if x<12 then s.ox=s.ox+12-x elseif x+v.w>(s.width or 660)-12 then s.ox=s.ox+(s.width or 660)-12-x-v.w end
  if y<12 then s.oy=s.oy+12-y elseif y+math.min(v.h,160)>(s.height or 410)-12 then s.oy=s.oy+(s.height or 410)-12-y-math.min(v.h,160) end
  if caret and s.inline then
    local row=1;for i,v in ipairs(b.rows) do if s.inline.cursor>=v.start then row=i end end
    local _,ry=S.rowPosition(b,row)
    local _,current=B.display(self:layout(s),s.zoom,s.ox,s.oy)
    local cy=current[id].y+ry*v.scale
    if cy<12 then s.oy=s.oy+12-cy elseif cy+b.lineHeight*v.scale>(s.height or 410)-12 then s.oy=s.oy+(s.height or 410)-12-cy-b.lineHeight*v.scale end
  end
end
function UI:add(s,kind,style,point,image,parent,dock)
  if s.inline then return self:finishInline(s,function() self:add(s,kind,style,point,image,parent,dock) end) end
  dock=dock or 'below'
  if parent then
    local _,map=S.layout(s.board);local box=assert(map[parent],'Element fehlt')
    assert(not S.occupied(s.board,box.card)[dock],'Diese Seite ist bereits belegt')
    point={x=dock=='left' and box.x-S.width-S.gap or dock=='right' and box.x+box.w+S.gap or box.x,
      y=dock=='below' and box.y+box.h+S.gap or box.y}
  end
  point=point or {x=math.floor(((s.width or 660)/2-S.width*B.visualScale(s.zoom)/2-s.ox)/s.zoom),y=math.floor(((s.height or 410)/2-s.oy)/s.zoom)}
  local c=N.newCard('',parent or '',clamp(point.x),clamp(point.y));c.dock=dock;c.kind=kind or 'text';c.listStyle=style or 'check';c.color=F.colors[(c.kind=='image' or c.kind=='paper') and 7 or c.kind=='list' and 2 or 1];c.image=image or (c.kind=='paper' and P.blank() or false)
  local patches={{id=c.id,expected=false,value=c}}
  self:action(s,{action='patch',patches=patches},function(ok,message)
    if ok then s.selected=c.id;s.selection={[c.id]=true};if c.kind~='image' and c.kind~='paper' then self:edit(s,c.id) end;self:reveal(s,c.id)
    else app.tip(message or 'Element konnte nicht erstellt werden.',5) end
  end)
end
function UI:import(s,point,parent,dock)
  if self.files then
    if s.picker then return end
    local token=N.uid();self.files.start(token,'Pick',s.windowToken)
    s.picker={token=token,point=point,parent=parent,dock=dock,started=os.time()}
    return
  end
  local picker=Dialog{title='Referenzbild auswählen'}
  picker:file{id='path',title='Referenzbild',open=true,entry=false,filetypes={'png','jpg','jpeg','webp','gif','bmp'},onchange=function()
    local path=picker.data.path
    if path and path~='' then picker:close();self:run(function() self:add(s,'image',nil,point,I.load(path),parent,dock) end) end
  end}:button{text='Abbrechen'}
  L.show(picker)
end
function UI:importFiles(s,paths,point,parent,dock)
  if s.inline then return self:finishInline(s,function() self:importFiles(s,paths,point,parent,dock) end) end
  assert(type(paths)=='table' and #paths>0 and #paths<=32,'Bitte höchstens 32 Bilder gleichzeitig auswählen.')
  assert(#s.board.cards+#paths<=128,'Die Ideenwand ist voll (höchstens 128 Elemente).')
  local cards,patches={},{}
  point=point or {x=math.floor(((s.width or 660)/2-S.width/2-s.ox)/s.zoom),y=math.floor(((s.height or 410)/2-s.oy)/s.zoom)}
  if parent then
    local _,map=S.layout(s.board);local box=assert(map[parent],'Element fehlt')
    dock=dock or 'below';assert(not S.occupied(s.board,box.card)[dock],'Diese Seite ist bereits belegt')
    point={x=dock=='left' and box.x-S.width-S.gap or dock=='right' and box.x+box.w+S.gap or box.x,y=dock=='below' and box.y+box.h+S.gap or box.y}
  end
  -- Load/validate the entire batch before submitting one atomic operation.
  for i,path in ipairs(paths) do
    assert(type(path)=='string' and #path>0 and #path<=32767,'Ungültiger Bildpfad')
    local ext=path:lower():match('%.([^%.\\/]+)$')
    assert(({png=true,jpg=true,jpeg=true,webp=true,gif=true,bmp=true})[ext],'Nicht unterstütztes Bildformat')
    local image=I.load(path)
    local c=N.newCard('',i==1 and (parent or '') or '',clamp(point.x+((i-1)%3)*(S.width+16)),clamp(point.y+math.floor((i-1)/3)*148))
    c.kind='image';c.image=image;c.color=F.colors[7];c.dock=dock or 'below'
    cards[#cards+1]=c;patches[#patches+1]={id=c.id,expected=false,value=c}
  end
  self:action(s,{action='patch',patches=patches},function(ok,message)
    if ok then s.selection={};for _,c in ipairs(cards) do s.selection[c.id]=true end;s.selected=cards[1].id;self:reveal(s,cards[1].id)
    else app.tip(message or 'Bilder konnten nicht eingefügt werden.',5) end
  end)
end
function UI:addAnimation(s,tag,point)
  if s.inline then return self:finishInline(s,function() self:addAnimation(s,tag,point) end) end
  assert(tag and N.field('tag',tag.name),'Animations-Tag-Name ist zu lang (höchstens 120 Bytes).')
  point=point or {x=math.floor(((s.width or 660)/2-S.animationWidth/2-s.ox)/s.zoom),y=math.floor(((s.height or 410)/2-s.oy)/s.zoom)}
  local c=N.newCard('', '',clamp(point.x),clamp(point.y))
  c.kind='animation';c.tag=tag.name;c.tagStart=tag.first;c.frame=tag.first;c.color=F.colors[7]
  self:action(s,{action='patch',patches={{id=c.id,expected=false,value=c}}},function(ok,message)
    if ok then s.selected=c.id;s.selection={[c.id]=true};self:reveal(s,c.id)
    else app.tip(message or 'Animation konnte nicht eingefügt werden.',5) end
  end)
end
function UI:thumbnail(s,frame,width,height)
  local key=frame..':'..width..':'..height
  local cached=s.animationThumbs[key]
  if cached==nil then
    local ok,image=pcall(A.thumbnail,s.sprite,frame,width,height)
    cached=ok and image or false;s.animationThumbs[key]=cached
  end
  return cached or nil
end
function UI:drawThumbnail(s,gc,frame,x,y,w,h)
  local image=self:thumbnail(s,frame,w,h)
  if not image then return false end
  local iw,ih=image.width,image.height
  gc:drawImage(image,Rectangle(0,0,iw,ih),Rectangle(math.floor(x+(w-iw)/2),math.floor(y+(h-ih)/2),iw,ih))
  return true
end
function UI:openSheet(s,id)
  local c=N.card(s.board,id)
  if not c or c.kind~='animation' then return end
  local tag=A.resolve(s.sprite,c)
  if not tag then app.tip('Animations-Tag nicht mehr gefunden: '..c.tag,4);return end
  s.playing=nil
  s.sheet={id=id,index=math.max(1,math.min(tag.last-tag.first+1,c.frame-tag.first+1))};s.selected=id;s.selection={[id]=true};self:refresh(s)
end
function UI:sheetStep(s,step)
  local sheet=s.sheet;if not sheet then return end
  local c=N.card(s.board,sheet.id);local tag=c and A.resolve(s.sprite,c)
  if not tag then s.sheet=nil;return end
  sheet.index=math.max(1,math.min(tag.last-tag.first+1,sheet.index+step));self:refresh(s)
end
function UI:commitSheet(s)
  local sheet=s.sheet;if not sheet then return end
  local c=N.card(s.board,sheet.id);local tag=c and A.resolve(s.sprite,c)
  if not tag then s.sheet=nil;self:refresh(s);return end
  local frame=math.max(tag.first,math.min(tag.last,tag.first+sheet.index-1))
  if frame==c.frame then s.sheet=nil;self:refresh(s);return end
  self:action(s,{action='patch',patches={N.patch(c,'frame',frame)}},function(ok,message)
    if ok then s.sheet=nil else app.tip(message or 'Frame konnte nicht gewählt werden.',5) end
    self:refresh(s)
  end)
end
function UI:togglePlay(s,id)
  if s.playing and s.playing.id==id then s.playing=nil;self:refresh(s);return end
  local c=N.card(s.board,id);local tag=c and A.resolve(s.sprite,c)
  if not tag then app.tip('Animations-Tag nicht gefunden.',4);return end
  local frame=math.max(tag.first,math.min(tag.last,c.frame))
  s.sheet=nil;s.playing={id=id,frame=frame,direction=nil,elapsed=0};self:refresh(s)
end
function UI:toggleSlow(s,id)
  s.slow[id]=not s.slow[id]
  self:refresh(s)
end
function UI:draftValue(d) return d.value end
function UI:endInline(s,d)
  local c=self:session(s);if c and c.connected then c:noteLock(d.id,d.field,true) end
  s.drafts[d.id..':'..d.field]=nil;if s.inline==d then s.inline=nil end;self:refresh(s)
end
function UI:finishInline(s,after)
  local d=s.inline;if not d then if after then after() end;return true end
  if after then d.after=after end
  if d.sending then return false end
  if not d.dirty then local fn=d.after;self:endInline(s,d);if fn then fn() end;return true end
  d.commitRequested=true
  local c=self:session(s)
  if not self:editable(s) then d.error='Verbindung fehlt · Entwurf bleibt hier.';d.commitRequested=false;return false end
  if c then
    if c.notePending or s.ack then return false end
    local owner
    for _,l in ipairs(c.noteLocks or {}) do if l.id==d.id and l.field==d.field then owner=l;break end end
    if not owner then
      if not d.requested or os.time()-d.requested>=3 then c:noteLock(d.id,d.field);d.requested=os.time() end
      return false
    end
    if owner.author~=c.author then d.error=owner.name..' bearbeitet diesen Text.';d.commitRequested=false;return false end
  end
  local current=N.card(s.board,d.id)
  if not current or current.versions.text~=d.base.versions.text or current.versions.title~=d.base.versions.title then
    d.error='Text wurde geändert · Rechtsklick zum Vergleichen.';d.commitRequested=false;self:refresh(s);return false
  end
  if not N.field('text',d.value) or (current.kind=='list' and select(2,d.value:gsub('\n',''))>=128) then d.error='Text zu lang (4096 Bytes / 128 Listenpunkte).';d.commitRequested=false;return false end
  local patches={N.patch(d.base,'text',d.value)}
  if d.base.title~='' then patches[#patches+1]=N.patch(d.base,'title','') end
  if current.kind=='list' then patches[#patches+1]=N.patch(current,'checks',S.checks(current,d.value)) end
  d.sending=true;d.commitRequested=false
  local ok,err=pcall(function() self:action(s,{action='patch',patches=patches},function(accepted,message)
    d.sending=false
    if not accepted then d.error=message or 'Entwurf bleibt erhalten.';d.after=nil;self:refresh(s);return end
    local card=N.card(s.board,d.id)
    if not card then d.error='Element gelöscht · Entwurf kopieren.';return end
    d.base=N.copy(card);d.dirty=d.value~=S.text(card)
    if d.dirty then d.commitRequested=true
    else local fn=d.after;self:endInline(s,d);if fn then fn() end end
  end) end)
  if not ok then d.sending=false;d.error=tostring(err);d.after=nil;self:refresh(s) end
  return not s.inline
end
function UI:edit(s,id)
  if s.inline then if s.inline.id==id then return end;return self:finishInline(s,function() self:edit(s,id) end) end
  local card=N.card(s.board,id);if not card or card.kind=='image' or card.kind=='animation' then return end
  if not self:editable(s) then app.tip('Notizen sind gerade nur lesbar.',4);return end
  local key=id..':text';local d=s.drafts[key]
  if not d then d=T.new(S.text(card));d.id=id;d.field='text';d.base=N.copy(card);d.dirty=false;s.drafts[key]=d end
  s.inline=d;s.selected=id
  local c=self:session(s);if c then c:noteLock(id,'text');d.renewed=os.time() end
  self:reveal(s,id);self:refresh(s)
end
function UI:inlineKey(s,ev)
  local d=s.inline;if not d then return end;ev:stopPropagation()
  if ev.code=='Escape' or ((ev.ctrlKey or ev.metaKey) and (ev.code=='Enter' or ev.code=='NumpadEnter')) then self:finishInline(s)
  elseif ev.code=='Enter' or ev.code=='NumpadEnter' then
    if not T.replace(d,'\n',4096) then d.error='Text zu lang.' end;d.dirty=d.value~=S.text(d.base)
  elseif ev.code~='Tab' then
    local previous=d.value;local err=T.key(d,ev,'text',app.clipboard)
    if err then d.error=err elseif previous~=d.value then d.dirty=d.value~=S.text(d.base) end
  end
  if s.inline then self:reveal(s,s.inline.id,true) end;self:refresh(s)
end
function UI:toggle(s,id,index)
  local c=assert(N.card(s.board,id));local value=c.checks..string.rep('0',math.max(0,index-#c.checks))
  value=value:sub(1,index-1)..(value:sub(index,index)=='1' and '0' or '1')..value:sub(index+1)
  self:action(s,{action='patch',patches={N.patch(c,'checks',value)}})
end
function UI:remove(s,id,tail)
  local c=N.card(s.board,id);if c then self:action(s,{action='delete',id=id,versions=N.copy(c.versions),revision=s.board.revision,children=tail}) end
end
function UI:chosen(s,id)
  if id and s.selection[id] then return N.copy(s.selection) end
  return id and {[id]=true} or N.copy(s.selection)
end
function UI:copy(s,id,tail)
  local text=tail and B.copyTail(s.board,id) or B.copy(s.board,id and {[id]=true} or s.selection)
  app.clipboard.text=text
end
function UI:cut(s,id)
  local selected=id and {[id]=true} or self:chosen(s,s.selected)
  local many=not id and next(selected,next(selected))~=nil
  local text=(id or not many) and B.copyTail(s.board,id or next(selected)) or B.copy(s.board,selected)
  app.clipboard.text=text -- Never delete if clipboard access was denied.
  if id or not many then
    local key=id or next(selected);local c=assert(N.card(s.board,key))
    local tail=S.tail(s.board,key)
    self:action(s,{action='delete',id=key,versions=N.copy(c.versions),revision=s.board.revision,children=true},function(ok,message)
      if ok then for _,removed in ipairs(tail) do s.selection[removed]=nil end;s.selected=next(s.selection)
      else app.tip(message or 'Ausschneiden fehlgeschlagen; Kopie bleibt in der Zwischenablage.',5) end
    end)
  else
    self:action(s,B.delete(s.board,selected),function(ok,message)
      if ok then s.selection={};s.selected=nil
      else app.tip(message or 'Ausschneiden fehlgeschlagen; Kopie bleibt in der Zwischenablage.',5) end
    end)
  end
end
function UI:paste(s,x,y)
  local clipboard=app.clipboard.content
  local text=clipboard and clipboard.text
  local image=clipboard and clipboard.image
  local point={x=clamp(((x or (s.width or 660)/2)-s.ox)/s.zoom),y=clamp(((y or (s.height or 410)/2)-s.oy)/s.zoom)}
  local operation,created
  if type(text)=='string' and (text:find('"idea-board-elements-v1"',1,true) or text:find('"idea-board-elements-v2"',1,true)) then
    operation,created=B.paste(s.board,text,point.x,point.y)
  elseif image then
    local c=N.newCard('','',point.x,point.y)
    c.kind='image';c.image=I.pack(image,clipboard.palette,0);c.color=F.colors[7]
    operation={action='patch',patches={{id=c.id,expected=false,value=c}}};created={c}
  elseif type(text)=='string' and text~='' then
    text=text:gsub('\r\n','\n'):gsub('\r','\n')
    assert(N.field('text',text),'Text aus Zwischenablage ist zu lang (4096 Bytes).')
    local c=N.newCard('','',point.x,point.y);c.text=text;c.color=F.colors[1]
    operation={action='patch',patches={{id=c.id,expected=false,value=c}}};created={c}
  else app.tip('Zwischenablage enthält keinen Text oder kein Bild.',4);return end
  self:action(s,operation,function(ok,message)
    if ok then
      s.selection={};for _,c in ipairs(created) do s.selection[c.id]=true end
      s.selected=created[1].id;self:reveal(s,created[1].id)
    else app.tip(message or 'Einfügen fehlgeschlagen.',5) end
  end)
end
function UI:duplicate(s,id,tail)
  local selected=id and {[id]=true} or s.selection
  local copied=tail and B.copyTail(s.board,id) or B.copy(s.board,selected)
  local _,map=self:layout(s)
  local minx,miny=1e6,1e6
  for key in pairs(selected) do if map[key] then minx=math.min(minx,map[key].x);miny=math.min(miny,map[key].y) end end
  local op,cards=B.paste(s.board,copied,minx+22,miny+22)
  self:action(s,op,function(ok,message)
    if ok then s.selection={};for _,c in ipairs(cards) do s.selection[c.id]=true end;s.selected=cards[1].id;self:reveal(s,cards[1].id)
    else app.tip(message or 'Duplizieren fehlgeschlagen.',5) end
  end)
end
function UI:deleteSelected(s)
  local selected=self:chosen(s,s.selected)
  if not next(selected) then return end
  local count=0;for _ in pairs(selected) do count=count+1 end
  if count==1 then
    local id=next(selected);local c=N.card(s.board,id)
    self:action(s,{action='delete',id=id,versions=N.copy(c.versions),revision=s.board.revision,children=false},function(ok,message)
      if ok then s.selection={};s.selected=nil else app.tip(message or 'Element wurde inzwischen verändert.',5) end
    end)
    return
  end
  self:action(s,B.delete(s.board,selected),function(ok,message)
    if ok then s.selection={};s.selected=nil else app.tip(message or 'Auswahl wurde inzwischen verändert.',5) end
  end)
end
function UI:menu(s,id,x,y,page)
  local items={};local function item(label,fn) items[#items+1]={label=label,fn=fn} end
  local c=id and N.card(s.board,id);local draft=s.inline
  if draft and draft.error then
    -- A conflicting unsent draft must remain recoverable even when the normal
    -- element menu is deliberately reduced to four actions.
    item('Entwurf kopieren',function() app.clipboard.text=draft.value end)
    item('Gemeinsamen Text ansehen',function() local now=N.card(s.board,draft.id);self:compare(s,now and S.text(now) or 'Element wurde gelöscht.') end)
    item('Meinen Text übernehmen',function()
      local now=N.card(s.board,draft.id);if not now then return end
      draft.base=N.copy(now);draft.error=nil;draft.dirty=draft.value~=S.text(now);self:finishInline(s)
    end)
    item('Entwurf verwerfen',function() if not draft.sending then self:endInline(s,draft) end end)
  else
    if not c then
      item('Einfügen',function() self:paste(s,x,y) end)
      item('Sortieren',function()
        local op=B.sort(s.board)
        if #op.patches>0 then self:action(s,op,function(ok,message)
          if ok then self:fit(s) else app.tip(message or 'Elemente wurden inzwischen verändert.',5) end
        end) end
      end)
      item('Undo',function() self:action(s,{action='undo'}) end)
      item('Redo',function() self:action(s,{action='redo'}) end)
    else
      item('Löschen',function()
        if s.selection[id] and next(s.selection,next(s.selection)) then self:deleteSelected(s)
        else self:remove(s,id,false) end
      end)
      item('Kopieren',function() self:copy(s,id,true) end)
      item('Ausschneiden',function() self:cut(s,id) end)
      item('Duplizieren',function() self:duplicate(s,id,false) end)
      items[#items+1]={colors=true,id=id}
    end
  end
  local width=112
  for _,v in ipairs(items) do if v.label then width=math.max(width,F.measure(v.label,'ui')+18) end end
  s.menu={x=x,y=y,w=width,items=items,offset=0};s.menuHover=nil
  self:refresh(s)
end
function UI:compare(s,text)
  local d=Dialog{title='Gemeinsamer Text'};local w,h=L.canvas(900,600)
  local uiScale=math.max(1,app.uiScale or 1)
  w=math.max(180,math.floor(w/uiScale));h=math.max(100,math.floor(h/uiScale))
  local rows=S.lines(text,false,w-24);local offset=0
  d:canvas{width=w,height=h,autoscaling=true,onpaint=function(ev)
    local gc=ev.context;F.bind(gc);gc.color=F.color('#2B2C30');gc:fillRect(Rectangle(0,0,gc.width,gc.height))
    for i=offset+1,math.min(#rows,offset+math.floor((gc.height-16)/20)) do F.draw(gc,rows[i].text,12,8+(i-offset-1)*20,1,'ui',true) end
    F.unbind()
  end,onwheel=function(ev) offset=math.max(0,math.min(math.max(0,#rows-1),offset+ev.deltaY*3));d:repaint() end}
    :newrow():button{text='Schließen'}
  L.show(d)
end
function UI:preview(s,id)
  local c=N.card(s.board,id);local cached=s.images[id]
  if not c or c.kind~='image' or not cached then return end
  if s.preview then s.preview:close() end
  local w,h=L.viewport();local uiScale=math.max(1,app.uiScale or 1)
  local width=math.max(120,math.min(c.image.width+24,math.floor(w*0.64/uiScale)))
  local height=math.max(100,math.min(c.image.height+24,math.floor(h*0.64/uiScale)))
  local panX,panY=0,0
  local dialog=Dialog{title='Referenzbild · '..c.image.width..' × '..c.image.height,onclose=function() s.preview=nil end}
  s.preview=dialog
  dialog:canvas{width=width,height=height,autoscaling=true,
    onpaint=function(ev)
      local gc=ev.context;gc.color=Color{r=35,g=37,b=41};gc:fillRect(Rectangle(0,0,gc.width,gc.height))
      local x=math.floor((gc.width-c.image.width)/2+panX)
      local y=math.floor((gc.height-c.image.height)/2+panY)
      gc:drawImage(cached.image,Rectangle(0,0,c.image.width,c.image.height),Rectangle(x,y,c.image.width,c.image.height))
      s.previewImage=rect(x,y,c.image.width,c.image.height)
    end,
    onmousedown=function(ev)
      if not s.previewImage or not inside(s.previewImage,ev.x,ev.y) then dialog:close() end
    end,
    onwheel=function(ev)
      if ev.shiftKey then panX=panX-ev.deltaY*20 else panY=panY-ev.deltaY*20 end
      dialog:repaint()
    end}
  L.show(dialog)
end
function UI:paperPreview(s,id)
  V.open(self,s,id)
end
function UI:placeOnPaper(s,sourceId,paperId,frame)
  local source=N.card(s.board,sourceId);local paper=N.card(s.board,paperId)
  assert(source and paper and paper.kind=='paper' and source.id~=paper.id,'Skizzenblatt oder Quelle fehlt')
  local draft=s.paperDrafts[paperId]
  assert(not draft or not draft.dirty,'Skizzenblatt hat noch ungespeicherte Striche')
  local sourceImage=P.source(s.sprite,source,frame)
  assert(sourceImage,'Bild/Frame konnte nicht als Vorlage gelesen werden')
  local composed=P.overlay(P.unpack(paper.image),sourceImage)
  self:action(s,{action='patch',patches={N.patch(paper,'image',composed)}},function(ok,message)
    if not ok then app.tip(message or 'Vorlage konnte nicht auf das Blatt gelegt werden.',5) end
  end)
end
function UI:paperAt(s,x,y,ignore)
  local displays=B.display(S.layout(s.board),s.zoom,s.ox,s.oy)
  for i=#displays,1,-1 do
    local v=displays[i]
    if v.box.card.kind=='paper' and v.box.card.id~=ignore and inside(rect(v.x,v.y,v.w,v.h),x,y) then
      return v.box.card.id
    end
  end
end
function UI:plusMenu(s,id,dock,x,y)
  local function add(kind,style) return function() self:add(s,kind,style,nil,nil,id,dock) end end
  s.menu={x=x,y=y,w=118,offset=0,items={
    {label='Text',fn=add('text')},
    {label='Checkliste',fn=add('list','check')},
    {label='Punktliste',fn=add('list','bullet')},
    {label='Nummeriert',fn=add('list','number')},
    {label='Bild',fn=function() self:import(s,nil,id,dock) end},
  }}
  self:refresh(s)
end
function UI:doubleClick(s,ev)
  if s.paper then return end
  s.drag=nil;s.marquee=nil;s.pendingCheck=nil;s.pointerDown=false;s.selecting=false
  local id,h=self:hit(s,ev.x,ev.y)
  if h and (h.kind=='tool' or h.kind=='menu' or h.kind=='color' or h.kind=='plus' or h.kind=='check') then return end
  if id then
    local c=N.card(s.board,id)
    if c and c.kind=='image' then self:preview(s,id)
    elseif c and c.kind=='paper' then self:paperPreview(s,id)
    elseif c and c.kind=='animation' then self:openSheet(s,id)
    elseif c then self:edit(s,id) end
  else
    self:add(s,'text',nil,{x=clamp((ev.x-s.ox)/s.zoom),y=clamp((ev.y-s.oy)/s.zoom)})
  end
end
function UI:paint(s,ev)
  if s.paper then V.paint(self,s,ev);return end
  local gc=ev.context;s.width=gc.width;s.height=gc.height;s.hits={}
  F.bind(gc)
  gc.antialias=false;gc.opacity=255;gc.color=Color{r=39,g=40,b=43};gc:fillRect(Rectangle(0,0,gc.width,gc.height))
  local function hit(id,kind,r,extra) s.hits[#s.hits+1]={id=id,kind=kind,r=r,extra=extra} end
  local boxes=self:layout(s)
  local moving=s.drag and s.drag.moved and (s.drag.group and s.drag.selection or {[s.drag.id]=true})
  local displays,displayMap=B.display(boxes,s.zoom,s.ox,s.oy,moving)
  for _,v in ipairs(displays) do
    local b=v.box;local c=b.card;local x,y,w,h,z=v.x,v.y,v.w,v.h,v.scale
    if x+w>0 and y+h>0 and x<gc.width and y<gc.height then
      local d=s.inline and s.inline.id==c.id and s.inline or nil
      F.box(gc,x,y+2,w,h,Color{r=23,g=24,b=26,a=120},5*z)
      local border=d and d.error and '#CF6F7E' or s.selection[c.id] and '#A9D6CA' or '#5D6268'
      F.box(gc,x-1,y-1,w+2,h+2,F.color(border),6*z)
      F.box(gc,x,y,w,h,F.paper(c.color),5*z)
      hit(c.id,'drag',rect(x,y,w,h),b)
      local attribution=s.board.authors and s.board.authors[c.id]
      if attribution then
        local name=L.short(attribution.edited~='' and attribution.edited or attribution.created,14)
        if name~='' then
          local nameWidth=math.min(w-14*z,F.measure(name,'ui')*z+9*z)
          F.box(gc,x+w-nameWidth-4*z,y+2*z,nameWidth,12*z,Color{r=36,g=47,b=53,a=42},3*z)
          F.draw(gc,name,x+w-nameWidth+1*z,y+2*z,z,'ui')
        end
      end
      if c.kind=='image' or c.kind=='paper' then
        local cached=s.images[c.id]
        if cached then
          local image=cached.image
          if c.kind=='paper' then image=self:paperThumbnail(s,c,math.max(1,math.floor(math.min(b.w-16,126)*z))) end
          local scale=math.min((b.w-16)/image.width,(c.kind=='paper' and 126 or 112)/image.height)*z
          local iw,ih=image.width*scale,image.height*scale
          if c.kind=='paper' then F.box(gc,math.floor(x+(w-iw)/2),math.floor(y+20*z),math.max(1,math.floor(iw)),math.max(1,math.floor(ih)),F.color('#FFFFFF')) end
          gc.blendMode=BlendMode.NORMAL
          gc:drawImage(image,Rectangle(0,0,image.width,image.height),Rectangle(math.floor(x+(w-iw)/2),math.floor(y+20*z),math.max(1,math.floor(iw)),math.max(1,math.floor(ih))))
        end
      elseif c.kind=='animation' then
        local tag=A.resolve(s.sprite,c)
        local frame=tag and (s.sheet and s.sheet.id==c.id and math.min(tag.last,tag.first+s.sheet.index-1) or
          s.playing and s.playing.id==c.id and s.playing.frame or math.max(tag.first,math.min(tag.last,c.frame)))
        F.draw(gc,L.short(c.tag~='' and c.tag or '(ohne Namen)',21),x+8*z,y+18*z,z,'ui',true)
        if frame then
          if not self:drawThumbnail(s,gc,frame,x+8*z,y+36*z,w-16*z,h-55*z) then F.draw(gc,'Bild zu groß',x+12*z,y+58*z,z,'ui') end
          F.draw(gc,frame..'/'..#s.sprite.frames,x+8*z,y+h-17*z,z,'ui')
          local sx,sy=math.floor(x+w-45*z),math.floor(y+h-23*z)
          F.panel(gc,sx,sy,18*z,17*z,F.color(s.slow[c.id] and '#557C70' or '#4B5559'))
          F.draw(gc,'¼',sx+3*z,sy+2*z,z,'ui',s.slow[c.id])
          hit(c.id,'slow',rect(sx,sy,18*z,17*z))
          local playing=s.playing and s.playing.id==c.id
          local px,py=math.floor(x+w-24*z),math.floor(y+h-23*z)
          F.panel(gc,px,py,18*z,17*z,F.color(playing and '#557C70' or '#4B5559'))
          if playing then F.box(gc,px+6*z,py+4*z,6*z,9*z,F.color('#F1F5F1'))
          else
            for row=0,8 do
              local length=math.max(1,5-math.abs(4-row))
              F.box(gc,px+6*z,py+(4+row)*z,length*z,z,F.color('#F1F5F1'))
            end
          end
          hit(c.id,'play',rect(px,py,18*z,17*z))
        else F.draw(gc,'Tag fehlt',x+8*z,y+58*z,z,'ui') end
      else
        local rows=b.rows
        hit(c.id,'text',rect(x+12*z,y+8*z,w-24*z,h-16*z),b)
        if d then d.draw={lines={},heading=b.heading,z=z} end
        local a,finish=0,0;if d then a,finish=T.selection(d) end
        for i,row in ipairs(rows) do
          local text=row.text
          local placeholder=text=='' and #rows==1
          local shown=placeholder and (c.kind=='list' and 'Listenpunkt …' or 'Text …') or text
          local rx,top=S.rowPosition(b,i,placeholder and not d and shown or text)
          local tx,ry=x+rx*z,y+top*z
          if d then
            local left=math.max(0,a-row.start);local right=math.min(T.length(text),finish-row.start)
            if right>left then
              gc.color=Color{r=113,g=156,b=187,a=100};gc:fillRect(Rectangle(math.floor(tx+F.measure(T.slice(text,0,left),b.heading)*z),math.floor(ry),math.max(1,math.floor((F.measure(T.slice(text,0,right),b.heading)-F.measure(T.slice(text,0,left),b.heading))*z)),math.floor(b.lineHeight*z)))
            end
            local widths={};for n=0,T.length(text) do widths[n]=F.measure(T.slice(text,0,n),b.heading)*z end
            d.draw.lines[#d.draw.lines+1]={r=rect(tx,ry,math.max(1,F.measure(text,b.heading))*z,b.lineHeight*z),widths=widths,start=row.start,length=T.length(text)}
            if d.cursor>=row.start and d.cursor<=row.start+T.length(text) then
              local cx=tx+widths[d.cursor-row.start];gc.color=Color{r=43,g=66,b=82};gc:fillRect(Rectangle(math.floor(cx),math.floor(ry+3*z),math.max(1,math.floor(z)),math.floor((b.lineHeight-5)*z)))
            end
          end
          if c.kind=='list' and row.first then
            if c.listStyle=='check' then
              local done=c.checks:sub(row.index,row.index)=='1';local cr=rect(tx-16*z,ry+1*z,10*z,10*z)
              F.box(gc,cr.x,cr.y,cr.w,cr.h,F.color(done and '#7EAC97' or '#839A8D'),3*z)
              if not done then F.box(gc,cr.x+z,cr.y+z,cr.w-2*z,cr.h-2*z,F.paper(c.color),2*z)
              else gc.color=Color{r=250,g=255,b=251};gc:beginPath();gc:moveTo(cr.x+2*z,cr.y+5*z);gc:lineTo(cr.x+4*z,cr.y+7*z);gc:lineTo(cr.x+8*z,cr.y+2*z);gc:stroke() end
              hit(c.id,'check',cr,{index=row.index,box=b})
            elseif c.listStyle=='number' then F.draw(gc,row.index..'.',tx-19*z,ry,z,false)
            else F.box(gc,tx-14*z,ry+5*z,3*z,3*z,F.color('#526559')) end
          end
          if placeholder then gc.opacity=110;if not d then text=shown end end
          F.draw(gc,text,tx,ry,z,b.heading);gc.opacity=255
          if c.kind=='list' and c.listStyle=='check' and c.checks:sub(row.index,row.index)=='1' and text~='' and not placeholder then
            gc.color=Color{r=43,g=57,b=62,a=230}
            gc:fillRect(Rectangle(math.floor(tx),math.floor(ry+6*z+0.5),math.max(1,math.floor(F.measure(text,b.heading)*z+0.5)),1))
          end
        end
      end
      if s.selection[c.id] or s.hover==c.id then F.box(gc,x+w/2-10*z,y+3*z,20*z,2*z,Color{r=103,g=114,b=121,a=100},z) end
      if d and (d.error or d.sending) then F.box(gc,x+w-10*z,y+7*z,4*z,4*z,F.color(d.error and '#B74158' or '#7295AB'),2*z) end
    end
  end
  local plusHover=s.hover
  if not plusHover and s.pointerX and s.pointerY then
    local best=1e9
    for _,candidate in ipairs(displays) do
      local v=candidate;local c=v.box.card
      for _,dock in ipairs({'below','left','right'}) do
        if not S.occupied(s.board,c)[dock] then
          local px=dock=='left' and v.x-13 or dock=='right' and v.x+v.w-2 or v.x+math.floor((v.w-15)/2)
          local py=dock=='below' and v.y+v.h-2 or v.y+math.floor((v.h-15)/2)
          local dx=math.max(px-11-s.pointerX,0,s.pointerX-(px+26))
          local dy=math.max(py-11-s.pointerY,0,s.pointerY-(py+26))
          local distance=(s.pointerX-px-7)^2+(s.pointerY-py-7)^2
          if dx==0 and dy==0 and distance<best then best=distance;plusHover=c.id end
        end
      end
    end
  end
  if plusHover and displayMap[plusHover] and not s.drag and not s.menu and not s.tagMenu and not s.sheet then
    local v=displayMap[plusHover]
    local occupied=S.occupied(s.board,v.box.card)
    for _,dock in ipairs({'below','left','right'}) do if not occupied[dock] then
      local px=dock=='left' and v.x-13 or dock=='right' and v.x+v.w-2 or v.x+math.floor((v.w-15)/2)
      local py=dock=='below' and v.y+v.h-2 or v.y+math.floor((v.h-15)/2)
      px=math.floor(px);py=math.floor(py)
      F.panel(gc,px,py,15,15,F.color('#252B2E'))
      F.box(gc,px+2,py+2,11,11,F.color('#789E91'))
      F.box(gc,px+7,py+4,1,7,F.color('#F1F5F1'))
      F.box(gc,px+4,py+7,7,1,F.color('#F1F5F1'))
      hit(plusHover,'plus',rect(px,py,15,15),{dock=dock})
    end end
  end
  if s.drag and s.drag.target then local v=displayMap[s.drag.target.card.id];if v then
    local dock=s.drag.target.dock
    if dock=='below' then F.box(gc,v.x,v.y+v.h+2*v.scale,v.w,3*v.scale,F.color('#B7DBC7'),v.scale)
    elseif dock=='left' then F.box(gc,v.x-5*v.scale,v.y,3*v.scale,v.h,F.color('#B7DBC7'),v.scale)
    else F.box(gc,v.x+v.w+2*v.scale,v.y,3*v.scale,v.h,F.color('#B7DBC7'),v.scale) end
  end end
  if s.drag and s.drag.sheetTarget and displayMap[s.drag.sheetTarget] then
    local v=displayMap[s.drag.sheetTarget]
    gc.color=F.color('#B9E8D9');gc:strokeRect(Rectangle(v.x-2,v.y-2,v.w+4,v.h+4))
  end
  if s.frameDrag and s.frameDrag.paperId and displayMap[s.frameDrag.paperId] then
    local v=displayMap[s.frameDrag.paperId]
    gc.color=F.color('#B9E8D9');gc:strokeRect(Rectangle(v.x-2,v.y-2,v.w+4,v.h+4))
  end
  if s.marquee then
    local a=s.marquee;local x1,y1=a.x1*s.zoom+s.ox,a.y1*s.zoom+s.oy
    local x2,y2=a.x2*s.zoom+s.ox,a.y2*s.zoom+s.oy
    local x,y=math.min(x1,x2),math.min(y1,y2)
    local w,h=math.abs(x2-x1),math.abs(y2-y1)
    if w>2 and h>2 then
      F.box(gc,x,y,w,h,Color{r=138,g=199,b=190,a=42},3)
      gc.color=F.color('#8ECFC6');gc:strokeRect(Rectangle(x,y,w,h))
    end
  end
  if s.sheet then
    local c=N.card(s.board,s.sheet.id);local tag=c and A.resolve(s.sprite,c);local anchor=displayMap[s.sheet.id]
    if tag and anchor then
      s.sheet.index=math.max(1,math.min(tag.last-tag.first+1,s.sheet.index))
      local thumbW,thumbH,step=48,48,56
      local cx=anchor.x+anchor.w/2
      local top=math.floor(anchor.y+anchor.h/2-thumbH/2)
      local visible=math.ceil(gc.width/step)+1
      local first=math.max(1,s.sheet.index-visible)
      local last=math.min(tag.last-tag.first+1,s.sheet.index+visible)
      for index=first,last do
        local x=math.floor(cx-thumbW/2+(index-s.sheet.index)*step)
        if x+thumbW>=0 and x<=gc.width then
          local active=index==s.sheet.index
          F.box(gc,x-3,top-3,thumbW+6,thumbH+20,F.color(active and '#B9E8D9' or '#646A70'),3)
          F.box(gc,x-1,top-1,thumbW+2,thumbH+2,F.color('#27292D'))
          self:drawThumbnail(s,gc,tag.first+index-1,x,top,thumbW,thumbH)
          F.draw(gc,tostring(tag.first+index-1),x+4,top+thumbH+1,1,'ui',active)
          hit(s.sheet.id,'frame',rect(x-3,top-3,thumbW+6,thumbH+20),{index=index})
        end
      end
    else s.sheet=nil end
  end
  -- A small floating island replaces creation commands in the context menu.
  local tools={
    {label='Text',run=function() self:add(s,'text') end},
    {label='Liste',run=function() s.listMenu=not s.listMenu;s.tagMenu=nil;self:refresh(s) end},
    {label='Bild',run=function() self:import(s) end},
    {label='Skizzenblatt',run=function() s.placingPaper=true;s.listMenu=nil;self:refresh(s) end},
    {label='Animationen',run=function() s.tagMenu=not s.tagMenu;s.listMenu=nil;s.sheet=nil;self:refresh(s) end},
  }
  local button=20;local gap=3;local islandW=4*button+5*gap;local historyW=2*button+3*gap
  local historyX=gc.width-historyW-5
  local islandY=6;local narrow=gc.width<islandW+historyW+50
  local islandX=math.max(39,math.min(math.floor((gc.width-islandW)/2),narrow and gc.width-islandW-5 or historyX-islandW-8))
  local historyY=narrow and islandY+29 or islandY
  F.panel(gc,islandX+1,islandY+2,islandW,button+6,F.color('#17191C'))
  F.panel(gc,islandX,islandY,islandW,button+6,F.color('#596069'))
  F.panel(gc,islandX+1,islandY+1,islandW-2,button+4,F.color('#3E4249'))
  for i,tool in ipairs(tools) do
    local tx=i==5 and 8 or islandX+gap+(i-1)*(button+gap);local ty=islandY+3
    if i==5 then
      F.panel(gc,6,islandY+2,26,button+6,F.color('#17191C'))
      F.panel(gc,5,islandY,26,button+6,F.color('#596069'))
      F.panel(gc,6,islandY+1,24,button+4,F.color('#3E4249'))
    end
    local active=s.toolHover==i
    F.panel(gc,tx,ty,button,button,F.color(active and '#606F75' or '#34383E'))
    if i==2 then
      F.box(gc,tx+3,ty+4,4,4,F.color('#BDDAD4'));F.box(gc,tx+3,ty+12,4,4,F.color('#BDDAD4'))
      F.box(gc,tx+9,ty+5,8,2,F.color('#E4E9EB'));F.box(gc,tx+9,ty+13,8,2,F.color('#E4E9EB'))
    elseif i==3 then
      gc.color=F.color('#E4E9EB');gc:strokeRect(Rectangle(tx+3,ty+4,14,12))
      gc:beginPath();gc:moveTo(tx+4,ty+15);gc:lineTo(tx+8,ty+10);gc:lineTo(tx+11,ty+12);gc:lineTo(tx+16,ty+7);gc:stroke()
    elseif i==4 then
      F.box(gc,tx+4,ty+3,12,15,F.color('#E4E9EB'))
      F.box(gc,tx+6,ty+6,8,1,F.color('#86989A'))
      F.box(gc,tx+6,ty+9,8,1,F.color('#86989A'))
      F.box(gc,tx+6,ty+12,5,1,F.color('#86989A'))
    elseif i==5 then
      F.box(gc,tx+3,ty+4,14,2,F.color('#E4E9EB'))
      F.box(gc,tx+3,ty+9,14,2,F.color('#E4E9EB'))
      F.box(gc,tx+3,ty+14,10,2,F.color('#E4E9EB'))
      F.box(gc,tx+14,ty+13,3,4,F.color('#B8D6CD'))
    else
      F.box(gc,tx+3,ty+4,14,2,F.color('#E4E9EB'))
      F.box(gc,tx+9,ty+5,2,11,F.color('#E4E9EB'))
    end
    hit(nil,'tool',rect(tx,ty,button,button),{index=i,run=tool.run})
  end
  if s.listMenu then
    local x,y=islandX+button+gap+2,islandY+button+11
    F.panel(gc,x,y,112,59,F.color('#33383D'))
    for i,item in ipairs({{label='Checkliste',style='check'},{label='Punktliste',style='bullet'},{label='Nummeriert',style='number'}}) do
      local row=rect(x+4,y+3+(i-1)*18,104,17)
      F.box(gc,row.x,row.y,row.w,row.h,F.color('#454B50'))
      F.draw(gc,item.label,row.x+7,row.y+2,1,'ui',true)
      hit(nil,'listChoice',row,item.style)
    end
  end
  F.panel(gc,historyX+1,historyY+2,historyW,button+6,F.color('#17191C'))
  F.panel(gc,historyX,historyY,historyW,button+6,F.color('#596069'))
  F.panel(gc,historyX+1,historyY+1,historyW-2,button+4,F.color('#3E4249'))
  for i,action in ipairs({'undo','redo'}) do
    local tx=historyX+gap+(i-1)*(button+gap);local ty=historyY+3
    F.panel(gc,tx,ty,button,button,F.color(s.historyHover==i and '#606F75' or '#34383E'))
    local ink=F.color('#E4E9EB')
    F.arrow(gc,tx+2,ty+3,i==2,ink)
    hit(nil,'tool',rect(tx,ty,button,button),{history=i,run=function() self:action(s,{action=action}) end})
  end
  if s.toolHover then
    local label=tools[s.toolHover].label;local w=F.measure(label,'ui')+18
    local x=s.toolHover==5 and 5 or islandX+(islandW-w)/2
    F.box(gc,x,islandY+button+8,w,17,F.color('#3E4249'))
    F.draw(gc,label,x+9,islandY+button+10,1,'ui',true)
  end
  if s.historyHover then
    local label=s.historyHover==1 and 'Undo' or 'Redo';local w=F.measure(label,false)+16
    F.panel(gc,historyX+historyW-w,historyY+button+8,w,16,F.color('#3E4249'))
    F.draw(gc,label,historyX+historyW-w+8,historyY+button+9,1,'ui',true)
  end
  if s.tagMenu then
    local tags=A.tags(s.sprite);local x,y,w,rowH=5,historyY+button+11,174,39
    w=math.min(w,gc.width-10)
    local visible=math.max(1,math.min(#tags,math.floor((gc.height-y-8)/rowH)))
    s.tagVisible=visible;s.tagScroll=math.max(0,math.min(s.tagScroll or 0,math.max(0,#tags-visible)))
    local h=math.max(rowH,visible*rowH)+8
    F.box(gc,x,y,w,h,F.color('#27292D'),4)
    if #tags==0 then F.draw(gc,'Keine Animationen',x+10,y+13,1,'ui') end
    for i=s.tagScroll+1,math.min(#tags,s.tagScroll+visible) do
      local tag=tags[i];local iy=y+4+(i-s.tagScroll-1)*rowH
      F.box(gc,x+4,iy,w-8,rowH-2,F.color('#3B4147'),3)
      F.box(gc,x+7,iy+4,30,30,F.color('#25282B'),2)
      self:drawThumbnail(s,gc,tag.first,x+8,iy+5,28,28)
      F.draw(gc,L.short(tag.name~='' and tag.name or '(ohne Namen)',16),x+43,iy+6,1,'ui',true)
      F.draw(gc,(tag.last-tag.first+1)..' Frames',x+43,iy+19,1,'ui')
      hit(nil,'tagItem',rect(x+4,iy,w-8,rowH-2),tag)
    end
  end
  if s.tagDrag and s.tagDrag.moved and s.pointerX and s.pointerY then
    local x,y=math.floor(s.pointerX-29),math.floor(s.pointerY-23)
    F.box(gc,x,y,58,46,F.color('#B9E8D9'),3)
    F.box(gc,x+2,y+2,54,42,F.color('#30353A'),2)
    self:drawThumbnail(s,gc,s.tagDrag.tag.first,x+5,y+4,48,31)
    F.draw(gc,L.short(s.tagDrag.tag.name,8),x+5,y+34,1,'ui')
  end
  if s.placingPaper and s.pointerX and s.pointerY then
    local x,y=math.floor(s.pointerX-14),math.floor(s.pointerY-18)
    F.box(gc,x,y,28,36,F.color('#DCE7DF'),2)
    F.box(gc,x+4,y+8,19,2,F.color('#879B91'))
    F.box(gc,x+4,y+14,15,2,F.color('#879B91'))
  end
  if s.menu then
    local m=s.menu;local rowHeight=17
    m.w=math.min(m.w,gc.width-8);m.visible=math.max(1,math.min(#m.items,math.floor((gc.height-18)/rowHeight)))
    m.offset=math.min(m.offset,#m.items-m.visible);local mh=m.visible*rowHeight+10
    m.x=math.max(4,math.min(m.x,gc.width-m.w-4));m.y=math.max(4,math.min(m.y,gc.height-mh-4))
    F.box(gc,m.x+2,m.y+3,m.w,mh,F.color('#191A1C'),4)
    F.box(gc,m.x-1,m.y-1,m.w+2,mh+2,F.color('#62636A'),4)
    F.box(gc,m.x,m.y,m.w,mh,F.color('#333438'),3)
    for i=m.offset+1,math.min(#m.items,m.offset+m.visible) do
      local item=m.items[i];local r=rect(m.x+5,m.y+5+(i-m.offset-1)*rowHeight,m.w-10,rowHeight)
      if item.colors then
        local step=r.w/#F.colors
        local current=N.card(s.board,item.id)
        for n,color in ipairs(F.colors) do
          local cr=rect(r.x+2+(n-1)*step,r.y+2,step-4,12)
          if current and current.color==color then F.box(gc,cr.x-1,cr.y-1,cr.w+2,cr.h+2,F.color('#E8F0F4'),4) end
          F.box(gc,cr.x,cr.y,cr.w,cr.h,F.color(color),3);hit(item.id,'color',cr,color)
        end
      else
        if s.menuHover==i and not item.section then F.box(gc,r.x,r.y,r.w,r.h,F.color('#50535B'),2) end
        F.draw(gc,item.label,r.x+8,r.y+2,1,'ui',true)
        if not item.section then hit(nil,'menu',r,item.fn) end
      end
    end
    if m.offset>0 then F.box(gc,m.x+m.w/2-8,m.y,16,2,F.color('#AEBECD'),1) end
    if m.offset+m.visible<#m.items then F.box(gc,m.x+m.w/2-8,m.y+mh-2,16,2,F.color('#AEBECD'),1) end
  end
  F.unbind()
end
function UI:hit(s,x,y)
  for i=#(s.hits or {}),1,-1 do local h=s.hits[i];if inside(h.r,x,y) then return h.id,h end end
end
function UI:placeCaret(d,x,y)
  if not d.draw then return end
  local rows=d.draw.lines;local row=rows[#rows]
  for _,r in ipairs(rows) do if y<r.r.y+r.r.h then row=r;break end end
  local pos=0;for n=1,row.length do if x-row.r.x>=(row.widths[n-1]+row.widths[n])/2 then pos=n else break end end
  d.cursor=row.start+pos
end
function UI:pointerDown(s,ev)
  if s.paper then V.down(self,s,ev);return end
  s.pointerDown=true;s.pointerX=ev.x;s.pointerY=ev.y;local id,h=self:hit(s,ev.x,ev.y)
  if ev.button==MouseButton.RIGHT then
    if id and not s.selection[id] then s.selection={[id]=true};s.selected=id end
    s.rightDown={id=id,x=ev.x,y=ev.y,ox=s.ox,oy=s.oy,moved=false}
    return
  end
  if s.menu then
    s.menu=nil
    if h and h.kind=='menu' then h.extra();self:refresh(s);return
    elseif h and h.kind=='color' then local c=N.card(s.board,h.id);if c then self:action(s,{action='patch',patches={N.patch(c,'color',h.extra)}}) end;return end
    self:refresh(s);return
  end
  if ev.button==MouseButton.MIDDLE then s.drag={startX=ev.x,startY=ev.y,ox=s.ox,oy=s.oy};return end
  if ev.button~=MouseButton.LEFT then return end
  if h and h.kind=='listChoice' then
    s.listMenu=nil;self:add(s,'list',h.extra);return
  end
  if s.listMenu then s.listMenu=nil;self:refresh(s) end
  if h and h.kind=='tagItem' then s.tagDrag={tag=h.extra,x=ev.x,y=ev.y};s.tagMenu=nil;self:refresh(s);return end
  if s.tagMenu then s.tagMenu=nil;self:refresh(s) end
  if h and h.kind=='frame' then s.frameDrag={index=h.extra.index,start=s.sheet.index,x=ev.x};return end
  if s.sheet and (not id or id~=s.sheet.id) then s.sheet=nil;self:refresh(s) end
  if h and h.kind=='play' then self:togglePlay(s,id);return end
  if h and h.kind=='slow' then self:toggleSlow(s,id);return end
  local d=s.inline
  if h and h.kind=='tool' then
    local fn=h.extra.run
    if d then self:finishInline(s,fn) else fn() end
    return
  end
  if h and h.kind=='plus' then
    local open=function() self:plusMenu(s,id,h.extra.dock,ev.x,ev.y) end
    if d then self:finishInline(s,open) else open() end
    return
  end
  if s.placingPaper and not id then
    s.placingPaper=nil;s.pointerDown=false
    self:add(s,'paper',nil,{x=clamp((ev.x-s.ox)/s.zoom-S.width/2),y=clamp((ev.y-s.oy)/s.zoom-S.paperHeight/2)})
    return
  end
  if d and id==d.id and h.kind=='text' then self:placeCaret(d,ev.x,ev.y);if not ev.shiftKey then d.anchor=d.cursor end;s.selecting=true;self:refresh(s);return end
  local function activate()
    if not s.pointerDown then return end
    s.selected=id
    if h and h.kind=='check' then s.pendingCheck={id=id,index=h.extra.index} end
    if id and self:editable(s) then
      local b=h.kind=='check' and h.extra.box or h.extra
      if not s.selection[id] then s.selection={[id]=true} end
      local group=next(s.selection,next(s.selection))~=nil
      s.drag={id=id,group=group,selection=N.copy(s.selection),board=N.copy(s.board),
        startX=ev.x,startY=ev.y,x=b.x,y=b.y,baseX=b.x,baseY=b.y,dx=0,dy=0}
    elseif not id then
      local x,y=(ev.x-s.ox)/s.zoom,(ev.y-s.oy)/s.zoom
      s.marquee={x1=x,y1=y,x2=x,y2=y,previous=(ev.ctrlKey or ev.shiftKey) and N.copy(s.selection) or {}}
    end
    self:refresh(s)
  end
  if d then self:finishInline(s,activate) else activate() end
end
function UI:autoPanMarquee(s)
  if not s.marquee or not s.pointerX or not s.pointerY then return end
  local w,h=s.width or 660,s.height or 410
  local margin=18
  local dx=s.pointerX<margin and 12 or s.pointerX>w-margin and -12 or 0
  local dy=s.pointerY<76 and 12 or s.pointerY>h-margin and -12 or 0
  if dx==0 and dy==0 then return end
  s.ox=s.ox+dx;s.oy=s.oy+dy
  s.marquee.x2=(math.max(0,math.min(w,s.pointerX))-s.ox)/s.zoom
  s.marquee.y2=(math.max(0,math.min(h,s.pointerY))-s.oy)/s.zoom
  self:refresh(s)
end
function UI:pointerMove(s,ev)
  if s.paper then V.move(self,s,ev);return end
  s.pointerX=ev.x;s.pointerY=ev.y
  if s.rightDown and s.pointerDown then
    local a=s.rightDown
    if not a.id and (a.moved or math.abs(ev.x-a.x)+math.abs(ev.y-a.y)>4) then
      a.moved=true;s.ox=a.ox+ev.x-a.x;s.oy=a.oy+ev.y-a.y
    end
    self:refresh(s);return
  end
  if s.frameDrag and s.sheet and s.pointerDown then
    local targetId=self:paperAt(s,ev.x,ev.y,s.sheet.id)
    if targetId then
      s.frameDrag.paperId=targetId;s.frameDrag.moved=true;self:refresh(s);return
    end
    s.frameDrag.paperId=nil
    local distance=ev.x-s.frameDrag.x
    if math.abs(distance)>5 then
      s.frameDrag.moved=true
      local target=s.frameDrag.start-math.floor(distance/56+0.5)
      self:sheetStep(s,target-s.sheet.index)
    end
    return
  end
  if s.tagDrag and s.pointerDown then s.tagDrag.moved=s.tagDrag.moved or math.abs(ev.x-s.tagDrag.x)+math.abs(ev.y-s.tagDrag.y)>7;self:refresh(s);return end
  if s.pointerDown and s.selecting and s.inline then self:placeCaret(s.inline,ev.x,ev.y);self:refresh(s);return end
  if s.pointerDown and s.marquee then s.marquee.x2=(ev.x-s.ox)/s.zoom;s.marquee.y2=(ev.y-s.oy)/s.zoom;self:autoPanMarquee(s) end
  local a=s.drag
  if a then
    if a.id then
      a.dx=math.floor((ev.x-a.startX)/s.zoom+0.5);a.dy=math.floor((ev.y-a.startY)/s.zoom+0.5)
      a.x=clamp(a.baseX+a.dx);a.y=clamp(a.baseY+a.dy)
      a.moved=a.moved or math.abs(ev.x-a.startX)+math.abs(ev.y-a.startY)>4
      if a.moved and not a.group then
        local source=N.card(s.board,a.id)
        local targetId=self:paperAt(s,ev.x,ev.y,a.id)
        a.sheetTarget=source and (source.kind=='image' or source.kind=='animation') and targetId or nil
        a.target=not a.sheetTarget and B.target(a.board,self:layout(s),a,s.zoom,s.ox,s.oy) or nil
      end
    else s.ox=a.ox+ev.x-a.startX;s.oy=a.oy+ev.y-a.startY end
  end
  local id,h=self:hit(s,ev.x,ev.y);s.hover=id
  s.toolHover=h and h.kind=='tool' and h.extra.index or nil
  s.historyHover=h and h.kind=='tool' and h.extra.history or nil
  if s.menu then s.menuHover=s.menu.offset+math.floor((ev.y-s.menu.y-5)/17)+1 end
  self:refresh(s)
end
function UI:pointerUp(s)
  if s.paper then V.up(self,s);return end
  if s.rightDown then
    local a=s.rightDown;s.rightDown=nil;s.pointerDown=false
    if not a.moved then
      local open=function() self:menu(s,a.id,a.x,a.y) end
      if s.inline and not s.inline.error then self:finishInline(s,open) else open() end
    else self:refresh(s) end
    return
  end
  local a=s.drag;local marquee=s.marquee;local pendingCheck=s.pendingCheck
  local tagDrag,frameDrag=s.tagDrag,s.frameDrag
  s.drag=nil;s.marquee=nil;s.pendingCheck=nil;s.tagDrag=nil;s.frameDrag=nil;s.pointerDown=false;s.selecting=false
  if tagDrag then
    local point=tagDrag.moved and {x=clamp((s.pointerX-s.ox)/s.zoom-S.width/2),y=clamp((s.pointerY-s.oy)/s.zoom-56)} or nil
    self:addAnimation(s,tagDrag.tag,point);self:refresh(s);return
  end
  if frameDrag then
    if frameDrag.paperId and s.sheet then
      local source=N.card(s.board,s.sheet.id);local tag=source and A.resolve(s.sprite,source)
      if tag then self:placeOnPaper(s,source.id,frameDrag.paperId,tag.first+frameDrag.index-1) end
      self:refresh(s);return
    end
    if s.sheet and not frameDrag.moved then
      if frameDrag.index==s.sheet.index then self:commitSheet(s)
      else self:sheetStep(s,frameDrag.index-s.sheet.index) end
    end
    self:refresh(s);return
  end
  if marquee then
    s.selection=marquee.previous
    local selected=B.select(self:layout(s),0,0,1,marquee.x1,marquee.y1,marquee.x2,marquee.y2)
    for id in pairs(selected) do s.selection[id]=true end
    s.selected=next(s.selection)
  end
  if a and a.id and a.moved then
    if a.sheetTarget then self:placeOnPaper(s,a.id,a.sheetTarget)
    else
      local b=a.target
      local operation=a.group and B.move(a.board,a.selection,a.dx,a.dy) or
        S.move(a.board,a.id,b and b.worldX or a.x,b and b.worldY or a.y,b and b.card.id or nil,b and b.dock or nil)
      self:action(s,operation,function(ok,message) if not ok then app.tip(message or 'Stapel wurde inzwischen verändert.',5) end end)
    end
  elseif a and a.id and N.card(s.board,a.id) and N.card(s.board,a.id).kind=='image' then
    self:preview(s,a.id)
  elseif a and a.id and N.card(s.board,a.id) and N.card(s.board,a.id).kind=='animation' then
    self:openSheet(s,a.id)
  elseif a and a.id and N.card(s.board,a.id) and N.card(s.board,a.id).kind=='paper' then
    self:paperPreview(s,a.id)
  elseif pendingCheck and not (a and a.moved) and self:editable(s) then
    self:toggle(s,pendingCheck.id,pendingCheck.index)
  end
  self:refresh(s)
end
function UI:show(sprite)
  sprite=sprite or app.sprite;if not sprite then app.tip('Bitte zuerst ein Bild öffnen.',4);return end
  local s=self:state(sprite);s.seen=true
  if s.dialog then return end
  s.windowToken=N.uid()
  self:prepare(s)
  s.dialog=Dialog{title='Collabsprite - Ideenwand #'..s.windowToken:sub(1,12),resizeable=true,onclose=function()
    if s.preview then s.preview:close() end
    if s.paper then V.close(self,s) end
    s.dialog=nil;s.realDialog=nil;s.pointerDown=false;s.selecting=false;s.drag=nil;s.rightDown=nil;s.marquee=nil;s.menu=nil;s.tagMenu=nil;s.tagDrag=nil;s.sheet=nil;s.frameDrag=nil;s.playing=nil;self:run(function() self:finishInline(s) end)
  end}
  local d=s.dialog
  local width,height=145,250
  s.realDialog=true
  s.width=width;s.height=height
  d:canvas{id='board',width=width,height=height,autoscaling=true,hexpand=true,vexpand=true,focus=true,
    onpaint=function(ev) self:paint(s,ev) end,
    ondblclick=function(ev) self:run(function() self:doubleClick(s,ev) end) end,
    onmousedown=function(ev) self:run(function() self:pointerDown(s,ev) end) end,
    onmousemove=function(ev) self:pointerMove(s,ev) end,
    onmouseup=function() self:run(function() self:pointerUp(s) end) end,
    onwheel=function(ev)
      if s.paper then V.wheel(self,s,ev);return end
      if s.menu then s.menu.offset=math.max(0,math.min(#s.menu.items-(s.menu.visible or 1),s.menu.offset+ev.deltaY));self:refresh(s);return end
      if s.tagMenu then local total=#A.tags(s.sprite);s.tagScroll=math.max(0,math.min(math.max(0,total-(s.tagVisible or 1)),(s.tagScroll or 0)+ev.deltaY));self:refresh(s);return end
      if ev.shiftKey then s.ox=s.ox-ev.deltaY*24
      else s.oy=s.oy-ev.deltaY*24 end
      self:refresh(s)
    end,
    onkeydown=function(ev)
      ev:stopPropagation()
      self:run(function()
        if s.paper then
          V.key(self,s,ev)
          return
        end
        if ev.code=='Escape' and (s.menu or s.tagMenu or s.sheet or s.listMenu or s.placingPaper) then s.menu=nil;s.tagMenu=nil;s.sheet=nil;s.listMenu=nil;s.placingPaper=nil;self:refresh(s);return end
        if s.inline then self:inlineKey(s,ev);return end
        if ev.ctrlKey or ev.metaKey then
          if ev.code=='KeyZ' or ev.code=='KeyY' then self:action(s,{action=(ev.code=='KeyY' or ev.shiftKey) and 'redo' or 'undo'})
          elseif ev.code=='KeyA' then s.selection={};for _,c in ipairs(s.board.cards) do s.selection[c.id]=true end;s.selected=next(s.selection);self:refresh(s)
          elseif ev.code=='KeyC' and s.selected then self:copy(s,nil,false)
          elseif ev.code=='KeyX' and s.selected then self:cut(s,nil)
          elseif ev.code=='KeyV' then self:paste(s)
          elseif ev.code=='KeyD' and s.selected then self:duplicate(s,nil,false) end
        elseif s.sheet and (ev.code=='ArrowLeft' or ev.code=='ArrowRight') then self:sheetStep(s,ev.code=='ArrowLeft' and -1 or 1)
        elseif s.sheet and ev.code=='Enter' then self:commitSheet(s)
        elseif (ev.code=='Delete' or ev.code=='Backspace') and s.selected then self:deleteSelected(s)
        elseif ev.code=='Enter' and s.selected then self:edit(s,s.selected) end
      end)
    end}
  if not s.layoutInitialized then self:fit(s);s.layoutInitialized=true end
  L.show(d)
  -- Use Windows' native title bar for moving and snapping the board.
  if app.preferences and app.preferences.experimental and
    app.preferences.experimental.multiple_windows==false then
    app.tip('Für Windows-Einrasten: Aseprite > Einstellungen > Experimental > Mehrere Fenster aktivieren und neu starten.',7)
  else
    if self.promote then self.promote(s.windowToken) end
    if self.files then self.files.start(s.windowToken,'Drop',s.windowToken) end
  end
  self:refresh(s)
end
function UI:pollFiles(s)
  if not self.files or not s.dialog or not s.sprite.isValid or s.ack or not self:editable(s) then return end
  local picker=s.picker
  local token=picker and picker.token or s.windowToken
  local event=self.files.read(token)
  if not event then
    if picker and os.time()-picker.started>600 then s.picker=nil;app.tip('Bildauswahl abgelaufen. Bitte erneut öffnen.',4) end
    return
  end
  if event.id==s.lastFileEvent then return end
  s.lastFileEvent=event.id
  if picker then s.picker=nil end
  if event.status=='error' then app.tip('Bildimport fehlgeschlagen. Bitte PNG, JPG, WebP, GIF oder BMP bis 64 MiB auswählen.',5);return end
  if event.status~='ok' then return end
  local point=picker and picker.point or {
    x=math.floor(((event.x or 0.5)*(s.width or 660)-s.ox)/s.zoom),
    y=math.floor(((event.y or 0.5)*(s.height or 410)-s.oy)/s.zoom)}
  self:importFiles(s,event.paths,point,picker and picker.parent,picker and picker.dock)
end
function UI:tick()
  if self.failed then return end
  self.ticks=(self.ticks or 0)+1
  for _,s in pairs(self.states) do if s.playing and s.sprite.isValid and s.dialog then
    local play=s.playing;local c=N.card(s.board,play.id);local tag=c and A.resolve(s.sprite,c)
    if not tag then s.playing=nil;self:refresh(s)
    else
      play.frame=math.max(tag.first,math.min(tag.last,play.frame))
      play.elapsed=play.elapsed+0.033*(s.slow[play.id] and 0.25 or 1)
      local changed=false
      for _=1,8 do
        local frame=s.sprite.frames[play.frame]
        local duration=frame and math.max(0.02,frame.duration) or 0.1
        if play.elapsed<duration then break end
        play.elapsed=play.elapsed-duration
        play.frame,play.direction=A.next(tag,play.frame,play.direction)
        changed=true
      end
      if changed then self:refresh(s) end
    end
  end end
  -- A resized editor must not rebuild the independent board window.
  if self.ticks%6~=0 then return end
  local current=app.sprite
  if current then local s=self:state(current);local c=self:session(s);if not s.seen and ((c and c.connected) or #s.board.cards>0) then self:show(current) end end
  for id,s in pairs(self.states) do
    if not s.sprite.isValid then if s.dialog then s.dialog:close() end;if s.preview then s.preview:close() end;if not next(s.drafts) then self.states[id]=nil end
    else
      self:run(function() self:pollFiles(s) end)
      if s.animationDirty or self.ticks%150==0 then
        s.animationThumbs={};s.animationDirty=false
        local visible=s.tagMenu or s.sheet
        if not visible then for _,card in ipairs(s.board.cards) do if card.kind=='animation' then visible=true;break end end end
        if s.dialog and visible then self:refresh(s) end
      end
      if s.marquee and s.pointerDown then self:autoPanMarquee(s) end
      local c=self:session(s)
      if not c then local raw=s.sprite.properties(N.key).board
        if raw~=s.raw then s.raw=raw;local board=N.read(s.sprite);if not N.equal(board,s.board) then s.board=board;s.history={undo={},redo={}} end end
      end
      local d=s.inline
      if d and c and c.connected and os.time()-(d.renewed or 0)>=5 then c:noteLock(d.id,d.field);d.renewed=os.time() end
      if d and d.commitRequested and not d.sending then self:finishInline(s) end
      if s.renderedBoard~=s.board or (c and s.renderedLocks~=c.noteLocks) then s.renderedBoard=s.board;s.renderedLocks=c and c.noteLocks;self:refresh(s) end
    end
  end
end
function UI:close()
  for _,s in pairs(self.states) do
    if s.dialog then s.dialog:close() end;if s.preview then s.preview:close() end
    if s.sprite.isValid and s.changeListener then s.sprite.events:off(s.changeListener) end
  end
end
return UI
