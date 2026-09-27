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
  -- Semantic zoom: 45% moves the cards closer together, but their text stays
  -- near normal screen size. Below 45% the cards can shrink again so fitting
  -- a very large board remains possible.
  if zoom>=0.75 then return zoom end
  if zoom>=0.45 then return 0.75+(0.75-zoom)*0.5 end
  return zoom*2
end
function B.display(boxes,zoom,ox,oy,moving)
  local scale=B.visualScale(zoom)
  local groups,last={},nil
  for _,box in ipairs(boxes) do
    if not last or box.card.parent~=last.card.id then
      groups[#groups+1]={root=box,cards={},height=0}
    end
    local group=groups[#groups]
    group.cards[#group.cards+1]=box
    group.height=group.height+(#group.cards>1 and S.gap*scale or 0)+box.h*scale
    last=box
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
      local width=group.root.w*scale;local gap=8*scale
      for _,prior in ipairs(placed) do
        if group.y<prior.y+prior.height+gap and group.y+group.height+gap>prior.y and
           group.x<prior.x+prior.width+gap and group.x+width+gap>prior.x then
          group.x=prior.x+prior.width+gap
        end
      end
    end
    if not dragged then placed[#placed+1]={x=group.x,y=group.y,width=group.root.w*scale,height=group.height} end
  end
  local result,map={},{}
  for _,group in ipairs(groups) do
    local y=group.y
    for _,box in ipairs(group.cards) do
      local v={box=box,x=group.x,y=y,w=box.w*scale,h=box.h*scale,scale=scale}
      result[#result+1]=v;map[box.card.id]=v
      y=y+v.h+S.gap*scale
    end
  end
  return result,map
end
function B.target(board,boxes,drag,zoom,ox,oy)
  local moving={};for _,id in ipairs(S.tail(board,drag.id)) do moving[id]=true end
  local displays,map=B.display(boxes,zoom,ox,oy,moving)
  local source=map[drag.id];if not source then return nil end
  local hasChild={};for _,c in ipairs(board.cards) do if c.id~=drag.id then hasChild[c.parent]=true end end
  local best,distance
  for _,v in ipairs(displays) do
    if not moving[v.box.card.id] and not hasChild[v.box.card.id] then
      local dx=math.abs(v.x-source.x)
      local dy=math.abs(v.y+v.h+S.gap*v.scale-source.y)
      if dx<44*v.scale and dy<28*v.scale and (not distance or dx+dy<distance) then
        best=v.box;distance=dx+dy
      end
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
function B.delete(board,selection)
  local patches={}
  for _,id in ipairs(ids(board,selection)) do
    local c=N.card(board,id);patches[#patches+1]={id=id,expected=N.copy(c),value=false}
  end
  for _,c in ipairs(board.cards) do if not selection[c.id] and selection[c.parent] then
    local parent=c.parent
    while selection[parent] do parent=N.card(board,parent).parent end
    patches[#patches+1]=N.patch(c,'parent',parent)
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
      checks=c.checks,image=c.image,color=c.color,status=c.status,
      x=b.x-minx,y=b.y-miny,parent=index[c.parent] or 0}
  end
  return json.encode({collabsprite='idea-board-elements-v1',elements=elements})
end
function B.copyTail(board,id)
  local selection={};for _,tail in ipairs(S.tail(board,id)) do selection[tail]=true end
  return B.copy(board,selection)
end
function B.paste(board,contents,x,y)
  assert(type(contents)=='string' and #contents<=N.bytes+4096,'Zwischenablage zu groß.')
  local payload=decode(contents)
  assert(type(payload)=='table' and payload.collabsprite=='idea-board-elements-v1' and
    type(payload.elements)=='table' and #payload.elements>0 and #payload.elements<=128,'Keine Collabsprite-Elemente.')
  assert(#board.cards+#payload.elements<=128,'Höchstens 128 Elemente.')
  local created,patches={},{}
  for i,e in ipairs(payload.elements) do
    assert(type(e)=='table' and type(e.parent)=='number' and e.parent%1==0 and
      e.parent>=0 and e.parent<=#payload.elements and e.parent~=i,'Ungültiger Elementstapel.')
    assert(N.field('title',e.title) and N.field('x',e.x) and N.field('y',e.y),'Ungültiger Elementinhalt.')
    local c=N.newCard(e.title,'',clamp(x+e.x),clamp(y+e.y))
    for _,field in ipairs({'kind','text','listStyle','checks','image','color','status'}) do
      assert(N.field(field,e[field]),'Ungültiges kopiertes Element.')
      c[field]=N.copy(e[field])
    end
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
