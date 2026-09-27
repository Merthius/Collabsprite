local root=assert(app.params.root)
local C=dofile(root..'/extension/codec.lua')
local Client=dofile(root..'/extension/client.lua')
local Json=dofile(root..'/extension/json.lua')
local function eq(a,b) return json.encode(a)==json.encode(b) end
local source=Sprite(8,8,ColorMode.RGB)
source.layers[1].name='Basis'
source:newCel(source.layers[1],1,Image(8,8,ColorMode.RGB),Point(0,0))
source:newEmptyFrame(2);source:newEmptyFrame(3)
local initial=C.capture(source)
local sprite,map=C.create(initial)
local known=C.track(sprite,map,initial)
app.sprite=sprite
-- Insert in the middle, not at the end. Existing identities follow native cels.
sprite:newEmptyFrame(2)
local inserted=C.capture(sprite,known)
assert(inserted.frameIds[1]==initial.frameIds[1] and inserted.frameIds[3]==initial.frameIds[2] and inserted.frameIds[4]==initial.frameIds[3],'Frame insertion confused identities')
assert(inserted.frameIds[2]~=initial.frameIds[2],'Inserted frame reused another ID')
map=C.flatten(sprite);known=C.track(sprite,map,inserted)
local group=sprite:newGroup();group.name='Aussehen';map[1].parent=group
local organized=C.capture(sprite,known)
assert(organized.layers[1].group and organized.layers[2].parent==1 and organized.layers[2].id==initial.layers[1].id,'Group organization lost identity')
local tag=sprite:newTag(1,3);tag.name='Laufen';tag.aniDir=AniDir.PING_PONG;tag.repeats=2;tag.color=Color{r=12,g=34,b=56}
local second=sprite:newTag(2,4);second.name='Idle'
local tagged=C.capture(sprite)
local other,otherMap=C.create(tagged)
local roundtrip=C.capture(other)
assert(eq(tagged.tags,roundtrip.tags),'Animation tags changed on roundtrip')
-- Actual native shared cel images (not visually equal independent copies).
for i,cel in ipairs(tagged.cels) do cel.link=tagged.frameIds[1];cel.opacity=80;cel.z=i end
local linked,linkedMap=C.create(tagged)
for _,cel in ipairs(tagged.cels) do
  local native=linkedMap[cel.layer]:cel(cel.frame)
  assert(native.opacity==cel.opacity and native.zIndex==cel.z,'Link properties: frame '..cel.frame..', opacity '..native.opacity..'/'..cel.opacity..', z '..native.zIndex..'/'..cel.z)
end
assert(linkedMap[2]:cel(1).image.id==linkedMap[2]:cel(3).image.id,'Native cels are not linked')
linkedMap[2]:cel(2).image:drawPixel(1,1,0xffaabbcc)
assert(linkedMap[2]:cel(4).image:getPixel(1,1)==0xffaabbcc,'Linked drawing failed')
local again=C.capture(linked)
assert(again.cels[1].link and again.cels[1].link==again.cels[4].link,'Link metadata lost')
-- Rebuild a canvas size change in the same native Sprite, preserving its tab.
again.width=16;again.height=16
C.replace(linked,again,C.decode(again))
assert(linked.width==16 and linked.height==16,'Canvas resize failed')
-- Standard commands are no longer intercepted as blocked append-only actions.
local client=Client.new();client.sprite=other;client.connected=true;client.meta=roundtrip
client.author='test'
client.mapping=otherMap;client.cells=C.decode(roundtrip);client.baseline=C.scan(other,otherMap);client.identity=C.track(other,otherMap,roundtrip)
local sent={};client.ws={sendText=function(_,data) sent[#sent+1]=Json.decode(data) end,close=function() end}
app.sprite=other
for _,name in ipairs{'NewFrame','NewLayer','MoveLayer','LinkCels','UnlinkCel','CanvasSize','CropSprite','MergeDownLayer','NewTag','FrameTagProperties'} do
  local stopped=false;client:beforeCommand{name=name,params={},stopPropagation=function() stopped=true end}
  assert(not stopped,'Native command blocked: '..name)
end
otherMap[2].name='Haare';client:capture()
assert(sent[1].type=='document' and sent[1].after.layers[2].name=='Haare','Native metadata edit not captured')
client:receive{type='document',author='test',requestId=sent[1].requestId,snapshot=sent[1].after,revision=1,structure=1}
assert(not client.documentPending and client.connected,'Document ack failed')
-- Deleting the final cel must not destroy the frame's stable identity.
client.sprite:deleteCel(client.mapping[2]:cel(2));client:capture()
assert(client.mapping[2]:cel(2),'Empty frame has no identity anchor')
local ids={table.unpack(client.meta.frameIds)}
client.sprite:newEmptyFrame(2)
local afterEmpty=C.capture(client.sprite,client.identity)
assert(afterEmpty.frameIds[3]==ids[2] and afterEmpty.frameIds[4]==ids[3],'Empty-frame insertion lost old frame identity')
for _,s in ipairs{source,sprite,other,linked} do s:close() end
print('PASS: native middle insertion, groups, tags, real links, resize, normal commands, document capture/ack')
io.stdout:flush();app.exit()
