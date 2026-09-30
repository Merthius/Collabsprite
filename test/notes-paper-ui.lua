local root=assert(app.params.root)
local N=dofile(root..'/extension/notes.lua')
local UI=dofile(root..'/extension/notes-ui.lua')
local I=dofile(root..'/extension/notes-image.lua')
local P=dofile(root..'/extension/notes-paper.lua')
local V=dofile(root..'/extension/notes-paper-view.lua')
local sprite=Sprite(16,16,ColorMode.RGB)
local ui=UI.new(function() end,function() return false end,function(fn) fn() end)
local s=ui:state(sprite);s.width=700;s.height=440
local canvas=Image(700,440,ColorMode.RGB)
ui:paint(s,{context=canvas.context})
local narrowCanvas=Image(170,350,ColorMode.RGB)
ui:paint(s,{context=narrowCanvas.context})
local _,tagHit=ui:hit(s,18,13)
local _,undoHit=ui:hit(s,123,43)
local _,listHit=ui:hit(s,81,13)
assert(tagHit and tagHit.kind=='tool' and tagHit.extra.index==5 and
  undoHit and undoHit.kind=='tool' and undoHit.extra.history==1 and
  listHit and listHit.kind=='tool' and listHit.extra.index==2,
  'Animation, list or Undo button is overlapped at narrow 400% layout')
local tinyCanvas=Image(145,350,ColorMode.RGB)
ui:paint(s,{context=tinyCanvas.context})
local _,tinyList=ui:hit(s,68,13)
local _,tinyUndo=ui:hit(s,97,43)
assert(tinyList and tinyList.kind=='tool' and tinyList.extra.index==2 and
  tinyUndo and tinyUndo.kind=='tool' and tinyUndo.extra.history==1,
  'Small monitor toolbar did not separate list and history rows')
ui:paint(s,{context=canvas.context})
local listTool,paperTool
for _,hit in ipairs(s.hits) do
  if hit.kind=='tool' and hit.extra.index==2 then listTool=hit end
  if hit.kind=='tool' and hit.extra.index==4 then paperTool=hit end
end
assert(listTool and paperTool,'Compact list or sketch-sheet tool missing')
ui:pointerDown(s,{button=MouseButton.LEFT,x=listTool.r.x+3,y=listTool.r.y+3});ui:pointerUp(s)
ui:paint(s,{context=canvas.context})
local styles={}
for _,hit in ipairs(s.hits) do if hit.kind=='listChoice' then styles[hit.extra]=true end end
assert(styles.check and styles.bullet and styles.number,'Combined list dropdown omits a style')
ui:pointerDown(s,{button=MouseButton.LEFT,x=paperTool.r.x+3,y=paperTool.r.y+3});ui:pointerUp(s)
assert(s.placingPaper and not s.listMenu,'Paper tool did not attach a sheet to pointer')
ui:paint(s,{context=canvas.context})
ui:pointerDown(s,{button=MouseButton.LEFT,x=360,y=210});ui:pointerUp(s)
assert(#s.board.cards==1 and s.board.cards[1].kind=='paper' and not s.placingPaper,'Blank click did not place a sketch-sheet')
local paper=s.board.cards[1]
local source=Image(16,16,ColorMode.RGB)
source:drawPixel(0,0,app.pixelColor.rgba(255,33,66,255))
local imageCard=N.newCard('','',300,300);imageCard.kind='image';imageCard.image=I.pack(source)
ui:action(s,{action='patch',patches={{id=imageCard.id,expected=false,value=imageCard}}})
ui:placeOnPaper(s,imageCard.id,paper.id)
local result=P.unpack(N.card(s.board,paper.id).image)
assert(result:getPixel(0,0)==app.pixelColor.rgba(255,33,66,255),'Image drag target did not import as editable sheet pixels')
ui:paperPreview(s,paper.id)
assert(s.paper and not s.dialog,'Sketch-sheet should open inside ideas board, not another dialog')
local sheetCanvas=Image(280,420,ColorMode.RGB)
ui:paint(s,{context=sheetCanvas.context})
if app.params.capture then sheetCanvas:saveAs(app.params.capture) end
local draft=s.paperDrafts[paper.id]
assert(draft.paperRect and draft.paperRect.x>=62 and draft.paperRect.x+draft.paperRect.w<=280 and
  draft.paperRect.y>=24 and draft.paperRect.y+draft.paperRect.h<=420 and
  draft.paperRect.w==draft.paperRect.h and draft.image.width==1000 and draft.image.height==1000,
  'Square sketch overlaps sidebar or is clipped')
local narrowPaper=Image(145,350,ColorMode.RGB)
ui:paint(s,{context=narrowPaper.context})
assert(draft.paperRect.x>=62 and draft.paperRect.x+draft.paperRect.w<=145 and
  draft.paperRect.w==draft.paperRect.h,'Sidebar or square page is clipped in a narrow window')
ui:paint(s,{context=sheetCanvas.context})
local fixedX,fixedY,fixedW=draft.paperRect.x,draft.paperRect.y,draft.paperRect.w
V.wheel(ui,s,{x=150,y=200,deltaY=-5})
ui:paint(s,{context=sheetCanvas.context})
assert(draft.paperRect.x==fixedX and draft.paperRect.y==fixedY and draft.paperRect.w==fixedW,
  'Sketch-sheet zoomed when scrolling over the page')
assert(not draft.pressure and not draft.stabilizer,'Pressure or stabilization was unexpectedly enabled')
ui:pointerDown(s,{button=MouseButton.LEFT,x=8,y=146})
assert(draft.pressure,'Stiftdruck checkbox is not reachable')
ui:pointerDown(s,{button=MouseButton.LEFT,x=8,y=168})
assert(draft.stabilizer,'Stabilization checkbox is not reachable')
ui:pointerDown(s,{button=MouseButton.LEFT,x=40,y=197})
assert(draft.strength>0,'Stabilization slider is not reachable')
ui:pointerUp(s)
ui:pointerDown(s,{button=MouseButton.LEFT,x=40,y=103})
assert(draft.size>8,'Brush-size slider is not reachable')
ui:pointerUp(s)
ui:pointerDown(s,{button=MouseButton.LEFT,x=10,y=121})
for _,digit in ipairs({'9','9','9'}) do V.key(ui,s,{code='Digit9',key=digit}) end
V.key(ui,s,{code='Enter'})
assert(draft.size==20,'Typed pen size was not limited to 20 pixels')
ui:pointerDown(s,{button=MouseButton.LEFT,x=10,y=121})
V.key(ui,s,{code='Digit0',key='0'});V.key(ui,s,{code='Enter'})
assert(draft.size==5,'Typed pen size was not limited to at least 5 pixels')
ui:pointerDown(s,{button=MouseButton.LEFT,x=10,y=121})
for _,digit in ipairs({'1','2'}) do V.key(ui,s,{code='Digit'..digit,key=digit}) end
V.key(ui,s,{code='Enter'})
assert(draft.size==12,'Typed brush size did not replace the previous size')
ui:pointerDown(s,{button=MouseButton.LEFT,x=41,y=40})
assert(draft.tool=='eraser','Eraser button is not reachable')
ui:pointerDown(s,{button=MouseButton.LEFT,x=10,y=121})
for _,digit in ipairs({'9','9','9'}) do V.key(ui,s,{code='Digit9',key=digit}) end
V.key(ui,s,{code='Enter'});assert(draft.size==100,'Eraser exceeds 100 px')
ui:pointerDown(s,{button=MouseButton.LEFT,x=10,y=121})
V.key(ui,s,{code='Digit0',key='0'});V.key(ui,s,{code='Enter'})
assert(draft.size==5,'Eraser allows less than 5 px')
ui:pointerDown(s,{button=MouseButton.LEFT,x=7,y=103});ui:pointerUp(s)
assert(draft.size==5,'Eraser slider minimum is not 5 px')
ui:pointerDown(s,{button=MouseButton.LEFT,x=50,y=103});ui:pointerUp(s)
assert(draft.size==100,'Eraser slider maximum is not 100 px')
local previousStrength=draft.strength
ui:pointerDown(s,{button=MouseButton.LEFT,x=8,y=168})
ui:pointerDown(s,{button=MouseButton.LEFT,x=25,y=197})
assert(draft.stabilizer and draft.strength==previousStrength,
  'Eraser changed the pen-only stabilization settings')
draft.image:drawPixel(500,500,app.pixelColor.rgba(255,33,66,255))
draft.drawing={x=0,y=0}
V.move(ui,s,{x=draft.paperRect.x+math.floor(500*draft.paperScale),
  y=draft.paperRect.y+math.floor(500*draft.paperScale),pressure=1})
assert(app.pixelColor.rgbaA(draft.image:getPixel(500,500))==0,
  'Eraser stroke was stabilized instead of reaching the pointer')
draft.drawing=nil
ui:pointerDown(s,{button=MouseButton.LEFT,x=13,y=40})
assert(draft.tool=='pen' and draft.stabilizer,'Pen stabilization was not restored')
ui:pointerDown(s,{button=MouseButton.LEFT,x=12,y=275})
assert(draft.colorIndex==1,'Visible palette swatch is not selectable')
local px,py=draft.paperRect.x+draft.paperRect.w/2,draft.paperRect.y+draft.paperRect.h/2
ui:pointerDown(s,{button=MouseButton.LEFT,x=px,y=py,pressure=0.5})
assert(draft.dirty,'Pen does not paint through the ideas-board sketch mode')
ui:pointerUp(s)
assert(not draft.dirty,'Completed sketch stroke was not saved')
assert(#draft.undo==1 and app.pixelColor.rgbaA(draft.image:getPixel(500,500))>0,
  'Sketch stroke was not added to paper history')
ui:pointerDown(s,{button=MouseButton.LEFT,x=15,y=66})
assert(app.pixelColor.rgbaA(draft.image:getPixel(500,500))==0 and #draft.redo==1,
  'Paper Undo did not revert its own stroke')
ui:pointerDown(s,{button=MouseButton.LEFT,x=42,y=66})
assert(app.pixelColor.rgbaA(draft.image:getPixel(500,500))>0,
  'Paper Redo did not restore its own stroke')
assert(s.images[paper.id] and N.equal(s.images[paper.id].data,N.card(s.board,paper.id).image),
  'Saved sketch preview cache has stale source data')
local preview=ui:paperThumbnail(s,N.card(s.board,paper.id),124)
assert(app.pixelColor.rgbaA(preview:getPixel(62,62))>0,
  'Fresh sketch is invisible on the ideas-board preview')
local sparse=Image(1000,1000,ColorMode.RGB)
sparse:drawPixel(501,503,app.pixelColor.rgba(13,83,217,255))
local tiny=P.thumbnail(sparse)
assert(app.pixelColor.rgbaA(tiny:getPixel(math.floor(501*124/1000),math.floor(503*124/1000)))>0,
  'A single-pixel sketch vanished while shrinking the preview')
local original=P.pack(draft.image)
ui:pointerDown(s,{button=MouseButton.LEFT,x=25,y=234})
assert(draft.image:isEmpty() and not draft.dirty,'Clear-all did not persist a blank sheet')
V.undo(ui,s)
assert(N.equal(P.pack(draft.image),original),'Clear-all is not undoable')
V.redo(ui,s);assert(draft.image:isEmpty(),'Clear-all redo failed')
V.undo(ui,s)
ui:pointerDown(s,{button=MouseButton.LEFT,x=260,y=10})
assert(not s.paper and N.card(s.board,paper.id).kind=='image','Checkmark did not finish the sketch as an image')
assert(N.card(s.board,paper.id).image.width==1000 and P.source(sprite,N.card(s.board,paper.id)):getPixel(500,500)==draft.image:getPixel(500,500),
  'Finalized image lost full-resolution sketch pixels')
local boardCanvas=Image(700,440,ColorMode.RGB)
ui:paint(s,{context=boardCanvas.context})
local paperHit
for _,hit in ipairs(s.hits) do if hit.id==paper.id and hit.kind=='drag' then paperHit=hit end end
assert(paperHit,'Sketch card disappeared after returning to the ideas board')
local rendered=boardCanvas:getPixel(paperHit.r.x+70,paperHit.r.y+76)
assert(rendered==draft.palette[1].color.rgbaPixel,
  'Saved sketch mark was not rendered on the ideas-board card')
if app.params.captureBoard then boardCanvas:saveAs(app.params.captureBoard) end
N.validate(s.board)
sprite:close()
print('PASS native list dropdown, paper placement, image import and integrated sketch sheet')
io.stdout:flush();app.exit()
