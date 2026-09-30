-- Bounds, centered text/caret, compact menus and checklist hit ordering.
local root=assert(app.params.root)
for _,scale in ipairs({1,2,3}) do
  for _,size in ipairs({{640,480},{1280,720},{2880,1648}}) do
    local fake={window={width=size[1],height=size[2]},uiScale=scale}
    local L=assert(loadfile(root..'/extension/ui-layout.lua','t',setmetatable({app=fake},{__index=_G})))()
    local w,h=L.canvas(740,490)
    assert(w<size[1]*0.75 and h<size[2]*0.75,'Canvas depends on UI magnification')
    local b=L.bounds(5000,4000)
    assert(b.width<=size[1]*0.76 and b.height<=size[2]*0.76 and b.x>=0 and b.y>=0)
    local dlg={sizeHint={width=5000,height=4000},show=function(self,v) self.shown=v end}
    L.show(dlg);assert(dlg.shown.autoscrollbars and not dlg.shown.wait)
    dlg.bounds=dlg.shown.bounds;dlg.sizeHint={width=0,height=0}
    L.fit(dlg);assert(dlg.bounds.width==dlg.shown.bounds.width and dlg.bounds.height==dlg.shown.bounds.height,'Native scrolling-view hint collapsed dialog')
    assert(L.short('äöüABCDE',5)=='äöüA…','UTF-8 truncation')
    assert(table.concat(L.lines('Härtegrad\nblau',4),'|')=='Härt|egra|d|blau')
  end
end
local N=dofile(root..'/extension/notes.lua')
local S=dofile(root..'/extension/notes-stack.lua')
local F=dofile(root..'/extension/notes-style.lua')
local UI=dofile(root..'/extension/notes-ui.lua')
local sprite=Sprite(8,8,ColorMode.RGB);local board=N.empty()
local a=N.newCard('','',20,20);a.text='Haare\nNachtblau'
local b=N.newCard('',a.id);b.kind='list';b.text='Kurz\nEin längerer Eintrag, der über mehrere Zeilen geht';b.checks='00'
board.cards={a,b};N.write(sprite,board)
local ui=UI.new(function() end,function() return false end,function(fn) fn() end)
local s=ui:state(sprite);ui:prepare(s)
local boxes=S.layout(board)
assert(boxes[1].heading and not boxes[2].heading)
assert(F.measure('Hexe',true)>F.measure('Hexe',false)*1.2 and boxes[1].lineHeight>boxes[2].lineHeight,'Main title is not larger')
for i,row in ipairs(boxes[1].rows) do
  local x,y=S.rowPosition(boxes[1],i)
  assert(math.abs(x+F.measure(row.text,true)/2-boxes[1].w/2)<0.01,'Text not horizontally centered')
  if i==1 then assert(math.abs(y+F.inkCenter(true)+( #boxes[1].rows-1)*boxes[1].lineHeight/2-boxes[1].h/2)<0.01,'Text not vertically centered') end
end
local image=Image(640,430,ColorMode.RGB)
ui:edit(s,a.id);ui:paint(s,{context=image.context})
for _,row in ipairs(s.inline.draw.lines) do
  ui:placeCaret(s.inline,row.r.x+row.widths[2],row.r.y+5);assert(s.inline.cursor==row.start+2,'Centered caret mapping')
end
ui:finishInline(s);ui:paint(s,{context=image.context})
local count=0
for _,hit in ipairs(s.hits) do if hit.kind=='check' then
  local id,target=ui:hit(s,hit.r.x+3,hit.r.y+3)
  assert(id==b.id and target.kind=='check','Text intercepts checkbox click');count=count+1
end end
assert(count==2,'Wrapped row duplicated a checkbox')
for _,id in ipairs({'',a.id,b.id}) do
  ui:menu(s,id~='' and id or nil,630,420)
  ui:paint(s,{context=image.context})
  assert(#s.menu.items<=8 and s.menu.x+s.menu.w<=640 and s.menu.y+s.menu.visible*17+10<=430,'Oversized context menu')
end
ui:menu(s,nil,630,420);assert(#s.menu.items==4 and s.menu.items[1].label=='Einfügen' and s.menu.items[2].label=='Sortieren' and s.menu.items[3].label=='Undo' and s.menu.items[4].label=='Redo')
ui:menu(s,a.id,630,420);assert(#s.menu.items==5 and s.menu.items[1].label=='Löschen' and s.menu.items[3].label=='Ausschneiden' and s.menu.items[5].colors)
ui:paint(s,{context=image.context})
local swatches=0;for _,target in ipairs(s.hits) do if target.kind=='color' then swatches=swatches+1 end end
assert(swatches==#F.colors,'Pastel colors are not visible directly on the right-click menu')
local small=Image(260,82,ColorMode.RGB)
ui:menu(s,b.id,255,76);ui:paint(s,{context=small.context})
assert(s.menu.visible<#s.menu.items and s.menu.y+s.menu.visible*17+10<=82,'Small canvas menu cannot scroll')
s.menu=nil;s.zoom=1.65;ui:paint(s,{context=image.context})
local toolbar,fit=0,0
for _,target in ipairs(s.hits) do if target.kind=='tool' then toolbar=toolbar+1 elseif target.kind=='fit' then fit=fit+1 end end
assert(toolbar==7 and fit==0,'Native tool/history islands changed unexpectedly')
local animationTool=false;for _,target in ipairs(s.hits) do if target.kind=='tool' and target.extra.index==5 then animationTool=true end end
assert(animationTool,'Animation selector is missing from the toolbar')
image:saveAs(root..'/test-results/notes-type-165.png')
s.zoom=0.45;ui:paint(s,{context=image.context})
image:saveAs(root..'/test-results/notes-type-45.png')
ui:toggle(s,b.id,1);assert(N.card(s.board,b.id).checks:sub(1,1)=='1','Checklist toggle failed')
ui:paint(s,{context=image.context})
image:saveAs(root..'/test-results/notes-check-45.png')
ui:menu(s,b.id,208,145);ui:paint(s,{context=image.context})
image:saveAs(root..'/test-results/notes-color-menu.png')
sprite:close();print('PASS adaptive popup bounds at UI scales 1/2/3, centered text/caret, compact menus and checkbox targets')
io.stdout:flush();app.exit()
