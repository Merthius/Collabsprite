-- File storage and bounded local editing. No network, UI or private text logs.
local dir=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local decode=dofile(app.fs.joinPath(dir,'json.lua')).decode
local N={key='Merthius/Collabsprite',bytes=8*1024*1024,fields={'title','text','parent','dock','x','y','color','status','kind','listStyle','checks','image','tag','tagStart','frame'}}
function N.empty() return {format=8,revision=0,cards={},trash={},authors={}} end
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
  if f=='dock' then return v=='below' or v=='left' or v=='right' end
  if f=='x' or f=='y' then return integer(v,-10000,10000) end
  if f=='color' then return type(v)=='string' and (v=='' or (#v==7 and v:match('^#%x+$'))) end
  if f=='status' then return v=='idea' or v=='decided' or v=='done' end
  if f=='kind' then return v=='text' or v=='list' or v=='image' or v=='animation' or v=='paper' end
  if f=='tag' then return type(v)=='string' and #v<=120 and not v:find('[%z\1-\8\11-\31]') end
  if f=='tagStart' then return integer(v,0,100000) end
  if f=='frame' then return integer(v,0,100000) end
  if f=='listStyle' then return v=='check' or v=='bullet' or v=='number' end
  if f=='checks' then return type(v)=='string' and #v<=128 and not v:find('[^01]') end
  if f=='image' then
    if v==false then return true end
    if type(v)~='table' or type(v.pixels)~='string' then return false end
    local count=0;for _ in pairs(v) do count=count+1 end
    if count==3 then
      return integer(v.width,1,512) and integer(v.height,1,512) and
        #v.pixels==v.width*v.height*8 and not v.pixels:find('[^a-f0-9]')
    end
    if count~=4 or v.width~=1000 or v.height~=1000 then return false end
    if v.encoding=='b64' then
      return #v.pixels==5333336 and v.pixels:sub(-2)=='==' and
        not v.pixels:sub(1,-3):find('[^%w%+%/]')
    end
    if v.encoding~='rle' or #v.pixels==0 or #v.pixels%12~=0 or
      #v.pixels>5333336 or v.pixels:find('[^a-f0-9]') then return false end
    local total=0
    for i=1,#v.pixels,12 do
      local run=tonumber(v.pixels:sub(i,i+3),16)
      if not run or run==0 then return false end
      total=total+run
      if total>1000000 then return false end
    end
    return total==1000000
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
  if type(b)=='table' and (b.format==2 or b.format==3 or b.format==4 or b.format==5 or b.format==6 or b.format==7) then
    b=N.copy(b);b.format=8;b.authors=b.authors or {}
  end
  assert(type(b)=='table' and b.format==8 and integer(b.revision,0,1e12),'Unbekanntes Notizformat')
  assert(type(b.cards)=='table' and #b.cards<=128 and type(b.trash)=='table' and #b.trash<=20,'Notizwand ist zu groß')
  assert(type(b.authors)=='table','Ungültige Autorenangaben')
  local authorCount=0
  for key,info in pairs(b.authors) do
    authorCount=authorCount+1
    assert(id(key) and type(info)=='table' and type(info.created)=='string' and type(info.edited)=='string' and
      #info.created<=160 and #info.edited<=160 and not info.created:find('[%z\1-\31]') and
      not info.edited:find('[%z\1-\31]'),'Ungültige Autorenangabe')
  end
  assert(authorCount<=2560,'Zu viele Autorenangaben')
  local function card(c)
    assert(type(c)=='table' and id(c.id) and type(c.versions)=='table','Ungültige Notizkarte')
    for f,v in pairs({kind='text',listStyle='check',checks='',image=false,dock='below',tag='',tagStart=0}) do if c[f]==nil then c[f]=v;c.versions[f]=0 end end
    if c.frame==nil then c.frame=c.kind=='animation' and c.tagStart or 0;c.versions.frame=0 end
    for _,f in ipairs(N.fields) do assert(N.field(f,c[f]) and integer(c.versions[f],0,b.revision),'Ungültiges Notizfeld') end
    assert(c.kind~='image' or (c.image and not c.image.encoding),'Referenzbild fehlt')
    assert(c.kind~='paper' or (c.image and ((c.image.width==128 and c.image.height==128 and not c.image.encoding) or
      (c.image.width==1000 and c.image.height==1000 and c.image.encoding))),'Skizzenblatt fehlt')
    assert(c.kind~='animation' or (c.tagStart>0 and c.frame>0 and c.image==false),'Animations-Tag fehlt')
    assert(c.kind~='list' or select(2,c.text:gsub('\n',''))<128,'Höchstens 128 Listenpunkte')
  end
  local map={}
  for _,c in ipairs(b.cards) do card(c);assert(not map[c.id],'Doppelte Notizkarte');map[c.id]=c end
  local attached={}
  for _,c in ipairs(b.cards) do
    local slot=c.parent..':'..c.dock
    assert(c.parent=='' or not attached[slot],'An dieser Seite hängt bereits ein Element');if c.parent~='' then attached[slot]=true end
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
  local relevant={};for _,c in ipairs(b.cards) do relevant[c.id]=true end
  for _,t in ipairs(b.trash) do for _,c in ipairs(t.cards) do relevant[c.id]=true end end
  for key in pairs(b.authors) do if not relevant[key] then b.authors[key]=nil end end
  assert(#json.encode(b)<=N.bytes,'Ideenwand ist voll (8 MiB inklusive Papierkorb)')
  return b
end
function N.read(sprite)
  local props=sprite.properties(N.key)
  local value=props.board
  if value==nil or value=='' then return N.empty() end
  assert(type(value)=='string','Ungültige gespeicherte Notizen')
  if value:sub(1,4)=='CS7:' then
    local count,length,checksum=value:match('^CS7:(%d+):(%d+):(%x+)$')
    count=tonumber(count);length=tonumber(length)
    assert(count and count>=1 and count<=150 and length and length<=N.bytes and length>0 and checksum,
      'Ungültiger Ideenwand-Speicherkopf')
    local parts={}
    for i=1,count do
      local part=props['board_'..i]
      assert(type(part)=='string' and #part>0 and #part<=60000,'Ideenwand-Datenabschnitt fehlt')
      parts[i]=part
    end
    value=table.concat(parts)
    assert(#value==length and N.checksum(value)==checksum,'Ideenwand-Daten sind unvollständig oder beschädigt')
  end
  assert(#value<=N.bytes,'Ungültige gespeicherte Notizen')
  return N.validate(decode(value))
end
function N.checksum(value)
  local a,b=1,0
  for i=1,#value do
    a=(a+value:byte(i))%65521
    b=(b+a)%65521
  end
  return string.format('%08x',b*65536+a)
end
function N.write(sprite,board)
  board=N.validate(board)
  local encoded=json.encode(board)
  assert(#encoded<=N.bytes,'Ideenwand ist voll')
  local props=sprite.properties(N.key)
  local previous=props.board
  local oldCount=type(previous)=='string' and tonumber(previous:match('^CS7:(%d+):')) or 0
  local count=math.ceil(#encoded/60000)
  assert(count<=150,'Zu viele Ideenwand-Datenabschnitte')
  for i=1,count do
    local part=encoded:sub((i-1)*60000+1,i*60000)
    local key='board_'..i
    if props[key]~=part then props[key]=part end
  end
  local header='CS7:'..count..':'..#encoded..':'..N.checksum(encoded)
  if previous~=header then props.board=header end
  for i=count+1,oldCount do props['board_'..i]=nil end
end
function N.card(board,id) for _,c in ipairs(board.cards) do if c.id==id then return c end end end
function N.newCard(title,parent,x,y)
  local c={id=N.uid(),title=title or '',text='',parent=parent or '',dock='below',x=x or 30,y=y or 30,color='',status='idea',kind='text',listStyle='check',checks='',image=false,tag='',tagStart=0,frame=0,versions={}}
  for _,f in ipairs(N.fields) do c.versions[f]=0 end
  return c
end
function N.patch(c,f,value) return {id=c.id,field=f,value=value,expected=c.versions[f]} end
-- JSON false represents absence for whole-card patches, avoiding Lua nil fields.
function N.commit(board,patches,author)
  local next=N.copy(board);next.revision=next.revision+1
  local inverse,seen,changed={},{},{}
  for _,p in ipairs(patches) do
    local c=N.card(next,p.id);local key=p.id..':'..(p.field or '*')
    assert(not seen[key],'Doppelte Notizänderung');seen[key]=true
    if p.field then
      assert(c and c.versions[p.field]==p.expected and N.field(p.field,p.value),'Karte wurde geändert. Entwurf bitte vergleichen.')
      table.insert(inverse,1,{id=p.id,field=p.field,value=c[p.field],expected=next.revision,restoreVersion=c.versions[p.field]})
      if not N.equal(c[p.field],p.value) then changed[p.id]=true end
      c[p.field]=p.value;c.versions[p.field]=next.revision
    else
      assert(N.equal(c or false,p.expected),'Karte wurde inzwischen geändert')
      local value=p.value and N.copy(p.value) or false
      if value then for _,f in ipairs(N.fields) do value.versions[f]=next.revision end end
      table.insert(inverse,1,{id=p.id,value=c or false,expected=value})
      for i,v in ipairs(next.cards) do if v.id==p.id then table.remove(next.cards,i);break end end
      if value then next.cards[#next.cards+1]=value;changed[p.id]=true end
    end
  end
  author=type(author)=='string' and author:sub(1,160) or 'Künstler'
  for cardId in pairs(changed) do
    local info=next.authors[cardId] or {created=author,edited=author}
    info.edited=author;next.authors[cardId]=info
  end
  return N.validate(next),inverse
end
function N.localAction(board,history,op,author)
  local next,inverse
  if op.action=='undo' or op.action=='redo' then
    local from=op.action=='undo' and history.undo or history.redo
    local to=op.action=='undo' and history.redo or history.undo
    assert(#from>0,'Keine eigene Notizänderung im Verlauf')
    local applied=from[#from]
    next,inverse=N.commit(board,applied,author);table.remove(from)
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
        elseif ids[v.parent] then patches[#patches+1]=N.patch(v,'parent','') end
      end
      next,inverse=N.commit(board,patches,author)
      next.trash[#next.trash+1]={id=N.uid(),cards=removed}
      while #next.trash>20 or #json.encode(next)>N.bytes do table.remove(next.trash,1) end
    elseif op.action=='restore' then
      local removed
      for _,t in ipairs(board.trash) do if t.id==op.id then removed=t end end
      assert(removed,'Papierkorb-Eintrag fehlt');patches={};local ids={}
      for _,c in ipairs(board.cards) do ids[c.id]=true end
      for _,c in ipairs(removed.cards) do ids[c.id]=true end
      for _,c in ipairs(removed.cards) do local v=N.copy(c);if not ids[v.parent] then v.parent='' end;patches[#patches+1]={id=v.id,expected=false,value=v} end
      next,inverse=N.commit(board,patches,author)
      for i,t in ipairs(next.trash) do if t.id==op.id then table.remove(next.trash,i);break end end
    else next,inverse=N.commit(board,patches,author) end
    history.undo[#history.undo+1]=inverse;if #history.undo>32 then table.remove(history.undo,1) end;history.redo={}
  end
  while #json.encode({history.undo,history.redo})>16*1024*1024 do
    if #history.undo>0 then table.remove(history.undo,1) else table.remove(history.redo,1) end
  end
  return N.validate(next)
end
return N
