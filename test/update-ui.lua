-- Deterministic controller tests; no network, permissions, or real installation.
local root=assert(app.params.root)
local source=root..'/extension/update-ui.lua'
local realDecode=dofile(root..'/extension/json.lua').decode
local reply,manifest,inventory,now,installs,launches,blocked,failInstall='', '', '', 1000,0,0,nil,false
local controls,dlg={}
local updater
local fakeApp={fs={joinPath=function(a,b) return a..'/'..b end,filePath=app.fs.filePath},alert=function() end,command={Options=function(params)
  assert(updater.phase=='installing' and updater.busy,'No installation status')
  assert(params.installExtension=='C:/Downloads/Collabsprite-v0.8.1.aseprite-extension','Wrong installer path')
  installs=installs+1
  local count=installs;updater:tick();assert(installs==count,'Recursive installation')
  if failInstall then error('test install failure') end
  if manifest=='INSTALL' then
    updater:close();assert(updater.dialog,'Self-unload closed progress dialog')
    manifest='{"name":"pixelkollab-native","version":"0.8.1"}'
    inventory='{"installedFiles":["package.json","main.lua"]}'
  end
end}}
local env=setmetatable({app=fakeApp,Dialog=function(spec)
  controls={};dlg={sizeHint={width=300,height=200},bounds=Rectangle(0,0,300,200)}
  return setmetatable(dlg,{__index=function(_,key) return function(self,item)
    if key=='close' then if spec.onclose then spec.onclose() end;return end
    if item and item.id then controls[item.id]=controls[item.id] or {};for k,v in pairs(item) do controls[item.id][k]=v end end
    return self
  end end})
end,os={getenv=function() return 'test-temp' end,time=function() return now end,remove=function() end,
  execute=function() launches=launches+1;return true end},io={open=function(path)
    local text=path:match('/package.json$') and manifest or path:match('/__info.json$') and inventory or reply
    return {read=function() return text end,close=function() end}
  end}},{__index=_G})
local Update=assert(loadfile(source,'t',env))()
local function fresh()
  reply='QUEUED';manifest='';inventory='';installs=0;launches=0;blocked=nil;failInstall=false
  updater=Update.new{path='extension',version='0.8.0',decode=realDecode,safely=function(fn) fn() end,
    log=function() end,blocked=function() return blocked end}
  return updater
end
local downloaded='DOWNLOADED v0.8.1|C:/Downloads/Collabsprite-v0.8.1.aseprite-extension'
fresh():start();updater:start();assert(launches==1,'Duplicate worker')
for _,phase in ipairs({'checking','downloading','verifying','preparing'}) do reply='PROGRESS '..phase;updater:tick();assert(updater.busy) end
manifest='INSTALL';reply=downloaded;assert(updater:tick());assert(installs==1 and updater.phase=='done' and not updater.busy)
local detail=(controls.detail1.text or '')..(controls.detail2.text or '')
assert(detail:find('installiert',1,true) and detail:find('neu starten',1,true))
fresh():start();reply=downloaded;updater:tick();assert(updater.phase=='cancelled' and controls.retry.visible,'Cancelled installer reported success')
manifest='INSTALL';controls.retry.onclick();assert(updater.phase=='done','Retry failed')
fresh():start();manifest='{"name":"pixelkollab-native","version":"0.8.1"}';reply=downloaded;updater:tick()
assert(updater.phase=='cancelled','Partial install without inventory reported success')
fresh():start();failInstall=true;reply=downloaded;updater:tick();assert(updater.phase=='error' and not updater.busy)
fresh():start();dlg:close();reply=downloaded;updater:tick();assert(installs==0,'Closed progress still installed')
fresh();blocked='Active session';updater:start();assert(launches==0)
fresh():start();blocked='Session started during download';reply=downloaded;updater:tick();assert(installs==0)
fresh():start();reply='CURRENT 0.8.0';updater:tick();assert(updater.phase=='current' and installs==0)
fresh():start();reply='ERROR No internet';updater:tick();assert(updater.phase=='error')
fresh():start();now=now+181;updater:tick();assert(updater.phase=='error' and installs==0)
fresh():start();reply='unexpected';updater:tick();assert(updater.phase=='error')
print('PASS: update progress, native handoff, cancellation/retry, self-unload, verified success, busy/timeout/error guards')
io.stdout:flush();app.exit()
