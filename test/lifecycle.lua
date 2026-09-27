-- Real Aseprite documents, deterministic transport. Run with --batch.
local root=assert(app.params.root)
local Client=dofile(root..'/extension/client.lua')
local Codec=dofile(root..'/extension/codec.lua')
local Json=dofile(root..'/extension/json.lua')
local source=Sprite(4,4,ColorMode.RGB)
local snapshot=Codec.capture(source)
local lastFatal=''
local function client(host)
  local c=Client.new(nil,function(event,detail) if event:find('FATAL',1,true) then lastFatal=detail end end)
  c:receive{type='welcome',host=host,author=host and 'host' or 'guest',room='test',
    snapshot=Json.decode(json.encode(snapshot)),revision=0,structure=0}
  local sent={}
  c.ws={sendText=function(_,text) sent[#sent+1]=Json.decode(text) end,
    close=function() c.socketClosed=true end}
  return c,sent
end
local function pixel(c,index)
  return string.unpack('<I4',Codec.scan(c.sprite,c.mapping)['1:1'].bytes,index*4+1)
end
local function draw(c,index,color)
  local cel=c.mapping[1]:cel(1)
  local image=cel.image:clone()
  image:drawPixel(index%4,index//4,color)
  cel.image=image
end
local guest,sent=client(false)
app.sprite=guest.sprite
draw(guest,0,0xff112233)
local finished=false
guest:requestLeave(function() finished=true end)
assert(sent[1].type=='paint','Last stroke not captured before leave')
assert(sent[2].type=='ping' and not finished and not guest.socketClosed,'Closed before host confirmation')
guest:receive{type='patch',revision=1,author='guest',seq=1,patches=sent[1].patches}
guest:receive{type='pong',nonce='wrong'};guest:finishLeave()
assert(not finished,'Unrelated pong allowed close')
-- A completed edit made during the wait must get a new barrier.
draw(guest,1,0xff445566)
guest:receive{type='pong',nonce=sent[2].nonce};guest:finishLeave()
assert(not finished and sent[3].type=='paint' and sent[4].type=='ping','Late edit was lost')
guest:receive{type='patch',revision=2,author='guest',seq=2,patches=sent[3].patches}
guest:receive{type='pong',nonce=sent[4].nonce};guest:render();guest:finishLeave()
assert(finished and guest.socketClosed,'Confirmed leave did not complete')
assert(pixel(guest,0)==0xff112233 and pixel(guest,1)==0xff445566,'Leave removed pixels')
local blocked={'SaveFile','SaveFileAs','SaveFileCopyAs','ExportSpriteSheet','ExportTileset','RepeatLastExport','DuplicateSprite','NewSpriteFromSelection'}
for _,name in ipairs(blocked) do
  local stopped=false
  guest:beforeCommand{name=name,stopPropagation=function() stopped=true end}
  assert(stopped,'Disconnected guest can run '..name)
end
local host,hostSent=client(true)
app.sprite=host.sprite
local stopped=false
host:beforeCommand{name='SaveFileAs',stopPropagation=function() stopped=true end}
assert(not stopped,'Host cannot save')
app.sprite=source
guest:beforeCommand{name='SaveFileAs',stopPropagation=function() error('Unrelated document blocked') end}

-- Exercise the actual command dispatcher, not just the guard method.
local path=app.fs.joinPath(os.getenv('TEMP'),'Collabsprite-save-guard-'..os.time()..'-'..math.random(100000,999999)..'.aseprite')
local listener=app.events:on('beforecommand',function(ev) guest:beforeCommand(ev);host:beforeCommand(ev) end)
app.sprite=guest.sprite
app.command.SaveFileAs{ui=false,filename=path}
assert(not app.fs.isFile(path),'Guest Save As wrote a file')
app.sprite=host.sprite
draw(host,2,0xff987654)
app.command.SaveFileCopyAs{ui=false,filename=path}
assert(app.fs.isFile(path),'Native host Save Copy As failed')
local reopened=Sprite{fromFile=path}
assert(reopened.cels[1].image:getPixel(2,0)==0xff987654,'Saved host pixel missing')
reopened:close();os.remove(path);app.events:off(listener)
host.dirty=false

-- A departure presence message must not sample a transient local tool cel.
local captures=0
host.capture=function() captures=captures+1 end
host.inbox={{type='presence',members={}}};host:tick()
assert(captures==0,'Presence triggered a pixel rescan without a completed change')
for _=1,35 do host:tick() end
assert(captures==0,'Idle metadata timer sampled a transient held stroke')
-- Final data and connection-close in one tick must render before detach.
host.needsRender=true
host.cells['1:1'].bytes=Codec.applyRuns(host.cells['1:1'].bytes,{6,1,0xff010203})
local renderOk,renderError=pcall(function() host:render() end)
assert(renderOk,'Render with inactive session: '..tostring(renderError))
assert(app.sprite==nil,'Remote render selected a tab that was not active')
app.sprite=source
host.cells['1:1'].bytes=Codec.applyRuns(host.cells['1:1'].bytes,{7,1,0xff010203})
host.needsRender=true;host:render()
assert(app.sprite==source,'Remote render did not restore unrelated active tab')
app.command.Undo()
assert(pixel(host,7)==0xff010203,'Unrelated document undo affected remote pixels')
host.inbox={{type='patch',author='guest',seq=1,revision=1,
  patches={{layer=1,frame=1,runs={5,1,0xffabcdef}}}},
  {type='error',message='Synthetic connection close'}}
host:tick()
assert(host.closed and pixel(host,5)==0xffabcdef,'Final received patch lost on close: '..tostring(lastFatal))

local waiting=client(false)
local unexpected=false
waiting:requestLeave(function() unexpected=true end)
waiting.leaving.started=os.time()-11
waiting:finishLeave()
assert(not unexpected and waiting.connected and waiting.sprite.isValid,'Timeout discarded unsent work')
waiting:disconnect()
source:close();guest.sprite:close();host.sprite:close();waiting.sprite:close()
print('PASS: last-stroke drain, acknowledgement barrier, late edit, timeout, guest save guard, presence and final patch')
io.stdout:flush()
app.exit()
