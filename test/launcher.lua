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
  assert(#groups==0)
  assert(#commands==1 and commands[1].group=='view_new' and commands[1].title=='Collabsprite...')
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
print(ok and 'PASS: kompakter Collabsprite-Dialog und Ansicht-Menue initialisiert' or 'FAIL: '..tostring(err))
io.stdout:flush()
app.exit()
