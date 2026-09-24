local Client,session,dialog,timer,commandListener,afterCommandListener,preferences,extensionPath
local guarded,discovered={},{}
local copyInvite,disconnect
local pane='host'
local discoveredCount=0
local startup,startupCounter=nil,0
local PORT=8766

local function alert(message)
  app.alert{title='Collabsprite',text=tostring(message)}
end

local function friendly(error)
  local message=tostring(error)
  return message:match('^.-%.lua:%d+:%s*(.+)$') or message
end

local function safely(action)
  local ok,error=pcall(action)
  if not ok then alert(friendly(error)) end
end

local function refresh(s)
  if s.sprite then guarded[s.sprite]=true end
  if not dialog then return end
  local busy=startup~=nil
  dialog:modify{id='status',text=busy and 'Vorbereitung ...' or s.connected and 'Verbunden' or s.connecting and 'Verbinde ...' or 'Nicht verbunden'}
  dialog:modify{id='startHost',enabled=not busy and not s.connected and not s.connecting}
  dialog:modify{id='joinManual',enabled=not busy and not s.connected and not s.connecting}
  dialog:modify{id='joinFound',enabled=not busy and not s.connected and not s.connecting}
  dialog:modify{id='search',enabled=not busy and not s.connected and not s.connecting}
  dialog:modify{id='copy',visible=s.connected and s.isHost}
  dialog:modify{id='disconnect',visible=busy or s.connected or s.connecting}
end

local function artistName()
  local value=dialog and dialog.data.name or preferences.name
  value=value and value:match('^%s*(.-)%s*$') or ''
  preferences.name=value
  return value~='' and value or 'Kuenstler'
end

local function newSession()
  if session and (session.connected or session.connecting) then error('Bereits mit einer Sitzung verbunden.') end
  session=Client.new(refresh)
  return session
end

local function beginBootstrap(action,endpoints,onReady)
  assert(not startup,'Verbindung wird bereits vorbereitet.')
  local temp=os.getenv('TEMP') or os.getenv('TMP')
  assert(temp and temp~='','Windows-Temp-Verzeichnis fehlt.')
  startupCounter=startupCounter+1
  local id=string.format('%d-%d-%d',os.time(),startupCounter,math.random(100000,999999))
  local resultPath=app.fs.joinPath(temp,'Collabsprite-start-'..id..'.status')
  local script=app.fs.joinPath(extensionPath,'Launcher.vbs')
  local command='wscript.exe //B //Nologo "'..script..'" '..action..' Network '..PORT..' "'..resultPath..'" "'..(endpoints or '0')..'"'
  -- WScript exits immediately after spawning the detached worker. Never wait for
  -- a pipe here: a child inheriting it can freeze Aseprite's UI indefinitely.
  local launched=os.execute(command)
  assert(launched==true or launched==0,'Verbindungsstart fehlgeschlagen. Windows Script Host prüfen.')
  startup={path=resultPath,started=os.time(),onReady=onReady}
  refresh(session or {})
end

local function pollBootstrap()
  if not startup then return end
  local file=io.open(startup.path,'rb')
  if not file then
    if os.time()-startup.started>90 then
      startup=nil;refresh(session or {})
      alert('Verbindungsstart dauert zu lange. Netzwerk und Windows-Freigabe prüfen.')
    end
    return
  end
  local reply=file:read('*a') or ''
  if reply=='QUEUED' then file:close();return end
  file:close();os.remove(startup.path)
  local job=startup;startup=nil
  refresh(session or {})
  if job.cancelled then return end
  local problem=reply:match('ERROR ([^\r\n]+)')
  local ready=reply:match('READY ([^\r\n]+)')
  if problem then alert(problem)
  elseif ready then safely(function() job.onReady(ready) end)
  elseif reply:sub(1,7)=='SEARCH\n' then safely(function() job.onReady(reply:sub(8)) end)
  else alert('Verbindungsstart fehlgeschlagen.') end
end

local function joinCode(code)
  safely(function()
    assert(code and code~='','Bitte eine Sitzung auswaehlen oder einen Einladungscode eingeben.')
    code=code:gsub('%s',''):gsub('^ws://','')
    local endpoints,room,token=code:match('^([^/]+)/(%x+)/(%x+)$')
    assert(endpoints and #room==8 and #token==32,'Bitte den vollständigen Einladungscode eingeben.')
    assert(#endpoints<160 and endpoints:match('^[%d%.,:]+$'),'Einladungscode enthält ungültige Adressen.')
    local name=artistName()
    beginBootstrap('Join',endpoints,function(address) newSession():join(address..'/'..room..'/'..token,name) end)
  end)
end

local function searchSessionsNow(output)
  safely(function()
    if not dialog then return end
    discovered={}
    discoveredCount=0
    local choices,seen={},{}
    for line in (output or ''):gmatch('[^\r\n]+') do
      local ok,result=pcall(function() return json.decode(line) end)
      if ok and result and result.protocol==2 then
        for _,room in ipairs(result.rooms or {}) do
          local invite=tostring(room.invite or '')
          local address=invite:match('^([^/]+)/') or ''
          if address:match('^[%d%.]+:%d+$') and invite:match('^[%d%.]+:%d+/%x+/%x+$') and not seen[invite] then
            seen[invite]=true
            local label=tostring(room.name or 'Kuenstler'):sub(1,30)..' - '..tostring(room.image or 'Bild'):sub(1,30)
            if discovered[label] then label=label..' ('..(#choices+1)..')' end
            discovered[label]=invite;choices[#choices+1]=label
            discoveredCount=discoveredCount+1
          end
        end
      end
    end
    if #choices==0 then
      dialog:modify{id='sessions',options={'Keine Sitzung gefunden'},option='Keine Sitzung gefunden',visible=false}
      dialog:modify{id='joinFound',visible=false}
      app.tip('Keine Sitzung gefunden. Einladungscode eingeben.',5)
    else
      table.sort(choices)
      dialog:modify{id='sessions',options=choices,option=choices[1],visible=true}
      dialog:modify{id='joinFound',visible=true}
    end
  end)
end

local function searchSessions()
  safely(function()
    beginBootstrap('Search',nil,function(result) searchSessionsNow(result) end)
  end)
end

local function showPane(which)
  pane=which
  if not dialog then return end
  local host=which=='host'
  dialog:modify{id='tabHost',text=host and '● Erstellen' or 'Erstellen'}
  dialog:modify{id='tabJoin',text=host and 'Beitreten' or '● Beitreten'}
  dialog:modify{id='startHost',visible=host}
  for _,id in ipairs({'manual','joinManual','search'}) do dialog:modify{id=id,visible=not host} end
  dialog:modify{id='sessions',visible=not host and discoveredCount>0}
  dialog:modify{id='joinFound',visible=not host and discoveredCount>0}
end

local function show()
  if dialog then dialog:close();dialog=nil end
  dialog=Dialog{title='Collabsprite',onclose=function()
    if dialog then preferences.name=dialog.data.name end
    dialog=nil
  end}
  dialog:button{id='tabHost',text='● Erstellen',onclick=function() showPane('host') end}
    :button{id='tabJoin',text='Beitreten',onclick=function() showPane('join') end}
    :newrow()
    :entry{id='name',label='Dein Name',text=preferences.name or 'Kuenstler'}
    :button{id='startHost',text='Sitzung erstellen',onclick=function()
      if not app.sprite then alert('Bitte zuerst ein Bild öffnen');return end
      safely(function()
        local sprite,name=app.sprite,artistName()
        beginBootstrap('Host',nil,function() newSession():host(sprite,name,PORT) end)
      end)
    end}
    :entry{id='manual',label='Einladungscode',text='',visible=false}
    :button{id='joinManual',text='Beitreten',visible=false,onclick=function() joinCode(dialog.data.manual) end}
    :button{id='search',text='Sitzungen suchen',visible=false,onclick=searchSessions}
    :combobox{id='sessions',label='Aktive Sitzungen',options={'Keine Sitzung gefunden'},visible=false}
    :button{id='joinFound',text='Ausgewählte Sitzung öffnen',visible=false,onclick=function()
      joinCode(discovered[dialog.data.sessions])
    end}
    :separator{}
    :label{id='status',label='Aktive Sitzung',text='Nicht verbunden'}
    :button{id='copy',text='Einladung kopieren',visible=false,onclick=function() copyInvite() end}
    :button{id='disconnect',text='Trennen',visible=false,onclick=function() disconnect() end}
  dialog:show{wait=false}
  showPane(pane)
  if session then refresh(session) end
end

copyInvite=function()
  if not session or not session.connected or not session.isHost then
    alert('Erst eine Sitzung erstellen.');return
  end
  session:send{type='invite'}
  session.copyWhenReady=true
end

disconnect=function()
  if startup then
    startup.cancelled=true
    app.tip('Collabsprite: Vorbereitung abgebrochen. Ein bereits gestarteter Server beendet sich bei Leerlauf.',5)
    return
  end
  if not session or not (session.connected or session.connecting) then return end
  if #session.pending>0 then
    alert('Eigene Aenderungen werden noch uebertragen. Bitte kurz warten.')
  else
    session:disconnect()
  end
end

function init(plugin)
  if not app.isUIAvailable then return end
  extensionPath=plugin.path
  Client=dofile(app.fs.joinPath(plugin.path,'client.lua'))
  preferences=plugin.preferences
  -- This is a native item in Aseprite's menu bar; Lua cannot add a brush-bar button.
  plugin:newCommand{id='PixelKollabMultiplayer',title='Collabsprite...',group='view_new',onclick=show}
  commandListener=app.events:on('beforecommand',function(ev)
    if session and session.connected then
      local ok,error=pcall(function() session:beforeCommand(ev) end)
      if not ok then session:disconnect(friendly(error)) end
    end
    if guarded[app.sprite] and not (session and session.connected and app.sprite==session.sprite) and
      (ev.name=='Undo' or ev.name=='Redo' or ev.name=='UndoHistory') then
      ev.stopPropagation()
      app.tip('Multiplayer getrennt. Kopie speichern und neu oeffnen fuer lokales Undo.',5)
    end
  end)
  afterCommandListener=app.events:on('aftercommand',function(ev)
    if session and session.connected and not session.applying and app.sprite==session.sprite then
      session.dirty=true
    end
  end)
  timer=Timer{interval=0.033,ontick=function()
    pollBootstrap()
    if session then session:tick() end
  end}
  timer:start()
end

function exit(plugin)
  if timer then timer:stop() end
  if session then session:disconnect() end
  if dialog then dialog:close() end
  if commandListener then app.events:off(commandListener) end
  if afterCommandListener then app.events:off(afterCommandListener) end
end
