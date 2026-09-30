local root=assert(app.params.root)
local N=dofile(root..'/extension/notes.lua')
local S=dofile(root..'/extension/notes-stack.lua')
local I=dofile(root..'/extension/notes-image.lua')
local F=dofile(root..'/extension/notes-style.lua')
local UI=dofile(root..'/extension/notes-ui.lua')
local a=N.newCard('Hexe','',10,20);local b=N.newCard('Haare',a.id);local c=N.newCard('Blau',b.id)
local board=N.empty();board.cards={a,b,c};N.validate(board)
local hist={undo={},redo={}}
local boxes,map=S.layout(board);assert(#boxes==3 and boxes[1].heading and not boxes[2].heading)
local wrapped=S.lines('Referenz: unser gemeinsames Projekt',false,S.width-28)
assert(#wrapped==3 and wrapped[1].text=='Referenz: unser' and wrapped[2].text=='gemeinsames' and wrapped[2].start==16 and wrapped[3].text=='Projekt' and wrapped[3].start==28,'Word wrap split a normal word or broke caret positions: '..json.encode(wrapped))
assert(map[b.id].y==map[a.id].y+map[a.id].h+S.gap)
local moved=N.localAction(board,hist,S.move(board,a.id,250,100))
local _,positions=S.layout(moved);assert(positions[b.id].x==250 and positions[c.id].x==250 and N.card(moved,b.id).parent==a.id,'Top did not move all')
local middle=N.localAction(moved,hist,S.move(moved,b.id,510,200));local _,p=S.layout(middle)
assert(N.card(middle,a.id).parent=='' and N.card(middle,b.id).parent=='' and N.card(middle,c.id).parent==b.id and p[b.id].heading and not p[c.id].heading,'Middle did not detach tail')
local bottom=N.localAction(middle,hist,S.move(middle,c.id,50,300));assert(N.card(bottom,c.id).parent=='')
local target=S.target(bottom,S.layout(bottom),{id=c.id,x=p[b.id].x,y=p[b.id].y+p[b.id].h+S.gap})
assert(target and target.card.id==b.id,'Magnetic target missing')
local joined=N.localAction(bottom,hist,S.move(bottom,c.id,target.x,target.y,b.id,target.dock));assert(N.card(joined,c.id).parent==b.id)
local undone=N.localAction(joined,hist,{action='undo'});assert(N.card(undone,c.id).parent=='','Stack undo failed')
local left=N.newCard('Links',a.id);left.dock='left'
local right=N.newCard('Rechts',a.id);right.dock='right'
local branch=N.empty();branch.cards={N.copy(a),N.copy(b),left,right};N.validate(branch)
local _,branchMap=S.layout(branch)
assert(branchMap[left.id].x+branchMap[left.id].w<branchMap[a.id].x and branchMap[right.id].x>branchMap[a.id].x+branchMap[a.id].w,'Side branches overlap their parent')
assert(S.occupied(branch,right).left and not S.occupied(branch,right).right,'Child side facing its parent was not marked occupied')
assert(not pcall(S.move,branch,b.id,0,0,right.id,'left'),'Move accepted an occupied parent-facing side')
assert(#S.tail(branch,a.id)==4,'Moving a parent must carry every side branch')
local detached=N.localAction(branch,{undo={},redo={}},S.move(branch,left.id,700,100))
assert(N.card(detached,left.id).parent=='' and N.card(detached,right.id).parent==a.id,'Detaching one side changed another branch')
local _,detachedMap=S.layout(detached);assert(detachedMap[left.id].x==700,'Detached branch did not keep its drop position')
assert(not pcall(N.validate,{format=7,revision=0,cards={a,b,N.newCard('Doppelt',a.id)},trash={},authors={}}),'Duplicate lower slot was accepted')
local conflict=N.copy(moved);conflict.revision=conflict.revision+1;N.card(conflict,c.id).versions.parent=conflict.revision
assert(not pcall(N.localAction,conflict,{undo={},redo={}},S.move(moved,b.id,200,200)),'Stale tail topology accepted')
local old=N.copy(board);old.format=1;old.cards[3].parent=a.id
local migrated=N.validate(old);assert(migrated.format==8 and migrated.cards[3].parent==b.id and old.format==1 and old.cards[3].parent==a.id,'Old branching notes were not safely migrated')
local previous=N.copy(board);previous.format=2
for _,item in ipairs(previous.cards) do item.dock=nil;item.versions.dock=nil end
local upgraded=N.validate(previous)
assert(upgraded.format==8 and upgraded.cards[2].dock=='below' and previous.format==2 and previous.cards[2].dock==nil,'Format-2 notes were not safely upgraded')
assert(S.checks({text='a\nb\nc',checks='101'},'a\nnew\nb\nc')=='1001','List insertion moved checks to wrong row')
assert(S.checks({text='a\nb\nc',checks='101'},'a\nc')=='11')
local im=Image(3,2,ColorMode.RGB);im:drawPixel(1,1,app.pixelColor.rgba(12,34,56,78))
local image=I.pack(im);assert(I.unpack(image):getPixel(1,1)==im:getPixel(1,1),'RGBA reference changed')
local gray=Image(2,2,ColorMode.GRAY);gray:drawPixel(0,0,app.pixelColor.graya(89,120));local rgb=I.unpack(I.pack(gray));assert(app.pixelColor.rgbaR(rgb:getPixel(0,0))==89)
local large=Image(1000,800,ColorMode.RGB);local packed=I.pack(large);assert(packed.width==512 and packed.height==409)
local ref=N.newCard('','',300,20);ref.kind='image';ref.image=image;ref.color='#D6E4F4'
local list=N.newCard('','',20,200);list.kind='list';list.text='Farbe: Blau\nLocken\nLänge';list.checks='100'
migrated.cards[#migrated.cards+1]=ref;migrated.cards[#migrated.cards+1]=list
local sprite=Sprite(8,8,ColorMode.RGB);N.write(sprite,migrated)
local path=root..'/test-results/notes-stack-roundtrip.aseprite';sprite:saveAs(path);sprite:close();sprite=app.open(path)
assert(N.equal(N.read(sprite),migrated),'Elements/images did not survive Save As/reopen')
local ui=UI.new(function() end,function() return false end,function(fn) fn() end);local state=ui:state(sprite)
ui:prepare(state)
-- Real native graphics, not a mock: schema, alpha, scaled type and geometry.
local preview=Image(680,500,ColorMode.RGB);ui:paint(state,{context=preview.context})
preview:saveAs(root..'/test-results/notes-stack-preview.png')
local png=root..'/test-results/notes-reference.png';im:saveAs(png)
local active=app.sprite;assert(N.equal(I.load(png),image) and app.sprite==active,'Import changed active image or pixels')
for _,ext in ipairs({'jpg','webp','gif','bmp'}) do
  local fixture=root..'/test-results/notes-reference.'..ext;im:saveAs(fixture)
  local loaded=I.load(fixture);assert(loaded.width==3 and loaded.height==2 and app.sprite==active,'Reference format failed: '..ext)
end
assert(F.paper('#000000').red>=178 and F.paper('#5E3A79').blue>=178,'Legacy colors make lettering illegible')
sprite:close()
print('PASS magnetic top/middle/bottom, snap, titles, undo, stale guard, migration, check remapping, reference pixels, native persistence and rendering')
io.stdout:flush();app.exit()
