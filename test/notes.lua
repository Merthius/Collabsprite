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
local client=Client.new()
client:receive{type='welcome',protocol=5,host=true,author='host',room='test',snapshot=snap,revision=0,structure=0}
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
print('PASS notes: .aseprite roundtrip, Save As, independent copy, custom userdata, session copy, dirty state, pixel undo isolation, validation')
io.stdout:flush();app.exit()
