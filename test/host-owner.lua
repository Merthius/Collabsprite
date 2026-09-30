-- Isolated native Aseprite host. Never opens an existing/user document.
local root=assert(app.params.root)
local result=assert(app.params.result)
local stop=assert(app.params.stop)
local port=assert(tonumber(app.params.port))
local sprite=Sprite(4,4,ColorMode.RGB)
local command='wscript.exe //B //Nologo "'..root..'/Launcher.vbs" Host Test '..port..' "'..result..'" 0'
assert(os.execute(command),'Native host launcher failed')
print('OWNER_READY');io.stdout:flush()
-- Batch mode has no UI/event loop. This short, bounded test waits for the
-- runner's own sentinel; production uses the OS process handle, not polling.
local deadline=os.time()+25
while os.time()<deadline do
  local f=io.open(stop,'r')
  if f then f:close();sprite:close();app.exit();return end
  local nextCheck=os.clock()+0.05
  while os.clock()<nextCheck do end
end
error('Owner runner timed out')
