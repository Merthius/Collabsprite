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
assert(S.rowPosition(map[c.id],1)==30 and S.rowPosition(map[c.id],2)==30,'List is not left aligned')
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
assert(B.visualScale(.45)>=.89,'Overview typography shrank below readability threshold')
local overview,overviewMap=B.display(boxes,.45,24,56)
assert(overviewMap[a.id].w>S.width*.45 and overviewMap[b.id].y>=overviewMap[a.id].y+overviewMap[a.id].h,'Overview boxes or stack overlap')
local lifted=S.layout(board,nil,{id=b.id,x=780,y=672,moved=true})
local dock=B.target(board,lifted,{id=b.id,x=780,y=672},.45,24,56)
assert(dock and dock.card.id==c.id,'Overview magnetic target does not match the visible card positions')
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
local copied=B.copyTail(board,a.id)
local pastedOp,pastedCards=B.paste(board,copied,300,60)
assert(#pastedCards==2 and pastedCards[2].parent==pastedCards[1].id and pastedCards[1].text=='Besen','Stack copy lost properties')
local pasted=N.localAction(board,history,pastedOp);N.validate(pasted)
assert(#pasted.cards==5 and pasted.cards[4].id~=a.id,'Paste did not create independent IDs')
local reduced=N.localAction(board,history,B.delete(board,{[a.id]=true,[c.id]=true}))
assert(#reduced.cards==1 and reduced.cards[1].id==b.id and b.parent==a.id and reduced.cards[1].parent=='','Multi-delete must retain and reparent unselected child')
local restored=N.localAction(reduced,history,{action='undo'});assert(#restored.cards==3,'Multi-delete personal undo failed')
assert(not pcall(B.paste,board,'{"collabsprite":"idea-board-elements-v1","elements":[{"parent":1}]}',0,0),'Invalid clipboard cycle accepted')
local UI=dofile(root..'/extension/notes-ui.lua')
local sprite=Sprite(8,8,ColorMode.RGB);N.write(sprite,board)
local ui=UI.new(function() end,function() return false end,function(fn) fn() end)
local state=ui:state(sprite);ui:prepare(state)
local preview=Image(700,430,ColorMode.RGB);ui:paint(state,{context=preview.context});ui:fit(state)
ui:paint(state,{context=preview.context})
local _,view=B.display(S.layout(state.board),state.zoom,state.ox,state.oy)
local x1,y1=view[a.id].x-5,view[a.id].y-5
local x2=view[a.id].x+view[a.id].w+5;local y2=view[b.id].y+view[b.id].h+5
ui:pointerDown(state,{button=MouseButton.LEFT,x=x1,y=y1})
ui:pointerMove(state,{x=x2,y=y2});ui:pointerUp(state)
assert(state.selection[a.id] and state.selection[b.id] and not state.selection[c.id],'Canvas marquee failed')
ui:paint(state,{context=preview.context})
local dragX,dragY=view[a.id].x+2,view[a.id].y+2
local dragId,dragHit=ui:hit(state,dragX,dragY);assert(dragId==a.id and dragHit.kind=='drag','Marquee item is not draggable')
ui:pointerDown(state,{button=MouseButton.LEFT,x=dragX,y=dragY})
ui:pointerMove(state,{x=dragX+60,y=dragY+20});ui:pointerUp(state)
local _,after=S.layout(state.board);assert(after[a.id].x>0 and after[b.id].x==after[a.id].x,'Selected group did not move')
ui:paint(state,{context=preview.context})
local tool,fit
for _,h in ipairs(state.hits) do if h.kind=='tool' and h.extra.index==1 then tool=h elseif h.kind=='fit' then fit=h end end
assert(tool and fit,'Toolbar/fit hit targets absent')
ui:pointerDown(state,{button=MouseButton.LEFT,x=fit.r.x+10,y=fit.r.y+10});assert(state.zoom<1,'Fit button did not adapt zoom')
ui:pointerDown(state,{button=MouseButton.LEFT,x=tool.r.x+10,y=tool.r.y+10})
assert(#state.board.cards==4 and state.inline and state.inline.id==state.board.cards[4].id,'Toolbar did not create an editable text box')
ui:finishInline(state);sprite:close()
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
fakeClipboard.content={text=copied}
pasteUi:paste(ps,200,130)
assert(#ps.board.cards==4 and ps.board.cards[4].parent==ps.board.cards[3].id,'Copied stack paste failed')
pasteSprite:close()
print('PASS zoom-to-all, compact left-aligned boxes, marquee/group drag, atomic multi-delete, clipboard paste and toolbar')
io.stdout:flush();app.exit()
