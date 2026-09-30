-- Pure stack geometry and optimistic, atomic drag operations.
local dir=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local N=dofile(app.fs.joinPath(dir,'notes.lua'))
local T=dofile(app.fs.joinPath(dir,'notes-input.lua'))
local F=dofile(app.fs.joinPath(dir,'notes-style.lua'))
local S={width=140,gap=3,animationWidth=176,animationHeight=210,paperHeight=154}
function S.occupied(board,c,ignoreId)
  local occupied={}
  if c.parent~='' then
    if c.dock=='left' then occupied.right=true
    elseif c.dock=='right' then occupied.left=true end
  end
  for _,child in ipairs(board.cards) do if child.id~=ignoreId and child.parent==c.id then occupied[child.dock]=true end end
  return occupied
end
function S.text(c) return c.title~='' and (c.title..(c.text~='' and '\n'..c.text or '')) or c.text end
function S.lines(text,heading,width)
  local rows,start,index={},0,1
  for line in (text..'\n'):gmatch('(.-)\n') do
    local current,offset='',start
    for _,cp in utf8.codes(line) do
      local ch=utf8.char(cp)
      if current~='' and F.measure(current..ch,heading)>width then
        local space=current:match('^.*()%s')
        local shown=space and space>1 and current:sub(1,space-1) or current
        rows[#rows+1]={text=shown,start=offset,index=index,first=offset==start}
        if space and space>1 then offset=offset+T.length(shown)+1;current=current:sub(space+1)
        else offset=offset+T.length(current);current='' end
      end
      current=current..ch
    end
    rows[#rows+1]={text=current,start=offset,index=index,first=offset==start}
    start=start+T.length(line)+1;index=index+1
  end
  return rows
end
function S.tail(board,id)
  local children,result={},{}
  for _,c in ipairs(board.cards) do
    children[c.parent]=children[c.parent] or {};children[c.parent][#children[c.parent]+1]=c.id
  end
  local function walk(current)
    result[#result+1]=current;assert(#result<=128,'Ungültiger Stapel')
    for _,child in ipairs(children[current] or {}) do walk(child) end
  end
  walk(id)
  return result
end
function S.layout(board,inline,drag)
  local children,boxes,byId={},{},{}
  for _,c in ipairs(board.cards) do
    if not (drag and drag.moved and c.id==drag.id) then
      children[c.parent]=children[c.parent] or {};children[c.parent][c.dock or 'below']=c
    end
  end
  local function tree(c,top)
    local heading=c.kind=='text' and top
    local value=inline and inline.id==c.id and inline.value or S.text(c)
    local rows=S.lines(value,heading,S.width-28)
    local lineHeight=heading and 27 or 14
    local h=c.kind=='image' and 28+math.min(112,(S.width-16)*c.image.height/c.image.width) or c.kind=='animation' and S.animationHeight or c.kind=='paper' and S.paperHeight or math.max(42,24+#rows*lineHeight)
    local width=c.kind=='animation' and S.animationWidth or S.width
    local box={card=c,x=0,y=0,w=width,h=math.ceil(h),heading=heading,rows=rows,lineHeight=lineHeight}
    local shape={boxes={box},minx=0,miny=0,maxx=width,maxy=box.h}
    local function append(child,dx,dy)
      for _,b in ipairs(child.boxes) do b.x=b.x+dx;b.y=b.y+dy;shape.boxes[#shape.boxes+1]=b end
      shape.minx=math.min(shape.minx,child.minx+dx);shape.miny=math.min(shape.miny,child.miny+dy)
      shape.maxx=math.max(shape.maxx,child.maxx+dx);shape.maxy=math.max(shape.maxy,child.maxy+dy)
    end
    local links=children[c.id] or {}
    if links.left then local child=tree(links.left,false);append(child,-S.gap-child.maxx,-child.miny) end
    if links.right then local child=tree(links.right,false);append(child,width+S.gap-child.minx,-child.miny) end
    if links.below then local child=tree(links.below,false);append(child,0,shape.maxy+S.gap-child.miny) end
    return shape
  end
  local function place(root,x,y)
    local shape=tree(root,true)
    for _,b in ipairs(shape.boxes) do b.x=b.x+x;b.y=b.y+y;boxes[#boxes+1]=b;byId[b.card.id]=b end
  end
  for _,c in ipairs(board.cards) do if c.parent=='' and not (drag and drag.moved and c.id==drag.id) then place(c,c.x,c.y) end end
  if drag and drag.moved then
    -- The dragged branch is temporarily a root for display and hit testing.
    -- Keep the stored parent unchanged until the drop is committed.
    local source=assert(N.card(board,drag.id))
    place(setmetatable({parent=''},{__index=source}),drag.x,drag.y)
  end
  return boxes,byId
end
function S.rowPosition(box,index,text)
  local row=box.rows[index]
  local width=F.measure(text or row.text,box.heading)
  -- Plain text is centered; list rows always start at the same left inset.
  local x=(box.w-width)/2
  if box.card.kind=='list' then x=22 end
  local y=(box.h-(#box.rows-1)*box.lineHeight)/2-F.inkCenter(box.heading)+(index-1)*box.lineHeight
  return x,y
end
function S.target(board,boxes,drag)
  local moving={};for _,id in ipairs(S.tail(board,drag.id)) do moving[id]=true end
  local _,byId=S.layout(board);local sourceWidth=byId[drag.id].w
  local best,distance
  for _,box in ipairs(boxes) do if not moving[box.card.id] then
    local occupied=S.occupied(board,box.card,drag.id)
    for _,dock in ipairs({'below','left','right'}) do if not occupied[dock] then
      local x=dock=='left' and box.x-sourceWidth-S.gap or dock=='right' and box.x+box.w+S.gap or box.x
      local y=dock=='below' and box.y+box.h+S.gap or box.y
      local dx,dy=math.abs(x-drag.x),math.abs(y-drag.y)
      if dx<44 and dy<28 and (not distance or dx+dy<distance) then best={card=box.card,dock=dock,x=x,y=y};distance=dx+dy end
    end end
  end end
  return best
end
function S.move(board,id,x,y,target,dock)
  local c=assert(N.card(board,id));dock=target and (dock or 'below') or 'below'
  assert(not target or (target~=id and N.card(board,target)),'Ungültiges Ziel')
  assert(not target or not S.occupied(board,N.card(board,target),id)[dock],'Diese Seite ist bereits belegt')
  local descendants={};for _,tail in ipairs(S.tail(board,id)) do descendants[tail]=true end
  assert(not target or not descendants[target],'Element kann nicht an sich selbst hängen')
  for _,other in ipairs(board.cards) do
    assert(not target or other.id==id or other.parent~=target or other.dock~=dock,'Diese Seite ist bereits belegt')
  end
  local patches={N.patch(c,'x',math.floor(math.max(-10000,math.min(10000,x)))),N.patch(c,'y',math.floor(math.max(-10000,math.min(10000,y)))),N.patch(c,'parent',target or ''),N.patch(c,'dock',dock)}
  -- Guard all tail links and the destination against concurrent rearrangement.
  for _,tail in ipairs(S.tail(board,id)) do if tail~=id then local v=N.card(board,tail);patches[#patches+1]=N.patch(v,'parent',v.parent);patches[#patches+1]=N.patch(v,'dock',v.dock) end end
  if target then local v=assert(N.card(board,target));patches[#patches+1]=N.patch(v,'parent',v.parent);patches[#patches+1]=N.patch(v,'dock',v.dock) end
  return {action='patch',patches=patches}
end
function S.checks(old,text)
  -- Preserve unchanged prefix/suffix rows, never move a tick onto a new item.
  local function split(s) local r={};for line in (s..'\n'):gmatch('(.-)\n') do r[#r+1]=line end;return r end
  local a,b=split(old.text),split(text);local checks={};for i=1,#b do checks[i]='0' end
  local first=1;while first<=math.min(#a,#b) and a[first]==b[first] do checks[first]=old.checks:sub(first,first)=='1' and '1' or '0';first=first+1 end
  local i,j=#a,#b;while i>=first and j>=first and a[i]==b[j] do checks[j]=old.checks:sub(i,i)=='1' and '1' or '0';i=i-1;j=j-1 end
  return table.concat(checks)
end
return S
