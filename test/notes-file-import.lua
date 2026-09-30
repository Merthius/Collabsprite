local root=assert(app.params.root)
local N=dofile(root..'/extension/notes.lua')
local P=dofile(root..'/extension/notes-paper.lua')
local UI=dofile(root..'/extension/notes-ui.lua')
local sprite=Sprite(16,16,ColorMode.RGB)
local ui=UI.new(function() end,function() return false end,function(fn) fn() end)
local s=ui:state(sprite);s.width=600;s.height=440
local one=app.fs.joinPath(root,'test-results','import-one.png')
local two=app.fs.joinPath(root,'test-results','import-two.png')
local image=Image(16,16,ColorMode.RGB);image:clear(app.pixelColor.rgba(30,60,120,255));image:saveAs(one)
image:clear(app.pixelColor.rgba(150,40,60,255));image:saveAs(two)
local count=#app.sprites
ui:importFiles(s,{one,two},{x=10,y=40})
assert(#s.board.cards==2 and s.board.cards[2].x>s.board.cards[1].x,'Batch images overlap or are missing')
assert(app.sprite==sprite and #app.sprites==count,'Import changed active document or leaked a tab')
ui:action(s,{action='undo'});assert(#s.board.cards==0,'Batch import is not atomic/undoable')
ui:action(s,{action='redo'});assert(#s.board.cards==2,'Batch import redo lost an image')
local before=N.copy(s.board)
ui:importFiles(s,{one,root..'/test-results/missing.png'})
assert(not s.importing,'Failed image import left the UI permanently busy')
assert(N.equal(before,s.board),'Failed batch changed the board')
local received,started
local fake={start=function(token,mode,board) started={token=token,mode=mode,board=board} end,
  read=function() local event=received;received=nil;return event end}
ui.files=fake;s.dialog={repaint=function() end}
ui:import(s);assert(started.mode=='Pick' and s.picker,'Image button did not open the picker directly')
received={id=N.uid(),status='cancel'};ui:pollFiles(s);assert(not s.picker and #s.board.cards==2,'Cancelling picker changed notes')
received={id=N.uid(),status='ok',paths={one,two},x=.25,y=.5}
ui:pollFiles(s);assert(#s.board.cards==4,'File drop did not import both images')
local last=s.lastFileEvent
received={id=last,status='ok',paths={one},x=.25,y=.5}
ui:pollFiles(s);assert(#s.board.cards==4,'Repeated file event duplicated images')
local c=N.newCard('','',500,400);c.kind='paper';c.image=P.blank()
ui:action(s,{action='patch',patches={{id=c.id,expected=false,value=c}}})
local draft={image=P.unpack(c.image),dirty=true,previewRevision=1,baseVersion=0}
s.paperDrafts[c.id]=draft;draft.image:drawPixel(987,998,app.pixelColor.rgba(6,75,130,255))
local thumb=ui:paperThumbnail(s,N.card(s.board,c.id),62)
assert(thumb:getPixel(61,61)~=app.pixelColor.rgba(255,255,255,255),'Unconfirmed fine sketch is invisible in thumbnail')
draft.image:clear();draft.previewRevision=2
thumb=ui:paperThumbnail(s,N.card(s.board,c.id),62)
assert(thumb:getPixel(61,61)==app.pixelColor.rgba(255,255,255,255),'Thumbnail cache did not update after erasing')
os.remove(one);os.remove(two);sprite:close()
print('PASS atomic multi-image import, drop/picker flow and live sketch thumbnail');io.stdout:flush();app.exit()
