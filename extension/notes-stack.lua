-- Pure stack geometry and optimistic, atomic drag operations.
local dir=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local N=dofile(app.fs.joinPath(dir,'notes.lua'))
local T=dofile(app.fs.joinPath(dir,'notes-input.lua'))
local F=dofile(app.fs.joinPath(dir,'notes-style.lua'))
local S={width=244,gap=7}
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
  for _,c in ipairs(board.cards) do children[c.parent]=c.id end
  while id do result[#result+1]=id;id=children[id];assert(#result<=128,'Ungültiger Stapel') end
  return result
end
function S.layout(board,inline,drag)
  local children,boxes,byId={}, {},{}
  for _,c in ipairs(board.cards) do children[c.parent]=c end
  local function chain(root,x,y)
    local c=root;local top=true
    while c do
      if drag and drag.moved and c.id==drag.id and root.id~=drag.id then break end
      local heading=c.kind=='text' and top
      local text=inline and inline.id==c.id and inline.value or S.text(c)
      local rows=S.lines(text,heading,S.width-32-(c.kind=='list' and 24 or 0))
      local lineHeight=heading and 29 or 20
      local h=c.kind=='image' and 28+math.min(260,(S.width-24)*c.image.height/c.image.width) or math.max(58,28+#rows*lineHeight)
      local box={card=c,x=x,y=y,w=S.width,h=math.ceil(h),heading=heading,rows=rows,lineHeight=lineHeight}
      boxes[#boxes+1]=box;byId[c.id]=box;y=y+box.h+S.gap;top=false;c=children[c.id]
    end
  end
  for _,c in ipairs(board.cards) do if c.parent=='' and not (drag and drag.moved and c.id==drag.id) then chain(c,c.x,c.y) end end
  if drag and drag.moved then chain(assert(N.card(board,drag.id)),drag.x,drag.y) end
  return boxes,byId
end
function S.target(board,boxes,drag)
  local moving={};for _,id in ipairs(S.tail(board,drag.id)) do moving[id]=true end
  local hasChild={};for _,c in ipairs(board.cards) do if c.id~=drag.id then hasChild[c.parent]=true end end
  local best,distance
  for _,box in ipairs(boxes) do if not moving[box.card.id] and not hasChild[box.card.id] then
    local dx=math.abs(box.x-drag.x);local dy=math.abs(box.y+box.h+S.gap-drag.y)
    if dx<44 and dy<28 and (not distance or dx+dy<distance) then best=box;distance=dx+dy end
  end end
  return best
end
function S.move(board,id,x,y,target)
  local c=assert(N.card(board,id));local patches={N.patch(c,'x',math.floor(math.max(-10000,math.min(10000,x)))),N.patch(c,'y',math.floor(math.max(-10000,math.min(10000,y)))),N.patch(c,'parent',target or '')}
  -- Guard all tail links and the destination against concurrent rearrangement.
  for _,tail in ipairs(S.tail(board,id)) do if tail~=id then local v=N.card(board,tail);patches[#patches+1]=N.patch(v,'parent',v.parent) end end
  if target then local v=assert(N.card(board,target));patches[#patches+1]=N.patch(v,'parent',v.parent) end
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
