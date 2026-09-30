local root=assert(app.params.root)
local N=dofile(root..'/extension/notes.lua')
local S=dofile(root..'/extension/notes-stack.lua')
local B=dofile(root..'/extension/notes-board.lua')
local board=N.empty()
local a=N.newCard('Waffe','',0,0);a.text='Besen'
local b=N.newCard('','',0,0);b.parent=a.id;b.text='Farbe: Blau'
local c=N.newCard('Aussehen','',780,550);c.kind='list';c.text='Haare\nKleid';c.checks='10'
board.cards={a,b,c};N.validate(board)
local boxes,map=S.layout(board)
assert(S.width<244 and map[a.id].w==S.width,'Boxes did not get more compact')
assert(S.rowPosition(map[c.id],1)==22 and S.rowPosition(map[c.id],2)==22,'List is not left aligned')
local zoom,ox,oy=B.fit(board,700,430)
local fitted,fitMap=B.display(boxes,zoom,ox,oy)
local left,right,top,bottom=1e6,-1e6,1e6,-1e6
for _,v in ipairs(fitted) do
  left=math.min(left,v.x);right=math.max(right,v.x+v.w)
  top=math.min(top,v.y);bottom=math.max(bottom,v.y+v.h)
  assert(v.x>=17 and v.x+v.w<=683,'Horizontal fit clips box')
  assert(v.y>=45 and v.y+v.h<=395,'Vertical fit clips box')
end
assert(zoom<1 and zoom>0 and math.abs((left+right)/2-350)<3,'Fit is not centered')
assert(B.visualScale(.45)>=.8,'Overview typography shrank below readability threshold')
for _,pair in ipairs({{.65,.56},{.56,.45},{.45,.4},{.75,.65},{1,.75}}) do
  local higher,lower=pair[1],pair[2]
  assert(B.visualScale(higher)>B.visualScale(lower),'Zooming out enlarged the cards: '..higher..' -> '..lower)
  local highView=B.display(boxes,higher,24,56)
  local lowView=B.display(boxes,lower,24,56)
  assert(highView[1].w>lowView[1].w,'Displayed card enlarged while zooming out')
end
local overview,overviewMap=B.display(boxes,.45,24,56)
assert(overviewMap[a.id].w>S.width*.45 and overviewMap[b.id].y>=overviewMap[a.id].y+overviewMap[a.id].h,'Overview boxes or stack overlap')
local targetView=map[c.id]
local drag={id=b.id,x=targetView.x,
  y=targetView.y+targetView.h+S.gap,moved=true}
local lifted=S.layout(board,nil,drag)
local dock=B.target(board,lifted,drag,1,24,56)
assert(dock and dock.card.id==c.id and dock.dock=='below','Magnetic target does not match the visible card positions')
local far=N.copy(board);N.card(far,c.id).x=10000;N.card(far,c.id).y=10000
local tiny=B.fit(far,700,430);assert(tiny<0.1,'Fit must go below the former 25% floor')
local selected=B.selectDisplay(fitted,fitMap[a.id].x-5,fitMap[a.id].y-5,fitMap[a.id].x+fitMap[a.id].w+5,fitMap[b.id].y+fitMap[b.id].h+5)
assert(selected[a.id] and selected[b.id] and not selected[c.id],'Marquee selected wrong boxes')
local history={undo={},redo={}}
local moved=N.localAction(board,history,B.move(board,{[a.id]=true,[c.id]=true},40,30))
local _,nextMap=S.layout(moved)
assert(nextMap[a.id].x==40 and nextMap[b.id].x==40 and nextMap[c.id].x==820,'Atomic multi-move failed')
local undone=N.localAction(moved,history,{action='undo'});local _,back=S.layout(undone)
assert(back[a.id].x==0 and back[c.id].x==780,'Multi-move own undo failed')
local nearby=N.copy(board)
local d=N.newCard('Nähe','',810,555);nearby.cards[#nearby.cards+1]=d
local layoutOperation=B.sort(nearby)
assert(#layoutOperation.patches>0,'Sortieren did not change scattered stacks')
local sorted=N.localAction(nearby,history,layoutOperation)
local _,sortedMap=S.layout(sorted)
local bounds={minx=1e6,miny=1e6,maxx=-1e6,maxy=-1e6}
for _,box in ipairs(S.layout(sorted)) do
  bounds.minx=math.min(bounds.minx,box.x);bounds.miny=math.min(bounds.miny,box.y)
  bounds.maxx=math.max(bounds.maxx,box.x+box.w);bounds.maxy=math.max(bounds.maxy,box.y+box.h)
end
local ratio=(bounds.maxx-bounds.minx)/(bounds.maxy-bounds.miny)
assert(ratio>0.55 and ratio<1.8,'Sortieren did not make an approximately square cluster')
assert(math.abs(sortedMap[c.id].x-sortedMap[d.id].x)+math.abs(sortedMap[c.id].y-sortedMap[d.id].y)<350,'Nearby stacks were separated')
local unsorted=N.localAction(sorted,history,{action='undo'})
assert(N.card(unsorted,c.id).x==780 and N.card(unsorted,d.id).x==810,'Sortieren own undo failed')
local crowded=N.empty()
for i=1,12 do
  local card=N.newCard('Gruppe '..i,'',((i*419)%1700)-800,((i*277)%1100)-500)
  card.text=string.rep('Titel ',i%3+1)
  crowded.cards[#crowded.cards+1]=card
end
local packed=N.localAction(crowded,{undo={},redo={}},B.sort(crowded))
local compact=S.layout(packed)
for i=1,#compact do for j=i+1,#compact do
  local one,two=compact[i],compact[j]
  assert(one.x+one.w+S.gap<=two.x or two.x+two.w+S.gap<=one.x or
    one.y+one.h+S.gap<=two.y or two.y+two.h+S.gap<=one.y,'Sortieren overlapped separate stacks')
end end
local copied=B.copyTail(board,a.id)
local pastedOp,pastedCards=B.paste(board,copied,300,60)
assert(#pastedCards==2 and pastedCards[2].parent==pastedCards[1].id and pastedCards[1].text=='Besen','Stack copy lost properties')
local pasted=N.localAction(board,history,pastedOp);N.validate(pasted)
assert(#pasted.cards==5 and pasted.cards[4].id~=a.id,'Paste did not create independent IDs')
local side=N.newCard('Seitlich',a.id);side.dock='right';board.cards[#board.cards+1]=side;N.validate(board)
local branchCopy=B.copyTail(board,b.id);local _,onlyBelow=B.paste(board,branchCopy,310,90)
assert(#onlyBelow==1 and onlyBelow[1].id~=a.id,'Copy from middle included its parent or siblings')
local allCopy=B.copyTail(board,a.id);local _,allCards=B.paste(board,allCopy,350,90)
assert(#allCards==3 and allCards[3].dock=='right' and allCards[3].parent==allCards[1].id,'Side attachment was lost during copy')
table.remove(board.cards)
local reduced=N.localAction(board,history,B.delete(board,{[a.id]=true,[c.id]=true}))
assert(#reduced.cards==1 and reduced.cards[1].id==b.id and b.parent==a.id and reduced.cards[1].parent=='','Multi-delete must retain and reparent unselected child')
local restored=N.localAction(reduced,history,{action='undo'});assert(#restored.cards==3,'Multi-delete personal undo failed')
assert(not pcall(B.paste,board,'{"collabsprite":"idea-board-elements-v1","elements":[{"parent":1}]}',0,0),'Invalid clipboard cycle accepted')
local UI=dofile(root..'/extension/notes-ui.lua')
local sprite=Sprite(8,8,ColorMode.RGB);N.write(sprite,board)
local promoteTokens={}
local ui=UI.new(function() end,function() return false end,function(fn) fn() end,nil,
  function(token) assert(type(token)=='string' and #token==32);promoteTokens[#promoteTokens+1]=token end)
local state=ui:state(sprite);ui:prepare(state)
local preview=Image(700,430,ColorMode.RGB);ui:paint(state,{context=preview.context});ui:fit(state)
ui:paint(state,{context=preview.context})
local windowHits,animationHits=0,0
for _,target in ipairs(state.hits) do
  if target.kind=='window' or target.kind=='title' then windowHits=windowHits+1 end
  if target.kind=='tool' and target.extra.index==5 then animationHits=animationHits+1 end
end
assert(windowHits==0 and animationHits==1,'Split bar remained or animation tool is missing')
state.dialog={bounds=Rectangle(80,90,500,400),repaint=function() end}
local waitingSession={sprite=sprite,connected=false,connecting=true}
ui.getSession=function() return waitingSession end
ui:tick()
waitingSession.connected=true;waitingSession.connecting=false
ui:tick()
assert(state.dialog.bounds.x==80 and #promoteTokens==0,'Joining must not rearrange the editor or board')
waitingSession.connected=false;ui:tick()
local nextSession={sprite=sprite,connected=true}
ui.getSession=function() return nextSession end
ui:tick()
assert(state.dialog.bounds.x==80 and #promoteTokens==0,'Later sessions must not trigger automatic split')
ui.getSession=function() end
state.dialog=nil
local _,view=B.display(S.layout(state.board),state.zoom,state.ox,state.oy)
local x1,y1=view[a.id].x-5,view[a.id].y-5
local x2=view[a.id].x+view[a.id].w+5;local y2=view[b.id].y+view[b.id].h+5
local oldOx,oldOy=state.ox,state.oy
ui:pointerDown(state,{button=MouseButton.LEFT,x=x1,y=y1})
assert(state.marquee and not state.drag,'Blank left drag should select')
ui:pointerMove(state,{x=x2,y=y2});ui:pointerUp(state)
assert(state.selection[a.id] and state.selection[b.id] and not state.selection[c.id],'Canvas marquee failed')
assert(state.ox==oldOx and state.oy==oldOy,'Left selection moved the board')
state.ox,state.oy=oldOx,oldOy;ui:paint(state,{context=preview.context})
ui:pointerDown(state,{button=MouseButton.RIGHT,x=x1,y=y1})
ui:pointerMove(state,{x=x1+40,y=y1+25});ui:pointerUp(state)
assert(state.ox==oldOx+40 and state.oy==oldOy+25 and not state.menu,'Blank right drag did not pan the wall')
state.ox,state.oy=oldOx,oldOy;ui:paint(state,{context=preview.context})
ui:pointerDown(state,{button=MouseButton.RIGHT,x=x1,y=y1});ui:pointerUp(state)
assert(state.menu and state.menu.items[1].label=='Einfügen','Stationary right click did not open the menu')
state.menu=nil;ui:paint(state,{context=preview.context})
state.selection={[b.id]=true};state.selected=b.id
ui:paint(state,{context=preview.context})
local _,beforeDetach=B.display(S.layout(state.board),state.zoom,state.ox,state.oy)
local bx,by=beforeDetach[b.id].x+beforeDetach[b.id].w/2,beforeDetach[b.id].y+beforeDetach[b.id].h/2
ui:pointerDown(state,{button=MouseButton.LEFT,x=bx,y=by})
ui:pointerMove(state,{x=bx+180,y=by+90})
local _,inFlight=B.display(ui:layout(state),state.zoom,state.ox,state.oy)
assert(inFlight[b.id].x>beforeDetach[b.id].x+100,'Dragging the connected card did not visually detach it')
ui:pointerUp(state)
assert(N.card(state.board,b.id).parent=='','Dropping a connected card on free space did not detach it')
ui:action(state,{action='undo'})
assert(N.card(state.board,b.id).parent==a.id,'Own undo did not restore the connection')
state.selection={[a.id]=true,[b.id]=true};state.selected=a.id
ui:paint(state,{context=preview.context})
local dragX,dragY=view[a.id].x+2,view[a.id].y+2
local dragId,dragHit=ui:hit(state,dragX,dragY);assert(dragId==a.id and dragHit.kind=='drag','Marquee item is not draggable')
ui:pointerDown(state,{button=MouseButton.LEFT,x=dragX,y=dragY})
ui:pointerMove(state,{x=dragX+60,y=dragY+20});ui:pointerUp(state)
local _,after=S.layout(state.board);assert(after[a.id].x>0 and after[b.id].x==after[a.id].x,'Selected group did not move')
ui:paint(state,{context=preview.context})
local _,current=B.display(S.layout(state.board),state.zoom,state.ox,state.oy)
local tx,ty=current[a.id].x+current[a.id].w/2,current[a.id].y+current[a.id].h/2
ui:pointerDown(state,{button=MouseButton.LEFT,x=tx,y=ty})
assert(state.drag and not state.inline,'Clicking inside a card should start dragging, not text editing')
ui:pointerUp(state)
ui:doubleClick(state,{x=tx,y=ty})
assert(state.inline and state.inline.id==a.id,'Double-click did not edit the card')
ui:finishInline(state)
ui:paint(state,{context=preview.context})
local tool
for _,h in ipairs(state.hits) do if h.kind=='tool' and h.extra.index==1 then tool=h end end
assert(tool and state.zoom==1,'Native toolbar or fixed-size view absent')
ui:pointerDown(state,{button=MouseButton.LEFT,x=tool.r.x+10,y=tool.r.y+10})
assert(#state.board.cards==4 and state.inline and state.inline.id==state.board.cards[4].id,'Toolbar did not create an editable text box')
ui:finishInline(state)
ui:paint(state,{context=preview.context})
local _,linked=B.display(S.layout(state.board),state.zoom,state.ox,state.oy)
ui:pointerMove(state,{x=linked[a.id].x+linked[a.id].w/2,y=linked[a.id].y+linked[a.id].h/2})
ui:paint(state,{context=preview.context})
local plus,plusCount
plusCount=0
for _,h in ipairs(state.hits) do if h.kind=='plus' and h.id==a.id then
  if h.extra.dock=='left' then plus=h end
  plusCount=plusCount+1;assert(h.extra.dock~='below','Plus appeared on an occupied side')
end end
assert(plusCount==2 and plus,'Only two unoccupied side buttons should appear')
ui:pointerMove(state,{x=plus.r.x+5,y=plus.r.y+5})
ui:paint(state,{context=preview.context})
local hoveredId,hoveredHit=ui:hit(state,plus.r.x+5,plus.r.y+5)
assert(hoveredId==a.id and hoveredHit.kind=='plus','Plus disappeared when entering its hit area')
ui:pointerDown(state,{button=MouseButton.LEFT,x=plus.r.x+5,y=plus.r.y+5})
assert(state.menu and #state.menu.items==5,'Add button did not open element choices')
state.menu.items[1].fn();state.menu=nil
local added=state.board.cards[#state.board.cards]
assert(added.parent==a.id and added.dock=='left' and N.card(state.board,b.id).parent==a.id,'Add button did not use the free left side')
ui:finishInline(state)
ui:paint(state,{context=preview.context})
assert(not ui:hit(state,650,300),'Test point for empty double-click is occupied')
ui:doubleClick(state,{x=650,y=300})
assert(state.inline and state.inline.id==state.board.cards[#state.board.cards].id,'Empty double-click did not create editable text')
ui:finishInline(state)
local fresh=state.board.cards[#state.board.cards]
ui:paint(state,{context=preview.context})
local _,freshView=B.display(S.layout(state.board),state.zoom,state.ox,state.oy)
ui:pointerMove(state,{x=freshView[fresh.id].x+10,y=freshView[fresh.id].y+10})
ui:paint(state,{context=preview.context})
local freeSides,rightPlus=0,nil
for _,target in ipairs(state.hits) do if target.kind=='plus' and target.id==fresh.id then
  freeSides=freeSides+1;if target.extra.dock=='right' then rightPlus=target end
end end
assert(freeSides==3 and rightPlus,'A free box should expose bottom, left and right plus buttons')
state.hover=nil
ui:pointerMove(state,{x=rightPlus.r.x+20,y=rightPlus.r.y+6})
ui:paint(state,{context=preview.context})
local nearPlus=false;for _,target in ipairs(state.hits) do if target.kind=='plus' and target.id==fresh.id and target.extra.dock=='right' then nearPlus=true end end
assert(nearPlus,'Plus did not appear while the mouse was only near the free side')
ui:pointerMove(state,{x=rightPlus.r.x+5,y=rightPlus.r.y+5})
ui:paint(state,{context=preview.context})
ui:pointerDown(state,{button=MouseButton.LEFT,x=rightPlus.r.x+5,y=rightPlus.r.y+5})
assert(state.menu and #state.menu.items==5,'Right plus did not open element choices')
state.menu.items[1].fn();state.menu=nil
local rightChild=state.board.cards[#state.board.cards]
assert(rightChild.parent==fresh.id and rightChild.dock=='right','Right plus did not attach on the right')
ui:finishInline(state)
ui:paint(state,{context=preview.context})
local _,rightView=B.display(S.layout(state.board),state.zoom,state.ox,state.oy)
ui:pointerMove(state,{x=rightView[rightChild.id].x+rightView[rightChild.id].w/2,y=rightView[rightChild.id].y+rightView[rightChild.id].h/2})
ui:paint(state,{context=preview.context})
local childPlus=0
for _,target in ipairs(state.hits) do if target.kind=='plus' and target.id==rightChild.id then
  childPlus=childPlus+1;assert(target.extra.dock~='left','Plus appeared on the child side occupied by its parent')
end end
assert(childPlus==2,'Right child should have exactly two free plus sides')
ui:menu(state,a.id,20,100)
local copies=0;for _,item in ipairs(state.menu.items) do if item.label and item.label:find('Kopieren',1,true) then copies=copies+1;assert(item.label=='Kopieren') end end
assert(copies==1,'Context menu has more than one copy action')
local original={}
for _,card in ipairs(state.board.cards) do if card.parent=='' then original[card.id]={x=card.x,y=card.y} end end
ui:menu(state,nil,400,300)
assert(#state.menu.items==4 and state.menu.items[2].label=='Sortieren','Empty-space menu lacks sorting/history')
state.menu.items[2].fn();state.menu=nil
local changed=false
for id,position in pairs(original) do local card=N.card(state.board,id);if card.x~=position.x or card.y~=position.y then changed=true end end
assert(changed,'Context Sortieren did not rearrange independent stacks')
ui:paint(state,{context=preview.context})
local redoHit
for _,target in ipairs(state.hits) do if target.kind=='tool' and target.extra.history==2 then redoHit=target end end
assert(redoHit,'Upper-right pixel history island is missing')
ui:menu(state,nil,400,300);state.menu.items[3].fn();state.menu=nil
for id,position in pairs(original) do local card=N.card(state.board,id);assert(card.x==position.x and card.y==position.y,'Context Undo did not restore stack coordinates') end
ui:paint(state,{context=preview.context})
ui:pointerDown(state,{button=MouseButton.LEFT,x=redoHit.r.x+10,y=redoHit.r.y+10});ui:pointerUp(state)
local redone=false
for id,position in pairs(original) do local card=N.card(state.board,id);if card.x~=position.x or card.y~=position.y then redone=true end end
assert(redone,'Upper-right Redo did not reapply sorting')
state.marquee={x1=0,y1=0,x2=0,y2=0,previous={}};state.pointerX=699;state.pointerY=210
local panBefore=state.ox
ui:autoPanMarquee(state)
assert(state.ox==panBefore-12 and state.marquee.x2>0,'Marquee did not pan and extend world selection at the viewport edge')
state.marquee=nil
sprite:close()
-- Exercise the actual paste entry point without touching the user's system clipboard.
local fakeClipboard={content={text='Aus externer App\r\nzweite Zeile'}}
local fakeApp=setmetatable({clipboard=fakeClipboard},{__index=app})
local fakeEnv=setmetatable({app=fakeApp},{__index=_G})
local PasteUI=assert(loadfile(root..'/extension/notes-ui.lua','t',fakeEnv))()
local pasteUi=PasteUI.new(function() end,function() return false end,function(fn) fn() end)
function pasteUi:action(s,op,callback)
  s.board=N.localAction(s.board,s.history,op)
  if callback then callback(true) end
end
local pasteSprite=Sprite(8,8,ColorMode.RGB)
local ps=pasteUi:state(pasteSprite);ps.width=700;ps.height=430
pasteUi:paste(ps,120,100)
assert(#ps.board.cards==1 and ps.board.cards[1].text=='Aus externer App\nzweite Zeile','External text paste failed')
local picture=Image(2,2,ColorMode.RGB);picture:drawPixel(0,0,app.pixelColor.rgba(255,0,0,255))
fakeClipboard.content={image=picture}
pasteUi:paste(ps,160,100)
assert(#ps.board.cards==2 and ps.board.cards[2].kind=='image' and ps.board.cards[2].image.width==2,'Clipboard image paste failed')
pasteUi:refresh(ps)
local popup
local function fakeDialog(options)
  local result={sizeHint={width=220,height=160}}
  function result:canvas(spec) self.canvasSpec=spec;return self end
  function result:show() self.shown=true end
  function result:close() self.closed=true;if options.onclose then options.onclose() end end
  popup=result;return result
end
local PreviewUI=assert(loadfile(root..'/extension/notes-ui.lua','t',setmetatable({Dialog=fakeDialog},{__index=_G})))()
local previewUi=PreviewUI.new(function() end,function() return false end,function(fn) fn() end)
previewUi:preview(ps,ps.board.cards[2].id)
assert(popup.shown and popup.canvasSpec and ps.preview==popup,'Image click did not open an in-app preview')
local viewImage=Image(220,160,ColorMode.RGB)
popup.canvasSpec.onpaint({context=viewImage.context})
assert(ps.previewImage.w==2 and ps.previewImage.h==2,'Preview did not use the stored image pixel dimensions')
popup.canvasSpec.onmousedown({x=0,y=0})
assert(popup.closed and ps.preview==nil,'Clicking outside the image did not close preview')
local called
function pasteUi:preview(_,id) called=id end
local boardPixels=Image(700,430,ColorMode.RGB);pasteUi:paint(ps,{context=boardPixels.context})
local _,imageView=B.display(S.layout(ps.board),ps.zoom,ps.ox,ps.oy)
local imageId=ps.board.cards[2].id
local ix,iy=imageView[imageId].x+8,imageView[imageId].y+8
pasteUi:pointerDown(ps,{button=MouseButton.LEFT,x=ix,y=iy})
pasteUi:pointerUp(ps)
assert(called==imageId,'A single image click did not request the preview')
fakeClipboard.content={text=copied}
pasteUi:paste(ps,200,130)
assert(#ps.board.cards==4 and ps.board.cards[4].parent==ps.board.cards[3].id,'Copied stack paste failed')
local cutId=ps.board.cards[3].id
pasteUi:cut(ps,cutId)
assert(#ps.board.cards==2 and fakeClipboard.text:find('idea-board-elements-v2',1,true),'Cut did not copy the branch before deletion')
fakeClipboard.content={text=fakeClipboard.text}
pasteUi:paste(ps,240,180)
assert(#ps.board.cards==4,'Cut branch could not be pasted back')
local savedClipboard=fakeApp.clipboard
fakeApp.clipboard=setmetatable({},{__newindex=function() error('Zwischenablage gesperrt') end})
assert(not pcall(function() pasteUi:cut(ps,ps.board.cards[1].id) end) and #ps.board.cards==4,'Denied clipboard access deleted an element')
fakeApp.clipboard=savedClipboard
pasteSprite:close()
print('PASS compact board, proximity plus, edge-pan marquee, cut/paste, clipboard and toolbar')
io.stdout:flush();app.exit()
