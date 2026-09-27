local root=assert(app.params.root)
local Client=dofile(root..'/extension/client.lua')
local C=dofile(root..'/extension/codec.lua')
local function snapshot()
  return {format=1,name='Resume test',width=4,height=4,
    layers={{id=string.rep('1',32),name='Layer',parent=0,group=false,opacity=255,blend=3,visible=true,editable=true}},
    frames={100},frameIds={string.rep('2',32)},cels={},palette={0,0xffffffff}}
end
local function client()
  local c=Client.new()
  c.ws={sendText=function() end,close=function() end}
  c:receive{type='welcome',protocol=5,author='guest',host=false,room='TEST',resumeToken=string.rep('a',64),resumeMs=120000,
    confirmedSeq=0,snapshot=snapshot(),revision=0,structure=0}
  return c
end
local c=client()
local same=c.sprite
c:suspend()
assert(c.reconnecting and not c.mapping[1].isEditable)
local stopped=false
c:beforeCommand{name='NewFrame',stopPropagation=function() stopped=true end}
assert(stopped,'Offline command not blocked')
c:receive{type='welcome',protocol=5,resumed=true,author='guest',host=false,room='TEST',resumeToken=string.rep('a',64),
  confirmedSeq=0,snapshot=snapshot(),revision=0,structure=0}
assert(c.connected and c.sprite==same and c.mapping[1].isEditable)
c:suspend()
-- Even scripts that bypass the temporary locks must not lose their edits.
local cel=c.mapping[1]:cel(1)
local im=cel.image:clone();im:drawPixel(1,1,0xff123456);cel.image=im
local ok,err=pcall(function() c:replaceSnapshot(snapshot(),0) end)
assert(not ok and tostring(err):find('lokal verändert',1,true))
assert(c.mapping[1]:cel(1).image:getPixel(1,1)==0xff123456)
c:disconnect();assert(c.mapping[1].isEditable)
c.sprite:close()
local d=client()
d.pending={{type='paint',seq=1,patches={{layer=1,frame=1,layerId=string.rep('3',32),frameId=string.rep('2',32),runs={0,1,23}}}}}
local before=d.mapping[1]
ok=pcall(function() d:replaceSnapshot(snapshot(),0) end)
assert(not ok and d.mapping[1]==before,'Deleted pending target changed native document')
d:disconnect();d.sprite:close()
print('PASS: native resume keeps tab, pauses edits, rejects local mutation and deleted pending targets without replacing art')
