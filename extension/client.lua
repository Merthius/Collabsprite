local directory=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local C=dofile(app.fs.joinPath(directory,'codec.lua'))
local decodeJson=dofile(app.fs.joinPath(directory,'json.lua')).decode
local Client={};Client.__index=Client
local blocked={}
for name in ('DuplicateSprite FlattenLayers FlattenVisibleLayers MergeDownLayer LayerFromBackground BackgroundFromLayer SpriteProperties SpriteSize CanvasSize ChangePixelFormat CropSprite TrimSprite RotateCanvas ReverseFrames MoveLayer LinkCels UnlinkCel ColorQuantization ImportSpriteSheet NewSpriteFromSelection'):gmatch('%S+') do blocked[name]=true end
function Client.new(notify)
  return setmetatable({notify=notify or function() end,inbox={},pending={},seq=0,connected=false,connecting=false,
    applying=false,dirty=false,ticks=0,undoCount=0,redoCount=0,status='Nicht verbunden',revision=0,structure=0},Client)
end
function Client:statusText(text)
  self.status=text;self.notify(self)
end
function Client:send(message)
  assert(self.ws,'Keine Verbindung')
  self.ws:sendText(json.encode(message))
end
function Client:connect(url,hello)
  assert(not self.connected and not self.connecting,'Bereits verbunden')
  self.connecting=true;self.started=os.time();self.hello=hello;self.closed=false
  self:statusText('Verbinde ...')
  self.ws=WebSocket{url=url,deflate=true,minreconnectwait=60,maxreconnectwait=60,
    onreceive=function(kind,data,err)
      -- No document mutations here: Aseprite can still hold a document lock.
      if self.closed then return end
      if kind==WebSocketMessageType.OPEN then self.inbox[#self.inbox+1]={type='_open'}
      elseif kind==WebSocketMessageType.TEXT then
        local ok,message=pcall(function() return decodeJson(data) end)
        local detail=not ok and tostring(message):gsub('[\r\n]',' '):sub(1,120) or nil
        self.inbox[#self.inbox+1]=ok and message or {type='error',message='Serverantwort konnte nicht gelesen werden: '..detail}
      elseif kind==WebSocketMessageType.ERROR or kind==WebSocketMessageType.CLOSE then
        self.inbox[#self.inbox+1]={type='error',message='Verbindung getrennt. Netzwerk/Server prüfen. Lokale Kopie bleibt erhalten.'}
      end
    end}
  self.ws:connect()
end
function Client:host(sprite,name,port)
  local snapshot=C.capture(sprite)
  self:connect('ws://127.0.0.1:'..(port or 8766),{type='hello',protocol=3,mode='host',name=name,snapshot=snapshot})
end
function Client:join(invite,name)
  invite=invite:gsub('%s',''):gsub('^ws://','')
  local address,code,token=invite:match('^([%w%.%-]+:%d+)/(%x+)/(%x+)$')
  assert(address and #code==8 and #token==32,'Bitte den gesamten Einladungscode vom Host einfuegen.')
  self.invite=invite
  self:connect('ws://'..address,{type='hello',protocol=3,mode='join',name=name,room=code,token=token})
end
function Client:disconnect(reason)
  local wasActive=self.connected or self.connecting
  self.closed=true;self.connected=false;self.connecting=false
  if self.ws then pcall(function() self.ws:close() end);self.ws=nil end
  if self.sprite and self.changeListener then pcall(function() self.sprite.events:off(self.changeListener) end) end
  self.changeListener=nil;self.inbox={}
  self:statusText(reason or 'Getrennt. Sitzungskopie bitte speichern.')
  if reason and wasActive then app.tip('Collabsprite getrennt: '..tostring(reason):sub(1,95),8) end
end
function Client:capture()
  if not self.connected or self.applying then return end
  C.checkTopology(self.sprite,self.mapping,self.meta)
  self:properties()
  local scan=C.scan(self.sprite,self.mapping,self.baseline)
  local patches={}
  for key,current in pairs(scan) do
    local previous=self.baseline[key]
    if current.bytes~=previous.bytes then
      local runs=C.runs(current.bytes,previous.bytes)
      if #runs>0 then patches[#patches+1]={layer=current.layer,frame=current.frame,runs=runs} end
    end
  end
  self.baseline=scan;self.dirty=false
  if #patches>0 then
    self.seq=self.seq+1
    local op={type='paint',seq=self.seq,structure=self.structure,patches=patches}
    self.pending[#self.pending+1]=op
    self:send(op)
  end
end
function Client:properties()
  if not self.connected or self.applying then return end
  C.checkTopology(self.sprite,self.mapping,self.meta)
  local fields={'name','opacity','blend','visible','editable','continuous'}
  for i,layer in ipairs(self.mapping) do
    local old=self.meta.layers[i]
    local current={name=layer.name,opacity=layer.opacity or 255,blend=layer.blendMode or BlendMode.NORMAL,
      visible=layer.isVisible,editable=layer.isEditable,continuous=not layer.isGroup and layer.isContinuous or false}
    for _,field in ipairs(fields) do
      if current[field]~=old[field] then
        old[field]=current[field]
        self:send{type='property',kind='layer',index=i,field=field,value=current[field],structure=self.structure}
      end
    end
  end
  for f,frame in ipairs(self.sprite.frames) do
    local ms=math.max(1,math.floor(frame.duration*1000+0.5))
    if ms~=self.meta.frames[f] then
      self.meta.frames[f]=ms
      self:send{type='property',kind='frame',index=f,field='duration',value=ms,structure=self.structure}
    end
  end
  for key,cell in pairs(self.cells) do
    local cel=self.mapping[cell.layer]:cel(cell.frame)
    local currentOpacity=cel and cel.opacity or 255
    local currentZ=cel and cel.zIndex or 0
    if currentOpacity~=cell.opacity then
      cell.opacity=currentOpacity
      self:send{type='celProperty',layer=cell.layer,frame=cell.frame,field='opacity',value=currentOpacity,structure=self.structure}
    end
    if currentZ~=cell.z then
      cell.z=currentZ
      self:send{type='celProperty',layer=cell.layer,frame=cell.frame,field='z',value=currentZ,structure=self.structure}
    end
  end
  local palette={}
  local pal=self.sprite.palettes[1]
  if pal then for i=0,math.min(#pal,256)-1 do palette[#palette+1]=pal:getColor(i).rgbaPixel end end
  local changed=#palette~=#self.meta.palette
  if not changed then for i,value in ipairs(palette) do if value~=self.meta.palette[i] then changed=true;break end end end
  if changed then
    self.meta.palette=palette
    self:send{type='palette',colors=palette}
  end
end
function Client:action(kind)
  if not self.connected then return end
  local ok,err=pcall(function() self:capture(); self:send{type=kind} end)
  if not ok then self:disconnect(tostring(err)) end
end
function Client:append(kind,name,source)
  if not self.connected then return end
  self:capture();self:send{type='append',kind=kind,name=name,source=source,structure=self.structure}
end
function Client:delete(kind,index)
  if not self.connected then return end
  self:capture()
  self:send{type='delete',kind=kind,index=index,structure=self.structure}
end
function Client:deleteMany(kind,indices)
  if not self.connected then return end
  self:capture()
  self:send{type='deleteMany',kind=kind,indices=indices,structure=self.structure}
end
function Client:beforeCommand(ev)
  if not self.connected or app.sprite~=self.sprite or self.applying then return end
  if ev.name=='Undo' or ev.name=='Redo' then
    ev.stopPropagation();self:action(ev.name=='Undo' and 'undo' or 'redo')
  elseif ev.name=='DuplicateLayer' then
    ev.stopPropagation()
    local selected=app.layer
    if selected and selected.isGroup then
      app.tip('Collabsprite: Gruppen duplizieren ist noch nicht unterstuetzt.',5)
      return
    end
    local source=nil
    for i,layer in ipairs(self.mapping) do if layer==selected then source=i;break end end
    if source then self:append('layer',selected.name..' Kopie',source) end
  elseif ev.name=='NewLayer' then
    ev.stopPropagation()
    local params=ev.params or {}
    if params.group or params.reference or params.tilemap or params.fromFile or params.fromClipboard or params.viaCut or params.viaCopy then
      app.tip('Collabsprite: Diese besondere Ebenenart oder Auswahl-Operation wird noch nicht synchronisiert.',5)
    else
      self:append('layer',params.name,nil)
    end
  elseif ev.name=='NewFrame' then
    ev.stopPropagation()
    local params=ev.params or {}
    local source=nil
    if params.content~='empty' then source=app.frame and app.frame.frameNumber or #self.meta.frames end
    self:append('frame',nil,source)
  elseif ev.name=='RemoveLayer' or ev.name=='RemoveFrame' then
    ev.stopPropagation()
    local kind=ev.name=='RemoveLayer' and 'layer' or 'frame'
    local selected=kind=='layer' and app.range.layers or app.range.frames
    local indices={}
    if selected and #selected>0 then
      for _,item in ipairs(selected) do
        if kind=='frame' then indices[#indices+1]=item.frameNumber
        else for i,layer in ipairs(self.mapping) do if layer==item then indices[#indices+1]=i;break end end end
      end
    else
      if kind=='frame' and app.frame then indices[1]=app.frame.frameNumber
      elseif kind=='layer' then for i,layer in ipairs(self.mapping) do if layer==app.layer then indices[1]=i;break end end end
    end
    if #indices==1 then self:delete(kind,indices[1])
    elseif #indices>1 then self:deleteMany(kind,indices) end
  elseif ev.name=='UndoHistory' or blocked[ev.name] then
    ev.stopPropagation()
    app.tip('Collabsprite: Diese Strukturaktion ist in der gemeinsamen Sitzung noch nicht unterstuetzt.',5)
  elseif ev.name=='SaveFile' then
    ev.stopPropagation();self:capture();app.command.SaveFileAs()
  elseif ev.name=='SaveFileAs' or ev.name=='SaveFileCopyAs' then
    -- Saving never shares a filesystem path and does not change the native save dialog.
    self:capture()
  end
end
function Client:receive(message)
  if message.type=='_open' then self:send(self.hello);self.hello=nil
  elseif message.type=='error' then error(message.message or 'Serverfehler')
  elseif message.type=='welcome' then
    assert(not self.connected,'Doppelte Anmeldung')
    self.author=message.author;self.room=message.room;self.isHost=message.host
    self.invite=message.invite or self.invite;self.localOnly=message.localOnly==true
    self.meta=message.snapshot;self.cells=C.decode(self.meta)
    self.applying=true
    self.sprite,self.mapping=C.create(self.meta,self.cells)
    self.baseline=C.scan(self.sprite,self.mapping)
    self.applying=false
    self.revision=message.revision;self.structure=message.structure or 0;self.connected=true;self.connecting=false
    self.changeListener=self.sprite.events:on('change',function()
      if not self.applying then self.dirty=true end
    end)
    self:statusText('Verbunden: '..self.room..(message.restored and ' (Backup, neuer Verlauf)' or ''))
  elseif message.type=='history' then
    self.undoCount=message.undo;self.redoCount=message.redo;self.notify(self)
  elseif message.type=='presence' then
    local previous={}
    for _,member in ipairs(self.members or {}) do previous[member.author]=true end
    self.members=message.members
    if self.hadPresence then
      for _,member in ipairs(self.members or {}) do
        if member.author~=self.author and not previous[member.author] then
          app.tip(member.name..' ist der Sitzung beigetreten.',3)
        end
      end
    end
    self.hadPresence=true;self.notify(self)
  elseif message.type=='invite' then
    self.invite=message.invite
    if self.copyWhenReady then
      self.copyWhenReady=false
      app.clipboard.text=self.invite
      app.tip('Einladungscode kopiert.',4)
    end
  elseif message.type=='patch' then
    assert(message.revision==self.revision+1,'Synchronisationsfolge unterbrochen; bitte neu verbinden.')
    for _,patch in ipairs(message.patches) do
      local cell=assert(self.cells[C.key(patch.layer,patch.frame)],'Unbekanntes Cel')
      cell.bytes=C.applyRuns(cell.bytes,patch.runs)
    end
    if message.author==self.author and message.seq then
      assert(self.pending[1] and self.pending[1].seq==message.seq,'Bestaetigungsfolge stimmt nicht')
      table.remove(self.pending,1)
    end
    self.revision=message.revision;self.needsRender=true
  elseif message.type=='append' then
    assert(message.revision==self.revision+1,'Synchronisationsfolge unterbrochen')
    assert(message.structure==self.structure+1,'Strukturfolge unterbrochen')
    assert(#self.pending==0,'Eigene Aenderungen vor Strukturwechsel noch nicht bestätigt')
    self.applying=true
    app.transaction('Collabsprite: '..(message.kind=='layer' and 'Neue Ebene' or 'Neues Frame'),function()
      if message.kind=='layer' then
        local layer=self.sprite:newLayer();layer.name=message.layer.name
        layer.parent=self.sprite;layer.stackIndex=#self.sprite.layers
        layer.opacity=message.layer.opacity;layer.blendMode=message.layer.blend;layer.isVisible=message.layer.visible
        layer.isEditable=message.layer.editable~=false
        if not message.layer.group then layer.isContinuous=message.layer.continuous==true end
        self.mapping[message.index]=layer;self.meta.layers[message.index]=message.layer
      else
        self.sprite:newEmptyFrame(message.index)
        self.sprite.frames[message.index].duration=message.duration/1000
        self.meta.frames[message.index]=message.duration
      end
    end)
    local blank=string.rep('\0',self.meta.width*self.meta.height*4)
    for l,layer in ipairs(self.meta.layers) do if not layer.group then
      for f=1,#self.meta.frames do
        local key=C.key(l,f)
        if not self.cells[key] then self.cells[key]={layer=l,frame=f,bytes=blank,opacity=255,z=0} end
      end
    end end
    for _,cel in ipairs(message.cels or {}) do
      local cell=assert(self.cells[C.key(cel.layer,cel.frame)],'Unbekanntes kopiertes Cel')
      cell.bytes=C.applyRuns(blank,cel.runs)
      cell.opacity=cel.opacity or 255;cell.z=cel.z or 0
    end
    self.baseline=C.scan(self.sprite,self.mapping)
    self.applying=false;self.revision=message.revision;self.structure=message.structure;self.needsRender=true
  elseif message.type=='delete' then
    assert(message.revision==self.revision+1 and message.structure==self.structure+1,'Strukturfolge unterbrochen')
    assert(#self.pending==0,'Eigene Aenderungen vor Strukturwechsel noch nicht bestätigt')
    self.applying=true
    if message.kind=='layer' then
      local target=assert(self.mapping[message.index],'Unbekannte Ebene')
      app.transaction('Collabsprite: Ebene löschen',function() self.sprite:deleteLayer(target) end)
      local old=self.cells;self.cells={}
      for key,cell in pairs(old) do
        if cell.layer<message.index then self.cells[key]=cell
        elseif cell.layer>=message.index+message.count then
          cell.layer=cell.layer-message.count
          self.cells[C.key(cell.layer,cell.frame)]=cell
        end
      end
      for _=1,message.count do table.remove(self.mapping,message.index) end
      self.meta.layers=message.layers
    else
      app.transaction('Collabsprite: Frame löschen',function() self.sprite:deleteFrame(message.index) end)
      local old=self.cells;self.cells={}
      for key,cell in pairs(old) do
        if cell.frame<message.index then self.cells[key]=cell
        elseif cell.frame>message.index then
          cell.frame=cell.frame-1
          self.cells[C.key(cell.layer,cell.frame)]=cell
        end
      end
      table.remove(self.meta.frames,message.index)
    end
    self.baseline=C.scan(self.sprite,self.mapping)
    self.applying=false;self.revision=message.revision;self.structure=message.structure
    app.refresh()
  elseif message.type=='property' then
    assert(message.revision==self.revision+1,'Synchronisationsfolge unterbrochen')
    self.applying=true
    app.transaction('Collabsprite: Eigenschaft',function()
      if message.kind=='layer' then
        local layer=assert(self.mapping[message.index],'Unbekannte Ebene')
        self.meta.layers[message.index][message.field]=message.value
        local field={name='name',opacity='opacity',blend='blendMode',visible='isVisible',editable='isEditable',continuous='isContinuous'}
        assert(field[message.field],'Unbekannte Ebeneneigenschaft')
        layer[field[message.field]]=message.value
      else
        assert(message.kind=='frame' and message.field=='duration','Unbekannte Frame-Eigenschaft')
        self.meta.frames[message.index]=message.value
        self.sprite.frames[message.index].duration=message.value/1000
      end
    end)
    self.applying=false;self.revision=message.revision
  elseif message.type=='celProperty' then
    assert(message.revision==self.revision+1,'Synchronisationsfolge unterbrochen')
    local cell=assert(self.cells[C.key(message.layer,message.frame)],'Unbekanntes Cel')
    self.applying=true
    app.transaction('Collabsprite: Cel-Eigenschaft',function()
      cell[message.field]=message.value
      local cel=self.mapping[message.layer]:cel(message.frame)
      if not cel then
        C.writeCel(self.sprite,self.mapping[message.layer],message.frame,cell.bytes,cell.opacity,cell.z)
        cel=self.mapping[message.layer]:cel(message.frame)
      end
      if cel then
        if message.field=='opacity' then cel.opacity=message.value
        elseif message.field=='z' then cel.zIndex=message.value
        else error('Unbekannte Cel-Eigenschaft') end
      end
    end)
    self.baseline=C.scan(self.sprite,self.mapping)
    self.applying=false;self.revision=message.revision
  elseif message.type=='palette' then
    assert(message.revision==self.revision+1,'Synchronisationsfolge unterbrochen')
    self.applying=true
    app.transaction('Collabsprite: Palette',function()
      self.meta.palette=message.colors
      if #message.colors>0 then
        local pal=Palette(#message.colors)
        for i,value in ipairs(message.colors) do
          pal:setColor(i-1,Color{r=value&255,g=(value>>8)&255,b=(value>>16)&255,a=(value>>24)&255})
        end
        self.sprite:setPalette(pal)
      end
    end)
    self.applying=false;self.revision=message.revision
  end
end
function Client:render()
  if not self.needsRender then return end
  local desired={}
  for key,c in pairs(self.cells) do desired[key]=c.bytes end
  -- Keep local, unacknowledged strokes visible while server-ordered patches arrive.
  for _,op in ipairs(self.pending) do for _,p in ipairs(op.patches) do
    local key=C.key(p.layer,p.frame);desired[key]=C.applyRuns(desired[key],p.runs)
  end end
  local changed={}
  for key,bytes in pairs(desired) do if bytes~=self.baseline[key].bytes then changed[#changed+1]=key end end
  if #changed>0 then
    local editor=app.editor
    local sameEditor=editor and editor.sprite==self.sprite
    local scroll=sameEditor and editor.scroll or nil
    local zoom=sameEditor and editor.zoom or nil
    self.applying=true
    app.transaction('Collabsprite: Synchronisieren',function()
      for _,key in ipairs(changed) do
        local c=self.cells[key]
        C.writeCel(self.sprite,self.mapping[c.layer],c.frame,desired[key],c.opacity,c.z)
      end
    end)
    self.baseline=C.scan(self.sprite,self.mapping)
    self.applying=false
    if sameEditor then
      if zoom and editor.zoom~=zoom then editor.zoom=zoom end
      if scroll then
        local current=editor.scroll
        if current.x~=scroll.x or current.y~=scroll.y then editor.scroll=scroll end
      end
    end
    app.refresh()
  end
  self.needsRender=false
end
function Client:tick()
  if self.closed then return end
  local ok,err=pcall(function()
    if self.connecting and os.time()-self.started>20 then error('Keine Verbindung: Host, LAN/Radmin und Firewall prüfen.') end
    if self.connected then
      local exists=false
      for _,s in ipairs(app.sprites) do if s==self.sprite then exists=true;break end end
      if not exists then self:disconnect('Sitzungsbild geschlossen.');return end
      -- Read local edits before applying any remote updates, even if both arrived together.
      self.ticks=self.ticks+1
      -- Do not scan while the mouse is held: Aseprite can expose a transient
      -- cel position mid-stroke, which looks like the whole image jumping
      -- on peers. Sprite.change / aftercommand mark completed edits instead.
      if self.dirty or #self.inbox>0 then self:capture()
      elseif self.ticks%30==0 then self:properties() end
      if self.ticks%300==0 then self:send{type='ping',nonce=self.ticks} end
    end
    local inbox=self.inbox;self.inbox={}
    for _,message in ipairs(inbox) do self:receive(message) end
    if self.connected then self:render() end
  end)
  if not ok then
    self.applying=false
    local trace=debug and debug.traceback and debug.traceback(tostring(err),2) or tostring(err)
    pcall(function() print('[Collabsprite] '..trace) end)
    self:disconnect(tostring(err))
  end
end
-- Exposed only to native regression scripts.
Client._decodeForTest=decodeJson
return Client
