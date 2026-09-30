-- Optional visible smoke test; never opens or saves a user image.
local root=assert(app.params.root)
local N=dofile(root..'/extension/notes.lua')
local UI=dofile(root..'/extension/notes-ui.lua')
local sprite=Sprite(16,16,ColorMode.RGB)
local board=N.empty()
local title=N.newCard('','',20,20);title.text='Hexe'
local child=N.newCard('',title.id);child.kind='list';child.text='Besen\nKleid'
board.cards={title,child};N.write(sprite,board)
local ui=UI.new(function() return nil end,function() return false end,function(fn) fn() end)
ui:show(sprite)
local state=ui:state(sprite)
local timer
timer=Timer{interval=1,ontick=function()
  timer:stop()
  print('GUI_BOARD_PASS='..tostring(state.dialog~=nil and #(state.hits or {})>=7))
  io.stdout:flush()
  ui:close();sprite:close();app.exit()
end}
timer:start()
state.dialog:show{wait=true}
