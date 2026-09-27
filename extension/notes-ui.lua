local dir=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local N=dofile(app.fs.joinPath(dir,'notes.lua'))
local UI={};UI.__index=UI
local labels={title='Titel',text='Notiz',color='Farbe',status='Status',parent='Übergeordnete Karte'}
local statuses={idea='Idee',decided='Festgelegt',done='Erledigt'}
local W,H=168,78
local function short(text,n)
  text=(text or ''):gsub('[\r\n]',' ')
  if utf8.len(text) and utf8.len(text)>n then return text:sub(1,utf8.offset(text,n+1)-1)..'…' end
  return text
end
function UI.new(getSession,guestGuard,safe)
  return setmetatable({states={},getSession=getSession,guestGuard=guestGuard,safe=safe},UI)
end
function UI:state(sprite)
  -- app.sprite returns equal but distinct Lua userdata wrappers; table keys
  -- must use the document's stable native ID, never the wrapper identity.
  if not self.states[sprite.id] then self.states[sprite.id]={sprite=sprite,board=N.read(sprite),history={undo={},redo={}},collapsed={},zoom=1,ox=20,oy=20,drafts={},seen=false} end
  return self.states[sprite.id]
end
function UI:session(s) local c=self.getSession();return c and c.sprite==s.sprite and (c.connected or c.connecting or c.reconnecting) and c or nil end
function UI:editable(s)
  local c=self:session(s)
  if c then return c.connected and not c.leaving end
  return not self.guestGuard(s.sprite)
end
function UI:run(fn) self.safe(fn) end
function UI:action(s,op,callback)
  assert(s.sprite.isValid and self:editable(s),'Notizen sind derzeit nur lesbar. Verbindung prüfen.')
  local c=self:session(s)
  if c then
    c:noteAction(op);s.ack=callback
  else
    local history=N.copy(s.history)
    local next=N.localAction(s.board,history,op)
    local previous,layer,frame=app.sprite,app.layer,app.frame
    app.sprite=s.sprite
    local ok,err=pcall(function() app.transaction('Collabsprite: Notizen',function() N.write(s.sprite,next) end) end)
    app.sprite=previous;if previous then app.layer=layer;app.frame=frame end
    if not ok then error(err) end
    s.board=next;s.history=history;if callback then callback(true) end
  end
  self:refresh(s)
end
function UI:attach(c)
  if not c.sprite then return end
  local s=self:state(c.sprite)
  c.onNotes=function(message)
    if message.type=='notes' then
      s.board=N.copy(c.meta.notes)
      if s.acceptedDraft then
        local d=s.acceptedDraft;local card=N.card(s.board,d.id)
        if card then d.base=N.copy(card);d.dirty=self:draftValue(d)~=card[d.field] end
        s.acceptedDraft=nil
      end
    elseif message.type=='noteAck' then
      local callback=s.ack;s.ack=nil
      if callback then callback(message.ok,message.message) end
    end
    self:refresh(s)
  end
  c.notesCanLeave=function() return self:canLeave(s) end
end
function UI:canLeave(s)
  for _,d in pairs(s.drafts) do if d.dirty then
    app.tip('Notizentwurf noch offen. In Gemeinsame Notizen übernehmen oder verwerfen.',6)
    self:show(s.sprite);self:edit(s,d.id,d.field);return false
  end end
  local c=self:session(s)
  if c and c.notePending then app.tip('Notizänderung wird noch bestätigt. Bitte kurz warten.',4);return false end
  return true
end
function UI:status(s)
  local c=self:session(s)
  for _,d in pairs(s.drafts) do if d.dirty then return 'Notizentwurf – noch nicht übernommen' end end
  if c then
    if c.notePending then return 'Wird übertragen …' end
    if not c.connected then return 'Verbindung unterbrochen – Entwürfe bleiben offen' end
    return c.notesSaved==s.board.revision and 'In Datei gespeichert (Host)' or 'Mit Host synchronisiert · Datei noch nicht gespeichert'
  end
  local file=s.sprite.filename:lower()
  if #s.board.cards>0 and not file:match('%.aseprite$') and not file:match('%.ase$') then return 'Notizen nur hier · bitte als .aseprite speichern' end
  return (s.sprite.isModified or not app.fs.isFile(s.sprite.filename)) and 'Notizen im Bild · Datei noch nicht gespeichert' or 'In Datei gespeichert'
end
-- Repeated Dialog:modify() relayouts native modeless windows and can raise the
-- parent over a text editor. Update widgets only when a value really changes.
local function modify(form,cache,id,values)
  if N.equal(cache[id],values) then return end
  cache[id]=N.copy(values);local args=N.copy(values);args.id=id;form:modify(args)
end
function UI:refresh(s)
  local editing=false;for _,d in pairs(s.drafts) do if d.dialog then editing=true;break end end
  if s.dialog and not editing then
    s.rendered=s.rendered or {};local r=s.rendered
    modify(s.dialog,r,'document',{text='Bild: '..short(app.fs.fileTitle(s.sprite.filename or 'Bild'),36)})
    modify(s.dialog,r,'state',{text=self:status(s)})
    modify(s.dialog,r,'selected',{enabled=s.selected~=nil})
    local c=self:session(s);local h=c and c.noteHistory
    modify(s.dialog,r,'undo',{enabled=self:editable(s) and (h and h.undo>0 or not c and #s.history.undo>0) or false})
    modify(s.dialog,r,'redo',{enabled=self:editable(s) and (h and h.redo>0 or not c and #s.history.redo>0) or false})
    local draft=false;for _,d in pairs(s.drafts) do if d.dirty then draft=true;break end end
    modify(s.dialog,r,'draft',{visible=draft})
    if s.lastBoard~=s.board or s.lastLocks~=(c and c.noteLocks) then
      s.lastBoard=s.board;s.lastLocks=c and c.noteLocks;s.dialog:repaint()
    end
  end
  for _,d in pairs(s.drafts) do if d.dialog then
    local c=self:session(s);local owner
    for _,l in ipairs(c and c.noteLocks or {}) do if l.id==d.id and l.field==d.field then owner=l end end
    local allowed=self:editable(s) and (not c or (owner and owner.author==c.author)) and not (c and c.notePending)
    d.rendered=d.rendered or {}
    modify(d.dialog,d.rendered,'apply',{enabled=allowed==true})
    modify(d.dialog,d.rendered,'hint',{text=d.error or (owner and c and owner.author~=c.author and (owner.name..' bearbeitet dieses Feld') or 'Änderungen mit Übernehmen bestätigen')})
  end end
end
function UI:add(s,parent,source)
  local p=N.card(s.board,parent)
  local c=N.newCard(source and source.title..' Kopie' or 'Neue Idee',p and p.id or '',p and p.x+210 or 30,p and p.y+100 or 30+#s.board.cards*12)
  if source then c.text=source.text;c.color=source.color;c.status=source.status;c.x=source.x+30;c.y=source.y+90;c.parent=source.parent end
  self:action(s,{action='patch',patches={{id=c.id,expected=false,value=c}}},function(ok) if ok then s.selected=c.id end end)
end
function UI:arrange(s)
  local patches,stack={},{}
  for i=#s.board.cards,1,-1 do local c=s.board.cards[i];if c.parent=='' then stack[#stack+1]={c,0} end end
  local row=0
  while #stack>0 do
    local item=table.remove(stack);local c,depth=item[1],item[2]
    patches[#patches+1]=N.patch(c,'x',30+depth*205);patches[#patches+1]=N.patch(c,'y',30+row*95);row=row+1
    for i=#s.board.cards,1,-1 do local child=s.board.cards[i];if child.parent==c.id then stack[#stack+1]={child,depth+1} end end
  end
  if #patches>0 then self:action(s,{action='patch',patches=patches}) end
end
function UI:fit(s)
  local minx,miny,maxx,maxy=0,0,350,200
  for _,c in ipairs(s.board.cards) do minx=math.min(minx,c.x);miny=math.min(miny,c.y);maxx=math.max(maxx,c.x+W);maxy=math.max(maxy,c.y+H) end
  s.zoom=math.max(0.25,math.min(1,(s.width or 440)/(maxx-minx+60),(s.height or 230)/(maxy-miny+60)))
  s.ox=25-minx*s.zoom;s.oy=25-miny*s.zoom
  if s.dialog then s.dialog:repaint() end
end
function UI:visible(s)
  local map={};for _,c in ipairs(s.board.cards) do map[c.id]=c end
  local result={}
  for _,c in ipairs(s.board.cards) do
    local p=map[c.parent];local hidden=false
    for _=1,24 do if not p then break end;if s.collapsed[p.id] then hidden=true;break end;p=map[p.parent] end
    if not hidden then result[#result+1]=c end
  end
  return result
end
function UI:paint(s,ev)
  local gc=ev.context;s.width=gc.width;s.height=gc.height
  gc.color=Color{r=31,g=33,b=39};gc:fillRect(Rectangle(0,0,gc.width,gc.height))
  s.hits={};local positions={};local visible=self:visible(s)
  for _,c in ipairs(visible) do
    local x,y=c.x,c.y
    if s.drag and s.drag.id==c.id then x,y=s.drag.x,s.drag.y end
    positions[c.id]={x=math.floor(s.ox+x*s.zoom),y=math.floor(s.oy+y*s.zoom),w=math.floor(W*s.zoom),h=math.floor(H*s.zoom)}
  end
  gc.color=Color{r=104,g=112,b=134}
  for _,c in ipairs(visible) do
    local r,p=positions[c.id],positions[c.parent]
    if p then
      local mid=math.floor((p.x+p.w+r.x)/2);local y1,y2=math.floor(p.y+p.h/2),math.floor(r.y+r.h/2)
      gc:fillRect(Rectangle(math.min(p.x+p.w,mid),y1,math.max(1,math.abs(mid-p.x-p.w)),2))
      gc:fillRect(Rectangle(mid,math.min(y1,y2),2,math.max(1,math.abs(y2-y1))))
      gc:fillRect(Rectangle(math.min(mid,r.x),y2,math.max(1,math.abs(r.x-mid)),2))
    end
  end
  local query=(s.dialog and s.dialog.data.search or ''):lower()
  for _,c in ipairs(visible) do
    local r=positions[c.id];s.hits[#s.hits+1]={id=c.id,r=r}
    local match=query~='' and (c.title..' '..c.text):lower():find(query,1,true)
    gc.color=s.selected==c.id and Color{r=141,g=124,b=225} or match and Color{r=235,g=182,b=87} or Color{r=71,g=77,b=94}
    gc:fillRect(Rectangle(r.x,r.y,r.w,r.h));gc.color=Color{r=47,g=50,b=60}
    gc:fillRect(Rectangle(r.x+2,r.y+2,r.w-4,r.h-4))
    if s.zoom>=0.4 then
      gc.color=Color{r=236,g=235,b=242};gc:fillText(short(c.title,math.floor((r.w-14)/6)),r.x+7,r.y+7)
      if r.h>=58 then gc.color=Color{r=177,g=182,b=196};gc:fillText(short(c.text,math.floor((r.w-14)/6)),r.x+7,r.y+23) end
      if r.h>=42 then
        gc.color=Color{r=131,g=202,b=183};gc:fillText((s.collapsed[c.id] and '+ ' or '')..statuses[c.status],r.x+7,r.y+r.h-17)
        if c.color~='' then gc.color=Color{r=tonumber(c.color:sub(2,3),16),g=tonumber(c.color:sub(4,5),16),b=tonumber(c.color:sub(6,7),16)};gc:fillRect(Rectangle(r.x+r.w-19,r.y+r.h-19,11,11)) end
      end
      local session=self:session(s)
      for _,l in ipairs(session and session.noteLocks or {}) do if l.id==c.id and l.author~=session.author then
        gc.color=Color{r=240,g=187,b=100};gc:fillText(short(l.name,18)..' …',r.x+7,r.y+r.h+2);break
      end end
    end
  end
  if #visible==0 then
    gc.color=Color{r=199,g=199,b=214};gc:fillText('Eure Ideen haben hier Platz.',28,35)
    gc.color=Color{r=146,g=152,b=170};gc:fillText('Mit + Karte beginnen. Rechtsklick verbindet und ordnet.',28,57)
  end
end
function UI:hit(s,x,y)
  for i=#(s.hits or {}),1,-1 do local h=s.hits[i];local r=h.r;if x>=r.x and y>=r.y and x<r.x+r.w and y<r.y+r.h then return h.id end end
end
function UI:menu(s,id)
  local c=N.card(s.board,id);if not c then return end
  s.selected=id;local d=Dialog{title=short(c.title,28)}
  local function button(text,fn) d:button{text=text,onclick=function() d:close();self:run(fn) end}:newrow() end
  button('+ Unterkarte',function() self:add(s,id) end)
  for _,f in ipairs({'title','text','color','status','parent'}) do button(labels[f]..' ändern',function() self:edit(s,id,f) end) end
  button(s.collapsed[id] and 'Zweig ausklappen' or 'Zweig einklappen',function() s.collapsed[id]=not s.collapsed[id];self:refresh(s) end)
  button('Karte duplizieren',function() self:add(s,'',c) end)
  button('Karte löschen …',function()
    local answer=app.alert{title='Notiz löschen',text='Unterkarten behalten oder den ganzen Zweig löschen?',buttons={'Unterkarten behalten','Ganzen Zweig löschen','Abbrechen'}}
    if answer==1 or answer==2 then self:action(s,{action='delete',id=id,versions=N.copy(c.versions),revision=s.board.revision,children=answer==2}) end
  end)
  d:button{text='Schließen'};d:show{wait=false}
end
function UI:draftValue(d)
  if not d.dialog then return d.value end
  local data=d.dialog.data
  if d.field=='text' then local lines={};for i=1,6 do lines[i]=data['line'..i] or '' end;return table.concat(lines,'\n'):gsub('\n+$','') end
  if d.field=='status' then for k,v in pairs(statuses) do if data.value==v then return k end end end
  if d.field=='parent' then return d.parents[data.value] or '' end
  return data.value or ''
end
function UI:edit(s,id,field)
  local key=id..':'..field;local d=s.drafts[key]
  local c=N.card(s.board,id) or (d and d.base);if not c then return end
  if d and d.dialog then return end
  if not d then d={id=id,field=field,base=N.copy(c),value=c[field],dirty=false};s.drafts[key]=d end
  local session=self:session(s)
  if session then session:noteLock(id,field);d.renewed=os.time() end
  local form
  form=Dialog{title=labels[field]..' – '..short(c.title,22),onclose=function()
    d.value=self:draftValue(d);d.dirty=d.value~=d.base[field];d.dialog=nil
    if session then session:noteLock(id,field,true) end
    if not d.dirty then s.drafts[key]=nil end;self:refresh(s)
  end}
  d.dialog=form;d.rendered={}
  local function changed() d.dirty=true;d.value=self:draftValue(d);self:refresh(s) end
  if field=='text' then
    local lines={};for line in (d.value..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line end
    -- Six native entry rows retain normal text/clipboard behavior. Keep any
    -- additional imported lines together in the last row, never silently cut.
    if #lines>6 then lines[6]=table.concat(lines,'\n',6) end
    for i=1,6 do form:entry{id='line'..i,label=i==1 and 'Notiz' or '',text=lines[i] or '',onchange=changed}:newrow() end
  elseif field=='status' then form:combobox{id='value',options={'Idee','Festgelegt','Erledigt'},option=statuses[d.value],onchange=changed}
  elseif field=='parent' then
    d.parents={['(Hauptkarte)']=''};local choices={'(Hauptkarte)'};local selected='(Hauptkarte)'
    for i,v in ipairs(s.board.cards) do if v.id~=id then local label=i..' · '..short(v.title,28);d.parents[label]=v.id;choices[#choices+1]=label;if v.id==d.value then selected=label end end end
    form:combobox{id='value',options=choices,option=selected,onchange=changed}
  else form:entry{id='value',label=field=='color' and '#RRGGBB / leer' or labels[field],text=d.value,onchange=changed} end
  form:newrow():label{id='hint',text='Änderungen mit Übernehmen bestätigen'}:newrow()
    :button{id='apply',text='Übernehmen',onclick=function() self:run(function()
      local value=self:draftValue(d);assert(N.field(field,value),'Text zu lang oder ungültiger Wert (Titel 120, Notiz 2048 UTF-8-Bytes).')
      if value==d.base[field] then d.dirty=false;form:close();return end
      self:action(s,{action='patch',patches={N.patch(d.base,field,value)}},function(ok,message)
        if ok then
          if self:draftValue(d)==value then
            d.base[field]=value;d.value=value;d.dirty=false
            form:close();s.drafts[key]=nil
          else s.acceptedDraft=d end
        else d.error=message or 'Entwurf bitte mit aktuellem Stand vergleichen.';d.dirty=true;self:refresh(s) end
      end)
    end) end}
    :button{text='Stand vergleichen',onclick=function()
      local current=N.card(s.board,id)
      if current then
        local choice=app.alert{title='Aktueller gemeinsamer Stand',text={short(current[field],100),'Dein Entwurf bleibt erhalten. Auf diesem Stand weiterarbeiten?'},buttons={'Ja, Entwurf behalten','Abbrechen'}}
        if choice==1 then d.base=N.copy(current);d.error=nil;if session then session:noteLock(id,field) end end
      else app.alert{title='Karte gelöscht',text='Entwurf kopieren oder verwerfen. Er wird nicht still gelöscht.'} end
    end}
    :newrow():button{text='Entwurf kopieren',onclick=function() app.clipboard.text=self:draftValue(d);app.tip('Notizentwurf kopiert.',3) end}
    :button{text='Verwerfen',onclick=function()
      if app.alert{title='Entwurf verwerfen?',text='Nur deinen unbestätigten Entwurf verwerfen?',buttons={'Verwerfen','Abbrechen'}}==1 then
        d.value=d.base[field];d.dirty=false;d.dialog=nil;s.drafts[key]=nil;form:close()
      end
    end}
    :button{text='Später',onclick=function() form:close() end}
  form:show{wait=false};self:refresh(s)
end
function UI:show(sprite)
  assert(sprite,'Bitte zuerst ein Bild öffnen')
  local s=self:state(sprite);s.seen=true
  if s.dialog then return end
  s.rendered={};s.dialog=Dialog{title='Ideenwand',onclose=function() s.dialog=nil end}
  local d=s.dialog
  d:label{id='document',text='Bild: '..short(app.fs.fileTitle(sprite.filename or 'Bild'),36)}:newrow()
    :button{text='+ Karte',onclick=function() self:run(function() self:add(s,'') end) end}
    :button{text='Alles anzeigen',onclick=function() s.collapsed={};self:fit(s) end}
    :button{text='Anordnen',onclick=function() self:run(function() self:arrange(s);self:fit(s) end) end}
    :newrow():entry{id='search',text='',label='Suche',onchange=function() d:repaint() end}
    :newrow():canvas{id='board',width=440,height=230,autoscaling=true,
      onpaint=function(ev) self:paint(s,ev) end,
      onmousedown=function(ev)
        local id=self:hit(s,ev.x,ev.y);s.selected=id
        if ev.button==MouseButton.RIGHT and id then self:menu(s,id);return end
        local c=N.card(s.board,id)
        s.drag=c and {id=id,startX=ev.x,startY=ev.y,x=c.x,y=c.y,base=N.copy(c)} or {startX=ev.x,startY=ev.y,ox=s.ox,oy=s.oy}
        self:refresh(s)
      end,
      onmousemove=function(ev)
        local a=s.drag;if not a then return end
        if a.id then a.x=math.max(-10000,math.min(10000,math.floor(a.base.x+(ev.x-a.startX)/s.zoom)));a.y=math.max(-10000,math.min(10000,math.floor(a.base.y+(ev.y-a.startY)/s.zoom)))
        else s.ox=a.ox+ev.x-a.startX;s.oy=a.oy+ev.y-a.startY end
        d:repaint()
      end,
      onmouseup=function()
        local a=s.drag;s.drag=nil
        if a and a.id and (a.x~=a.base.x or a.y~=a.base.y) then self:run(function()
          self:action(s,{action='patch',patches={N.patch(a.base,'x',a.x),N.patch(a.base,'y',a.y)}})
        end) end;d:repaint()
      end,
      ondblclick=function(ev) local id=self:hit(s,ev.x,ev.y);if id then self:edit(s,id,'text') end end,
      onwheel=function(ev)
        local old=s.zoom;s.zoom=math.max(0.25,math.min(2,s.zoom*(ev.deltaY>0 and 0.85 or 1.18)))
        s.ox=ev.x-(ev.x-s.ox)*s.zoom/old;s.oy=ev.y-(ev.y-s.oy)*s.zoom/old;d:repaint()
      end,
      onkeydown=function(ev)
        if ev.ctrlKey and (ev.code=='KeyZ' or ev.code=='KeyY') then ev:stopPropagation();self:run(function() self:action(s,{action=ev.code=='KeyY' and 'redo' or 'undo'}) end) end
      end}
    :newrow():button{id='selected',text='Karte bearbeiten …',onclick=function() self:menu(s,s.selected) end}
    :button{id='undo',text='Notiz zurück',onclick=function() self:run(function() self:action(s,{action='undo'}) end) end}
    :button{id='redo',text='Vor',onclick=function() self:run(function() self:action(s,{action='redo'}) end) end}
    :button{text='Papierkorb',onclick=function()
      local choices,map={},{}
      for i,t in ipairs(s.board.trash) do local name=i..' · '..short(t.cards[1].title,28);choices[#choices+1]=name;map[name]=t.id end
      if #choices==0 then app.tip('Keine gelöschten Notizen.',3);return end
      local bin=Dialog{title='Gelöschte Notizkarten'}
      bin:combobox{id='item',options=choices}:button{text='Wiederherstellen',onclick=function() self:run(function() self:action(s,{action='restore',id=map[bin.data.item]});bin:close() end) end}:button{text='Schließen'}:show{wait=false}
    end}
    :button{id='draft',text='Entwurf weiter …',visible=false,onclick=function() for _,draft in pairs(s.drafts) do if draft.dirty then self:edit(s,draft.id,draft.field);break end end end}
    :newrow():label{id='state',text=self:status(s)}
  self:fit(s);d:show{wait=false};self:refresh(s)
end
function UI:tick()
  if self.failed then return end
  self.ticks=(self.ticks or 0)+1;if self.ticks%6~=0 then return end
  local current=app.sprite
  if current then
    local s=self:state(current)
    local c=self:session(s)
    if not s.seen and ((c and c.connected) or #s.board.cards>0) then self:show(current) end
  end
  for _,s in pairs(self.states) do
    local sprite=s.sprite
    if not sprite.isValid then
      if s.dialog then s.dialog:close() end
      -- Keep unsent text reachable until the user explicitly discards it.
      for _,d in pairs(s.drafts) do if d.dialog then d.error='Bild geschlossen – Entwurf kopieren';d.dialog:modify{id='apply',enabled=false} end end
    else
      local c=self:session(s)
      if not c then
        local board=N.read(sprite)
        if not N.equal(board,s.board) then s.board=board;s.history={undo={},redo={}} end
      end
      for _,d in pairs(s.drafts) do if d.dialog and c and c.connected and os.time()-(d.renewed or 0)>=5 then c:noteLock(d.id,d.field);d.renewed=os.time() end end
      self:refresh(s)
    end
  end
end
function UI:close()
  for _,s in pairs(self.states) do if s.dialog then s.dialog:close() end;for _,d in pairs(s.drafts) do if d.dialog then d.dialog:close() end end end
end
return UI
