-- Native layout review with deterministic transport; no host/network or user art.
local root=assert(app.params.root)
local callbacks,client,notify
callbacks={}
local realApp=app
local start
start=Timer{interval=0.4,ontick=function()
  start:stop()
  local env=setmetatable({
    io={open=function() return {read=function() return 'READY 8766' end,write=function() end,close=function() end} end},
    os=setmetatable({execute=function() return true end,remove=function() end},{__index=os}),
    dofile=function(path)
      if path:match('diagnostics%.lua$') then return {new=function() return {log=function() end} end} end
      if path:match('notes%-ui%.lua$') then return {new=function() return {states={},attach=function() end,tick=function() end,close=function() end,show=function() app.tip('Ideenwand-Schaltfläche erreicht',3) end} end} end
      if path:match('client%.lua$') then return {blockGuestSave=function() end,new=function(n)
        notify=n;client={tick=function() end,send=function() end,
          host=function(self,sprite) self.sprite=sprite;self.isHost=true;self.connected=true;self.members={{},{}};notify(self) end,
          disconnect=function(self) self.connected=false;self.status='Nicht verbunden';notify(self) end,
          requestLeave=function(self,fn) self:disconnect();if fn then fn() end end}
        return client
      end} end
      return dofile(path)
    end}, {__index=_G})
  assert(loadfile(root..'/extension/main.lua','t',env))()
  env.init{path=root..'/extension',version='0.13.0',preferences={name='Mert'},
    newMenuSeparator=function() end,newMenuGroup=function() end,
    newCommand=function(_,spec) callbacks[spec.id]=spec.onclick end}
  Sprite(32,32,ColorMode.RGB).filename='Collabsprite UI-Test.aseprite'
  callbacks.PixelKollabMultiplayer()
  print('SESSION_UI_READY scale='..realApp.uiScale);io.stdout:flush()
end};start:start()
