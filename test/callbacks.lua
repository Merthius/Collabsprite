-- Run with Aseprite --batch. Model a nested UI dispatch during a file
-- permission dialog without granting permissions or touching user settings.
local root=assert(app.params.root)
local callbacks,controls,events,clock,tick,opens,hostCalls={}, {}, {}, 1000, nil, 0, 0
local fileReply='READY 18765'
local fileError=false
local fakeSession
local fakeDialog={data={name='Test'}}
setmetatable(fakeDialog,{__index=function(_,key)
  return function(self,item)
    if item and item.id then
      controls[item.id]=controls[item.id] or {}
      for k,v in pairs(item) do controls[item.id][k]=v end
    end
    return self
  end
end})
local fakeApp={isUIAvailable=true,version='test',sprite={},sprites={},
  fs={joinPath=function(a,b) return a..'/'..b end},
  events={on=function(_,event,callback) events[event]=callback;return callback end,off=function() end},
  alert=function() end,tip=function() end}
local env=setmetatable({app=fakeApp,
  os={getenv=function() return 'test-temp' end,time=function() return clock end,execute=function() return true end,remove=function() end},
  io={open=function()
    opens=opens+1
    assert(opens<5,'Nested permission callback recursed')
    tick() -- Aseprite dispatches another timer while asking for access.
    if fileError then error('Permission denied') end
    return {read=function() return fileReply end,close=function() end}
  end},
  Dialog=function() return fakeDialog end,
  Timer=function(item) tick=item.ontick;return {start=function() end,stop=function() end} end,
  dofile=function(path)
    if path:find('diagnostics.lua',1,true) then return {new=function() return {log=function() end} end} end
    if path:find('json.lua',1,true) then return {decode=function() return {} end} end
    return {new=function(notify,logger)
      assert(type(logger)=='function','Session diagnostics not wired')
      fakeSession={host=function(self) hostCalls=hostCalls+1;self.connected=true;notify(self) end,
        tick=function() end,disconnect=function(self) self.connected=false end}
      return fakeSession
    end}
  end}, {__index=_G})
assert(loadfile(root..'/extension/main.lua','t',env))()
env.init{path='test',version='0.6.5',preferences={},newMenuGroup=function() end,
  newCommand=function(_,item) callbacks[item.id]=item.onclick end}
callbacks.PixelKollabMultiplayer()
controls.startHost.onclick()
tick()
assert(opens==1 and hostCalls==1,'Reentrant bootstrap must open once and start one session')
fakeSession.connected=false
controls.startHost.onclick()
fileReply='QUEUED';opens=0;tick()
clock=clock+91;tick()
assert(opens==1,'QUEUED must obey deadline without repeated file reads')
assert(controls.status.text=='Nicht verbunden','Timed out job kept UI busy')
controls.startHost.onclick();opens=0;fileError=true;tick();tick()
assert(opens==1,'Denied file access must terminate the job instead of repeating every tick')
assert(controls.status.text=='Nicht verbunden','Error left callback locked')
env.exit({})

-- The client also protects its own callback if used by another controller.
local Client=dofile(root..'/extension/client.lua')
local count=0
local client=Client.new()
client.receive=function(self) count=count+1;self:tick() end
client.inbox={{type='test'}}
client:tick()
assert(count==1 and not client.ticking,'Client callback is reentrant or stays locked')
client.receive=function() error('synthetic failure') end
client.inbox={{type='test'}};client:tick()
assert(client.closed and not client.ticking,'Client failure did not release callback guard')
print('PASS: nested permission dispatch, QUEUED timeout, denied access, client callback guard')
io.stdout:flush()
app.exit()
