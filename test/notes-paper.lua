local root=assert(app.params.root)
local N=dofile(root..'/extension/notes.lua')
local P=dofile(root..'/extension/notes-paper.lua')
local sprite=Sprite(16,16,ColorMode.RGB)
local palette=P.palette(sprite)
assert(#palette>0,'The sheet pen has no session palette')
local blank=P.blank()
assert(blank.width==1000 and blank.height==1000 and blank.encoding=='rle')
local drawing=P.unpack(blank)
local ink=palette[1].color
P.stroke(drawing,4,4,4,4,1,ink,false)
assert(drawing:getPixel(4,4)==ink.rgbaPixel,'A one-pixel pen stroke did not paint')
assert(app.pixelColor.rgbaA(drawing:getPixel(3,4))==0,'A one-pixel pen stroke exceeded its circle')
P.stroke(drawing,20,20,25,20,4,ink,false)
for x=20,25 do assert(app.pixelColor.rgbaA(drawing:getPixel(x,20))==255,'Pen line has a gap') end
P.stroke(drawing,20,20,20,20,4,ink,true)
assert(app.pixelColor.rgbaA(drawing:getPixel(20,20))==0,'Eraser did not clear the sketch')
local chunk=Image(96,96,ColorMode.RGB)
for y=0,95 do for x=0,95 do chunk:drawPixel(x,y,ink.rgbaPixel) end end
P.stroke(chunk,10,10,80,80,8,ink,true)
for n=10,80 do
  assert(app.pixelColor.rgbaA(chunk:getPixel(n,n))==0,'Fast diagonal erase left a gap')
end
assert(app.pixelColor.rgbaA(chunk:getPixel(10,7))==0 and
  app.pixelColor.rgbaA(chunk:getPixel(7,10))==0,'Eraser did not clear a square chunk')
assert(app.pixelColor.rgbaA(chunk:getPixel(1,1))==255,'Eraser removed pixels outside its stroke')
local lower=P.unpack(blank);P.paint(lower,20,20,1,ink,false)
local upper=P.unpack(blank);P.paint(upper,20,20,8,ink,false)
local function count(image)
  local n=0;for y=0,40 do for x=0,40 do if app.pixelColor.rgbaA(image:getPixel(x,y))>0 then n=n+1 end end end;return n
end
assert(count(upper)>count(lower),'Pressure-adjusted sizes did not change stroke width')
local source=Image(16,16,ColorMode.RGB)
source:drawPixel(0,0,app.pixelColor.rgba(12,34,56,255))
local packed=P.overlay(P.unpack(blank),source)
assert(packed.width==1000 and packed.height==1000)
local result=P.unpack(packed)
assert(result:getPixel(0,0)==app.pixelColor.rgba(12,34,56,255),'Imported image was not upscaled onto the sheet')
local legacy={width=128,height=128,pixels=string.rep('00000000',128*128)}
assert(P.unpack(legacy).width==1000,'Existing 128-pixel sketch did not scale up safely')
assert(N.field('image',blank) and not N.field('image',{width=1000,height=1000,encoding='rle',pixels='000000000000'}),
  'Sketch storage accepted invalid run lengths')
local dense=Image(1000,1000,ColorMode.RGB)
dense.bytes=string.rep(string.rep(string.char(7,11,19,255)..string.char(23,29,31,255),500),1000)
local densePacked=P.pack(dense)
assert(densePacked.encoding=='b64' and N.field('image',densePacked),'Dense sheets were not encoded within the transfer limit')
assert(P.unpack(densePacked):getPixel(999,999)==dense:getPixel(999,999),'Dense sheet compression lost a pixel')
local denseSprite=Sprite(1,1,ColorMode.RGB)
local denseCard=N.newCard('','',1,1);denseCard.kind='paper';denseCard.image=densePacked
local denseBoard=N.empty();denseBoard.cards={denseCard};N.write(denseSprite,denseBoard)
local densePath=root..'/test-results/notes-paper-dense.aseprite'
denseSprite:saveAs(densePath);denseSprite:close()
local denseReopened=app.open(densePath)
assert(P.unpack(N.read(denseReopened).cards[1].image):getPixel(999,999)==dense:getPixel(999,999),
  'Dense 1000-pixel sketch did not survive .aseprite save')
denseReopened:close()
local paper=N.newCard('','',10,10);paper.kind='paper';paper.image=P.pack(drawing)
local board=N.empty();board.cards={paper}
N.validate(board);N.write(sprite,board)
local saved=root..'/test-results/notes-paper-roundtrip.aseprite'
sprite:saveAs(saved);sprite:close()
local reopened=app.open(saved)
local loaded=N.read(reopened)
assert(loaded.cards[1].kind=='paper' and loaded.cards[1].image.pixels==paper.image.pixels,'Shared sheet lost pixels when saved')
local old=N.copy(loaded);old.format=6
assert(N.validate(old).format==8,'Previous notes format did not migrate to paper format')
local second=N.newCard('','',40,40);second.kind='paper';second.image=P.blank()
loaded.cards[#loaded.cards+1]=second
N.write(reopened,loaded)
local props=reopened.properties(N.key)
local previousCount=tonumber(props.board:match('^CS7:(%d+):'))
assert(previousCount and previousCount>=1 and props.board_1,'A second sheet was not split into safe property chunks')
table.remove(loaded.cards)
N.write(reopened,loaded)
local currentCount=tonumber(props.board:match('^CS7:(%d+):'))
assert(currentCount and currentCount<=previousCount,'Sketch storage chunk count changed unexpectedly')
for i=currentCount+1,previousCount do assert(props['board_'..i]==nil,'Old sketch data chunk was not removed') end
assert(N.read(reopened).cards[1].image.pixels==paper.image.pixels,'Rewritten sketch was corrupted')
reopened:close()
print('PASS native sketch strokes, eraser, palette, import, persistence and migration')
io.stdout:flush();app.exit()
