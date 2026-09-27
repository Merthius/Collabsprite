-- Three real Aseprite WebSockets; only disposable test sprites/files.
local root=assert(app.params.root)
local Client=dofile(root..'/extension/client.lua')
local N=dofile(root..'/extension/notes.lua')
local function log(event,detail) print(event..': '..tostring(detail));io.stdout:flush() end
local a,b,c=Client.new(nil,log),Client.new(nil,log),Client.new(nil,log)
for _,peer in ipairs({a,b,c}) do peer.onNotes=function(m) if m.type=='noteAck' then peer.lastAck=m end end end
local source=Sprite(8,8,ColorMode.RGB)
local idea=N.newCard('Hexe')
local stage,started=0,os.time();local timer;local oldTab;local leaving=false;local dialog;local busy=false
local function card(peer) return peer.meta and peer.meta.notes and N.card(peer.meta.notes,idea.id) end
local function patch(peer,field,value)
  peer:noteAction{action='patch',patches={N.patch(assert(card(peer)),field,value)}}
end
local function finish(result)
  log('RESULT',result);timer:stop()
  if dialog then dialog:close() end
  for _,peer in ipairs({b,c,a}) do peer:disconnect() end
  for _,sprite in ipairs(app.sprites) do sprite:close() end
  app.exit()
end
a:host(source,'Host',tonumber(app.params.port) or 18766)
timer=Timer{interval=0.04,ontick=function()
  if busy then return end;busy=true
  local ok,err=xpcall(function()
    a:tick();if stage~=6 then b:tick() end;c:tick()
    assert(os.time()-started<45,'Timeout stage '..stage)
    assert(not a.closed and (not b.closed or leaving) and not c.closed,'Native client stopped')
    if stage==0 and a.connected then
      b:join(a.invite,'Gast');stage=1
    elseif stage==1 and b.connected and b.noteHistory then
      oldTab=b.sprite;b:noteAction{action='patch',patches={{id=idea.id,expected=false,value=idea}}};stage=2
    elseif stage==2 and card(a) and card(b) and not b.notePending then
      patch(a,'title','Hexe – Entwurf');patch(b,'text','Kleid violett');stage=3
    elseif stage==3 and card(a).text=='Kleid violett' and card(b).title=='Hexe – Entwurf' and not a.notePending and not b.notePending then
      b:noteAction{action='undo'};stage=4
    elseif stage==4 and card(a).text=='' and not b.notePending then
      assert(card(a).title=='Hexe – Entwurf','Note undo erased host title');b:noteAction{action='redo'};stage=5
    elseif stage==5 and card(a).text=='Kleid violett' and not b.notePending then
      patch(b,'color','#5E3A79');stage=6
    elseif stage==6 and card(a).color=='#5E3A79' then
      assert(b.notePending,'Lost acknowledgement test requires pending note')
      b:suspend();b.retryAt=os.time()+1;patch(a,'title','Hexe – gemeinsam');stage=7
    elseif stage==7 and b.connected and not b.notePending and card(b).title=='Hexe – gemeinsam' then
      assert(b.sprite==oldTab and b.noteSeq==5,'Note resume duplicated change or tab')
      assert(N.equal(N.read(a.sprite),N.read(b.sprite)),'Embedded notes differ')
      c:join(a.invite,'Später Gast');stage=9
    elseif stage==9 and c.connected and card(c) then
      assert(card(c).text=='Kleid violett' and card(c).color=='#5E3A79','Late join lost notes')
      b:noteLock(idea.id,'text');stage=10
    elseif stage==10 and #(a.noteLocks or {})>0 then
      patch(a,'text','Must be rejected');stage=11
    elseif stage==11 and not a.notePending then
      assert(a.lastAck.ok==false and card(a).text=='Kleid violett','Lease allowed overwrite')
      leaving=true;b:requestLeave(function() end);stage=12
    elseif stage==12 and b.closed then
      assert(card(a).text=='Kleid violett' and card(c).text=='Kleid violett','Guest departure erased notes')
      assert(N.equal(N.read(a.sprite),a.meta.notes),'Host sprite lost embedded collaborative notes')
      finish('PASS native notes: 3 peers, parallel fields, own undo/redo, lost ack/resume, same tab, embedded notes, late join, leases, departure.')
    end
  end,debug.traceback)
  if not ok then finish('FAIL stage '..stage..': '..tostring(err)) end
  busy=false
end};timer:start()
dialog=Dialog{title='Collabsprite Notiztest'}
dialog:label{text='Drei Verbindungen, Wiederverbindung und gemeinsame Notizen …'}:show{wait=true}
