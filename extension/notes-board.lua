-- Viewport geometry and atomic multi-element operations for the idea board.
local dir=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local N=dofile(app.fs.joinPath(dir,'notes.lua'))
local S=dofile(app.fs.joinPath(dir,'notes-stack.lua'))
local decode=dofile(app.fs.joinPath(dir,'json.lua')).decode
local B={}
local function clamp(v) return math.floor(math.max(-10000,math.min(10000,v))) end
local function ids(board,selection)
  local result={};for _,c in ipairs(board.cards) do if selection[c.id] then result[#result+1]=c.id end end
  return result
end
function B.fit(board,width,height)
  local boxes=S.layout(board)
  if #boxes==0 then return 1,24,56 end
  local minx,miny,maxx,maxy=1e6,1e6,-1e6,-1e6
  for _,b in ipairs(boxes) do
    minx=math.min(minx,b.x);miny=math.min(miny,b.y)
    maxx=math.max(maxx,b.x+b.w);maxy=math.max(maxy,b.y+b.h)
  end
  local left,right,top,bottom=18,18,46,36
  local z=math.max(0.01,math.min(1,(width-left-right)/(maxx-minx),(height-top-bottom)/(maxy-miny)))
  local view
  for _=1,10 do
    view=B.display(boxes,z,0,0)
    minx,miny,maxx,maxy=1e6,1e6,-1e6,-1e6
    for _,v in ipairs(view) do
      minx=math.min(minx,v.x);miny=math.min(miny,v.y)
      maxx=math.max(maxx,v.x+v.w);maxy=math.max(maxy,v.y+v.h)
    end
    local ratio=math.min((width-left-right)/(maxx-minx),(height-top-bottom)/(maxy-miny))
    if ratio>=0.999 or z<=0.01 then break end
    z=math.max(0.01,z*ratio)
  end
  view=B.display(boxes,z,0,0)
  minx,miny,maxx,maxy=1e6,1e6,-1e6,-1e6
  for _,v in ipairs(view) do
    minx=math.min(minx,v.x);miny=math.min(miny,v.y)
    maxx=math.max(maxx,v.x+v.w);maxy=math.max(maxy,v.y+v.h)
  end
  return z,(width-minx-maxx)/2,(top+height-bottom-miny-maxy)/2
end
function B.visualScale(zoom)
  -- Keep overview cards readable without reversing the wheel direction:
  -- their screen size must always grow (or stay equal) as zoom increases.
  -- The old 45%-75% branch had a negative slope, so 65% -> 56% enlarged
  -- every card even though the zoom indicator decreased.
  if zoom>=1 then return zoom end
  if zoom>=0.45 then return 0.8+(zoom-0.45)*(0.2/0.55) end
  return zoom*(0.8/0.45)
end
function B.display(boxes,zoom,ox,oy,moving)
  local scale=B.visualScale(zoom)
  local groups,byId,groupById={},{},{}
  for _,box in ipairs(boxes) do byId[box.card.id]=box end
  for _,box in ipairs(boxes) do
    local root=box.card
    while root.parent~='' and byId[root.parent] do root=byId[root.parent].card end
    local group=groupById[root.id]
    if not group then
      group={root=byId[root.id],cards={},minx=1e6,miny=1e6,maxx=-1e6,maxy=-1e6}
      groups[#groups+1]=group;groupById[root.id]=group
    end
    group.cards[#group.cards+1]=box
    group.minx=math.min(group.minx,box.x-group.root.x);group.miny=math.min(group.miny,box.y-group.root.y)
    group.maxx=math.max(group.maxx,box.x-group.root.x+box.w);group.maxy=math.max(group.maxy,box.y-group.root.y+box.h)
  end
  local order={};for _,group in ipairs(groups) do order[#order+1]=group end
  table.sort(order,function(a,b)
    if a.root.x~=b.root.x then return a.root.x<b.root.x end
    return a.root.y<b.root.y
  end)
  local placed={}
  for _,group in ipairs(order) do
    group.x=ox+group.root.x*zoom;group.y=oy+group.root.y*zoom
    local dragged=moving and moving[group.root.card.id]
    if scale>zoom and not dragged then
      local width=(group.maxx-group.minx)*scale;local height=(group.maxy-group.miny)*scale;local gap=8*scale
      for _,prior in ipairs(placed) do
        local gx,gy=group.x+group.minx*scale,group.y+group.miny*scale
        if gy<prior.y+prior.height+gap and gy+height+gap>prior.y and
           gx<prior.x+prior.width+gap and gx+width+gap>prior.x then
          group.x=prior.x+prior.width+gap-group.minx*scale
        end
      end
    end
    if not dragged then placed[#placed+1]={x=group.x+group.minx*scale,y=group.y+group.miny*scale,width=(group.maxx-group.minx)*scale,height=(group.maxy-group.miny)*scale} end
  end
  local result,map={},{}
  for _,group in ipairs(groups) do
    for _,box in ipairs(group.cards) do
      local v={box=box,x=group.x+(box.x-group.root.x)*scale,y=group.y+(box.y-group.root.y)*scale,w=box.w*scale,h=box.h*scale,scale=scale}
      result[#result+1]=v;map[box.card.id]=v
    end
  end
  return result,map
end
function B.target(board,boxes,drag,zoom,ox,oy)
  local moving={};for _,id in ipairs(S.tail(board,drag.id)) do moving[id]=true end
  local displays,map=B.display(boxes,zoom,ox,oy,moving)
  local source=map[drag.id];if not source then return nil end
  local best,distance
  for _,v in ipairs(displays) do
    if not moving[v.box.card.id] then
      local occupied=S.occupied(board,v.box.card,drag.id)
      for _,dock in ipairs({'below','left','right'}) do if not occupied[dock] then
        local x=dock=='left' and v.x-source.w-S.gap*v.scale or dock=='right' and v.x+v.w+S.gap*v.scale or v.x
        local y=dock=='below' and v.y+v.h+S.gap*v.scale or v.y
        local dx,dy=math.abs(x-source.x),math.abs(y-source.y)
        if dx<44*v.scale and dy<28*v.scale and (not distance or dx+dy<distance) then
          best={card=v.box.card,dock=dock,x=v.box.x,y=v.box.y,w=v.box.w,h=v.box.h,
            worldX=dock=='left' and v.box.x-source.box.w-S.gap or dock=='right' and v.box.x+v.box.w+S.gap or v.box.x,
            worldY=dock=='below' and v.box.y+v.box.h+S.gap or v.box.y,
            screenX=x,screenY=y};distance=dx+dy
        end
      end end
    end
  end
  return best
end
function B.selectDisplay(displays,x1,y1,x2,y2)
  local left,right=math.min(x1,x2),math.max(x1,x2)
  local top,bottom=math.min(y1,y2),math.max(y1,y2)
  local selected={}
  for _,v in ipairs(displays) do
    if v.x<right and v.x+v.w>left and v.y<bottom and v.y+v.h>top then selected[v.box.card.id]=true end
  end
  return selected
end
function B.select(boxes,ox,oy,zoom,x1,y1,x2,y2)
  local left,right=math.min(x1,x2),math.max(x1,x2)
  local top,bottom=math.min(y1,y2),math.max(y1,y2)
  local selected={}
  for _,b in ipairs(boxes) do
    local x,y=ox+b.x*zoom,oy+b.y*zoom
    if x<right and x+b.w*zoom>left and y<bottom and y+b.h*zoom>top then selected[b.card.id]=true end
  end
  return selected
end
function B.move(board,selection,dx,dy)
  local _,map=S.layout(board);local patches={}
  for _,id in ipairs(ids(board,selection)) do
    local card=N.card(board,id)
    -- The selected parent already carries this card and its attached tail.
    local ancestor=card.parent;local covered=false
    while ancestor~='' do
      if selection[ancestor] then covered=true;break end
      local parent=N.card(board,ancestor);ancestor=parent and parent.parent or ''
    end
    if not covered then
      local b=assert(map[id]);local operation=S.move(board,id,clamp(b.x+dx),clamp(b.y+dy))
      for _,patch in ipairs(operation.patches) do patches[#patches+1]=patch end
    end
  end
  return {action='patch',patches=patches}
end
function B.sort(board)
  local _,map=S.layout(board)
  local groups={}
  for _,root in ipairs(board.cards) do if root.parent=='' then
    local group={root=root,minx=1e6,miny=1e6,maxx=-1e6,maxy=-1e6}
    for _,id in ipairs(S.tail(board,root.id)) do
      local b=assert(map[id]);group.minx=math.min(group.minx,b.x);group.miny=math.min(group.miny,b.y)
      group.maxx=math.max(group.maxx,b.x+b.w);group.maxy=math.max(group.maxy,b.y+b.h)
    end
    group.w=group.maxx-group.minx;group.h=group.maxy-group.miny
    group.cx=(group.minx+group.maxx)/2;group.cy=(group.miny+group.maxy)/2
    groups[#groups+1]=group
  end end
  if #groups<2 then return {action='patch',patches={}} end
  -- Walk nearest neighbours so stacks that were close remain adjacent when
  -- the whole wall is compacted into a roughly square, serpentine grid.
  local order,used={},{}
  local function closest(previous)
    local best,distance
    for _,g in ipairs(groups) do if not used[g.root.id] then
      local d=previous and ((g.cx-previous.cx)^2+(g.cy-previous.cy)^2) or (g.cx+g.cy)*100000+g.cx
      if not best or d<distance or (d==distance and g.root.id<best.root.id) then best=g;distance=d end
    end end
    return best
  end
  while #order<#groups do local g=closest(order[#order]);used[g.root.id]=true;order[#order+1]=g end
  local bestLayout,bestScore
  local gap=12
  for cols=1,#groups do
    local rows=math.ceil(#groups/cols)
    local widths,heights,slots={}, {}, {}
    for i,g in ipairs(order) do
      local row=math.floor((i-1)/cols)+1
      local column=(row%2==1) and ((i-1)%cols+1) or (cols-(i-1)%cols)
      slots[i]={row=row,column=column}
      widths[column]=math.max(widths[column] or 0,g.w)
      heights[row]=math.max(heights[row] or 0,g.h)
    end
    local w,h=(cols-1)*gap,(rows-1)*gap
    for column=1,cols do w=w+(widths[column] or 0) end
    for row=1,rows do h=h+(heights[row] or 0) end
    local score=math.abs(math.log(w/h))+(cols*rows-#groups)*0.08
    if not bestScore or score<bestScore then bestScore=score;bestLayout={cols=cols,rows=rows,widths=widths,heights=heights,slots=slots} end
  end
  local startX,startY=1e6,1e6
  for _,g in ipairs(groups) do startX=math.min(startX,g.minx);startY=math.min(startY,g.miny) end
  local xs,ys={},{}
  local pos=startX
  for column=1,bestLayout.cols do xs[column]=pos;pos=pos+(bestLayout.widths[column] or 0)+gap end
  pos=startY
  for row=1,bestLayout.rows do ys[row]=pos;pos=pos+(bestLayout.heights[row] or 0)+gap end
  local patches={}
  for i,g in ipairs(order) do
    local slot=bestLayout.slots[i]
    local x=math.floor(xs[slot.column]-(g.minx-g.root.x))
    local y=math.floor(ys[slot.row]-(g.miny-g.root.y))
    assert(N.field('x',x) and N.field('y',y),'Ideenwand ist für automatisches Sortieren zu groß.')
    if x~=g.root.x or y~=g.root.y then
      patches[#patches+1]=N.patch(g.root,'x',x)
      patches[#patches+1]=N.patch(g.root,'y',y)
      patches[#patches+1]=N.patch(g.root,'parent','') -- reject a concurrent reattachment
    end
  end
  return {action='patch',patches=patches}
end
function B.delete(board,selection)
  local patches={}
  for _,id in ipairs(ids(board,selection)) do
    local c=N.card(board,id);patches[#patches+1]={id=id,expected=N.copy(c),value=false}
  end
  for _,c in ipairs(board.cards) do if not selection[c.id] and selection[c.parent] then
    patches[#patches+1]=N.patch(c,'parent','')
  end end
  return {action='patch',patches=patches}
end
function B.copy(board,selection)
  local _,map=S.layout(board);local chosen=ids(board,selection)
  assert(#chosen>0,'Keine Elemente ausgewählt.')
  local index={};for i,id in ipairs(chosen) do index[id]=i end
  local minx,miny=1e6,1e6
  for _,id in ipairs(chosen) do minx=math.min(minx,map[id].x);miny=math.min(miny,map[id].y) end
  local elements={}
  for _,id in ipairs(chosen) do
    local c=N.card(board,id);local b=map[id]
    elements[#elements+1]={kind=c.kind,title=c.title,text=c.text,listStyle=c.listStyle,
      checks=c.checks,image=c.image,color=c.color,status=c.status,tag=c.tag,tagStart=c.tagStart,frame=c.frame,
      x=b.x-minx,y=b.y-miny,parent=index[c.parent] or 0,dock=c.dock}
  end
  return json.encode({collabsprite='idea-board-elements-v2',elements=elements})
end
function B.copyTail(board,id)
  local selection={};for _,tail in ipairs(S.tail(board,id)) do selection[tail]=true end
  return B.copy(board,selection)
end
function B.paste(board,contents,x,y)
  assert(type(contents)=='string' and #contents<=N.bytes+4096,'Zwischenablage zu groß.')
  local payload=decode(contents)
  assert(type(payload)=='table' and (payload.collabsprite=='idea-board-elements-v1' or payload.collabsprite=='idea-board-elements-v2') and
    type(payload.elements)=='table' and #payload.elements>0 and #payload.elements<=128,'Keine Collabsprite-Elemente.')
  assert(#board.cards+#payload.elements<=128,'Höchstens 128 Elemente.')
  local created,patches={},{}
  for i,e in ipairs(payload.elements) do
    assert(type(e)=='table' and type(e.parent)=='number' and e.parent%1==0 and
      e.parent>=0 and e.parent<=#payload.elements and e.parent~=i,'Ungültiger Elementstapel.')
    assert(N.field('title',e.title) and N.field('x',e.x) and N.field('y',e.y),'Ungültiger Elementinhalt.')
    local c=N.newCard(e.title,'',clamp(x+e.x),clamp(y+e.y))
    for _,field in ipairs({'kind','text','listStyle','checks','image','color','status','tag','tagStart','frame'}) do
      if field=='tag' and e[field]==nil then e[field]='' end
      if field=='tagStart' and e[field]==nil then e[field]=0 end
      if field=='frame' and e[field]==nil then e[field]=e.tagStart or 0 end
      assert(N.field(field,e[field]),'Ungültiges kopiertes Element.')
      c[field]=N.copy(e[field])
    end
    c.dock=e.dock or 'below';assert(N.field('dock',c.dock),'Ungültige Elementverbindung.')
    created[i]=c
  end
  for i,e in ipairs(payload.elements) do
    local c=created[i];if e.parent~=0 then c.parent=created[e.parent].id end
    patches[#patches+1]={id=c.id,expected=false,value=c}
  end
  local operation={action='patch',patches=patches}
  -- Reject invalid clipboard topology, dimensions, size and other fields before
  -- sending any part of the group to the shared server.
  N.commit(board,patches)
  return operation,created
end
return B
