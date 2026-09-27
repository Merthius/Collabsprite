-- The background worker downloads/verifies; Aseprite owns installation.
-- No self-extraction into a loaded extension and no forced app restart.
local Update={}
Update.__index=Update
local phases={checking='Version prüfen',downloading='Herunterladen',verifying='Paket prüfen',installing='Installieren'}
local order={'checking','downloading','verifying','installing'}

function Update.new(options)
  return setmetatable({options=options,counter=0,phase='checking',detail='',busy=false},Update)
end

function Update:setState(phase,detail)
  self.phase,self.detail=phase,detail or ''
  if not self.dialog then return end
  local active=0
  for i,key in ipairs(order) do if key==phase then active=i end end
  for i,key in ipairs(order) do
    local prefix=(phase=='done' or (phase=='current' and i==1)) and '✓ ' or active>i and '✓ ' or active==i and '› ' or '· '
    self.dialog:modify{id=key,text=prefix..phases[key]}
  end
  local first,second=self.detail,''
  if #first>80 then
    local cut=first:sub(1,80):match('^.*() ')
    cut=cut or 80
    first,second=self.detail:sub(1,cut-1),self.detail:sub(cut+1)
  end
  self.dialog:modify{id='detail',text=first}
  self.dialog:modify{id='detail2',text=second:sub(1,100),visible=second~=''}
  self.dialog:modify{id='close',text=self.busy and 'Abbrechen' or 'Schließen',enabled=phase~='installing'}
  self.dialog:modify{id='retry',visible=phase=='cancelled' and self.packagePath~=nil}
  self.dialog:repaint()
end

function Update:show()
  if self.dialog then self.dialog:close() end
  local dlg
  dlg=Dialog{title='Collabsprite · Update',onclose=function()
    if self.dialog==dlg then self.dialog=nil end
    -- Closing during a download cancels the installation, not an in-flight
    -- HTTPS write. The worker may finish its checked file in Downloads.
    if self.busy and self.phase~='installing' then self.cancelled=true end
  end}
  self.dialog=dlg
  for _,key in ipairs(order) do dlg:label{id=key,text='· '..phases[key]}:newrow() end
  dlg:separator{}:label{id='detail',text='GitHub wird im Hintergrund geprüft …'}:newrow()
    :label{id='detail2',text='',visible=false}:newrow()
    :button{id='retry',text='Installation erneut öffnen',visible=false,onclick=function()
      self.options.safely(function() self:install() end)
    end}
    :button{id='close',text='Abbrechen',onclick=function() dlg:close() end}
  dlg:show{wait=false}
  self:setState(self.phase,self.detail)
end

function Update:finish(phase,message)
  self.busy=false
  self:setState(phase,message)
  self.options.log('update',phase)
end

function Update:start()
  if self.busy then
    -- Do not trigger another download when the menu is clicked repeatedly.
    if not self.dialog and not self.cancelled then self:show() end
    return
  end
  local reason=self.options.blocked()
  if reason then app.alert{title='Collabsprite',text=reason};return end
  local temp=os.getenv('TEMP') or os.getenv('TMP')
  assert(temp and temp~='','Windows-Temp-Verzeichnis fehlt.')
  self.counter=self.counter+1
  self.path=app.fs.joinPath(temp,string.format('Collabsprite-start-%d-%d-%d.status',os.time(),self.counter,math.random(100000,999999)))
  self.started=os.time();self.busy=true;self.cancelled=false;self.packagePath=nil
  self.phase='checking';self.detail='GitHub wird im Hintergrund geprüft …'
  self:show()
  local command='wscript.exe //B //Nologo "'..app.fs.joinPath(self.options.path,'Launcher.vbs')..'" Update Network 8766 "'..self.path..'" "'..self.options.version..'"'
  local ok,result=pcall(os.execute,command)
  if not ok or not (result==true or result==0) then self:finish('error','Update konnte nicht gestartet werden.');return end
  self.options.log('update','background check started')
end

function Update:install()
  local reason=self.options.blocked()
  if reason then self:finish('cancelled',reason);return end
  if self.cancelled or not self.packagePath then return end
  self.busy=true
  self:setState('installing','Bitte die Installation in Aseprite bestätigen.')
  self.options.log('update','native installer opened')
  -- This can unload this very plugin. Keep the local updater alive until the
  -- command returns; do not touch an unloaded session or its timers afterwards.
  local ok,err=pcall(function() app.command.Options{installExtension=self.packagePath} end)
  if not ok then self:finish('error','Installation fehlgeschlagen. Diagnose prüfen.');self.options.log('update error',tostring(err));return end
  local file=io.open(app.fs.joinPath(self.options.path,'package.json'),'rb')
  local text=file and file:read('*a') or '';if file then file:close() end
  local decoded,manifest=pcall(self.options.decode,text)
  local inventoryFile=io.open(app.fs.joinPath(self.options.path,'__info.json'),'rb')
  local inventoryText=inventoryFile and inventoryFile:read('*a') or '';if inventoryFile then inventoryFile:close() end
  local inventoryOk,inventory=pcall(self.options.decode,inventoryText)
  local complete=false
  if inventoryOk and type(inventory)=='table' and type(inventory.installedFiles)=='table' then
    for _,name in ipairs(inventory.installedFiles) do if name=='main.lua' then complete=true end end
  end
  if decoded and manifest and manifest.name=='pixelkollab-native' and manifest.version==self.targetVersion and complete then
    self:finish('done','Version '..self.targetVersion..' installiert. Aseprite neu starten.')
  else
    self:finish('cancelled','Nicht installiert. Du kannst es erneut versuchen.')
  end
end

function Update:tick()
  if not self.busy or self.phase=='installing' then return end
  if os.time()-self.started>180 then self:finish('error','Zeitüberschreitung. Internet prüfen und erneut versuchen.');return end
  local file=io.open(self.path,'rb')
  if not file then return end
  local reply=file:read('*a') or '';file:close()
  if reply=='QUEUED' or reply=='' then return end
  local phase=reply:match('^PROGRESS (%a+)$')
  if phase then
    if phase=='preparing' then self:setState('verifying','Bisherige Version wird gesichert …');return end
    if phases[phase] and phase~='installing' and phase~=self.phase then
      local detail=phase=='downloading' and 'Neue Version wird heruntergeladen …' or 'Prüfsumme und Erweiterung werden geprüft …'
      self:setState(phase,detail)
    end
    return
  end
  os.remove(self.path)
  if self.cancelled then self:finish('cancelled','Update abgebrochen. Nichts installiert.');return end
  local problem=reply:match('^ERROR ([^\r\n]+)')
  local current=reply:match('^CURRENT ([^\r\n]+)')
  local version,path=reply:match('^DOWNLOADED v(%d+%.%d+%.%d+)|([^\r\n]+)$')
  if problem then self:finish('error',problem)
  elseif current then self:finish('current','Du hast die neueste Version ('..current..').')
  elseif version and path and path:match('%.aseprite%-extension$') then
    self.packagePath=path;self.targetVersion=version
    self:install()
    return true -- The old main.lua must not run another session tick after unload.
  else self:finish('error','Unbekannte Update-Antwort. Diagnose prüfen.') end
end

function Update:close()
  -- Aseprite calls exit() during self-update; keep the progress view alive.
  if self.phase=='installing' then return end
  if self.dialog then self.dialog:close();self.dialog=nil end
end
return Update
