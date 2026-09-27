-- The actual UI renderer on Aseprite's graphics context, with disposable data.
local root=assert(app.params.root)
local N=dofile(root..'/extension/notes.lua')
local UI=dofile(root..'/extension/notes-ui.lua')
local I=dofile(root..'/extension/notes-image.lua')
local sprite=Sprite(8,8,ColorMode.RGB);local b=N.empty()
local function add(text,parent,x,y,color,kind,style)
  local c=N.newCard('',parent,x,y);c.text=text;c.color=color;c.kind=kind or 'text';c.listStyle=style or 'check';b.cards[#b.cards+1]=c;return c
end
local a=add('Waffe','',24,24,'#E5DDF2')
local a2=add('Stab aus altem Eichenholz',a.id,0,0,'#E5DDF2')
add('Farbe: Nachtblau\nSpitze: Mondstein\nGriff: weiches Leder',a2.id,0,0,'#E5DDF2','list','bullet')
local c=add('Aussehen','',304,24,'#F0D8DC')
local c2=add('Haare: silbern und lockig',c.id,0,0,'#F0D8DC')
local c3=add('Silhouette zeichnen\nFarben abstimmen\nAnimation testen',c2.id,0,0,'#D4E8DB','list');c3.checks='100'
local ref=add('','',584,24,'#D6E4F4','image');ref.image=I.load(root..'/branding/collabsprite-icon-512.png')
add('Referenz: unser gemeinsames Projekt',ref.id,0,0,'#D6E4F4')
N.write(sprite,b)
local ui=UI.new(function() end,function() return false end,function(fn) fn() end)
local s=ui:state(sprite);ui:prepare(s)
local image=Image(852,355,ColorMode.RGB);s.width=image.width;s.height=image.height;ui:fit(s);ui:paint(s,{context=image.context})
image:saveAs(root..'/test-results/notes-magnetic-showcase.png')
sprite:close();print('PASS native idea-board showcase rendered');io.stdout:flush();app.exit()
