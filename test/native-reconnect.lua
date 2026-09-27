-- Real native sockets + disposable sprites. Never opens or saves user artwork.
local root=assert(app.params.root)
local Client=dofile(root..'/extension/client.lua')
local C=dofile(root..'/extension/codec.lua')
local function trace(event,detail) print(event..': '..tostring(detail));io.stdout:flush() end
local a,b=Client.new(nil,trace),Client.new(nil,trace)
local source=Sprite(8,8,ColorMode.RGB)
source:newLayer();source:newEmptyFrame(2)
local stage,started=0,os.time()
local timer,dialog,guestSprite
local function pixel(c,l,f,i) return string.unpack('<I4',C.scan(c.sprite,c.mapping)[C.key(l,f)].bytes,i*4+1) end
local function draw(c,l,f,i,value)
  app.sprite=c.sprite;app.layer=c.mapping[l];app.frame=c.sprite.frames[f]
  app.transaction('Testpixel',function()
    local cel=c.mapping[l]:cel(f)
    local im=cel and cel.image:clone() or Image(8,8,ColorMode.RGB)
    im:drawPixel(i%8,i//8,value)
    if cel then cel.image=im else c.sprite:newCel(c.mapping[l],f,im,Point(0,0)) end
  end)
  c:capture()
end
local function finish(result)
  trace('result',result);timer:stop();a:disconnect();b:disconnect()
  if app.params.result then local file=assert(io.open(app.params.result,'wb'));file:write(result);file:close() end
  if dialog then dialog:modify{id='status',text=result} end
end
a:host(source,'Host',tonumber(app.params.port))
timer=Timer{interval=0.04,ontick=function()
  local ok,err=pcall(function()
    a:tick()
    -- Stage 2 deliberately withholds the guest's acknowledgement processing.
    if stage~=2 then b:tick() end
    if a.closed or b.closed then error(a.status..' / '..b.status) end
    if os.time()-started>60 then error('Zeitlimit Schritt '..stage) end
    if stage==0 and a.connected then
      b:join(a.invite,'Gast');stage=1
    elseif stage==1 and b.connected then
      guestSprite=b.sprite;draw(b,2,2,0,0xff0000ff);stage=2
    elseif stage==2 and pixel(a,2,2,0)==0xff0000ff then
      assert(#b.pending==1,'Lost-ack test needs pending operation')
      -- A second completed stroke is queued locally but never put on the wire.
      local transport=b.ws;b.ws={sendText=function() end}
      draw(b,2,2,1,0xff00ff00);b.ws=transport
      assert(#b.pending==2)
      b:suspend();b.retryAt=os.time()+3
      assert(not b.mapping[2].isEditable,'Offline drawing was not paused')
      a:delete('layer',1);stage=3
    elseif stage==3 and #a.mapping==1 then
      a:delete('frame',1);stage=4
    elseif stage==4 and #a.sprite.frames==1 then
      draw(a,1,1,2,0xffff0000);stage=5
    elseif stage==5 and b.connected and #b.pending==0 and #b.mapping==1 and #b.sprite.frames==1 then
      assert(b.sprite==guestSprite,'Reconnect created another tab')
      assert(pixel(a,1,1,0)==0xff0000ff and pixel(a,1,1,1)==0xff00ff00 and pixel(b,1,1,2)==0xffff0000,'Rebase or pending reconciliation failed')
      assert(b.mapping[1].isEditable,'Drawing was not unlocked')
      assert(b.undoCount==2,'Personal history lost or duplicate operation applied')
      b:action('undo');stage=6
    elseif stage==6 and pixel(a,1,1,1)==0 and pixel(b,1,1,1)==0 then
      assert(pixel(a,1,1,2)==0xffff0000,'Peer pixel erased by guest undo')
      b:action('undo');stage=7
    elseif stage==7 and pixel(a,1,1,0)==0 and pixel(b,1,1,0)==0 then
      b:restoreDeletion();stage=8
    elseif stage==8 and #a.sprite.frames==2 and #b.sprite.frames==2 then
      assert(b.sprite==guestSprite and pixel(b,1,2,2)==0xffff0000)
      b:restoreDeletion();stage=9
    elseif stage==9 and #a.mapping==2 and #b.mapping==2 then
      assert(pixel(a,2,2,2)==0xffff0000 and pixel(b,2,2,2)==0xffff0000,'Restoration erased newer content')
      a:action('undo');stage=10
    elseif stage==10 and pixel(a,2,2,2)==0 and pixel(b,2,2,2)==0 then
      finish('PASS native reconnect: lost ack, unsent stroke, rebase, same tab, own undo, restore, peer undo.')
    end
  end)
  if not ok then finish('FAIL stage '..stage..': '..tostring(err)) end
end}
timer:start()
dialog=Dialog{title='Collabsprite Wiederverbindungstest'}
dialog:label{id='status',text='Test mit neuen Bildern und absichtlichem Verbindungsabbruch ...'}
dialog:show{wait=true}
