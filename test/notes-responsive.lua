-- Regression for the real controller's non-reentrant callback guard.
local root=assert(app.params.root)
local N=dofile(root..'/extension/notes.lua')
local UI=dofile(root..'/extension/notes-ui.lua')
local V=dofile(root..'/extension/notes-paper-view.lua')
local P=dofile(root..'/extension/notes-paper.lua')
local I=dofile(root..'/extension/notes-image.lua')
local J=dofile(root..'/extension/jobs.lua')
local Client=dofile(root..'/extension/client.lua')
local sprite=Sprite(16,16,ColorMode.RGB)
local busy=false
local function safe(fn)
  if busy then return end
  busy=true;local ok,error=pcall(fn);busy=false;assert(ok,error)
end
local ui=UI.new(function() end,function() return false end,safe)
local s=ui:state(sprite)
ui:add(s,'paper',nil,{x=10,y=40});local paper=s.board.cards[1]
V.open(ui,s,paper.id);s.width=280;s.height=420
ui:paint(s,{context=Image(280,420,ColorMode.RGB).context})
local pv=s.paper;local r=pv.paperRect
ui:run(function() ui:pointerDown(s,{button=MouseButton.LEFT,x=r.x+r.w/2,y=r.y+r.h/2,pressure=1}) end)
ui:run(function() ui:pointerUp(s) end)
assert(not pv.dirty and not pv.sending,'Callback guard discarded the sketch commit')
local count=#app.sprites
local png=root..'/test-results/responsive-import.png'
local jpg=root..'/test-results/responsive-import.jpg'
local source=Image(64,32,ColorMode.RGB);source:clear(app.pixelColor.rgba(190,60,110,255));source:saveAs(png);source:saveAs(jpg)
local received
ui.files={start=function() end,read=function() local event=received;received=nil;return event end}
s.dialog={repaint=function() end};ui:import(s)
received={id=N.uid(),status='ok',paths={png,jpg}}
-- Main's timer holds busy=true, but internal polling must not reacquire it.
busy=true;for _=1,6 do ui:tick() end;busy=false
assert(#s.board.cards==1 and not s.picker and not pv.dirty,'Import skipped or created invisible cards outside the sketch')
assert(app.pixelColor.rgbaA(pv.image:getPixel(500,500))==255,'PNG/JPG never reached the sketch canvas')
assert(app.sprite==sprite and #app.sprites==count,'Import leaked or activated a temporary document')
ui:run(function() V.close(ui,s) end)
assert(not s.paper and s.board.cards[1].kind=='image' and s.board.cards[1].image.width==1000,'Checkmark failed to preserve the full-size raster image')
local first=s.board.cards[1]
ui:add(s,'paper',nil,{x=240,y=40});local second=s.board.cards[2]
ui:placeOnPaper(s,first.id,second.id)
assert(P.unpack(N.card(s.board,second.id).image):getPixel(500,500)==P.source(sprite,first):getPixel(500,500),'Finalized image cannot be drawn onto another sheet')
V.open(ui,s,second.id);pv=s.paper
pv.image:drawPixel(700,800,app.pixelColor.rgba(20,50,80,255));pv.dirty=true;pv.previewRevision=99
busy=true;local leave=ui:canLeave(s);busy=false
assert(leave and not s.paper and not pv.dirty,'Closing requires an unreachable manual sketch-save button')
local path=root..'/test-results/responsive-roundtrip.aseprite'
sprite:saveAs(path);local reopened=app.open(path)
assert(N.read(reopened).format==9 and N.read(reopened).cards[2].kind=='image','Finished images lost after save/reopen')
assert(P.source(reopened,N.read(reopened).cards[2]):getPixel(700,800)==app.pixelColor.rgba(20,50,80,255),'Final pixel lost during persistence')
reopened:close();app.sprite=sprite
-- Dirty foreign-version drafts are preserved as extra images, not overwritten.
ui:add(s,'paper',nil,{x=300,y=200});local concurrent=s.board.cards[3]
V.open(ui,s,concurrent.id);local draft=s.paper
draft.image:drawPixel(99,88,app.pixelColor.rgba(1,2,3,255));draft.dirty=true
ui:action(s,{action='patch',patches={N.patch(concurrent,'image',P.blank())}})
V.close(ui,s)
assert(#s.board.cards==4 and N.card(s.board,concurrent.id).kind=='paper' and s.board.cards[4].kind=='image','Foreign edit was overwritten or draft blocked closing')
assert(P.source(sprite,s.board.cards[4]):getPixel(99,88)==app.pixelColor.rgba(1,2,3,255),'Concurrent local draft was lost')
-- Deleting someone else's sheet must not erase their already open local draft.
ui:add(s,'paper',nil,{x=400,y=300});local deleted=s.board.cards[5]
V.open(ui,s,deleted.id);draft=s.paper
draft.image:drawPixel(11,22,app.pixelColor.rgba(5,6,7,255));draft.dirty=true
ui:action(s,{action='patch',patches={{id=deleted.id,expected=deleted,value=false}}})
assert(s.paper==draft and s.paperDrafts[deleted.id]==draft,'Deleted remote sheet erased the local draft')
V.close(ui,s)
assert(#s.board.cards==5 and s.board.cards[5].kind=='image' and P.source(sprite,s.board.cards[5]):getPixel(11,22)==app.pixelColor.rgba(5,6,7,255),'Deleted sheet draft was not preserved as a separate image')
-- Permission/constructor failures must never leave a false connecting state.
local actual=WebSocket;WebSocket=function() error('permission denied') end
local c=Client.new();assert(not pcall(function() c:connect('ws://127.0.0.1:1',{}) end))
WebSocket=actual
assert(not c.connected and not c.connecting and c.closed,'Denied socket still displays Disconnect')
local host=Client.new()
host:host(sprite,'Preparation test',18766,true)
assert(host.preparing and not host.connecting,'Host capture did not defer work')
app.transaction(function() sprite:newLayer() end)
assert(host.preparing.changed,'Source edit was ignored during preparation')
host:tick()
assert(host.closed and not host.preparing and not host.connected,'Changed host source was submitted as a mixed snapshot')
-- Dense processing yields back to the UI and preserves every byte.
local dense=Image(1000,1000,ColorMode.RGB)
dense.bytes=string.rep(string.char(7,11,19,255)..string.char(23,29,31,255),500000)
local pack=J.new(function() return P.pack(dense) end);local turns=0
repeat J.step(pack);turns=turns+1 until pack.done
assert(not pack.error and turns>3,'Dense sheet was not processed cooperatively')
local unpack=J.new(function() return P.unpack(pack.value) end)
repeat J.step(unpack) until unpack.done
assert(not unpack.error and unpack.value.bytes==dense.bytes,'Cooperative image decoding changed pixels')
print(string.format('RESPONSIVE pack turns=%d max CPU slice=%.3f s',turns,pack.elapsed));io.stdout:flush()
-- Use the real asynchronous UI path, including loading and thumbnail scheduling.
local async=UI.new(function() end,function() return false end,safe);async.async=true
local state=async:state(sprite)
assert(state.loading and #state.board.cards==0,'Large saved board was loaded on the caller thread')
for _=1,1000 do async:stepJobs(state);if not state.loading and #(state.jobs or {})==0 then break end end
assert(not state.loading and #state.board.cards==5,'Background board load never completed')
state.dialog={repaint=function() end};async:importFiles(state,{png},{x=10,y=300})
assert(state.importing and #state.board.cards==5,'Import blocked the UI instead of scheduling work')
for _=1,1000 do async:stepJobs(state);if not state.importing and #(state.jobs or {})==0 then break end end
assert(not state.importing and #state.board.cards==6,'Asynchronous import never committed')
-- Native metadata writes stay atomic, but preparation happens before the transaction.
local savedCount=#state.board.cards
async:add(state,'paper',nil,{x=10,y=600})
assert(state.localPending and #state.board.cards==savedCount,'Asynchronous card creation blocks or mutates early')
for _=1,1000 do async:stepJobs(state);if not state.localPending and #(state.jobs or {})==0 then break end end
assert(#state.board.cards==savedCount+1 and not state.localPending,'Prepared metadata never committed')
local last=state.board.cards[#state.board.cards];V.open(async,state,last.id)
for _=1,1000 do async:stepJobs(state);if state.paper then break end end
local pending=state.paper;pending.image:drawPixel(25,50,app.pixelColor.rgba(90,60,40,255));pending.dirty=true
assert(not async:canLeave(state),'Async sketch should wait for metadata confirmation')
for _=1,1000 do async:stepJobs(state);if not pending.dirty and not pending.sending and not state.localPending then break end end
assert(async:canLeave(state) and not state.paper and N.card(state.board,last.id).kind=='image','Async finalization never releases the native close barrier')
local function drain()
  for _=1,2000 do async:stepJobs(state);if #(state.jobs or {})==0 then return end end
  error('Background tasks never finish')
end
-- A later stroke must not alter the image belonging to an earlier mouse-up.
async:add(state,'paper',nil,{x=500,y=600});drain()
local successive=state.board.cards[#state.board.cards]
V.open(async,state,successive.id);drain()
local mutable=state.paper
local firstColor=app.pixelColor.rgba(120,40,10,255)
local laterColor=app.pixelColor.rgba(30,80,170,255)
mutable.image:drawPixel(123,234,firstColor);mutable.dirty=true;mutable.previewRevision=1
V.commit(async,state)
mutable.image:drawPixel(123,234,laterColor);mutable.previewRevision=2
drain()
assert(P.source(sprite,N.card(state.board,successive.id)):getPixel(123,234)==firstColor,'A yielded commit captured an incomplete later stroke')
assert(mutable.dirty and mutable.image:getPixel(123,234)==laterColor,'Pending next stroke was lost')
V.close(async,state);drain()
assert(N.card(state.board,successive.id).kind=='image' and P.source(sprite,N.card(state.board,successive.id)):getPixel(123,234)==laterColor,'Later stroke was not finalized')
-- A remote deletion while loading an image must not crash or resurrect a sheet.
async:add(state,'paper',nil,{x=700,y=600});drain()
local target=state.board.cards[#state.board.cards]
V.open(async,state,target.id);drain()
local completionErrors={};async.log=function(event) if event=='notes completion error' then completionErrors[#completionErrors+1]=event end end
async:importFiles(state,{png},nil,nil,nil,target.id)
state.board=N.localAction(state.board,state.history,{action='patch',patches={{id=target.id,expected=target,value=false}}},'Peer')
N.write(sprite,state.board);state.raw=sprite.properties(N.key).board
drain()
assert(not state.importing and not N.card(state.board,target.id) and #completionErrors==0,'Import into a removed sheet crashed or resurrected it')
os.remove(png);os.remove(jpg);sprite:close()
print('PASS guarded sketch commit, PNG/JPG import, checkmark, auto-close, conflicts and responsive jobs');io.stdout:flush();app.exit()
