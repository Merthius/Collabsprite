local root=assert(app.params.root)
local Client=dofile(root..'/extension/client.lua')
local C=dofile(root..'/extension/codec.lua')
local Json=dofile(root..'/extension/json.lua')
local seq=0
local function bridge(peer,action,data)
  seq=seq+1
  local request=root..'/test-results/native-document-request.json'
  local response=root..'/test-results/native-document-response.json'
  local file=assert(io.open(request,'wb'));file:write(json.encode{peer=peer,action=action,data=data,token=app.params.token});file:close()
  local cmd='curl.exe --silent --show-error --fail --max-time 5 --data-binary @"'..request..'" --output "'..response..'" http://127.0.0.1:'..app.params.bridge
  local ok=os.execute(cmd);assert(ok,'Bridge failed')
  file=assert(io.open(response,'rb'));local out=Json.decode(file:read('*a'));file:close();return out
end
local function client(key)
  local c=Client.new(nil,function(event,detail)
    if event:find('FATAL') or event:find('error') then print(event..': '..tostring(detail)) end
  end)
  function c:connect(url,hello)
    self.connecting=true;self.started=os.time();self.closed=false
    self.ws={sendText=function(_,data) bridge(key,'send',data) end,close=function() end}
    self:send(hello)
  end
  function c:pump()
    for _,message in ipairs(bridge(key,'poll')) do self:enqueue(message) end
    self:tick();assert(not self.closed,'Disconnected: '..self.status)
  end
  return c
end
local a,b=client('A'),client('B')
local before=app.events:on('beforecommand',function(ev) a:beforeCommand(ev);b:beforeCommand(ev) end)
local after=app.events:on('aftercommand',function() if app.sprite==a.sprite then a.dirty=true elseif app.sprite==b.sprite then b.dirty=true end end)
local source=Sprite(8,8,ColorMode.RGB)
a:host(source,'Host',0);a:pump();assert(a.connected)
b:join(a.invite,'Gast');b:pump();a:pump();assert(b.connected)
local function flush()
  for _=1,2 do a:pump();b:pump() end
  assert(not a.documentPending and not b.documentPending,'Document confirmation missing')
  assert(a.revision==b.revision,'Revision divergence')
  local sa=C.capture(a.sprite,a.identity);local sb=C.capture(b.sprite,b.identity)
  sa.name='test';sb.name='test';assert(json.encode(sa)==json.encode(sb),'Native document divergence')
end
local function native(c,action)
  print('Native step at revision '..a.revision);io.stdout:flush()
  app.sprite=c.sprite;action();assert(c.dirty,'Completed native edit did not signal a change');c:capture();flush()
end
native(a,function() app.command.NewFrame{content='empty'} end)
native(b,function() app.frame=b.sprite.frames[1];app.command.NewFrame{content='empty'} end)
assert(#a.sprite.frames==3)
native(a,function() app.command.NewLayer{name='Details',ui=false} end)
native(b,function() app.command.NewLayer{name='Figur',group=true,ui=false} end)
native(a,function() a.mapping[2].parent=a.mapping[3] end)
assert(a.meta.layers[2].group and a.meta.layers[3].parent==2)
native(b,function() b.mapping[2].stackIndex=1 end)
native(a,function()
  local tag=a.sprite:newTag(1,3);tag.name='Idle';tag.aniDir=AniDir.PING_PONG;tag.repeats=2
end)
native(b,function()
  app.layer=b.mapping[2];app.frame=b.sprite.frames[1];app.range:clear();app.range.layers={app.layer};app.range.frames={1,2,3}
  app.command.LinkCels()
end)
assert(a.mapping[2]:cel(1).image.id==a.mapping[2]:cel(3).image.id,'Links flattened on receiver')
native(a,function()
  app.useTool{tool='pencil',color=Color{r=255,g=0,b=0,a=255},brush=Brush(1),points={Point(2,2)},layer=a.mapping[2],frame=a.sprite.frames[2]}
end)
assert(b.mapping[2]:cel(1).image:getPixel(2,2)==0xff0000ff,'Linked pixel not synchronized')
native(b,function() app.command.UnlinkCel() end)
local oldIds={table.unpack(a.meta.frameIds)}
native(a,function() app.range:clear();app.range.frames={1,2,3};app.command.ReverseFrames() end)
assert(a.meta.frameIds[1]==oldIds[3] and a.meta.frameIds[3]==oldIds[1],'Reversed frames lost stable identity')
native(b,function() b.mapping[2].name='Gast-Details' end)
b:action('undo');flush();assert(a.mapping[2].name~='Gast-Details','Own property undo failed')
b:action('redo');flush();assert(a.mapping[2].name=='Gast-Details')
native(a,function() app.range:clear();a.sprite:crop(Rectangle(-2,-2,12,12)) end)
assert(b.sprite.width==12)
a:action('undo');flush();assert(b.sprite.width==8,'Canvas undo failed')
a:action('redo');flush();assert(b.sprite.width==12)
-- Rename from stale state while the peer paints: field-wise merge, no loss.
app.sprite=a.sprite;a.mapping[2].name='Gemeinsam';a:capture()
app.sprite=b.sprite
app.useTool{tool='pencil',color=Color{r=0,g=255,b=0},brush=Brush(1),points={Point(3,3)},layer=b.mapping[2],frame=b.sprite.frames[1]}
b:capture();flush();assert(a.mapping[2]:cel(1).image:getPixel(3,3)==0xff00ff00)
-- Simultaneous conflicting renames preserve a separate local draft and keep
-- the guest's normal saving restriction attached through the notify hook.
app.sprite=a.sprite;a.mapping[2].name='A';a:capture()
app.sprite=b.sprite;b.mapping[2].name='B';b:capture();flush()
assert(b.recoverySprites and #b.recoverySprites>=1,'Conflict draft missing')
assert(a.mapping[2].name=='A' and b.mapping[2].name=='A')
native(a,function() app.range:clear();app.layer=a.mapping[#a.mapping];app.command.RemoveLayer() end)
a:action('undo');flush()
native(b,function() app.range:clear();app.frame=b.sprite.frames[2];app.command.RemoveFrame() end)
b:action('undo');flush();assert(#a.sprite.frames==3)
native(a,function() app.command.NewLayer{name='Merge-Test',top=true} end)
local layers=#a.mapping
native(b,function() app.useTool{tool='pencil',color=Color{r=20,g=30,b=40},brush=Brush(1),points={Point(1,1)},layer=b.mapping[#b.mapping],frame=b.sprite.frames[1]} end)
native(a,function() app.range:clear();app.layer=a.mapping[#a.mapping];app.command.MergeDownLayer() end)
assert(#b.mapping==layers-1,'Native merge not synchronized')
a:action('undo');flush();assert(#b.mapping==layers,'Native merge undo failed')
b:action('undo');flush();assert(b.mapping[#b.mapping]:cel(1).image:getPixel(1,1)==0,'Restored pre-merge guest history lost')
a:disconnect();b:disconnect();app.events:off(before);app.events:off(after)
for _,c in ipairs{a,b} do for _,s in ipairs(c.recoverySprites or {}) do s:close() end;c.sprite:close() end
source:close()
os.remove(root..'/test-results/native-document-request.json');os.remove(root..'/test-results/native-document-response.json')
print('PASS: native cooperative document transactions: host + guest, groups, frame insertion/reorder, links, tags, canvas, undo/redo, simultaneous paint, conflict recovery, deletion')
io.stdout:flush();app.exit()
