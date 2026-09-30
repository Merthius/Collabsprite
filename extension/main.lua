local Client,decodeJson,session,dialog,timer,commandListener,afterCommandListener,preferences,extensionPath,diagnostics
local guarded,discovered={},{}
local copyInvite,disconnect
local pane='host'
local discoveredCount=0
local startup,startupCounter=nil,0
local updater
local installedVersion='0.0.0'
local PORT=8766
local debugDialog=nil
local callbackBusy=false
local notesUI
local Layout
local windowToken
local pendingCommand
local cancelledStarts={}

local function traceback(err)
  return debug and debug.traceback and debug.traceback(tostring(err),2) or tostring(err)
end

local function logDiagnostic(event,detail)
  if diagnostics then pcall(function() diagnostics:log(event,detail) end) end
end

local function alert(message)
  if Layout then Layout.alert(message) else app.alert{title='Collabsprite',text=tostring(message)} end
end

local function friendly(error)
  local message=tostring(error):match('[^\r\n]+') or 'Unbekannter Fehler. Diagnose prüfen.'
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
  if s.sprite and s.sprite.isValid then guarded[s.sprite.id]={guest=s.isHost==false} end
  for _,sprite in ipairs(s.recoverySprites or {}) do if sprite.isValid then guarded[sprite.id]={guest=s.isHost==false} end end
  if notesUI and s.sprite and s.sprite.isValid and not s.notesAttached then notesUI:attach(s);s.notesAttached=true end
  if not dialog then return end
  local busy=not not (startup~=nil or s.reconnecting or s.preparing)
  local status=startup and (startup.action=='Search' and 'Suche läuft ...' or 'Vorbereitung ...') or
    s.preparing and 'Bild wird vorbereitet ...' or s.reconnecting and 'Verbinde erneut ...' or
    s.connected and (s.syncStatus or 'Verbunden') or s.connecting and 'Verbinde ...' or 'Nicht verbunden'
  dialog:modify{id='status',text=Layout.short(status,36)}
  dialog:modify{id='startHost',enabled=not busy and not s.connected and not s.connecting}
  dialog:modify{id='joinManual',enabled=not busy and not s.connected and not s.connecting}
  dialog:modify{id='joinFound',enabled=not busy and not s.connected and not s.connecting}
  dialog:modify{id='search',enabled=not busy and not s.connected and not s.connecting}
  dialog:modify{id='copy',visible=s.connected and s.isHost}
  dialog:modify{id='admission',visible=s.connected and s.isHost,selected=s.acceptingGuests~=false}
  dialog:modify{id='disconnect',visible=not not (busy or s.connected or s.connecting),text=s.connected and 'Trennen' or 'Abbrechen'}
  Layout.fit(dialog,280*(app.uiScale or 1),(pane=='host' and 160 or 210)*(app.uiScale or 1))
end

local function artistName()
  local value=dialog and dialog.data.name or preferences.name
  value=value and value:match('^%s*(.-)%s*$') or ''
  preferences.name=value
  return value~='' and value or 'Kuenstler'
end

local function newSession()
  if session and (session.connected or session.connecting or session.reconnecting or session.preparing) then error('Bereits mit einer Sitzung verbunden.') end
  session=Client.new(refresh,logDiagnostic)
  return session
end

local function beginBootstrap(action,endpoints,onReady)
  assert(not (updater and updater.busy),'Bitte zuerst das Update abschließen oder abbrechen.')
  assert(not startup,'Verbindung wird bereits vorbereitet.')
  if action=='Host' or action=='Join' then
    if diagnostics and diagnostics.beginSession then pcall(function() diagnostics:beginSession(action) end) end
  end
  logDiagnostic('bootstrap','start action='..tostring(action))
  local temp=os.getenv('TEMP') or os.getenv('TMP')
  assert(temp and temp~='','Windows-Temp-Verzeichnis fehlt.')
  startupCounter=startupCounter+1
  local id=string.format('%d-%d-%d',os.time(),startupCounter,math.random(100000,999999))
  local resultPath=app.fs.joinPath(temp,'Collabsprite-start-'..id..'.status')
  local script=app.fs.joinPath(extensionPath,'Launcher.vbs')
  local command='wscript.exe //B //Nologo "'..script..'" '..action..' Network '..PORT..' "'..resultPath..'" "'..(endpoints or '0')..'"'
  if action=='Host' and dialog and windowToken and app.preferences and app.preferences.experimental and
    app.preferences.experimental.multiple_windows~=false then command=command..' '..windowToken end
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

local function joinCodeNow(code)
    assert(code and code~='','Bitte eine Sitzung auswaehlen oder einen Einladungscode eingeben.')
    code=code:gsub('%s',''):gsub('^ws://','')
    local endpoints,room,token=code:match('^([^/]+)/(%x+)/(%x+)$')
    assert(endpoints and #room==8 and #token==32,'Bitte den vollständigen Einladungscode eingeben.')
    assert(#endpoints<160 and endpoints:match('^[%d%.,:]+$'),'Einladungscode enthält ungültige Adressen.')
    logDiagnostic('session','join input validated; invite and address hidden')
    local name=artistName()
    beginBootstrap('Join',endpoints,function(address) newSession():join(address..'/'..room..'/'..token,name) end)
end
local function joinCode(code) safely(function() joinCodeNow(code) end) end

local function searchSessionsNow(output)
  do
    if not dialog then return end
    discovered={}
    discoveredCount=0
    local choices,seen={},{}
    for line in (output or ''):gmatch('[^\r\n]+') do
      local ok,result=pcall(function() return decodeJson(line) end)
      if ok and result and result.protocol==14 then
        for _,room in ipairs(result.rooms or {}) do
          local invite=tostring(room.invite or '')
          local address=invite:match('^([^/]+)/') or ''
          if address:match('^[%d%.]+:%d+$') and invite:match('^[%d%.]+:%d+/%x+/%x+$') and not seen[invite] then
            seen[invite]=true
            local label=Layout.short(room.name or 'Kuenstler',16)..' · '..Layout.short(room.image or 'Bild',18)
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
      if #choices==1 and not (session and (session.connected or session.connecting or session.reconnecting or session.preparing)) then
        joinCodeNow(discovered[choices[1]])
      end
    end
  end
end

local function searchSessions()
  safely(function()
    beginBootstrap('Search',nil,function(result) searchSessionsNow(result) end)
  end)
end

local function update()
  safely(function() updater:start() end)
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
    :label{text='Gemeinsam zeichnen im LAN'}:newrow()
    :label{text='oder über Radmin VPN.'}
    :button{text='Schliessen'}
  Layout.show(about)
end

local function showDiagnostics()
  safely(function()
    if not diagnostics then alert('Diagnoseprotokoll ist nicht verfügbar.');return end
    logDiagnostic('diagnostics','console opened')
    if debugDialog then debugDialog.dialog:close();debugDialog=nil end
    local dlg=Dialog{title='Collabsprite - Diagnose',onclose=function() debugDialog=nil end}
    local width,height=Layout.canvas(660,370)
    local view={scroll=0,total=0,maxOffset=0,visible=1,dragging=false}
    local function moveScrollbar(y)
      local track=view.track
      if not track or view.maxOffset==0 then return end
      local travel=math.max(1,track.h-track.thumb)
      local fraction=math.max(0,math.min(1,(y-track.y-track.thumb/2)/travel))
      view.scroll=math.floor(view.maxOffset*(1-fraction)+0.5)
      dlg:repaint()
    end
    dlg:label{text='Lokales Protokoll · ohne Bilddaten'}
      :newrow()
      :canvas{id='tail',width=width,height=height,autoscaling=false,focus=true,onpaint=function(ev)
        local gc=ev.context
        gc.color=Color{r=35,g=37,b=43,a=255}
        gc:fillRect(Rectangle(0,0,gc.width,gc.height))
        gc.color=Color{r=200,g=205,b=215,a=255}
        local count=math.max(1,math.floor((gc.height-36)/20));view.visible=count
        local lines,total,maxOffset,offset=diagnostics:window(count,view.scroll)
        if view.scroll>0 and total>view.total then
          view.scroll=math.min(maxOffset,view.scroll+total-view.total)
          lines,total,maxOffset,offset=diagnostics:window(count,view.scroll)
        end
        view.total=total;view.maxOffset=maxOffset;view.scroll=offset
        for i,line in ipairs(lines) do gc:fillText(line:sub(1,120),12,10+(i-1)*20) end
        local trackY,trackH=8,math.max(24,gc.height-38)
        local thumb=math.max(20,math.floor(trackH*math.min(1,count/math.max(1,total))))
        local thumbY=trackY+(maxOffset>0 and math.floor((maxOffset-offset)/maxOffset*(trackH-thumb)) or 0)
        view.track={x=gc.width-17,y=trackY,h=trackH,thumb=thumb}
        gc.color=Color{r=59,g=62,b=70,a=255}
        gc:fillRect(Rectangle(gc.width-17,trackY,9,trackH))
        gc.color=Color{r=143,g=159,b=174,a=255}
        gc:fillRect(Rectangle(gc.width-17,thumbY,9,thumb))
        gc.color=Color{r=145,g=153,b=168,a=255}
        gc:fillText('Einträge '..(total==0 and 0 or total-offset-#lines+1)..'–'..(total-offset)..' / '..total..' · Kopie: aktuelle Sitzung',12,gc.height-12)
      end,onwheel=function(ev)
        view.scroll=math.max(0,math.min(view.maxOffset,view.scroll-(ev.deltaY or 0)*3))
        dlg:repaint()
      end,onmousedown=function(ev)
        if view.track and ev.x>=view.track.x-5 then view.dragging=true;moveScrollbar(ev.y) end
      end,onmousemove=function(ev)
        if view.dragging then moveScrollbar(ev.y) end
      end,onmouseup=function() view.dragging=false end,
      onkeydown=function(ev)
        local step=ev.code=='PageUp' and view.visible or ev.code=='PageDown' and -view.visible or
          ev.code=='ArrowUp' and 1 or ev.code=='ArrowDown' and -1 or 0
        if ev.code=='Home' then view.scroll=view.maxOffset
        elseif ev.code=='End' then view.scroll=0
        elseif step~=0 then view.scroll=math.max(0,math.min(view.maxOffset,view.scroll+step))
        else return end
        ev:stopPropagation();dlg:repaint()
      end}
      :newrow()
      :button{text='Protokoll kopieren',onclick=function()
        safely(function()
          app.clipboard.text=diagnostics:export()
          logDiagnostic('diagnostics','report copied to clipboard')
          app.tip('Aktuelle Sitzung kopiert. Jetzt hier einfügen.',5)
          if debugDialog then debugDialog.dialog:repaint() end
        end)
      end}
      :button{text='Leeren',onclick=function()
        safely(function()
          assert(diagnostics:clear(),'Protokoll konnte nicht geleert werden.')
          logDiagnostic('diagnostics','new capture started; version='..installedVersion..'; aseprite='..tostring(app.version or 'unknown'))
          app.tip('Neues Protokoll gestartet. Jetzt den Beitritt erneut versuchen.',5)
          view.scroll=0;view.total=0
          if debugDialog then debugDialog.dialog:repaint() end
        end)
      end}
      :button{text='Schließen',onclick=function() dlg:close() end}
    Layout.show(dlg)
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
  Layout.fit(dialog,280*(app.uiScale or 1),(host and 160 or 210)*(app.uiScale or 1))
end

local function show()
  if dialog then dialog:close();dialog=nil end
  windowToken=tostring(Uuid()):gsub('-',''):lower()
  dialog=Dialog{title='Collabsprite #'..windowToken:sub(1,12),onclose=function()
    if dialog then preferences.name=dialog.data.name end
    dialog=nil
  end}
  dialog:button{id='tabHost',text='● Erstellen',onclick=function() showPane('host') end}
    :button{id='tabJoin',text='Beitreten',onclick=function() showPane('join') end}
    :newrow()
    :entry{id='name',label='Dein Name',text=preferences.name or 'Kuenstler'}:newrow()
    :button{id='startHost',text='Sitzung erstellen',onclick=function()
      if not app.sprite then alert('Bitte zuerst ein Bild öffnen');return end
      if app.sprite and guarded[app.sprite.id] and guarded[app.sprite.id].guest then
        alert('Dieses Gast-Sitzungsbild kann nur der ursprüngliche Host speichern oder neu hosten.');return
      end
      safely(function()
        local sprite,name=app.sprite,artistName()
        beginBootstrap('Host',nil,function() newSession():host(sprite,name,PORT,true) end)
      end)
    end}
    :newrow():entry{id='manual',label='Einladungscode',text='',visible=false}
    :newrow()
    :button{id='joinManual',text='Beitreten',visible=false,onclick=function() joinCode(dialog.data.manual) end}
    :button{id='search',text='Sitzungen suchen',visible=false,onclick=searchSessions}
    :newrow():combobox{id='sessions',label='Sitzungen',options={'Keine Sitzung gefunden'},visible=false}
    :newrow()
    :button{id='joinFound',text='Ausgewählte Sitzung öffnen',visible=false,onclick=function()
      joinCode(discovered[dialog.data.sessions])
    end}
    :separator{}
    :label{id='status',label='Aktive Sitzung',text='Nicht verbunden'}
    :check{id='admission',label='Zugriff',text='Beitritte erlauben',selected=true,visible=false,onclick=function()
      safely(function()
        if session and session.connected and session.isHost then session:send{type='admission',open=dialog.data.admission==true} end
      end)
    end}
    :newrow()
    :button{id='copy',text='Einladung kopieren',visible=false,onclick=function() copyInvite() end}
    :button{id='disconnect',text='Trennen',visible=false,onclick=function() disconnect() end}
  Layout.show(dialog)
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
    local job=startup;startup=nil;cancelledStarts[#cancelledStarts+1]=job
    pcall(function() local f=assert(io.open(job.path..'.cancel','wb'));f:write('CANCEL');f:close() end)
    refresh(session or {})
    app.tip('Collabsprite: Vorbereitung abgebrochen. Ein bereits gestarteter Server beendet sich bei Leerlauf.',5)
    return
  end
  if not session or not (session.connected or session.connecting or session.reconnecting or session.preparing) then return end
  safely(function()
    local leaving=session
    leaving:requestLeave(function()
      -- Only discard the guest's session view after the server confirms its
      -- edits. Never close the host document or unrelated local artwork.
      if leaving.isHost==false and leaving.sprite and leaving.sprite.isValid then leaving.sprite:close() end
    end)
  end)
end

function init(plugin)
  if not app.isUIAvailable then return end
  extensionPath=plugin.path
  Layout=dofile(app.fs.joinPath(plugin.path,'ui-layout.lua'))
  local temp=os.getenv('TEMP') or os.getenv('TMP')
  local logPath=temp and app.fs.joinPath(temp,'Collabsprite-debug.log') or (os.tmpname()..'.collabsprite.log')
  diagnostics=dofile(app.fs.joinPath(plugin.path,'diagnostics.lua')).new(logPath)
  decodeJson=dofile(app.fs.joinPath(plugin.path,'json.lua')).decode
  Client=dofile(app.fs.joinPath(plugin.path,'client.lua'))
  notesUI=dofile(app.fs.joinPath(plugin.path,'notes-ui.lua')).new(function() return session end,
    function(sprite) return sprite and guarded[sprite.id] and guarded[sprite.id].guest end,safely,artistName,
    function(token)
      local script=app.fs.joinPath(plugin.path,'Window.vbs')
      if app.fs.isFile(script) and token:match('^[a-f0-9]+$') and #token==32 then
        os.execute('wscript.exe //B //Nologo "'..script..'" '..token)
      end
    end,dofile(app.fs.joinPath(plugin.path,'board-files.lua')),logDiagnostic)
  preferences=plugin.preferences
  installedVersion=plugin.version and tostring(plugin.version) or '0.0.0'
  updater=dofile(app.fs.joinPath(plugin.path,'update-ui.lua')).new{
    path=extensionPath,version=installedVersion,decode=decodeJson,safely=safely,log=logDiagnostic,
    blocked=function()
      if startup or (session and (session.connected or session.connecting or session.reconnecting)) then
        return 'Bitte die Multiplayer-Sitzung vor dem Update über Trennen beenden.'
      end
      if notesUI then
        for _,s in pairs(notesUI.states) do
          if s.sprite.isValid and not notesUI:canLeave(s) then return 'Bitte warten, bis die Ideenwand ihre Änderungen bestätigt hat.' end
        end
      end
    end}
  logDiagnostic('startup','Collabsprite '..installedVersion..'; Aseprite '..tostring(app.version or 'unknown')..'; log file ready')
  -- file_import is the last built-in item before File > Scripts. Inserting a
  -- separator and then our group there places a distinct submenu above Scripts.
  plugin:newMenuSeparator{group='file_import'}
  plugin:newMenuGroup{id='CollabspriteMenu',title='Multiplayer (Collabsprite)',group='file_import'}
  plugin:newCommand{id='PixelKollabMultiplayer',title='Server erstellen / beitreten...',group='CollabspriteMenu',onclick=show}
  plugin:newCommand{id='CollabspriteNotes',title='Gemeinsame Notizen...',group='CollabspriteMenu',
    onclick=function() safely(function() notesUI.failed=nil;notesUI:show(app.sprite) end) end}
  plugin:newCommand{id='CollabspriteUpdate',title='Update...',group='CollabspriteMenu',onclick=update}
  plugin:newCommand{id='CollabspriteInfo',title='Info...',group='CollabspriteMenu',onclick=info}
  plugin:newCommand{id='CollabspriteDebugConsole',title='Diagnosekonsole...',group='CollabspriteMenu',onclick=showDiagnostics}
  commandListener=app.events:on('beforecommand',function(ev)
    local protection=app.sprite and guarded[app.sprite.id]
    if Client.blockGuestSave(ev,protection and protection.guest) then return end
    if notesUI then
      local targets={}
      if ev.name=='CloseAllFiles' or ev.name=='Exit' then
        for _,s in pairs(notesUI.states) do if s.sprite.isValid then targets[#targets+1]=s end end
      elseif ev.name=='CloseFile' or ev.name=='SaveFile' or ev.name=='SaveFileAs' or ev.name=='SaveFileCopyAs' then
        if app.sprite and notesUI.states[app.sprite.id] then targets[1]=notesUI.states[app.sprite.id] end
      end
      for _,s in ipairs(targets) do if not notesUI:canLeave(s) then
        ev.stopPropagation()
        pendingCommand={name=ev.name,params=ev.params,targetId=app.sprite and app.sprite.id,targets=targets,started=os.time()}
        app.tip('Skizze wird übernommen. Danach geht es automatisch weiter.',4)
        return
      end end
    end
    if session and (session.connected or session.connecting) then
      logDiagnostic('aseprite command',tostring(ev.name or 'unknown'))
    end
    if session and (session.connected or session.reconnecting) then
      if ev.name=='CloseAllFiles' or ev.name=='Exit' or (ev.name=='CloseFile' and app.sprite and
          session.sprite and session.sprite.isValid and app.sprite.id==session.sprite.id) then
        ev.stopPropagation()
        local leaving,name,params,target=session,ev.name,ev.params,app.sprite
        local targetId=target and target.id
        local ok,problem=xpcall(function()
          leaving:requestLeave(function()
            local guest=leaving.isHost==false
            if guest and leaving.sprite and leaving.sprite.isValid then leaving.sprite:close() end
            if name=='CloseFile' and not guest and (not app.sprite or app.sprite.id~=targetId) then
              app.tip('Verbindung getrennt. Das Sitzungsbild kann jetzt geschlossen werden.',5)
              return
            end
            if name~='CloseFile' or not guest then app.command[name](params or {}) end
          end)
        end,traceback)
        if not ok then logDiagnostic('close error',problem);app.tip(friendly(problem),6) end
        return
      end
      local ok,error=xpcall(function() session:beforeCommand(ev) end,function(err)
        return debug and debug.traceback and debug.traceback(tostring(err),2) or tostring(err)
      end)
      if not ok then
        logDiagnostic('Aseprite command error',error)
        session:disconnect(friendly(error))
      end
    end
    if protection and not (session and session.connected and app.sprite==session.sprite) and
      (ev.name=='Undo' or ev.name=='Redo' or ev.name=='UndoHistory') then
      ev.stopPropagation()
      app.tip('Multiplayer getrennt. Kopie speichern und neu oeffnen fuer lokales Undo.',5)
    end
  end)
  afterCommandListener=app.events:on('aftercommand',function(ev)
    if session and (ev.name=='SaveFileAs' or ev.name=='SaveFile') then session:notesFileSaved() end
    if notesUI and (ev.name=='SaveFileAs' or ev.name=='SaveFileCopyAs' or ev.name=='ExportSpriteSheet') then
      local s=app.sprite and notesUI.states[app.sprite.id]
      if s and #s.board.cards>0 then
        app.tip('Ideenwand sichern: zusätzlich als .aseprite speichern. PNG/Spritesheets enthalten keine Notizen.',7)
      end
    end
    if session and session.connected and not session.applying and app.sprite==session.sprite then
      session.dirty=true
    end
  end)
  timer=Timer{interval=0.033,ontick=function()
    if callbackBusy then return end
    callbackBusy=true
    local ok,err=xpcall(function()
      pollBootstrap()
      for index=#cancelledStarts,1,-1 do
        local job=cancelledStarts[index]
        local f=io.open(job.path,'rb');local reply=f and f:read('*a');if f then f:close() end
        if (reply and reply~='QUEUED') or os.time()-job.started>95 then
          os.remove(job.path);os.remove(job.path..'.cancel');table.remove(cancelledStarts,index)
        end
      end
      if updater then
        -- An update problem must not disconnect a drawing session.
        local updateOk,installed=xpcall(function() return updater:tick() end,traceback)
        if not updateOk then
          updater:finish('error','Update fehlgeschlagen. Diagnose prüfen.');logDiagnostic('update error',installed)
        elseif installed then return end
      end
      if session then session:tick() end
      if notesUI and not notesUI.failed then
        local noteOk,noteError=xpcall(function() notesUI:tick() end,traceback)
        if not noteOk then
          notesUI.failed=true;logDiagnostic('Notes UI paused',noteError)
          app.tip('Notizfenster pausiert. Diagnose prüfen und Gemeinsame Notizen erneut öffnen. Zeichnen bleibt möglich.',8)
        end
      end
      if pendingCommand then
        local command=pendingCommand;local ready=true
        for _,s in ipairs(command.targets) do if s.sprite.isValid and not notesUI:canLeave(s) then ready=false;break end end
        if ready then
          pendingCommand=nil
          if command.name~='CloseFile' or (app.sprite and app.sprite.id==command.targetId) then app.command[command.name](command.params or {}) end
        elseif os.time()-command.started>25 then
          pendingCommand=nil;app.tip('Entwurf bleibt erhalten. Verbindung oder Diagnose prüfen; nichts wurde verworfen.',7)
        end
      end
      if debugDialog and os.time()~=debugDialog.lastPaint then
        debugDialog.lastPaint=os.time()
        debugDialog.dialog:repaint()
      end
    end,traceback)
    if not ok then
      -- Do not repeat a failed protected file operation every 33 ms.
      startup=nil
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
  if updater then updater:close() end
  if session then session:disconnect() end
  if notesUI then notesUI:close() end
  if dialog then dialog:close() end
  if debugDialog then debugDialog.dialog:close();debugDialog=nil end
  if commandListener then app.events:off(commandListener) end
  if afterCommandListener then app.events:off(afterCommandListener) end
end
