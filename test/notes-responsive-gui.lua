-- Disposable native UI proof; never opens or writes user artwork.
local root=assert(app.params.root)
local token=assert(app.params.token)
local N=dofile(root..'/extension/notes.lua')
local P=dofile(root..'/extension/notes-paper.lua')
local V=dofile(root..'/extension/notes-paper-view.lua')
local UI=dofile(root..'/extension/notes-ui.lua')
local sprite=Sprite(16,16,ColorMode.RGB);sprite.filename='Collabsprite 0.12.1 - Test'
local errors={}
local busy=false
local function safe(fn)
  if busy then return end
  busy=true;local ok,err=pcall(fn);busy=false
  if not ok then errors[#errors+1]=tostring(err) end
end
local ui=UI.new(function() end,function() return false end,safe)
local s=ui:state(sprite)
local owner=Dialog{title='Collabsprite #'..token:sub(1,12)}
owner:label{text='Isolierter Starttest - keine Nutzerdaten'}
local dense=Image(1000,1000,ColorMode.RGB)
dense.bytes=string.rep(string.char(40,110,170,255)..string.char(220,180,80,255),500000)
ui:task(s,'Skizzenblatt vorbereiten',function() return P.pack(dense) end,function(ok,data)
  assert(ok,'Dense packing failed')
  local card=N.newCard('','',0,0);card.kind='paper';card.image=data
  ui:action(s,{action='patch',patches={{id=card.id,expected=false,value=card}}},function(ok)
    assert(ok);V.open(ui,s,card.id)
  end)
end)
local last,maxGap,count=os.clock(),0,0
local timer=Timer{interval=0.033,ontick=function()
  local now=os.clock();maxGap=math.max(maxGap,now-last);last=now;count=count+1
  safe(function() ui:tick() end)
  if count==180 then owner:modify{id='health',text=string.format('Ticks: %d | CPU-Pause: %.3f s | Fehler: %d',count,maxGap,#errors)} end
end};timer:start()
local quit=Timer{interval=150,ontick=function()
  timer:stop();ui:close();owner:close();sprite:close();app.exit()
end};quit:start()
owner:label{id='health',text='Vorbereitung läuft ...'}
local launch
launch=Timer{interval=0.5,ontick=function()
  ui:show(sprite);owner:show{wait=false};launch:stop()
end};launch:start()
