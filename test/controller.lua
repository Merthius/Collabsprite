-- Test main.lua routing, without native dialogs or editing user files.
local root=assert(app.params.root)
local RealClient=dofile(root..'/extension/client.lua')
local callbacks,controls,events,commands={}, {}, {}, {}
local tick,client,notify,closed,continued=nil,nil,nil,0,0
local notesShown,notesTicks,groups=nil,0,{}
local owned={id=1,isValid=true,close=function() closed=closed+1 end}
local other={id=2}
local dlg={data={name='Test',manual='127.0.0.1:8766/12345678/0123456789abcdef0123456789abcdef'},sizeHint={width=300,height=200},bounds=Rectangle(0,0,300,200)}
setmetatable(dlg,{__index=function(_,key) return function(self,item)
  if item and item.id then
    controls[item.id]=controls[item.id] or {}
    for k,v in pairs(item) do controls[item.id][k]=v end
  end
  return self
end end})
local fakeApp={isUIAvailable=true,version='test',sprite=other,sprites={owned,other},
  fs={joinPath=function(a,b) return a..'/'..b end},
  events={on=function(_,name,callback) events[name]=callback;return callback end,off=function() end},
  command={CloseFile=function() continued=continued+1 end,Exit=function() continued=continued+1 end},
  tip=function() end,alert=function() end}
local fakeClient={blockGuestSave=RealClient.blockGuestSave,new=function(n)
  notify=n
  client={pending={},tick=function() end,beforeCommand=function() end,
    send=function(self,message) self.sent=message end,
    restoreDeletion=function(self) self.restored=true end,
    host=function(self) self.sprite=owned;self.isHost=true;self.connected=true;notify(self) end,
    join=function(self) self.sprite=owned;self.isHost=false;self.connected=true;notify(self) end,
    requestLeave=function(self,ready) self.completeLeave=ready end,
    disconnect=function(self) self.connected=false;notify(self) end}
  return client
end}
local env=setmetatable({app=fakeApp,
  Dialog=function() return dlg end,Timer=function(t) tick=t.ontick;return {start=function() end,stop=function() end} end,
  os={time=os.time,getenv=function() return 'test-temp' end,execute=function() return true end,remove=function() end},
  io={open=function() return {read=function() return 'READY 127.0.0.1:8766' end,close=function() end} end},
  dofile=function(path)
    if path:find('ui-layout.lua',1,true) then return dofile(root..'/extension/ui-layout.lua') end
    if path:find('update-ui.lua',1,true) then return {new=function() return {tick=function() end,close=function() end} end} end
    if path:find('client.lua',1,true) then return fakeClient end
    if path:find('json.lua',1,true) then return {decode=function() return {} end} end
    if path:find('notes-ui.lua',1,true) then return {new=function() return {states={},attach=function() end,tick=function() notesTicks=notesTicks+1 end,close=function() end,show=function(_,sprite) notesShown=sprite end} end} end
    return {new=function() return {log=function() end} end}
  end},{__index=_G})
assert(loadfile(root..'/extension/main.lua','t',env))()
env.init{path='test',version='0.8.0',preferences={},newMenuGroup=function(_,item) groups[item.id]=item end,
  newCommand=function(_,item) callbacks[item.id]=item.onclick;commands[item.id]=item end}
assert(groups.CollabspriteMenu.group=='view_new' and commands.CollabspriteNotes.group=='CollabspriteMenu','Notes command missing from View > Collabsprite')
callbacks.CollabspriteNotes();assert(notesShown==other and client==nil,'Notes require a multiplayer session')
tick();assert(notesTicks==1 and client==nil,'Automatic notes polling requires a multiplayer session')
assert(not commands.CollabspriteRestoreDeletion.onenabled(),'Recovery enabled without session')
callbacks.PixelKollabMultiplayer();controls.joinManual.onclick();tick()
client.recovery='test-recovery'
assert(commands.CollabspriteRestoreDeletion.onenabled(),'Recovery missing for connected guest')
callbacks.CollabspriteRestoreDeletion();assert(client.restored,'Recovery menu is not wired')
client.reconnecting=true;client.connected=false;notify(client)
assert(not controls.joinManual.enabled and not controls.startHost.enabled and controls.disconnect.visible,'Reconnect controls allow second session')
client.reconnecting=false;client.connected=true;notify(client)
local function command(name)
  local stopped=false
  events.beforecommand{name=name,params={},stopPropagation=function() stopped=true end}
  return stopped
end
fakeApp.sprite=owned
assert(command('SaveFileAs'),'Connected guest save not blocked')
local recovered={id=3,isValid=true}
client.recoverySprites={recovered};notify(client);fakeApp.sprite=recovered
assert(command('SaveFileAs'),'Conflict draft bypassed guest save guard')
fakeApp.sprite=owned
assert(command('CloseFile'),'CloseFile did not wait for host acknowledgement')
assert(closed==0,'Closed guest before acknowledgement')
client:disconnect();client.completeLeave()
assert(closed==1 and continued==0,'Guest close resumed native Save dialog')
assert(command('SaveFileAs'),'Disconnected guest save not blocked')
fakeApp.sprite={id=owned.id,isValid=true}
assert(command('SaveFileAs'),'Fresh native wrapper bypassed disconnected guest save guard')
fakeApp.sprite=owned
local previousClient=client
controls.startHost.onclick();tick()
assert(client==previousClient,'Guest document can be rehosted to bypass save guard')
fakeApp.sprite=other
assert(not command('SaveFileAs'),'Unrelated local file blocked')
controls.startHost.onclick();tick()
fakeApp.sprite=owned
assert(not command('SaveFileAs'),'Host save blocked')
assert(controls.admission.visible,'Host admission switch missing')
dlg.data.admission=false;controls.admission.onclick()
assert(client.sent.type=='admission' and client.sent.open==false,'Admission switch did not send host command')
assert(command('Exit'),'Exit did not wait for host acknowledgement')
assert(continued==0,'Exit resumed early')
client:disconnect();client.completeLeave()
assert(continued==1 and closed==1,'Host close/save flow replaced instead of resumed')
client.connected=true
assert(command('CloseFile'),'Host CloseFile not intercepted')
fakeApp.sprite=other
client:disconnect();client.completeLeave()
assert(continued==1,'Delayed CloseFile targeted an unrelated newly selected document')
env.exit({})
print('PASS: controller guest save/close, detached role, local document and host close routing')
io.stdout:flush();app.exit()
