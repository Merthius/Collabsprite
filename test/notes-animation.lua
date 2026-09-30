local root=assert(app.params.root)
local N=dofile(root..'/extension/notes.lua')
local A=dofile(root..'/extension/notes-animation.lua')
local B=dofile(root..'/extension/notes-board.lua')
local S=dofile(root..'/extension/notes-stack.lua')
local UI=dofile(root..'/extension/notes-ui.lua')
local sprite=Sprite(16,16,ColorMode.RGB)
sprite:newEmptyFrame(2);sprite:newEmptyFrame(3)
for frame,color in ipairs({app.pixelColor.rgba(255,70,70,255),app.pixelColor.rgba(70,120,255,255),app.pixelColor.rgba(90,215,130,255)}) do
  local image=Image(16,16,ColorMode.RGB);image:drawPixel(0,0,color)
  sprite:newCel(sprite.layers[1],frame,image,Point(0,0))
end
local tag=sprite:newTag(1,3);tag.name='Hexe läuft'
local other=sprite:newTag(2,3);other.name='Hexe springt'
local found=A.tags(sprite);assert(#found==2 and found[1].name=='Hexe läuft' and found[1].last==3)
local thumb=A.thumbnail(sprite,1,160,160);assert(thumb and thumb.width==160 and thumb.height==160 and thumb:getPixel(9,9)==app.pixelColor.rgba(255,70,70,255))
assert(thumb:getPixel(10,10)~=thumb:getPixel(9,9),'Upscaled thumbnail blurred adjacent source pixels')
assert(A.thumbnail(sprite,2,32,32):getPixel(0,0)==app.pixelColor.rgba(70,120,255,255),'Frame thumbnail did not render the selected frame')
assert(A.next(found[1],3)==1 and A.next(found[1],1)==2,'Forward tag playback does not loop')
tag.aniDir=AniDir.REVERSE;assert(A.next(found[1],1)==3 and A.next(found[1],3)==2,'Reverse tag playback is wrong')
tag.aniDir=AniDir.PING_PONG
local bounced,direction=A.next(found[1],3,1);assert(bounced==2 and direction==-1,'Ping-pong tag playback did not bounce')
tag.aniDir=AniDir.FORWARD
local ui=UI.new(function() end,function() return false end,function(fn) fn() end)
local s=ui:state(sprite);s.width=700;s.height=430
local canvas=Image(700,430,ColorMode.RGB)
ui:paint(s,{context=canvas.context})
local button;for _,h in ipairs(s.hits) do if h.kind=='tool' and h.extra.index==5 then button=h end end
assert(button,'Tag button missing')
ui:pointerDown(s,{button=MouseButton.LEFT,x=button.r.x+4,y=button.r.y+4});ui:pointerUp(s)
ui:paint(s,{context=canvas.context})
local first;for _,h in ipairs(s.hits) do if h.kind=='tagItem' then first=h;break end end
assert(first and first.extra.name=='Hexe läuft','Tag picker has no named preview')
canvas:saveAs(root..'/test-results/notes-animation-picker.png')
ui:pointerDown(s,{button=MouseButton.LEFT,x=first.r.x+5,y=first.r.y+5});ui:pointerUp(s)
local c=s.board.cards[1]
assert(c.kind=='animation' and c.tag=='Hexe läuft' and c.tagStart==1 and c.frame==1 and c.image==false,'Tag click did not create a linked animation')
assert(A.resolve(sprite,c).last==3 and S.layout(s.board)[1].h>=100)
ui:paint(s,{context=canvas.context})
local _,map=B.display(S.layout(s.board),1,s.ox,s.oy)
ui:pointerDown(s,{button=MouseButton.LEFT,x=map[c.id].x+10,y=map[c.id].y+10});ui:pointerUp(s)
assert(s.sheet and s.sheet.index==1,'Animation card did not open the strip')
ui:paint(s,{context=canvas.context})
canvas:saveAs(root..'/test-results/notes-animation-sheet.png')
local second;for _,h in ipairs(s.hits) do if h.kind=='frame' and h.extra.index==2 then second=h end end
assert(second,'Horizontal strip omitted the second frame')
ui:pointerDown(s,{button=MouseButton.LEFT,x=second.r.x+5,y=second.r.y+5});ui:pointerUp(s)
assert(s.sheet.index==2,'Click did not select a frame')
ui:paint(s,{context=canvas.context})
local center;for _,h in ipairs(s.hits) do if h.kind=='frame' and h.extra.index==2 then center=h;break end end
local selectedX=center.r.x
ui:pointerDown(s,{button=MouseButton.LEFT,x=center.r.x+5,y=center.r.y+5})
ui:pointerMove(s,{x=center.r.x-51,y=center.r.y+5});ui:pointerUp(s)
assert(s.sheet.index==3,'Horizontal drag did not advance the filmstrip')
ui:paint(s,{context=canvas.context})
local newCenter;for _,h in ipairs(s.hits) do if h.kind=='frame' and h.extra.index==3 then newCenter=h;break end end
assert(newCenter and newCenter.r.x==selectedX,'Selected frame moved away from its fixed anchor')
ui:sheetStep(s,-1);assert(s.sheet.index==2,'Arrow step did not move left')
ui:sheetStep(s,-20);assert(s.sheet.index==1,'Frame selection escaped the tag range')
ui:sheetStep(s,1);ui:commitSheet(s)
assert(not s.sheet and N.card(s.board,c.id).frame==2,'Enter-style frame confirmation was not persisted')
ui:openSheet(s,c.id);assert(s.sheet.index==2,'Filmstrip did not reopen at committed frame')
ui:paint(s,{context=canvas.context})
local selected;for _,h in ipairs(s.hits) do if h.kind=='frame' and h.extra.index==2 then selected=h end end
ui:pointerDown(s,{button=MouseButton.LEFT,x=selected.r.x+5,y=selected.r.y+5});ui:pointerUp(s)
assert(not s.sheet and N.card(s.board,c.id).frame==2,'Second click on selected frame did not confirm it')
ui:paint(s,{context=canvas.context})
local play;for _,h in ipairs(s.hits) do if h.kind=='play' and h.id==c.id then play=h end end
assert(play,'Animation card is missing its play button')
ui:pointerDown(s,{button=MouseButton.LEFT,x=play.r.x+3,y=play.r.y+3});ui:pointerUp(s)
assert(s.playing and s.playing.id==c.id,'Play button did not start preview')
ui:paint(s,{context=canvas.context})
local slow;for _,h in ipairs(s.hits) do if h.kind=='slow' and h.id==c.id then slow=h end end
assert(slow and slow.r.x<play.r.x,'Slow-motion control is not beside playback')
ui:pointerDown(s,{button=MouseButton.LEFT,x=slow.r.x+3,y=slow.r.y+3});ui:pointerUp(s)
assert(s.slow[c.id],'Slow-motion button did not activate')
local beforeFrame=s.playing.frame
s.dialog={repaint=function() end}
for _=1,4 do ui:tick() end
s.dialog=nil
assert(s.playing.frame==beforeFrame,'Slow-motion preview advanced too fast')
ui:paint(s,{context=canvas.context})
for _,h in ipairs(s.hits) do if h.kind=='slow' and h.id==c.id then slow=h end end
ui:pointerDown(s,{button=MouseButton.LEFT,x=slow.r.x+3,y=slow.r.y+3});ui:pointerUp(s)
assert(not s.slow[c.id],'Slow-motion button did not turn off')
s.dialog={repaint=function() end}
for _=1,4 do ui:tick() end
s.dialog=nil
assert(s.playing.frame~=beforeFrame,'Timer did not advance the animation preview')
ui:paint(s,{context=canvas.context})
for _,h in ipairs(s.hits) do if h.kind=='play' and h.id==c.id then play=h end end
ui:pointerDown(s,{button=MouseButton.LEFT,x=play.r.x+3,y=play.r.y+3});ui:pointerUp(s)
assert(not s.playing,'Play button did not stop preview')
ui:pointerDown(s,{button=MouseButton.LEFT,x=button.r.x+4,y=button.r.y+4});ui:pointerUp(s)
ui:paint(s,{context=canvas.context})
local dragged;for _,h in ipairs(s.hits) do if h.kind=='tagItem' and h.extra.name=='Hexe springt' then dragged=h end end
assert(dragged,'Second animation was not listed')
ui:pointerDown(s,{button=MouseButton.LEFT,x=dragged.r.x+8,y=dragged.r.y+8})
ui:pointerMove(s,{x=500,y=270});ui:pointerUp(s)
assert(#s.board.cards==2 and s.board.cards[2].kind=='animation' and s.board.cards[2].tag=='Hexe springt','Tag drag-and-drop did not create an animation')
assert(s.board.cards[2].frame==2,'A tag beginning on frame 2 used tag-relative frame 1')
local copied=B.copyTail(s.board,c.id);local op,created=B.paste(s.board,copied,280,70)
assert(created[1].kind=='animation' and created[1].tag==c.tag and created[1].tagStart==1 and created[1].frame==2,'Clipboard lost animation selection')
ui:action(s,op)
local saved=root..'/test-results/notes-animation-roundtrip.aseprite'
sprite:saveAs(saved);sprite:close()
local reopened=app.open(saved)
local board=N.read(reopened);assert(board.format==8 and #board.cards==3 and board.cards[1].frame==2 and A.resolve(reopened,board.cards[1]).last==3,'Animation link and selected frame did not survive .aseprite save')
local old=N.copy(board);old.format=4;old.cards[1].frame=nil;old.cards[1].versions.frame=nil
local migrated=N.validate(old);assert(migrated.format==8 and migrated.cards[1].frame==1 and board.cards[1].frame==2,'Format-4 animation did not inherit its tag start frame')
reopened:close()
print('PASS native tag picker, thumbnail, filmstrip selection, clipboard and .aseprite roundtrip')
io.stdout:flush();app.exit()
