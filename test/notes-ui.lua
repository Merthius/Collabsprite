-- Disposable UI showcase and native interaction test; no user artwork.
local root=assert(app.params.root)
local N=dofile(root..'/extension/notes.lua')
local UI=dofile(root..'/extension/notes-ui.lua')
local sprite=Sprite(32,32,ColorMode.RGB);sprite.filename='Collabsprite – Ideenwand-Test.aseprite'
local board=N.empty()
local witch=N.newCard('Hexe','',20,130)
local clothes=N.newCard('Kleidung',witch.id,225,35)
local dress=N.newCard('Kleid',clothes.id,430,35);dress.text='Flicken und ausgefranster Saum';dress.color='#5E3A79';dress.status='decided'
local tool=N.newCard('Waffe / Werkzeug',witch.id,225,225)
local broom=N.newCard('Besen',tool.id,430,225);broom.text='Krummes Holz · leuchtet beim Fliegen'
board.cards={witch,clothes,dress,tool,broom};N.write(sprite,board)
local function safe(fn) local ok,err=xpcall(fn,debug.traceback);if not ok then print(err);io.stdout:flush();app.alert(tostring(err)) end end
local ui=UI.new(function() end,function() return false end,safe)
ui:show(sprite)
local timer=Timer{interval=0.033,ontick=function() safe(function() ui:tick() end) end};timer:start()
