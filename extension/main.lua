local Client,decodeJson,session,dialog,timer,commandListener,afterCommandListener,preferences,extensionPath,diagnostics
local guarded,discovered={},{}
local copyInvite,disconnect
local pane='host'
local discoveredCount=0
local startup,startupCounter=nil,0
local updateJob,updateCounter=nil,0
local installedVersion='0.0.0'
local PORT=8766
local debugDialog=nil
local callbackBusy=false

local function traceback(err)
  return debug and debug.traceback and debug.traceback(tostring(err),2) or tostring(err)
end

local function logDiagnostic(event,detail)
  if diagnostics then pcall(function() diagnostics:log(event,detail) end) end
end

local function alert(message)
  app.alert{title='Collabsprite',text=tostring(message)}
end

local function friendly(error)
  local message=tostring(error)
  return message:match('^.-%.lua:%d+:%s*(.+)$') or message
end

local function safely(action)
  -- Permission and modal dialogs run a nested UI loop. Keep timer callbacks
  -- from entering Lua again while the current callback is waiting for it.
  if callbackBusy then return end
  callbackBusy=true
  local ok,error=xpcall(action,traceback)
  if not ok then logDiagnostic('UI error',error);pcall(alert,friendly(error)) end
  callbackBusy=false
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
  session=Client.new(refresh,logDiagnostic)
  return session
end

local function beginBootstrap(action,endpoints,onReady)
  assert(not startup,'Verbindung wird bereits vorbereitet.')
  logDiagnostic('bootstrap','start action='..tostring(action))
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
  startup={path=resultPath,started=os.time(),onReady=onReady,action=action}
  logDiagnostic('bootstrap','worker launched action='..tostring(action))
  refresh(session or {})
end

local function pollBootstrap()
  if not startup then return end
  if os.time()-startup.started>90 then
    startup=nil;refresh(session or {})
    logDiagnostic('bootstrap error','worker timeout')
    alert('Verbindungsstart dauert zu lange. Netzwerk und Windows-Freigabe prüfen.')
    return
  end
  local file=io.open(startup.path,'rb')
  if not file then return end
  local reply=file:read('*a') or ''
  if reply=='QUEUED' then file:close();return end
  file:close();os.remove(startup.path)
  local job=startup;startup=nil
  refresh(session or {})
  if job.cancelled then return end
  local problem=reply:match('ERROR ([^\r\n]+)')
  local ready=reply:match('READY ([^\r\n]+)')
  if problem then logDiagnostic('bootstrap error','worker returned an error; details shown in UI only');alert(problem)
  elseif ready then logDiagnostic('bootstrap ready','action='..tostring(job.action or 'connection'));job.onReady(ready)
  elseif reply:sub(1,7)=='SEARCH\n' then logDiagnostic('discovery','worker returned results');job.onReady(reply:sub(8))
  else logDiagnostic('bootstrap error','unexpected worker response');alert('Verbindungsstart fehlgeschlagen.') end
end

local function joinCode(code)
  safely(function()
    assert(code and code~='','Bitte eine Sitzung auswaehlen oder einen Einladungscode eingeben.')
    code=code:gsub('%s',''):gsub('^ws://','')
    local endpoints,room,token=code:match('^([^/]+)/(%x+)/(%x+)$')
    assert(endpoints and #room==8 and #token==32,'Bitte den vollständigen Einladungscode eingeben.')
    assert(#endpoints<160 and endpoints:match('^[%d%.,:]+$'),'Einladungscode enthält ungültige Adressen.')
    logDiagnostic('session','join input validated; invite and address hidden')
    local name=artistName()
    beginBootstrap('Join',endpoints,function(address) newSession():join(address..'/'..room..'/'..token,name) end)
  end)
end

local function searchSessionsNow(output)
  do
    if not dialog then return end
    discovered={}
    discoveredCount=0
    local choices,seen={},{}
    for line in (output or ''):gmatch('[^\r\n]+') do
      local ok,result=pcall(function() return decodeJson(line) end)
      if ok and result and result.protocol==3 then
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
      logDiagnostic('discovery','no sessions returned')
      dialog:modify{id='sessions',options={'Keine Sitzung gefunden'},option='Keine Sitzung gefunden',visible=false}
      dialog:modify{id='joinFound',visible=false}
      app.tip('Keine Sitzung gefunden. Einladungscode eingeben.',5)
    else
      logDiagnostic('discovery','sessions found='..#choices..'; names and invite codes omitted')
      table.sort(choices)
      dialog:modify{id='sessions',options=choices,option=choices[1],visible=true}
      dialog:modify{id='joinFound',visible=true}
    end
  end
end

local function searchSessions()
  safely(function()
    beginBootstrap('Search',nil,function(result) searchSessionsNow(result) end)
  end)
end

local function update()
  safely(function()
    if updateJob then app.tip('Collabsprite prüft bereits auf Updates.',4);return end
    local temp=os.getenv('TEMP') or os.getenv('TMP')
    assert(temp and temp~='','Windows-Temp-Verzeichnis fehlt.')
    updateCounter=updateCounter+1
    local id=string.format('%d-%d-%d',os.time(),updateCounter,math.random(100000,999999))
    local resultPath=app.fs.joinPath(temp,'Collabsprite-start-'..id..'.status')
    local script=app.fs.joinPath(extensionPath,'Launcher.vbs')
    local command='wscript.exe //B //Nologo "'..script..'" Update Network '..PORT..' "'..resultPath..'" "'..installedVersion..'"'
    local launched=os.execute(command)
    assert(launched==true or launched==0,'Update-Prüfung konnte nicht gestartet werden.')
    updateJob={path=resultPath,started=os.time()}
    app.tip('Collabsprite prüft GitHub im Hintergrund auf Updates.',5)
  end)
end

local function pollUpdate()
  if not updateJob then return end
  if os.time()-updateJob.started>160 then
    updateJob=nil
    alert('Update-Prüfung hat zu lange gedauert. Internetverbindung prüfen.')
    return
  end
  local file=io.open(updateJob.path,'rb')
  if not file then
    return
  end
  local reply=file:read('*a') or ''
  if reply=='QUEUED' then file:close();return end
  file:close();os.remove(updateJob.path)
  updateJob=nil
  local problem=reply:match('^ERROR ([^\r\n]+)')
  local current=reply:match('^CURRENT ([^\r\n]+)')
  local version,path=reply:match('^DOWNLOADED (v[%d%.]+)|([^\r\n]+)')
  if problem then alert(problem)
  elseif current then alert('Keine neuere Version veröffentlicht. Installiert: '..current)
  elseif version and path then
    local filename=path:match('([^\\/]+)$') or 'Collabsprite.aseprite-extension'
    local downloaded=Dialog{title='Collabsprite - Update'}
    downloaded:label{text='Neue Version '..version..' heruntergeladen.'}
      :newrow()
      :label{label='Downloads',text=filename}
      :newrow()
      :label{text='Datei oeffnen, Installation bestaetigen,'}
      :newrow()
      :label{text='Aseprite danach neu starten.'}
      :button{text='OK'}
    downloaded:show{wait=false}
  else alert('Update-Prüfung fehlgeschlagen.') end
end

local function info()
  local about=Dialog{title='Collabsprite - Info'}
  about:label{label='Version',text=installedVersion}
    :newrow()
    :label{label='Entwickler',text='Merthius'}
    :newrow()
    :label{label='Lizenz',text='MIT'}
    :newrow()
    :label{label='Projekt',text='github.com/Merthius/Collabsprite'}
    :newrow()
    :label{text='Zusammen zeichnen im LAN oder ueber Radmin VPN.'}
    :button{text='Schliessen'}
  about:show{wait=false}
end

local function showDiagnostics()
  safely(function()
    if not diagnostics then alert('Diagnoseprotokoll ist nicht verfügbar.');return end
    logDiagnostic('diagnostics','console opened')
    if debugDialog then debugDialog.dialog:close();debugDialog=nil end
    local dlg=Dialog{title='Collabsprite - Diagnose',onclose=function() debugDialog=nil end}
    dlg:label{text='Laufendes, lokales Protokoll · bleibt nach Aseprite-Neustart erhalten'}
      :newrow()
      :canvas{id='tail',width=740,height=350,autoscaling=false,onpaint=function(ev)
        local gc=ev.context
        gc.color=Color{r=35,g=37,b=43,a=255}
        gc:fillRect(Rectangle(0,0,gc.width,gc.height))
        gc.color=Color{r=200,g=205,b=215,a=255}
        gc:fillText('Letzte Ereignisse · ältere Einträge werden automatisch begrenzt',12,22)
        local lines=diagnostics:memoryTail(15)
        local start=math.max(1,#lines-14)
        for i=start,#lines do
          gc:fillText(lines[i]:sub(1,130),12,24+(i-start+1)*20)
        end
        gc.color=Color{r=145,g=153,b=168,a=255}
        gc:fillText('Lokales Protokoll · höchstens 512 KiB · keine Bilddaten',12,gc.height-12)
      end}
      :newrow()
      :button{text='Protokoll kopieren',onclick=function()
        safely(function()
          app.clipboard.text=diagnostics:export()
          logDiagnostic('diagnostics','report copied to clipboard')
          app.tip('Diagnoseprotokoll kopiert. Jetzt hier einfügen.',5)
          if debugDialog then debugDialog.dialog:repaint() end
        end)
      end}
      :button{text='Neues Protokoll',onclick=function()
        safely(function()
          assert(diagnostics:clear(),'Protokoll konnte nicht geleert werden.')
          logDiagnostic('diagnostics','new capture started; version='..installedVersion..'; aseprite='..tostring(app.version or 'unknown'))
          app.tip('Neues Protokoll gestartet. Jetzt den Beitritt erneut versuchen.',5)
          if debugDialog then debugDialog.dialog:repaint() end
        end)
      end}
      :button{text='Schließen',onclick=function() dlg:close() end}
    dlg:show{wait=false}
    debugDialog={dialog=dlg,lastPaint=os.time()}
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
  local temp=os.getenv('TEMP') or os.getenv('TMP')
  local logPath=temp and app.fs.joinPath(temp,'Collabsprite-debug.log') or (os.tmpname()..'.collabsprite.log')
  diagnostics=dofile(app.fs.joinPath(plugin.path,'diagnostics.lua')).new(logPath)
  decodeJson=dofile(app.fs.joinPath(plugin.path,'json.lua')).decode
  Client=dofile(app.fs.joinPath(plugin.path,'client.lua'))
  preferences=plugin.preferences
  installedVersion=plugin.version and tostring(plugin.version) or '0.0.0'
  logDiagnostic('startup','Collabsprite '..installedVersion..'; Aseprite '..tostring(app.version or 'unknown')..'; log file ready')
  -- Aseprite exposes groups within existing menus, not a group on main_menu.
  plugin:newMenuGroup{id='CollabspriteMenu',title='Collabsprite',group='view_new'}
  plugin:newCommand{id='PixelKollabMultiplayer',title='Server erstellen / beitreten...',group='CollabspriteMenu',onclick=show}
  plugin:newCommand{id='CollabspriteUpdate',title='Update...',group='CollabspriteMenu',onclick=update}
  plugin:newCommand{id='CollabspriteInfo',title='Info...',group='CollabspriteMenu',onclick=info}
  plugin:newCommand{id='CollabspriteDebugConsole',title='Diagnosekonsole...',group='CollabspriteMenu',onclick=showDiagnostics}
  commandListener=app.events:on('beforecommand',function(ev)
    if session and (session.connected or session.connecting) then
      logDiagnostic('aseprite command',tostring(ev.name or 'unknown'))
    end
    if session and session.connected then
      local ok,error=xpcall(function() session:beforeCommand(ev) end,function(err)
        return debug and debug.traceback and debug.traceback(tostring(err),2) or tostring(err)
      end)
      if not ok then
        logDiagnostic('Aseprite command error',error)
        session:disconnect(friendly(error))
      end
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
    if callbackBusy then return end
    callbackBusy=true
    local ok,err=xpcall(function()
      pollBootstrap()
      pollUpdate()
      if session then session:tick() end
      if debugDialog and os.time()~=debugDialog.lastPaint then
        debugDialog.lastPaint=os.time()
        debugDialog.dialog:repaint()
      end
    end,traceback)
    if not ok then
      -- Do not repeat a failed protected file operation every 33 ms.
      startup=nil;updateJob=nil
      logDiagnostic('FATAL main timer',err)
      if session then pcall(function() session:disconnect('Diagnoseprotokoll bitte kopieren.') end) end
      pcall(function() refresh(session or {});app.tip('Collabsprite: Fehler. Diagnoseprotokoll bitte kopieren.',8) end)
    end
    callbackBusy=false
  end}
  timer:start()
end

function exit(plugin)
  if timer then timer:stop() end
  if session then session:disconnect() end
  if dialog then dialog:close() end
  if debugDialog then debugDialog.dialog:close();debugDialog=nil end
  if commandListener then app.events:off(commandListener) end
  if afterCommandListener then app.events:off(afterCommandListener) end
end
