local directory=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local C=dofile(app.fs.joinPath(directory,'codec.lua'))
local Client={};Client.__index=Client
local blocked={}
for name in ('RemoveLayer RemoveFrame DuplicateLayer DuplicateSprite FlattenLayers FlattenVisibleLayers MergeDownLayer LayerFromBackground BackgroundFromLayer LayerProperties FrameProperties CelProperties SpriteProperties SpriteSize CanvasSize ChangePixelFormat CropSprite TrimSprite RotateCanvas ReverseFrames MoveLayer LinkCels UnlinkCel SetPalette ColorQuantization SetLayerOpacity SetLayerBlendMode ImportSpriteSheet NewSpriteFromSelection'):gmatch('%S+') do blocked[name]=true end
local function plain(value)
  if type(value)~='table' and type(value)~='userdata' then return value end
  local result={}
  -- Aseprite JsonValue arrays support numeric indexing/ipairs, but not pairs.
  if value[1]~=nil then
    for i=1,#value do result[i]=plain(value[i]) end
  else
    for k,v in pairs(value) do result[k]=plain(v) end
  end
  return result
end
function Client.new(notify)
  return setmetatable({notify=notify or function() end,inbox={},pending={},seq=0,connected=false,connecting=false,
    applying=false,dirty=false,ticks=0,undoCount=0,redoCount=0,status='Nicht verbunden',revision=0},Client)
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
        local ok,message=pcall(function() return plain(json.decode(data)) end)
        self.inbox[#self.inbox+1]=ok and message or {type='error',message='Ungueltige Serverantwort'}
      elseif kind==WebSocketMessageType.ERROR or kind==WebSocketMessageType.CLOSE then
        self.inbox[#self.inbox+1]={type='error',message='Verbindung getrennt. Server/Radmin pruefen. Lokale Kopie bleibt erhalten.'}
      end
    end}
  self.ws:connect()
end
function Client:host(sprite,name,port)
  local snapshot=C.capture(sprite)
  self:connect('ws://127.0.0.1:'..(port or 8765),{type='hello',protocol=1,mode='host',name=name,snapshot=snapshot})
end
function Client:join(invite,name)
  invite=invite:gsub('%s',''):gsub('^ws://','')
  local address,code,token=invite:match('^([%w%.%-]+:%d+)/(%x+)/(%x+)$')
  assert(address and #code==8 and #token==32,'Bitte den gesamten Einladungscode vom Host einfuegen.')
  self.invite=invite
  self:connect('ws://'..address,{type='hello',protocol=1,mode='join',name=name,room=code,token=token})
end
function Client:getLocalInvite()
  assert(self.connected and self.isHost and self.invite,'Lokale Einladung nur am verbundenen Host kopieren.')
  -- Only replace the address, never the room or secret. Preserve non-default test ports.
  return (self.invite:gsub('^[^/]+:(%d+)/','127.0.0.1:%1/',1))
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
    local op={type='paint',seq=self.seq,patches=patches}
    self.pending[#self.pending+1]=op
    self:send(op)
  end
end
function Client:action(kind)
  if not self.connected then return end
  local ok,err=pcall(function() self:capture(); self:send{type=kind} end)
  if not ok then self:disconnect(tostring(err)) end
end
function Client:append(kind,name,source)
  if not self.connected then return end
  self:capture();self:send{type='append',kind=kind,name=name,source=source}
end
function Client:beforeCommand(ev)
  if not self.connected or app.sprite~=self.sprite or self.applying then return end
  if ev.name=='Undo' or ev.name=='Redo' then
    ev.stopPropagation();self:action(ev.name=='Undo' and 'undo' or 'redo')
  elseif ev.name=='NewLayer' then
    ev.stopPropagation()
    local params=ev.params or {}
    if params.viaCut then
      app.tip('Collabsprite: Ausschneiden als neue Ebene geht hier noch nicht. Kopieren oder neue Ebene verwenden.',5)
    else
      local selected=app.layer
      local source=nil
      if params.viaCopy and selected then
        for i,layer in ipairs(self.mapping) do if layer==selected then source=i;break end end
      end
      self:append('layer',nil,source)
    end
  elseif ev.name=='NewFrame' then
    ev.stopPropagation()
    local params=ev.params or {}
    local source=nil
    if params.content~='empty' then source=app.frame and app.frame.frameNumber or #self.meta.frames end
    self:append('frame',nil,source)
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
    self.invite=message.invite or self.invite;self.hasRadmin=message.radmin;self.localOnly=message.localOnly==true
    self.meta=message.snapshot;self.cells=C.decode(self.meta)
    self.applying=true
    self.sprite,self.mapping=C.create(self.meta,self.cells)
    self.baseline=C.scan(self.sprite,self.mapping)
    self.applying=false
    self.revision=message.revision;self.connected=true;self.connecting=false
    self.changeListener=self.sprite.events:on('change',function()
      if not self.applying then self.dirty=true end
    end)
    self:statusText('Verbunden: '..self.room..(message.restored and ' (Backup, neuer Verlauf)' or ''))
  elseif message.type=='history' then
    self.undoCount=message.undo;self.redoCount=message.redo;self.notify(self)
  elseif message.type=='presence' then
    self.members=message.members;self.notify(self)
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
    self.applying=true
    app.transaction('Collabsprite: '..(message.kind=='layer' and 'Neue Ebene' or 'Neues Frame'),function()
      if message.kind=='layer' then
        local layer=self.sprite:newLayer();layer.name=message.layer.name
        layer.parent=self.sprite;layer.stackIndex=#self.sprite.layers
        layer.opacity=message.layer.opacity;layer.blendMode=message.layer.blend;layer.isVisible=message.layer.visible
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
    self.applying=false;self.revision=message.revision;self.needsRender=true
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
    if self.connecting and os.time()-self.started>20 then error('Keine Verbindung: Host-Server starten, Radmin und Firewall pruefen.') end
    if self.connected then
      local exists=false
      for _,s in ipairs(app.sprites) do if s==self.sprite then exists=true;break end end
      if not exists then self:disconnect('Sitzungsbild geschlossen.');return end
      -- Read local edits before applying any remote updates, even if both arrived together.
      self.ticks=self.ticks+1
      -- Do not scan while the mouse is held: Aseprite can expose a transient
      -- cel position mid-stroke, which looks like the whole image jumping
      -- on peers. Sprite.change / aftercommand mark completed edits instead.
      if self.dirty or #self.inbox>0 then self:capture() end
      if self.ticks%300==0 then self:send{type='ping',nonce=self.ticks} end
    end
    local inbox=self.inbox;self.inbox={}
    for _,message in ipairs(inbox) do self:receive(message) end
    if self.connected then self:render() end
  end)
  if not ok then self.applying=false;self:disconnect(tostring(err)) end
end
return Client
