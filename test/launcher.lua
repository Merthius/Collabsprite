-- Run in a disposable Aseprite UI process to verify dialog/menu registration.
local root=assert(app.params.root,'root fehlt')
assert(app.isUIAvailable,'UI-Test braucht ein Aseprite-Fenster')
assert(loadfile(root..'/extension/main.lua'))()
local groups,commands={},{}
local plugin={path=root..'/extension',preferences={},
  newMenuGroup=function(_,item) groups[#groups+1]=item end,
  newCommand=function(_,item) commands[#commands+1]=item end}
local ok,err=pcall(function()
  init(plugin)
  assert(#groups==1 and groups[1].title=='Collabsprite')
  assert(#commands==4 and commands[1].group=='CollabspriteMenu' and commands[4].id=='CollabspriteDebugConsole')
  commands[4].onclick()
  commands[1].onclick()
  local switched=false
  for i=1,32 do
    local name,value=debug.getupvalue(commands[1].onclick,i)
    if not name then break end
    if name=='showPane' then
      value('join');value('host')
      switched=true;break
    end
  end
  assert(switched,'Ansicht-Umschaltung nicht gefunden')
  exit(plugin)
end)
print(ok and 'PASS: Collabsprite-Menue, Dialoge und Diagnosekonsole initialisiert' or 'FAIL: '..tostring(err))
io.stdout:flush()
local resultPath=app.params.result
if not resultPath or resultPath=='' then
  if os.getenv('TEMP') then
  resultPath=app.fs.joinPath(os.getenv('TEMP'),'Collabsprite-ui-test-'..os.time()..'-'..math.random(100000,999999)..'.txt')
  end
end
if resultPath then
  local file=io.open(resultPath,'wb')
  if file then file:write(ok and 'PASS' or ('FAIL: '..tostring(err)));file:flush();file:close()
  else print('Could not write UI test result.') end
end
app.exit()
