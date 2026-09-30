local root=assert(app.params.root)
local N=dofile(root..'/extension/notes.lua')
local C=dofile(root..'/extension/codec.lua')
local Client=dofile(root..'/extension/client.lua')
assert(loadfile(root..'/extension/notes-ui.lua'))
local b=N.empty();local h={undo={},redo={}};local c=N.newCard('Hexe')
b=N.localAction(b,h,{action='patch',patches={{id=c.id,expected=false,value=c}}})
local c2=N.newCard('Kleid',c.id,240,30)
b=N.localAction(b,h,{action='patch',patches={{id=c2.id,expected=false,value=c2}}})
b=N.localAction(b,h,{action='patch',patches={N.patch(N.card(b,c2.id),'text','Dunkelviolett\nFlicken und Saum')}})
local s=Sprite(4,4,ColorMode.RGB)
local UI=dofile(root..'/extension/notes-ui.lua')
local ui=UI.new(function() end,function() return false end,function(fn) fn() end)
assert(not rawequal(s,app.sprite),'Identity regression needs real native wrappers')
assert(ui:state(s)==ui:state(app.sprite),'Native wrappers created duplicate notes windows/states')
for _=1,12 do ui:tick() end
local count=0;for _ in pairs(ui.states) do count=count+1 end;assert(count==1,'Tick created duplicate note states')
s.data='Existing user data';s.properties('Other/Plugin').keep='untouched'
app.transaction('Notizen',function() N.write(s,b) end)
assert(s.isModified,'Notes did not mark dirty')
local file=root..'/test-results/notes-roundtrip.aseprite'
s:saveAs(file);s:close();s=app.open(file)
assert(N.equal(N.read(s),b),'Saved notes mismatch');assert(s.data=='Existing user data' and s.properties('Other/Plugin').keep=='untouched')
local snap=C.capture(s);local copy,mapping=C.create(snap)
assert(N.equal(N.read(copy),b),'Session copy lost notes')
local second=root..'/test-results/notes-copy.aseprite'
copy:saveAs(second);copy:close();copy=app.open(second);assert(N.equal(N.read(copy),b),'Save As lost notes')
app.sprite=copy
local changed=N.localAction(b,h,{action='patch',patches={N.patch(N.card(b,c2.id),'color','#5E3A79')}})
app.transaction('Notizen',function() N.write(copy,changed) end)
assert(copy.isModified and N.equal(N.read(s),b),'Independent file was changed')
-- Reopening a saved image must show its notes without a server or a guest.
-- Exercise the real polling/persistence logic; replace only native painting.
local offline=UI.new(function() return nil end,function() return false end,function(fn) fn() end)
local opened={}
function offline:show(sprite)
  local state=self:state(sprite);state.seen=true
  opened[#opened+1]={id=sprite.id,board=N.copy(state.board)}
end
local function poll() for _=1,12 do offline:tick() end end
app.sprite=s;poll()
assert(#opened==1 and opened[1].id==s.id and N.equal(opened[1].board,b),'Saved notes did not auto-open offline')
poll();assert(#opened==1,'Closed notes window reopened every tick')
app.sprite=copy;poll()
assert(#opened==2 and opened[2].id==copy.id and N.equal(opened[2].board,changed),'Different image displayed the wrong notes')
app.sprite=s;poll();assert(#opened==2,'Switching tabs ignored dismissed notes window')
local reopened=app.open(file);poll()
assert(#opened==3 and opened[3].id==reopened.id and N.equal(opened[3].board,b),'Reopening image did not restore automatic notes')
reopened:close()
local empty=Sprite(4,4,ColorMode.RGB);poll()
assert(#opened==3,'Unannotated image opened an unwanted empty popup')
offline:show(empty);assert(#opened==4,'Empty image cannot open notes manually');empty:close()
local client=Client.new()
client:receive{type='welcome',protocol=14,host=true,author='host',room='test',snapshot=snap,revision=0,structure=0}
client.ws={sendText=function() end,close=function() end}
client:receive{type='notes',board=changed,history={seq=0,undo=0,redo=0},locks={},saved=-1}
assert(N.equal(N.read(client.sprite),changed),'Received notes not embedded')
client.sprite:saveAs(root..'/test-results/notes-received.aseprite')
local received=app.open(root..'/test-results/notes-received.aseprite')
assert(N.equal(N.read(received),changed),'Received notes did not survive native save/reopen');received:close()
app.sprite=client.sprite
local sent={};client.ws.sendText=function(_,text) sent[#sent+1]=text end
client:capture();assert(#sent==0,'Note property leaked as a pixel operation')
local stopped=false
client:beforeCommand{name='Undo',stopPropagation=function() stopped=true end}
assert(stopped and sent[1]:find('undo'),'Pixel undo routing was changed')
local corrupt=N.copy(changed);corrupt.cards[1].parent=corrupt.cards[1].id
assert(not pcall(N.validate,corrupt),'Cycle accepted')
client:disconnect();client.sprite:close();copy:close();s:close()
print('PASS notes: .aseprite roundtrip, offline automatic reopening, per-file notes, dismissal, empty image, Save As, independent copy, custom userdata, session copy, dirty state, pixel undo isolation, validation')
io.stdout:flush();app.exit()
