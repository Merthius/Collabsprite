-- Disposable native UI test. The real worker can fetch the public release;
-- the native installer still asks the person at the computer to confirm.
local root=assert(app.params.root)
local path=assert(app.params.extension)
local Update=dofile(root..'/extension/update-ui.lua')
local busy=false
local function safely(fn)
  if busy then return end
  busy=true
  local ok,err=pcall(fn)
  busy=false
  if not ok then app.alert(tostring(err)) end
end
local updater=Update.new{path=path,version=app.params.version or '0.8.0',decode=dofile(root..'/extension/json.lua').decode,
  blocked=function() end,safely=safely,log=function() end}
local timer=Timer{interval=0.1,ontick=function() safely(function() updater:tick() end) end}
timer:start()
if app.params.prepared then
  -- Explicit test fixture only; production reaches this after worker validation.
  updater.packagePath=app.params.prepared;updater.targetVersion=app.params.target or '0.8.1'
  updater.phase='verifying';updater.detail='Geprüftes Testpaket · separate Aseprite-Testkopie'
  updater:show()
  updater.dialog:modify{id='retry',text='Installer testen',visible=true}
else
  safely(function() updater:start() end)
end
