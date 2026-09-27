-- Dedicated Aseprite UI test. Uses new disposable sprites, never user artwork.
local root=assert(app.params.root,'root fehlt')
local Client=dofile(root..'/extension/client.lua')
local codec=dofile(root..'/extension/codec.lua')
local rejections=0
local function trace(event,detail)
  if event=='websocket receive' and detail=='rejected' then rejections=rejections+1 end
  print(event..': '..tostring(detail));io.stdout:flush()
end
local a,b=Client.new(nil,trace),Client.new(nil,trace)
local source=Sprite(8,8,ColorMode.RGB)
local before=app.events:on('beforecommand',function(ev) a:beforeCommand(ev);b:beforeCommand(ev) end)
local stage,started,lastLoggedStage=0,os.time(),nil
local timer,dialog
local function log(text)
  print(text);io.stdout:flush()
  if dialog then dialog:modify{id='result',text=text} end
end
local function scan(client,layer,frame)
  return codec.scan(client.sprite,client.mapping)[codec.key(layer,frame)].bytes
end
local function pixel(client,layer,frame,index)
  return string.unpack('<I4',scan(client,layer,frame),index*4+1)
end
local function finish(result)
  log(result)
  if timer then timer:stop() end
  a:disconnect();b:disconnect();app.events:off(before)
  if app.params.result then
    local file=assert(io.open(app.params.result,'wb'));file:write(result);file:close()
    app.exit()
  end
end
a:host(source,'Host',tonumber(app.params.port) or 8766)
timer=Timer{interval=0.04,ontick=function()
  local ok,err=pcall(function()
    a:tick();b:tick()
    if a.closed or (b.closed and stage<12) then error('Verbindung: '..a.status..' / '..b.status) end
    if os.time()-started>60 then error('Zeitlimit in Schritt '..stage) end
    if stage~=lastLoggedStage then lastLoggedStage=stage;log('STAGE '..stage) end
    if stage==0 and a.connected then
      local invite=a.invite:gsub('^[^/]+:(%d+)/','127.0.0.1:%1/',1)
      b:join(invite,'Gast');stage=1
    elseif stage==1 and b.connected then
      a:send{type='admission',open=false};stage=1.5
    elseif stage==1.5 and a.acceptingGuests==false and b.acceptingGuests==false then
      a:append('layer','Zweite');stage=2
    elseif stage==2 and #b.mapping==2 then
      app.sprite=b.sprite;app.layer=b.mapping[2]
      app.useTool{tool='pencil',color=Color{r=255,g=0,b=0,a=255},brush=Brush(1),
        points={Point(1,1)},layer=b.mapping[2],frame=b.sprite.frames[1]}
      b:capture();stage=3
    elseif stage==3 and pixel(a,2,1,9)==0xff0000ff and #b.pending==0 then
      app.sprite=b.sprite;app.range:clear();app.layer=b.mapping[1]
      assert(app.command.RemoveLayer(),'RemoveLayer nicht verfuegbar')
      assert(#b.sprite.layers==1,'Native Ebenenloeschung wurde blockiert')
      stage=4
    elseif stage==4 and #a.mapping==1 and #b.mapping==1 then
      assert(pixel(a,1,1,9)==0xff0000ff and pixel(b,1,1,9)==0xff0000ff,'Cel nach Ebenenloeschung verloren')
      app.sprite=b.sprite;app.command.Undo();stage=5
    elseif stage==5 and #a.mapping==2 and #b.mapping==2 then
      assert(pixel(a,2,1,9)==0xff0000ff,'Struktur-Undo verlor vorherige Pixel')
      b:action('undo');stage=5.5
    elseif stage==5.5 and pixel(a,2,1,9)==0 and #b.pending==0 then
      app.sprite=a.sprite;app.command.NewFrame{content='empty'};stage=6
    elseif stage==6 and #b.sprite.frames==2 then
      app.sprite=a.sprite;app.range:clear();app.frame=a.sprite.frames[1]
      assert(app.command.RemoveFrame(),'RemoveFrame nicht verfuegbar')
      stage=7
    elseif stage==7 and #a.sprite.frames==1 and #b.sprite.frames==1 then
      a.mapping[1].name='Figur'
      a.mapping[1].isVisible=false
      a.mapping[1].isEditable=false
      a.mapping[1].opacity=128
      a.mapping[1].blendMode=BlendMode.MULTIPLY
      a.mapping[1].isContinuous=true
      a.sprite.frames[1].duration=0.25
      local cel=a.mapping[1]:cel(1) or a.sprite:newCel(a.mapping[1],1,Image(8,8,ColorMode.RGB),Point(0,0))
      cel.opacity=127
      cel.zIndex=2
      local pal=Palette(2)
      pal:setColor(0,Color{r=10,g=20,b=30,a=255})
      pal:setColor(1,Color{r=40,g=50,b=60,a=255})
      a.sprite:setPalette(pal)
      a:properties();stage=8
    elseif stage==8 and b.mapping[1].name=='Figur' and not b.mapping[1].isVisible and
      not b.mapping[1].isEditable and b.mapping[1].opacity==128 and
      b.mapping[1].blendMode==BlendMode.MULTIPLY and b.mapping[1].isContinuous and
      b.mapping[1]:cel(1).opacity==127 and b.mapping[1]:cel(1).zIndex==2 and #b.sprite.palettes[1]==2 and
      math.floor(b.sprite.frames[1].duration*1000+0.5)==250 then
      app.sprite=a.sprite;app.command.NewFrame{content='empty'};stage=9
    elseif stage==9 and #a.sprite.frames==2 and #b.sprite.frames==2 then
      app.sprite=a.sprite;app.command.NewFrame{content='empty'};stage=10
    elseif stage==10 and #a.sprite.frames==3 and #b.sprite.frames==3 then
      app.sprite=b.sprite;app.range.frames={1,2}
      -- Exercise native multi-delete inside one completed transaction.
      app.transaction(function() b.sprite:deleteFrame(2);b.sprite:deleteFrame(1) end)
      stage=11
    elseif stage==11 and #a.sprite.frames==1 and #b.sprite.frames==1 then
      b.mapping[1].isVisible=true;b.mapping[1].isEditable=true
      app.sprite=b.sprite
      app.transaction('Test: letzter Gast-Pixel',function()
        local cel=b.mapping[1]:cel(1)
        local image=cel and cel.image:clone() or Image(8,8,ColorMode.RGB)
        image:drawPixel(3,3,0xff7f3f1f)
        if cel then cel.image=image else b.sprite:newCel(b.mapping[1],1,image,Point(0,0)) end
      end)
      -- Deliberately no capture/timer between the last stroke and Leave.
      b:requestLeave(function() trace('leave','closing guest view');b.sprite:close();trace('leave','guest view closed') end)
      trace('leave','request queued')
      stage=12
    elseif stage==12 and b.closed and pixel(a,1,1,27)==0xff7f3f1f then
      app.sprite=a.sprite
      a:action('undo') -- Host's structural/property undo must preserve guest pixels.
      stage=13
    elseif stage==13 and #a.inbox==0 and a.ticks%10==0 then
      assert(pixel(a,1,1,27)==0xff7f3f1f,'Gast-Pixel nach Verlassen/Host-Undo verloren')
      a:delete('frame',1);stage=14 -- Deliberately rejected legacy request.
    elseif stage==14 and rejections>0 then
      assert(a.connected and #a.sprite.frames==1,'Abgelehnte Aktion beendet Sitzung')
      finish('PASS native: Struktur, Verlauf, Metadaten, Gast-Trennen/Host-Undo, Beitrittssperre, letzte-Frame-Ablehnung.')
    end
  end)
  if not ok then finish('FAIL native stage '..stage..': '..tostring(err)) end
end}
timer:start()
dialog=Dialog{title='Collabsprite Strukturtest'}
dialog:label{text='Automatischer Test mit neuen, ungespeicherten Bildern.'}
dialog:label{id='result',text='Test startet ...'}
dialog:show{wait=true}
