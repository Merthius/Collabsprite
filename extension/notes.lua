-- File storage and bounded local editing. No network, UI or private text logs.
local dir=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local decode=dofile(app.fs.joinPath(dir,'json.lua')).decode
local N={key='Merthius/Collabsprite',bytes=8*1024*1024,fields={'title','text','parent','x','y','color','status','kind','listStyle','checks','image'}}
function N.empty() return {format=2,revision=0,cards={},trash={}} end
function N.copy(v)
  if type(v)~='table' then return v end
  local r={};for k,x in pairs(v) do r[k]=N.copy(x) end;return r
end
function N.equal(a,b)
  if type(a)~=type(b) then return false end
  if type(a)~='table' then return a==b end
  for k,v in pairs(a) do if not N.equal(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end;return true
end
local function integer(v,lo,hi) return type(v)=='number' and v%1==0 and v>=lo and v<=hi end
local function id(v) return type(v)=='string' and #v==32 and v:match('^[a-f0-9]+$') end
function N.uid() return tostring(Uuid()):gsub('-',''):lower() end
function N.field(f,v)
  if f=='title' or f=='text' then return type(v)=='string' and #v<=(f=='title' and 120 or 4096) and not v:find('[%z\1-\8\11-\31]') end
  if f=='parent' then return v=='' or id(v) end
  if f=='x' or f=='y' then return integer(v,-10000,10000) end
  if f=='color' then return type(v)=='string' and (v=='' or (#v==7 and v:match('^#%x+$'))) end
  if f=='status' then return v=='idea' or v=='decided' or v=='done' end
  if f=='kind' then return v=='text' or v=='list' or v=='image' end
  if f=='listStyle' then return v=='check' or v=='bullet' or v=='number' end
  if f=='checks' then return type(v)=='string' and #v<=128 and not v:find('[^01]') end
  if f=='image' then
    if v==false then return true end
    if type(v)~='table' or not integer(v.width,1,512) or not integer(v.height,1,512) or type(v.pixels)~='string' then return false end
    local count=0;for _ in pairs(v) do count=count+1 end
    return count==3 and #v.pixels==v.width*v.height*8 and not v.pixels:find('[^a-f0-9]')
  end
  return false
end
function N.migrate(b)
  b=N.copy(b)
  local groups={b.cards};for _,t in ipairs(b.trash or {}) do groups[#groups+1]=t.cards end
  for _,cards in ipairs(groups) do
    assert(type(cards)=='table' and #cards<=128,'Ungültige alte Notizen')
    local map,children,seen={},{},{}
    for _,c in ipairs(cards) do map[c.id]=c;children[c.parent]=children[c.parent] or {};table.insert(children[c.parent],c) end
    for _,root in ipairs(cards) do if root.parent=='' or not map[root.parent] then
      local previous=''
      local function walk(c)
        assert(not seen[c.id],'Ungültige alte Notizverbindung');seen[c.id]=true
        c.parent=previous;previous=c.id
        for _,child in ipairs(children[c.id] or {}) do walk(child) end
      end
      walk(root)
    end end
    for _,c in ipairs(cards) do assert(seen[c.id],'Ungültige alte Notizverbindung') end
  end
  b.format=2;return b
end
function N.validate(b)
  if type(b)=='table' and b.format==1 then b=N.migrate(b) end
  assert(type(b)=='table' and b.format==2 and integer(b.revision,0,1e12),'Unbekanntes Notizformat')
  assert(type(b.cards)=='table' and #b.cards<=128 and type(b.trash)=='table' and #b.trash<=20,'Notizwand ist zu groß')
  local function card(c)
    assert(type(c)=='table' and id(c.id) and type(c.versions)=='table','Ungültige Notizkarte')
    for f,v in pairs({kind='text',listStyle='check',checks='',image=false}) do if c[f]==nil then c[f]=v;c.versions[f]=0 end end
    for _,f in ipairs(N.fields) do assert(N.field(f,c[f]) and integer(c.versions[f],0,b.revision),'Ungültiges Notizfeld') end
    assert(c.kind~='image' or c.image,'Referenzbild fehlt')
    assert(c.kind~='list' or select(2,c.text:gsub('\n',''))<128,'Höchstens 128 Listenpunkte')
  end
  local map={}
  for _,c in ipairs(b.cards) do card(c);assert(not map[c.id],'Doppelte Notizkarte');map[c.id]=c end
  local attached={}
  for _,c in ipairs(b.cards) do
    assert(c.parent=='' or not attached[c.parent],'An dieser Box hängt bereits ein Element');attached[c.parent]=true
    local seen,count={},0
    while c do
      count=count+1;assert(count<=128 and not seen[c.id],'Ungültige Notizverbindung')
      seen[c.id]=true;assert(c.parent=='' or map[c.parent],'Übergeordnete Notiz fehlt');c=map[c.parent]
    end
  end
  local seen={}
  for _,t in ipairs(b.trash) do
    assert(id(t.id) and not seen[t.id] and type(t.cards)=='table' and #t.cards>0 and #t.cards<=128,'Ungültiger Notizpapierkorb');seen[t.id]=true
    local ids={};for _,c in ipairs(t.cards) do card(c);assert(not ids[c.id],'Doppelte Notizkarte');ids[c.id]=true end
  end
  assert(#json.encode(b)<=N.bytes,'Ideenwand ist voll (8 MiB inklusive Papierkorb)')
  return b
end
function N.read(sprite)
  local value=sprite.properties(N.key).board
  if value==nil or value=='' then return N.empty() end
  assert(type(value)=='string' and #value<=N.bytes,'Ungültige gespeicherte Notizen')
  return N.validate(decode(value))
end
function N.write(sprite,board)
  board=N.validate(board)
  local encoded=json.encode(board)
  if sprite.properties(N.key).board~=encoded then sprite.properties(N.key).board=encoded end
end
function N.card(board,id) for _,c in ipairs(board.cards) do if c.id==id then return c end end end
function N.newCard(title,parent,x,y)
  local c={id=N.uid(),title=title or '',text='',parent=parent or '',x=x or 30,y=y or 30,color='',status='idea',kind='text',listStyle='check',checks='',image=false,versions={}}
  for _,f in ipairs(N.fields) do c.versions[f]=0 end
  return c
end
function N.patch(c,f,value) return {id=c.id,field=f,value=value,expected=c.versions[f]} end
-- JSON false represents absence for whole-card patches, avoiding Lua nil fields.
function N.commit(board,patches)
  local next=N.copy(board);next.revision=next.revision+1
  local inverse,seen={},{}
  for _,p in ipairs(patches) do
    local c=N.card(next,p.id);local key=p.id..':'..(p.field or '*')
    assert(not seen[key],'Doppelte Notizänderung');seen[key]=true
    if p.field then
      assert(c and c.versions[p.field]==p.expected and N.field(p.field,p.value),'Karte wurde geändert. Entwurf bitte vergleichen.')
      table.insert(inverse,1,{id=p.id,field=p.field,value=c[p.field],expected=next.revision,restoreVersion=c.versions[p.field]})
      c[p.field]=p.value;c.versions[p.field]=next.revision
    else
      assert(N.equal(c or false,p.expected),'Karte wurde inzwischen geändert')
      local value=p.value and N.copy(p.value) or false
      if value then for _,f in ipairs(N.fields) do value.versions[f]=next.revision end end
      table.insert(inverse,1,{id=p.id,value=c or false,expected=value})
      for i,v in ipairs(next.cards) do if v.id==p.id then table.remove(next.cards,i);break end end
      if value then next.cards[#next.cards+1]=value end
    end
  end
  return N.validate(next),inverse
end
function N.localAction(board,history,op)
  local next,inverse
  if op.action=='undo' or op.action=='redo' then
    local from=op.action=='undo' and history.undo or history.redo
    local to=op.action=='undo' and history.redo or history.undo
    assert(#from>0,'Keine eigene Notizänderung im Verlauf')
    local applied=from[#from]
    next,inverse=N.commit(board,applied);table.remove(from)
    for _,p in ipairs(applied) do
      local restored=p.field and {[p.field]=p.restoreVersion} or (p.value and p.value.versions or {})
      for field,version in pairs(restored) do for _,stack in ipairs({history.undo,history.redo}) do for _,entry in ipairs(stack) do for _,q in ipairs(entry) do
        if q.id==p.id then
          if q.field==field and q.expected==version then q.expected=next.revision end
          if not q.field and q.expected and q.expected.versions[field]==version then q.expected.versions[field]=next.revision end
        end
      end end end end
    end
    to[#to+1]=inverse
  else
    local patches=op.patches
    if op.action=='delete' then
      local c=assert(N.card(board,op.id),'Karte fehlt')
      assert(board.revision==op.revision and N.equal(c.versions,op.versions),'Wand wurde geändert')
      local ids={[c.id]=true}
      if op.children then
        for _=1,128 do for _,v in ipairs(board.cards) do if ids[v.parent] then ids[v.id]=true end end end
      end
      patches={};local removed={}
      for _,v in ipairs(board.cards) do
        if ids[v.id] then patches[#patches+1]={id=v.id,expected=v,value=false};removed[#removed+1]=N.copy(v)
        elseif ids[v.parent] then patches[#patches+1]=N.patch(v,'parent',c.parent) end
      end
      next,inverse=N.commit(board,patches)
      next.trash[#next.trash+1]={id=N.uid(),cards=removed}
      while #next.trash>20 or #json.encode(next)>N.bytes do table.remove(next.trash,1) end
    elseif op.action=='restore' then
      local removed
      for _,t in ipairs(board.trash) do if t.id==op.id then removed=t end end
      assert(removed,'Papierkorb-Eintrag fehlt');patches={};local ids={}
      for _,c in ipairs(board.cards) do ids[c.id]=true end
      for _,c in ipairs(removed.cards) do ids[c.id]=true end
      for _,c in ipairs(removed.cards) do local v=N.copy(c);if not ids[v.parent] then v.parent='' end;patches[#patches+1]={id=v.id,expected=false,value=v} end
      next,inverse=N.commit(board,patches)
      for i,t in ipairs(next.trash) do if t.id==op.id then table.remove(next.trash,i);break end end
    else next,inverse=N.commit(board,patches) end
    history.undo[#history.undo+1]=inverse;if #history.undo>32 then table.remove(history.undo,1) end;history.redo={}
  end
  while #json.encode({history.undo,history.redo})>16*1024*1024 do
    if #history.undo>0 then table.remove(history.undo,1) else table.remove(history.redo,1) end
  end
  return N.validate(next)
end
return N
