-- Interactive isolated proof, with no user sprite or regular installation.
local root=assert(app.params.root)
local N=dofile(root..'/extension/notes.lua')
local P=dofile(root..'/extension/notes-paper.lua')
local UI=dofile(root..'/extension/notes-ui.lua')
local files=dofile(root..'/extension/board-files.lua')
local sprite=Sprite(16,16,ColorMode.RGB)
sprite.filename='Collabsprite Vorschau-Test'
local source=Image(1000,1000,ColorMode.RGB)
P.stroke(source,130,140,810,850,5,Color{r=40,g=100,b=190,a=255})
P.stroke(source,180,720,770,170,20,Color{r=180,g=65,b=60,a=255})
local c=N.newCard('','',0,0);c.kind='paper';c.image=P.pack(source)
local board=N.empty();board.cards={c};N.write(sprite,board)
local ui=UI.new(function() end,function() return false end,function(fn)
  local ok,err=pcall(fn);if not ok then print('PROBE_ERROR '..tostring(err));io.stdout:flush() end
end,nil,function(token)
  os.execute('wscript.exe //B //Nologo "'..root..'/extension/Window.vbs" '..token)
end,files)
ui:show(sprite)
local s=ui:state(sprite);s.ox=12;s.oy=78
local tick=Timer{interval=0.033,ontick=function() ui:tick() end};tick:start()
local quit=Timer{interval=180,ontick=function() tick:stop();ui:close();sprite:close();app.exit() end};quit:start()
print('GUI_PREVIEW_READY '..s.windowToken);io.stdout:flush()
if app.params.ready then local out=assert(io.open(app.params.ready,'w'));out:write(s.windowToken);out:close() end
-- Return to Aseprite's normal loop; re-showing as modal would fold this
-- independent board into the main window and invalidate the drop target.
