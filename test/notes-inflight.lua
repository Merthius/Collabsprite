-- Two local strokes during a delayed first acknowledgement, then finish.
-- Real native images and board transactions; only the delivery clock is held.
local root=assert(app.params.root)
local N=dofile(root..'/extension/notes.lua')
local UI=dofile(root..'/extension/notes-ui.lua')
local P=dofile(root..'/extension/notes-paper.lua')
local V=dofile(root..'/extension/notes-paper-view.lua')
local sprite=Sprite(16,16,ColorMode.RGB)
local ui=UI.new(function() end,function() return false end,function(fn) fn() end)
local s=ui:state(sprite)
local card=N.newCard('','',20,20);card.kind='paper';card.image=P.blank()
ui:action(s,{action='patch',patches={{id=card.id,expected=false,value=card}}})
V.open(ui,s,card.id)
ui:paint(s,{context=Image(400,440,ColorMode.RGB).context})
local pv=s.paper
local originalAction=ui.action
local deliveries={}
ui.action=function(self,state,op,callback)
  deliveries[#deliveries+1]=function() originalAction(self,state,op,callback) end
end
local function stroke(fraction)
  local r=pv.paperRect
  V.down(ui,s,{button=MouseButton.LEFT,x=r.x+r.w*fraction,y=r.y+r.h*fraction,pressure=1})
  assert(pv.drawing,'Drawing stalled while an older stroke was in flight')
  V.up(ui,s)
end
stroke(0.25);assert(pv.sending and #deliveries==1)
stroke(0.75);assert(#deliveries==1,'Second stroke sent before first confirmation')
V.close(ui,s);assert(s.paper==pv,'Sheet closed before acknowledgement')
table.remove(deliveries,1)();assert(s.paper==pv and #deliveries==1,'Latest drawing was dropped during finish')
table.remove(deliveries,1)()
assert(not s.paper and not s.paperDrafts[card.id],'Finished sheet did not close')
local finished=N.card(s.board,card.id)
assert(finished.kind=='image')
local image=P.unpack(finished.image)
assert(app.pixelColor.rgbaA(image:getPixel(250,250))>0 and app.pixelColor.rgbaA(image:getPixel(750,750))>0,
  'One of the two strokes was lost')
-- A completed follow-up is queued without requiring the finish checkmark.
card=N.newCard('','',220,20);card.kind='paper';card.image=P.blank()
originalAction(ui,s,{action='patch',patches={{id=card.id,expected=false,value=card}}})
V.open(ui,s,card.id);ui:paint(s,{context=Image(400,440,ColorMode.RGB).context});pv=s.paper
stroke(0.25);stroke(0.75)
table.remove(deliveries,1)();assert(#deliveries==1,'Completed follow-up stroke was not queued')
table.remove(deliveries,1)();assert(not pv.dirty and not pv.sending)
-- An acknowledgement in the middle of a new stroke must not submit it early.
stroke(0.5)
local r=pv.paperRect
V.down(ui,s,{button=MouseButton.LEFT,x=r.x+r.w*0.9,y=r.y+r.h*0.9,pressure=1})
table.remove(deliveries,1)()
assert(pv.drawing and #deliveries==0 and pv.dirty,'Incomplete stroke was submitted at acknowledgement')
V.up(ui,s);assert(#deliveries==1,'Mouse-up did not submit the final stroke')
table.remove(deliveries,1)()
image=P.unpack(N.card(s.board,card.id).image)
for _,point in ipairs({250,500,750,900}) do
  assert(app.pixelColor.rgbaA(image:getPixel(point,point))>0,'Queued drawing lost a stroke')
end
sprite:close();print('PASS: drawing continues during delayed acknowledgement; finish retains both strokes')
io.stdout:flush();app.exit()
