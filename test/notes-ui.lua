-- Disposable UI showcase and native interaction test; no user artwork.
local root=assert(app.params.root)
-- Defer to the native event loop: startup scripts otherwise request native
-- resources before the first editor window can show permission dialogs.
local launch
launch=Timer{interval=0.5,ontick=function()
launch:stop();print('Ideenwand test starting');io.stdout:flush()
local N=dofile(root..'/extension/notes.lua')
local UI=dofile(root..'/extension/notes-ui.lua')
local sprite=Sprite(32,32,ColorMode.RGB);sprite.filename='Hexe – Ideenwand-Test.aseprite'
local board=N.empty()
local weapon=N.newCard('','',20,20);weapon.text='Waffe';weapon.color='#E5DDF2'
local staff=N.newCard('',weapon.id);staff.text='Stab aus altem Eichenholz';staff.color='#E5DDF2'
local props=N.newCard('',staff.id);props.kind='list';props.listStyle='bullet';props.text='Farbe: Nachtblau\nSpitze: Mondstein\nGriff: Lederband';props.color='#E5DDF2'
local look=N.newCard('','',300,20);look.text='Aussehen';look.color='#F0D8DC'
local hair=N.newCard('',look.id);hair.text='Haare: silbern und lockig';hair.color='#F0D8DC'
local todo=N.newCard('',hair.id);todo.kind='list';todo.text='Silhouette zeichnen\nFarben abstimmen\nAnimation testen';todo.checks='100';todo.color='#D4E8DB'
board.cards={weapon,staff,props,look,hair,todo}
board.authors[weapon.id]={created='Mert',edited='Mert'}
board.authors[staff.id]={created='Mert',edited='Freundin'}
N.write(sprite,board)
local function safe(fn) local ok,err=xpcall(fn,debug.traceback);if not ok then print(err);io.stdout:flush();app.alert(tostring(err)) end end
local ui=UI.new(function() end,function() return false end,safe)
ui:show(sprite)
local timer=Timer{interval=0.033,ontick=function() safe(function() ui:tick() end) end};timer:start()
end};launch:start()
