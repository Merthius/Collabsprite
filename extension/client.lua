local directory=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local C=dofile(app.fs.joinPath(directory,'codec.lua'))
local decodeJson=dofile(app.fs.joinPath(directory,'json.lua')).decode
local Client={};Client.__index=Client
local MAX_INBOX=2048
local MAX_INBOX_BYTES=128*1024*1024
local function equal(a,b)
  if type(a)~=type(b) then return false end
  if type(a)~='table' then return a==b end
  for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end
local blocked={}
local guestSaveCommands={SaveFile=true,SaveFileAs=true,SaveFileCopyAs=true,
  ExportSpriteSheet=true,ExportTileset=true,RepeatLastExport=true,
  DuplicateSprite=true,NewSpriteFromSelection=true}
for name in ('DuplicateSprite FlattenLayers FlattenVisibleLayers MergeDownLayer LayerFromBackground BackgroundFromLayer SpriteProperties SpriteSize CanvasSize ChangePixelFormat CropSprite TrimSprite RotateCanvas ReverseFrames MoveLayer LinkCels UnlinkCel ColorQuantization ImportSpriteSheet NewSpriteFromSelection'):gmatch('%S+') do blocked[name]=true end
function Client.new(notify,log)
  return setmetatable({notify=notify or function() end,log=log or function() end,inbox={},pending={},seq=0,connected=false,connecting=false,
    applying=false,dirty=false,ticks=0,undoCount=0,redoCount=0,status='Nicht verbunden',revision=0,structure=0},Client)
end
function Client:trace(event,detail)
  pcall(self.log,event,detail)
end
function Client:transaction(label,action)
  -- app.transaction uses the active document. A different tab (or no active
  -- tab after closing another image) must not own our multiplayer undo record.
  local previous=app.sprite
  if previous==self.sprite then return app.transaction(label,action) end
  local layer,frame=app.layer,app.frame
  app.sprite=self.sprite
  local ok,err=pcall(function() app.transaction(label,action) end)
  app.sprite=previous
  if previous then
    if layer then app.layer=layer end
    if frame then app.frame=frame end
  end
  if not ok then error(err,0) end
end
function Client:statusText(text)
  self.status=text
  local category=text=='Verbinde ...' and 'connecting' or text:match('^Verbunden') and 'connected' or text:match('^Getrennt') and 'disconnected' or 'status'
  self:trace('session',category)
  self.notify(self)
end
function Client:enqueue(message)
  -- Called from the native socket callback: no IO, UI or exceptions here.
  if self.closed or self.inboxOverflow then return end
  local size=message.type=='_text' and #message.data or 0
  if size>64*1024*1024 or #self.inbox>=MAX_INBOX or (self.inboxBytes or 0)+size>MAX_INBOX_BYTES then
    self.inboxOverflow=true;return
  end
  self.inboxBytes=(self.inboxBytes or 0)+size
  self.inbox[#self.inbox+1]=message
end
function Client:syncStatusText()
  if self.reconnecting then return 'Verbindung unterbrochen · verbinde erneut ...' end
  if self.leaving then return 'Warte auf Bestätigung ...' end
  if self.backupError and self.isHost then return 'Sicherung fehlgeschlagen' end
  if self.lastReceived and os.time()-self.lastReceived>15 then return 'Host antwortet nicht ...' end
  if #self.pending>0 then return 'Verbunden · '..#self.pending..' Pixelaktionen offen' end
  return self.acceptingGuests==false and 'Verbunden · Beitritt gesperrt' or 'Verbunden'
end
function Client:send(message)
  assert(self.ws,'Keine Verbindung')
  local bytes=json.encode(message)
  if message.type=='paint' and not message.wireBytes then
    assert((self.pendingBytes or 0)+#bytes<=64*1024*1024 and #self.pending<=2048,'Zu viele unbestätigte Änderungen. Lokale Kopie bleibt erhalten.')
    self.pendingBytes=(self.pendingBytes or 0)+#bytes
    message.wireBytes=#bytes
  end
  local kind=tostring(message.type or 'unknown')
  if kind~='ping' then self:trace('websocket send',kind..' bytes='..#bytes) end
  local ok=pcall(function() self.ws:sendText(bytes) end)
  if not ok then self:enqueue{type='_lost'};return false end
  self.sentCount=(self.sentCount or 0)+1
  return true
end
-- This is a UI workflow restriction, not DRM: Aseprite must receive the
-- document to edit it. Scripts, recovery files and screenshots cannot be
-- reliably prevented by an extension. Keep the role attached after disconnect.
function Client.blockGuestSave(ev,guest)
  if not guest or not guestSaveCommands[ev.name] then return false end
  ev.stopPropagation()
  app.tip('Collabsprite: Nur der Host speichert oder exportiert das Sitzungsbild.',5)
  return true
end
function Client:connect(url,hello)
  assert(not self.connected and not self.connecting,'Bereits verbunden')
  self.connecting=true;self.started=os.time();self.hello=hello;self.closed=false
  self.url=url
  self.generation=(self.generation or 0)+1
  local generation=self.generation
  self.lastReceived=self.started;self.lastPing=self.started
  self.inbox={};self.inboxBytes=0;self.inboxOverflow=false
  self:trace('websocket','connect-start; endpoint hidden')
  self:statusText('Verbinde ...')
  self.ws=WebSocket{url=url,deflate=true,minreconnectwait=60,maxreconnectwait=60,
    onreceive=function(kind,data,err)
      -- No document mutations here: Aseprite can still hold a document lock.
      if self.closed or generation~=self.generation then return end
      if kind==WebSocketMessageType.OPEN then
        self:enqueue{type='_open'}
      elseif kind==WebSocketMessageType.TEXT then
        -- Only queue in the native callback: even diagnostic IO can open a
        -- permission dialog and recursively dispatch another native callback.
        self:enqueue{type='_text',data=data}
      elseif kind==WebSocketMessageType.ERROR or kind==WebSocketMessageType.CLOSE then
        self:enqueue{type='_lost'}
      end
    end}
  self.ws:connect()
end
function Client:host(sprite,name,port)
  local snapshot=C.capture(sprite)
  self:connect('ws://127.0.0.1:'..(port or 8766),{type='hello',protocol=4,mode='host',name=name,snapshot=snapshot})
end
function Client:join(invite,name)
  invite=invite:gsub('%s',''):gsub('^ws://','')
  local address,code,token=invite:match('^([%w%.%-]+:%d+)/(%x+)/(%x+)$')
  assert(address and #code==8 and #token==32,'Bitte den gesamten Einladungscode vom Host einfuegen.')
  self:trace('session','join-requested; address and invite hidden')
  self.invite=invite
  self:connect('ws://'..address,{type='hello',protocol=4,mode='join',name=name,room=code,token=token})
end
function Client:unfreeze()
  if not self.frozen then return end
  self.applying=true
  pcall(function()
    self:transaction('Collabsprite: Bearbeitung freigeben',function()
      for i,layer in ipairs(self.mapping) do layer.isEditable=self.meta.layers[i].editable~=false end
    end)
  end)
  self.applying=false;self.frozen=nil
end
function Client:suspend()
  if not self.resumeToken or not self.sprite then self:disconnect('Keine Verbindung. Host, LAN/Radmin und Firewall prüfen.');return end
  if self.leaving then self.leaving=nil end
  if self.connected then self:render() end
  self.connected=false;self.connecting=false
  self.generation=(self.generation or 0)+1
  if self.ws then pcall(function() self.ws:close() end);self.ws=nil end
  self.inbox={};self.inboxBytes=0
  if not self.reconnecting then
    self.reconnecting=true;self.resumeDeadline=os.time()+math.floor((self.resumeMs or 120000)/1000);self.retry=0
    self.applying=true
    self:transaction('Collabsprite: Verbindung unterbrochen',function()
      for _,layer in ipairs(self.mapping) do layer.isEditable=false end
    end)
    self.applying=false;self.frozen=true;self.frozenSnapshot=C.capture(self.sprite)
    app.tip('Verbindung unterbrochen. Zeichnen pausiert; Collabsprite verbindet automatisch neu.',5)
  end
  self.retry=self.retry+1;self.retryAt=os.time()+math.min(10,2^(self.retry-1))
  self:trace('reconnect','retry scheduled attempt='..self.retry)
  self:statusText('Verbindung unterbrochen · verbinde erneut ...')
end
function Client:disconnect(reason)
  local wasActive=self.connected or self.connecting or self.reconnecting
  self:trace('session','disconnect requested')
  if self.ws and self.connected then pcall(function() self.ws:sendText(json.encode{type='leave'}) end) end
  self.closed=true;self.connected=false;self.connecting=false;self.reconnecting=false;self.leaving=nil
  self.generation=(self.generation or 0)+1
  if self.ws then pcall(function() self.ws:close() end);self.ws=nil end
  self:unfreeze()
  if self.sprite and self.changeListener then pcall(function() self.sprite.events:off(self.changeListener) end) end
  self.changeListener=nil;self.inbox={};self.inboxBytes=0
  self:statusText(reason or (self.isHost and 'Getrennt. Sitzungskopie beim Host speichern.' or 'Getrennt. Bestätigte Beiträge bleiben beim Host.'))
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
      if #runs>0 then patches[#patches+1]={layer=current.layer,frame=current.frame,
        layerId=self.meta.layers[current.layer].id,frameId=self.meta.frameIds and self.meta.frameIds[current.frame],runs=runs} end
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
function Client:leaveBarrier()
  local job=assert(self.leaving)
  job.acknowledged=false
  job.nonce='leave:'..tostring((self.sentCount or 0)+1)
  self:send{type='ping',nonce=job.nonce}
  job.sentCount=self.sentCount
end
function Client:requestLeave(onReady)
  if self.reconnecting then
    -- Never close an unconfirmed guest view or discard its pending edits.
    self:disconnect('Wiederverbindung abgebrochen. Lokale Ansicht bleibt offen.');return
  end
  if not self.connected then self:disconnect();if onReady then onReady() end;return end
  if self.leaving then return end
  -- Capture even when the 33ms timer has not seen the last completed stroke.
  -- WebSocket close alone does not confirm that queued edits reached the host.
  self:capture()
  self.leaving={started=os.time(),onReady=onReady}
  self:trace('session','leave: waiting for server acknowledgement')
  self:leaveBarrier()
end
function Client:finishLeave()
  local job=self.leaving
  if not job then return end
  if os.time()-job.started>10 then
    self.leaving=nil
    self:trace('session','leave confirmation timed out; document retained')
    app.tip('Host bestätigt noch nicht. Bild bleibt offen; Verbindung prüfen und erneut trennen.',8)
    return
  end
  if not job.acknowledged then return end
  self:capture()
  if #self.pending>0 or self.sentCount~=job.sentCount then self:leaveBarrier();return end
  self:trace('session','leave: all outgoing changes confirmed')
  self:disconnect()
  if job.onReady then job.onReady() end
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
function Client:restoreDeletion()
  if not self.connected or not self.recovery then app.tip('Keine gelöschte Ebene / kein Frame zum Wiederherstellen.',4);return end
  self:capture();self:send{type='restore',recovery=self.recovery}
end
function Client:beforeCommand(ev)
  if app.sprite==self.sprite and Client.blockGuestSave(ev,self.isHost==false) then return end
  if self.reconnecting and app.sprite==self.sprite and not self.applying then
    if ev.name=='SaveFileAs' and self.isHost then return end
    ev.stopPropagation();app.tip('Collabsprite verbindet erneut. Bearbeitung ist kurz pausiert.',3);return
  end
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
function Client:rebasePending(meta,confirmedSeq)
  local indices,frames={},{}
  for i,l in ipairs(meta.layers) do if l.id then indices[l.id]=i end end
  for i,id in ipairs(meta.frameIds or {}) do frames[id]=i end
  local result={}
  for _,op in ipairs(self.pending) do if not confirmedSeq or op.seq>confirmedSeq then
    local patches={}
    for _,p in ipairs(op.patches) do
      local layer,frame=indices[p.layerId],frames[p.frameId]
      assert(layer and frame,'Ziel einer eigenen Pixelaktion wurde gelöscht. Lokale Ansicht bleibt unverändert offen.')
      patches[#patches+1]={layer=layer,frame=frame,layerId=p.layerId,frameId=p.frameId,runs=p.runs}
    end
    result[#result+1]={type='paint',seq=op.seq,structure=self.structure,patches=patches,wireBytes=op.wireBytes}
  end end
  return result
end
function Client:replaceSnapshot(meta,confirmedSeq)
  local cells=C.decode(meta)
  local pending=self:rebasePending(meta,confirmedSeq)
  if self.frozenSnapshot then
    assert(equal(self.frozenSnapshot,C.capture(self.sprite)),'Bild während der Unterbrechung lokal verändert. Lokale Ansicht bleibt unverändert offen.')
  end
  local desired={}
  for key,c in pairs(cells) do desired[key]={layer=c.layer,frame=c.frame,bytes=c.bytes,opacity=c.opacity,z=c.z} end
  for _,op in ipairs(pending) do for _,p in ipairs(op.patches) do
    local c=desired[C.key(p.layer,p.frame)];c.bytes=C.applyRuns(c.bytes,p.runs)
  end end
  local selectedLayer,selectedFrame
  if app.sprite==self.sprite then
    for i,l in ipairs(self.mapping) do if l==app.layer then selectedLayer=self.meta.layers[i].id end end
    selectedFrame=self.meta.frameIds and app.frame and self.meta.frameIds[app.frame.frameNumber]
  end
  local editor=app.editor
  local same=editor and editor.sprite==self.sprite
  local zoom,scroll=same and editor.zoom,same and editor.scroll
  self.applying=true
  self:transaction('Collabsprite: Sitzungsstand abgleichen',function() self.mapping=C.replace(self.sprite,meta,desired) end)
  self.meta=meta;self.cells=cells;self.pending=pending;self.pendingBytes=0
  for _,op in ipairs(pending) do self.pendingBytes=self.pendingBytes+(op.wireBytes or 0) end
  self.baseline=C.scan(self.sprite,self.mapping);self.dirty=false;self.needsRender=false
  self.frozen=nil;self.frozenSnapshot=nil;self.applying=false
  if app.sprite==self.sprite then
    for i,l in ipairs(meta.layers) do if l.id==selectedLayer then app.layer=self.mapping[i] end end
    for i,id in ipairs(meta.frameIds or {}) do if id==selectedFrame then app.frame=self.sprite.frames[i] end end
  end
  if same then editor.zoom=zoom;editor.scroll=scroll end
  app.refresh()
end
function Client:receive(message)
  self.lastReceived=os.time()
  local messageType=tostring(message.type or 'unknown')
  local summary=messageType
  if messageType=='patch' then summary=summary..' patches='..tostring(#(message.patches or {}))
  elseif messageType=='welcome' then
    local snap=message.snapshot or {}
    summary=summary..' layers='..tostring(#(snap.layers or {}))..' frames='..tostring(#(snap.frames or {}))..
      ' cels='..tostring(#(snap.cels or {}))..' size='..tostring(snap.width or '?')..'x'..tostring(snap.height or '?')
  elseif messageType=='presence' then summary=summary..' members='..tostring(#(message.members or {}))
  elseif messageType=='invite' then summary='invite received; code hidden'
  elseif messageType=='error' then summary='server error (details omitted for privacy)' end
  self:trace('websocket receive',summary)
  if message.type=='_open' then self:send(self.hello);self.hello=nil
  elseif message.type=='_lost' then self:suspend();return
  elseif message.type=='error' or message.type=='ended' then
    -- A final patch and CLOSE can arrive in the same timer batch. Render the
    -- confirmed state before disconnect disables the normal end-of-tick render.
    if self.connected then self:render() end
    self:disconnect(tostring(message.message or 'Serverfehler.'))
    return
  elseif message.type=='pong' then
    if self.leaving and message.nonce==self.leaving.nonce then self.leaving.acknowledged=true end
  elseif message.type=='rejected' then
    app.tip('Collabsprite: '..tostring(message.message or 'Aktion nicht möglich.'):sub(1,180),5)
  elseif message.type=='admission' then
    self.acceptingGuests=message.open==true;self.notify(self)
  elseif message.type=='backup' then
    if self.isHost then
      local wasError=self.backupError
      self.backupError=message.state=='error'
      self.savedRevision=message.revision
      if self.backupError and not wasError then
        app.tip('Collabsprite: Automatische Sicherung fehlgeschlagen. Bitte das Bild selbst speichern!',8)
      elseif wasError and not self.backupError then app.tip('Collabsprite: Automatische Sicherung funktioniert wieder.',4) end
      self.notify(self)
    end
  elseif message.type=='welcome' then
    assert(not self.connected,'Doppelte Anmeldung')
    assert(message.protocol==nil or message.protocol==4,'Unpassende Erweiterungsversion')
    local resumed=self.reconnecting
    if resumed then
      assert(message.resumed and message.author==self.author and message.room==self.room and message.host==self.isHost,'Falsche Wiederverbindungsantwort')
      assert(type(message.confirmedSeq)=='number' and message.confirmedSeq>=0 and message.confirmedSeq<=self.seq,'Ungültige Wiederverbindungssequenz')
      self:replaceSnapshot(message.snapshot,message.confirmedSeq)
    else
      self.author=message.author;self.room=message.room;self.isHost=message.host
    end
    self.invite=message.invite or self.invite;self.localOnly=message.localOnly==true
    self.acceptingGuests=message.acceptingGuests~=false
    if not resumed then
      self.meta=message.snapshot;self.cells=C.decode(self.meta)
      self.applying=true
      self.sprite,self.mapping=C.create(self.meta,self.cells)
      self.baseline=C.scan(self.sprite,self.mapping)
      self.applying=false
      self.changeListener=self.sprite.events:on('change',function()
        if not self.applying then self.dirty=true end
      end)
    end
    self.resumeToken=message.resumeToken;self.resumeMs=message.resumeMs
    self.revision=message.revision;self.structure=message.structure or 0;self.connected=true;self.connecting=false
    self.reconnecting=false;self.lastPing=os.time();self.syncStatus=nil
    if resumed then
      for _,op in ipairs(self.pending) do op.structure=self.structure;self:send(op) end
      self:trace('reconnect','resumed; pending='..#self.pending)
      app.tip('Wieder verbunden. Eigener Verlauf bleibt erhalten.',4)
    end
    self:statusText('Verbunden: '..self.room..(message.restored and ' (Backup, neuer Verlauf)' or ''))
  elseif message.type=='history' then
    self.undoCount=message.undo;self.redoCount=message.redo;self.recovery=message.recovery;self.recoveryCount=message.recoveryCount or 0;self.notify(self)
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
  elseif message.type=='ack' then
    while self.pending[1] and self.pending[1].seq<=message.seq do
      local op=table.remove(self.pending,1);self.pendingBytes=math.max(0,(self.pendingBytes or 0)-(op.wireBytes or 0))
    end
  elseif message.type=='restore' then
    assert(message.revision==self.revision+1 and message.structure==self.structure+1,'Strukturfolge unterbrochen')
    self:replaceSnapshot(message.snapshot)
    self.revision=message.revision;self.structure=message.structure
  elseif message.type=='patch' then
    assert(message.revision==self.revision+1,'Synchronisationsfolge unterbrochen; bitte neu verbinden.')
    for _,patch in ipairs(message.patches) do
      local cell=assert(self.cells[C.key(patch.layer,patch.frame)],'Unbekanntes Cel')
      cell.bytes=C.applyRuns(cell.bytes,patch.runs)
    end
    if message.author==self.author and message.seq then
      assert(self.pending[1] and self.pending[1].seq==message.seq,'Bestaetigungsfolge stimmt nicht')
      local acknowledged=table.remove(self.pending,1)
      self.pendingBytes=math.max(0,(self.pendingBytes or 0)-(acknowledged.wireBytes or 0))
    end
    self.revision=message.revision;self.needsRender=true
  elseif message.type=='append' then
    assert(message.revision==self.revision+1,'Synchronisationsfolge unterbrochen')
    assert(message.structure==self.structure+1,'Strukturfolge unterbrochen')
    self.applying=true
    self:transaction('Collabsprite: '..(message.kind=='layer' and 'Neue Ebene' or 'Neues Frame'),function()
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
        if self.meta.frameIds then self.meta.frameIds[message.index]=message.frameId end
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
    local nextMeta={layers=message.kind=='layer' and message.layers or self.meta.layers,frameIds={}}
    for i,id in ipairs(self.meta.frameIds or {}) do
      if message.kind~='frame' or i~=message.index then nextMeta.frameIds[#nextMeta.frameIds+1]=id end
    end
    local pending=self:rebasePending(nextMeta)
    self.applying=true
    if message.kind=='layer' then
      local target=assert(self.mapping[message.index],'Unbekannte Ebene')
      self:transaction('Collabsprite: Ebene löschen',function() self.sprite:deleteLayer(target) end)
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
      self:transaction('Collabsprite: Frame löschen',function() self.sprite:deleteFrame(message.index) end)
      local old=self.cells;self.cells={}
      for key,cell in pairs(old) do
        if cell.frame<message.index then self.cells[key]=cell
        elseif cell.frame>message.index then
          cell.frame=cell.frame-1
          self.cells[C.key(cell.layer,cell.frame)]=cell
        end
      end
      table.remove(self.meta.frames,message.index)
      if self.meta.frameIds then table.remove(self.meta.frameIds,message.index) end
    end
    self.baseline=C.scan(self.sprite,self.mapping)
    self.pending=pending;self.needsRender=true
    self.applying=false;self.revision=message.revision;self.structure=message.structure
    app.refresh()
  elseif message.type=='property' then
    assert(message.revision==self.revision+1,'Synchronisationsfolge unterbrochen')
    self.applying=true
    self:transaction('Collabsprite: Eigenschaft',function()
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
    self:transaction('Collabsprite: Cel-Eigenschaft',function()
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
    self:transaction('Collabsprite: Palette',function()
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
    self:transaction('Collabsprite: Synchronisieren',function()
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
  if self.closed or self.ticking then return end
  self.ticking=true
  local ok,err=xpcall(function()
    if self.inboxOverflow then
      self:disconnect('Zu viele empfangene Daten. Lokale Kopie bleibt offen; Host/Netz prüfen.');return
    end
    if self.reconnecting then
      if os.time()>=self.resumeDeadline then self:disconnect('Wiederverbindung abgelaufen. Lokale Ansicht bleibt offen.');return end
      if self.connecting and os.time()-self.started>10 then self:suspend() end
      if not self.connecting and os.time()>=self.retryAt then
        self:connect(self.url,{type='hello',protocol=4,mode='resume',room=self.room,author=self.author,resumeToken=self.resumeToken})
      end
    elseif self.connecting and os.time()-self.started>20 then error('Keine Verbindung: Host, LAN/Radmin und Firewall prüfen.') end
    if self.connected or self.reconnecting then
      local exists=false
      for _,s in ipairs(app.sprites) do if s==self.sprite then exists=true;break end end
      if not exists then self:disconnect('Sitzungsbild geschlossen.');return end
    end
    if self.connected then
      -- Read local edits before applying any remote updates, even if both arrived together.
      self.ticks=self.ticks+1
      -- Do not scan while the mouse is held: Aseprite can expose a transient
      -- cel position mid-stroke, which looks like the whole image jumping
      -- on peers. Sprite.change / aftercommand mark completed edits instead.
      if self.dirty then self:capture()
      elseif self.ticks%30==0 then self:properties() end
      if os.time()-(self.lastPing or 0)>=5 then self.lastPing=os.time();self:send{type='ping',nonce=self.ticks} end
    end
    -- Yield back to Aseprite between bounded batches; a busy peer must not
    -- keep the UI inside one Lua timer callback indefinitely.
    for _=1,math.min(#self.inbox,64) do
      if self.closed or #self.inbox==0 then break end
      local message=table.remove(self.inbox,1)
      if message.type=='_text' then
        self.inboxBytes=math.max(0,(self.inboxBytes or 0)-#message.data)
        self:trace('websocket','text bytes='..#message.data)
        local decoded,value=pcall(decodeJson,message.data)
        if not decoded then self:trace('json decode error',value);error('Serverantwort konnte nicht gelesen werden.') end
        assert(type(value)=='table','Ungueltige Serverantwort')
        message=value
      end
      self:receive(message)
    end
    if self.connected then
      self:render();self:finishLeave()
      if self.connected and self.lastReceived and os.time()-self.lastReceived>60 then
        self:suspend();return
      end
      if self.connected then
        local status=self:syncStatusText()
        if status~=self.syncStatus then self.syncStatus=status;self.notify(self) end
      end
    end
  end,function(value)
    return debug and debug.traceback and debug.traceback(tostring(value),2) or tostring(value)
  end)
  if not ok then
    self.applying=false
    self:trace('FATAL client tick',err)
    self:disconnect('Clientfehler; Diagnoseprotokoll kopieren.')
  end
  self.ticking=false
end
-- Exposed only to native regression scripts.
Client._decodeForTest=decodeJson
return Client
