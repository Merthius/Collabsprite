local root=assert(app.params.root)
local N=dofile(root..'/extension/notes.lua')
local T=dofile(root..'/extension/notes-input.lua')
local dialogs,controls=0,{}
local env=setmetatable({Dialog=function(spec)
  dialogs=dialogs+1;local form={data={},spec=spec,sizeHint={width=720,height=470},bounds=Rectangle(0,0,720,470)}
  return setmetatable(form,{__index=function(_,method) return function(self,item)
    if method=='close' then if spec.onclose then spec.onclose() end;return self end
    if item and item.id then controls[item.id]=item end
    return self
  end end})
end},{__index=_G})
local UI=assert(loadfile(root..'/extension/notes-ui.lua','t',env))()
local sprite=Sprite(8,8,ColorMode.RGB)
local ui=UI.new(function() end,function() return false end,function(fn) fn() end)
ui:show(sprite);local s=ui:state(sprite)
assert(controls.board and not controls.search and not controls.undo,'Canvas contains old controls')
local function key(code,text,options)
  local ev=options or {};ev.code=code;ev.key=text or '';ev.stopPropagation=function() ev.stopped=true end
  ui:inlineKey(s,ev);assert(ev.stopped,'Notiztasten ändern Bild')
end
ui:add(s,'text');assert(dialogs==1 and s.inline.value=='','Creation opened popup or nonempty element')
key('Unidentified','Haare');key('Enter');key('Unidentified','Blau');key('Enter','',{ctrlKey=true})
local card=s.board.cards[1];assert(card.text=='Haare\nBlau' and not s.inline)
ui:edit(s,card.id);key('KeyA','',{ctrlKey=true});key('Unidentified','Härtegrad');assert(ui:canLeave(s) and N.read(sprite).cards[1].text=='Härtegrad')
ui:edit(s,card.id);key('Unidentified','!');s.dialog:close();assert(not s.inline and s.board.cards[1].text=='Härtegrad!')
ui:show(sprite);ui:add(s,'list','check',{x=30,y=200});key('Unidentified','Erste');key('Enter');key('Unidentified','Zweite');ui:finishInline(s)
local list=s.board.cards[2];ui:toggle(s,list.id,2);assert(s.board.cards[2].checks=='01')
assert(dialogs==2,'Text/list editing opened popups')
local image=Image(660,410,ColorMode.RGB);ui:paint(s,{context=image.context})
local hit;for _,h in ipairs(s.hits) do if h.kind=='text' and h.id==card.id then hit=h end end
ui:pointerDown(s,{x=hit.r.x+5,y=hit.r.y+5,button=MouseButton.LEFT});assert(s.drag and not s.inline,'Single click must select/drag')
ui:pointerUp(s);assert(type(controls.board.ondblclick)=='function','Native double-click event is not wired')
controls.board.ondblclick({x=hit.r.x+5,y=hit.r.y+5});assert(s.inline.id==card.id)
ui:paint(s,{context=image.context});assert(s.inline.draw);ui:finishInline(s)
local stopped=false;controls.board.onkeydown{code='KeyB',stopPropagation=function() stopped=true end};assert(stopped)
local buffer=T.new('ä🙂');T.key(buffer,{code='Backspace'},'text',{});assert(buffer.value=='ä');T.key(buffer,{code='KeyZ',ctrlKey=true},'text',{});assert(buffer.value=='ä🙂')
local clipboard={text='A\r\nB'};T.key(buffer,{code='KeyA',ctrlKey=true},'text',clipboard);T.key(buffer,{code='KeyV',ctrlKey=true},'text',clipboard);assert(buffer.value=='A\nB')
clipboard.text=string.rep('ü',2049);assert(T.key(buffer,{code='KeyV',ctrlKey=true},'text',clipboard) and buffer.value=='A\nB')
-- Real ACK/state ordering, continued typing, lease and stale-draft protection.
local peer={sprite=sprite,connected=true,author='guest',meta={notes=N.copy(s.board)},noteLocks={}}
function peer:noteAction(op) assert(not self.notePending);self.notePending=op end
function peer:noteLock(id,field,release) self.noteLocks=release and {} or {{id=id,field=field,author=self.author,name='Gast'}} end
local shared=UI.new(function() return peer end,function() return true end,function(fn) fn() end)
shared:attach(peer);shared:show(sprite);local state=shared:state(sprite);local history={undo={},redo={}}
local function ack(ok)
  local op=assert(peer.notePending);peer.notePending=nil;if ok then peer.meta.notes=N.localAction(peer.meta.notes,history,op) end
  peer.onNotes{type='noteAck',ok=ok,message=not ok and 'Konflikt' or nil};return function() peer.onNotes{type='notes'} end
end
shared:add(state,'text');assert(not state.inline);local broadcast=ack(true);assert(not state.inline);broadcast();assert(state.inline)
local id=state.inline.id;state.inline.value='Haare';state.inline.dirty=true;shared:finishInline(state)
state.inline.value='Haare blau';ack(true)();assert(state.inline and state.inline.commitRequested and state.inline.dirty)
shared:finishInline(state);ack(true)();assert(not state.inline and N.card(state.board,id).text=='Haare blau')
shared:edit(state,id);local draft=state.inline;draft.value='Rot';draft.dirty=true
local remote=N.card(peer.meta.notes,id);peer.meta.notes=N.localAction(peer.meta.notes,history,{action='patch',patches={N.patch(remote,'text','Schwarz')}});peer.onNotes{type='notes'}
shared:finishInline(state);assert(state.inline==draft and draft.error and not peer.notePending and draft.value=='Rot')
shared:endInline(state,draft);shared:edit(state,id);draft=state.inline;draft.value='Lock test';draft.dirty=true
peer.noteLocks={{id=id,field='text',author='host',name='Host'}};shared:finishInline(state);assert(draft.error and not peer.notePending)
peer.connected=false;shared:finishInline(state);assert(draft.value=='Lock test' and state.inline==draft and not peer.notePending)
sprite:close();print('PASS empty canvas, direct creation/editing, checklist, UTF-8, keyboard isolation, close/save, ACK ordering, in-flight typing, conflicts, leases and disconnect drafts')
io.stdout:flush();app.exit()
