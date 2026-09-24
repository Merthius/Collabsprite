-- Automated integration test in a dedicated Aseprite UI process, never the user's process.
local root=app.params.root
local Client=dofile(root..'/extension/client.lua')
local codec=dofile(root..'/extension/codec.lua')
local function log(text) print(text);io.stdout:flush() end
local a,b=Client.new(function(s) log('A: '..s.status) end),Client.new(function(s) log('B: '..s.status) end)
local size=tonumber(app.params.size) or 8
local idleSeconds=tonumber(app.params.idle) or 0
local source=Sprite(size,size,ColorMode.RGB)
local before=app.events:on('beforecommand',function(ev) a:beforeCommand(ev);b:beforeCommand(ev) end)
local started=os.time()
local stage=0
local idleStarted
local testTimer
local testDialog
local function report(text)
  log(text)
end
local function finish(text)
  report(text)
  testTimer:stop();a:disconnect();b:disconnect();app.events:off(before)
  for _,s in ipairs(app.sprites) do s:close() end
  if testDialog then testDialog:close() end
end
local function pixel(client,x,y)
  local scan=codec.scan(client.sprite,client.mapping)
  return string.unpack('<I4',scan['1:1'].bytes,(y*size+x)*4+1)
end
local function draw(client,color,points)
  app.sprite=client.sprite
  app.useTool{tool='pencil',color=Color{r=color&255,g=(color>>8)&255,b=(color>>16)&255,a=255},
    brush=Brush(1),points=points,layer=client.mapping[1],frame=client.sprite.frames[1]}
  client:capture()
end
a:host(source,'A',8766)
log('Host connect requested, API '..app.apiVersion)
started=os.time()
testTimer=Timer{interval=0.04,ontick=function()
  local ok,err=pcall(function()
    a:tick();b:tick()
    if a.closed or b.closed then error('Client stopped: '..a.status..' / '..b.status) end
    if os.time()-started>180 then error('Timeout stage '..stage..': '..a.status..' / '..b.status) end
    if stage==0 and a.connected then
      local localInvite=a.invite:gsub('^[^/]+:(%d+)/','127.0.0.1:%1/',1)
      assert(localInvite:match('^127%.0%.0%.1:8766/'),'Wrong local invitation')
      b:join(localInvite,'B');stage=1
    elseif stage==1 and b.connected then
      draw(a,0xff0000ff,{Point(1,1),Point(2,1)});stage=2
    elseif stage==2 and pixel(b,2,1)==0xff0000ff and #a.pending==0 then
      draw(b,0xff00ff00,{Point(1,1)});draw(b,0xff00ff00,{Point(3,1)});stage=3
    elseif stage==3 and pixel(a,1,1)==0xff00ff00 and pixel(a,3,1)==0xff00ff00 and #b.pending==0 then
      app.sprite=a.sprite;app.command.Undo();stage=4
    elseif stage==4 and a.revision>=4 and b.revision>=4 then
      assert(pixel(a,2,1)==0 and pixel(b,2,1)==0,'Own undo did not clear own pixel')
      assert(pixel(a,1,1)==0xff00ff00 and pixel(a,3,1)==0xff00ff00,'Own undo cleared peer pixels')
      app.command.Redo();stage=5
    elseif stage==5 and a.revision>=5 and b.revision>=5 then
      assert(pixel(a,2,1)==0xff0000ff and pixel(b,1,1)==0xff00ff00,'Redo damaged peer')
      a:append('layer','Gemeinsam 2');stage=6
    elseif stage==6 and #b.mapping==2 then
      a:append('frame');stage=7
    elseif stage==7 and #b.sprite.frames==2 then
      app.sprite=b.sprite
      app.command.NewLayer();stage=8
    elseif stage==8 and #a.mapping==3 and #b.mapping==3 then
      -- Native paint bucket, then verify one compact patch and undo over the wire.
      app.useTool{tool='paint_bucket',color=Color{r=11,g=22,b=33},points={Point(0,0)},layer=b.mapping[2],frame=b.sprite.frames[2]}
      b:capture();stage=9
    elseif stage==9 and a.revision>=9 and b.revision>=9 then
      local ca=codec.scan(a.sprite,a.mapping)['2:2'].bytes
      local cb=codec.scan(b.sprite,b.mapping)['2:2'].bytes
      assert(ca==cb and string.unpack('<I4',ca)==0xff21160b,'Fill did not synchronize')
      app.command.Undo();stage=10
    elseif stage==10 and a.revision>=10 and b.revision>=10 then
      assert(codec.scan(a.sprite,a.mapping)['2:2'].bytes==string.rep('\0',size*size*4),'Fill undo failed')
      local moved=b.mapping[1]:cel(1)
      moved.position=Point(1,0) -- intentionally extends one pixel off canvas
      b:capture();stage=11
    elseif stage==11 and pixel(a,4,1)==0xff00ff00 and pixel(a,1,1)==0 and #b.pending==0 then
      if idleSeconds>0 then idleStarted=os.time();stage=12
      else finish('PASS '..size..'x'..size..': native sync, own Undo/Redo, guest NewLayer, bucket and moved off-canvas cel.') end
    elseif stage==12 and os.time()-idleStarted>=idleSeconds then
      draw(a,0xffaa5500,{Point(0,0)});stage=13
    elseif stage==13 and pixel(b,0,0)==0xffaa5500 and #a.pending==0 then
      finish('PASS '..size..'x'..size..': moved cel and synchronization after '..idleSeconds..' idle seconds.')
    end
  end)
  if not ok then finish('FAIL stage '..stage..': '..tostring(err)) end
end}
testTimer:start()
log('Timer started')
testDialog=Dialog{title='Collabsprite - automatischer Verbindungstest'}
testDialog:label{text='Testet zwei native Verbindungen mit eigenen Testbildern.'}
testDialog:show{wait=true}
a:disconnect();b:disconnect();testTimer:stop()
app.exit()
