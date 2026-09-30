-- Private, bounded local mailbox for Windows file selection/drop events.
local dir=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local decode=dofile(app.fs.joinPath(dir,'json.lua')).decode
local M={}
local function valid(token) return type(token)=='string' and #token==32 and token:match('^[a-f0-9]+$') end
local function path(token)
  assert(valid(token),'Ungültige Bildauswahl')
  return app.fs.joinPath(assert(os.getenv('TEMP') or os.getenv('TMP')),'Collabsprite-files-'..token..'.json')
end
function M.start(token,mode,board)
  assert(valid(token) and valid(board or token) and (mode=='Pick' or mode=='Drop'),'Ungültige Bildauswahl')
  local script=app.fs.joinPath(dir,'BoardFiles.vbs')
  assert(app.fs.isFile(script),'Bildauswahl-Helfer fehlt')
  local result=os.execute('wscript.exe //B //Nologo "'..script..'" '..mode..' '..token..' '..(board or token))
  assert(result==true or result==0,'Bildauswahl konnte nicht gestartet werden')
end
function M.read(token)
  local filename=path(token)
  if not app.fs.isFile(filename) then return end
  local file=assert(io.open(filename,'rb'));local raw=file:read(256*1024+1);file:close()
  assert(#raw<=256*1024,'Bildauswahl ist zu groß')
  local event=decode(raw)
  assert(type(event)=='table' and valid(event.id),'Ungültige Bildauswahl')
  if event.status=='ok' then
    assert(type(event.paths)=='table' and #event.paths>=1 and #event.paths<=32,'Zu viele Bilder')
    for _,name in ipairs(event.paths) do assert(type(name)=='string' and #name<=32767 and not name:find('%z'),'Ungültiger Bildpfad') end
  else assert(event.status=='cancel' or event.status=='error','Ungültiger Bildauswahl-Status') end
  os.remove(filename);return event
end
return M
