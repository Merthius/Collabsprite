-- Real native dialogs with inert diagnostics/client. No network or installation.
local root=assert(app.params.root)
local launch
launch=Timer{interval=0.5,ontick=function()
  launch:stop()
  local callbacks={}
  local env=setmetatable({dofile=function(path)
    if path:match('diagnostics%.lua$') then return {new=function() return {log=function() end,memoryTail=function() return {'UI preview · no network'} end} end} end
    return dofile(path)
  end},{__index=_G})
  assert(loadfile(root..'/extension/main.lua','t',env))()
  local plugin={path=root..'/extension',version='0.10.1',preferences={},newMenuGroup=function() end,
    newCommand=function(_,spec) callbacks[spec.id]=spec.onclick end}
  env.init(plugin)
  local menu=Dialog{title='Collabsprite · UI-Test'}
  for _,entry in ipairs({{'PixelKollabMultiplayer','Sitzung'},{'CollabspriteInfo','Info'},{'CollabspriteDebugConsole','Diagnose'}}) do
    local id,label=entry[1],entry[2]
    -- Command identity must match main.lua; no commands are fired blindly.
    if callbacks[id] then menu:button{text=label,onclick=callbacks[id]} end
  end
  menu:button{text='Update-Ansicht',onclick=function()
    local U=dofile(root..'/extension/update-ui.lua').new{safely=function(fn) fn() end,log=function() end}
    U.phase='current';U.detail='Du hast die neueste Version (0.10.1).';U:show()
  end}
  menu:button{text='Schließen'}
  dofile(root..'/extension/ui-layout.lua').show(menu)
  print('UI preview ready · UI scale '..app.uiScale..' · window '..app.window.width..'x'..app.window.height)
  io.stdout:flush()
end};launch:start()
