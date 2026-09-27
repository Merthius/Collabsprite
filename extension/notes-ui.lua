-- A compact board surface with an island toolbar, marquee selection and boxes.
local dir=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local N=dofile(app.fs.joinPath(dir,'notes.lua'))
local T=dofile(app.fs.joinPath(dir,'notes-input.lua'))
local S=dofile(app.fs.joinPath(dir,'notes-stack.lua'))
local B=dofile(app.fs.joinPath(dir,'notes-board.lua'))
local F=dofile(app.fs.joinPath(dir,'notes-style.lua'))
local I=dofile(app.fs.joinPath(dir,'notes-image.lua'))
local L=dofile(app.fs.joinPath(dir,'ui-layout.lua'))
local UI={};UI.__index=UI
local function inside(r,x,y) return x>=r.x and y>=r.y and x<r.x+r.w and y<r.y+r.h end
local function rect(x,y,w,h) return {x=x,y=y,w=w,h=h} end
local function clamp(v) return math.floor(math.max(-10000,math.min(10000,v))) end
function UI.new(getSession,guestGuard,safe)
  return setmetatable({states={},getSession=getSession,guestGuard=guestGuard,safe=safe},UI)
end
function UI:state(sprite)
  if not self.states[sprite.id] then self.states[sprite.id]={sprite=sprite,board=N.read(sprite),history={undo={},redo={}},zoom=1,ox=24,oy=56,drafts={},seen=false,images={},selection={}} end
  return self.states[sprite.id]
end
function UI:session(s) local c=self.getSession();return c and c.sprite==s.sprite and (c.connected or c.connecting or c.reconnecting) and c or nil end
function UI:editable(s)
  local c=self:session(s);if c then return c.connected and not c.leaving end
  return not self.guestGuard(s.sprite)
end
function UI:run(fn) self.safe(fn) end
function UI:action(s,op,callback)
  assert(s.sprite.isValid and self:editable(s),'Notizen sind derzeit nur lesbar. Verbindung prüfen.')
  local c=self:session(s)
  if c then assert(not s.ack,'Eine Notizänderung wird noch bestätigt');c:noteAction(op);s.ack=callback or function() end
  else
    local history=N.copy(s.history);local next=N.localAction(s.board,history,op)
    local previous,layer,frame=app.sprite,app.layer,app.frame;app.sprite=s.sprite
    local ok,err=pcall(function() app.transaction('Collabsprite: Ideenwand',function() N.write(s.sprite,next) end) end)
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
      -- ACK precedes state: chain edits only after the authoritative revision.
      if s.ackResult then local fn,result=s.ack,s.ackResult;s.ack=nil;s.ackResult=nil;if fn then fn(result.ok,result.message) end end
    elseif message.type=='noteAck' then s.ackResult=message end
    self:refresh(s)
  end
  c.notesCanLeave=function() return self:canLeave(s) end
end
function UI:canLeave(s)
  if s.inline and s.inline.dirty and not s.inline.error then self:finishInline(s) end
  for _,d in pairs(s.drafts) do if d.dirty then
    app.tip('Notizentwurf noch offen. Rechtsklick auf das Element zum Vergleichen.',6)
    self:show(s.sprite);self:edit(s,d.id);return false
  end end
  local c=self:session(s)
  if c and c.notePending then app.tip('Notizänderung wird noch bestätigt. Bitte kurz warten.',4);return false end
  return true
end
function UI:refresh(s)
  if s.inline and s.inline.error and s.inline.error~=s.lastError then s.lastError=s.inline.error;app.tip(s.inline.error,5) end
  if not s.inline or not s.inline.error then s.lastError=nil end
  if s.cachedBoard~=s.board then
    local images={}
    for id in pairs(s.selection) do if not N.card(s.board,id) then s.selection[id]=nil end end
    if s.selected and not N.card(s.board,s.selected) then s.selected=next(s.selection) end
    for _,c in ipairs(s.board.cards) do if c.kind=='image' then
      local old=s.images[c.id];images[c.id]=old and N.equal(old.data,c.image) and old or {data=c.image,image=I.unpack(c.image)}
    end end
    s.images=images;s.cachedBoard=s.board
  end
  if s.dialog then s.dialog:repaint() end
end
function UI:layout(s)
  if s.drag and s.drag.group and s.drag.moved then
    local board=N.copy(s.drag.board)
    for _,patch in ipairs(B.move(s.drag.board,s.drag.selection,s.drag.dx,s.drag.dy).patches) do
      N.card(board,patch.id)[patch.field]=N.copy(patch.value)
    end
    return S.layout(board,s.inline)
  end
  return S.layout(s.board,s.inline,s.drag)
end
function UI:prepare(s) F.load();self:refresh(s) end
function UI:fit(s)
  s.zoom,s.ox,s.oy=B.fit(s.board,s.width or 660,s.height or 410)
  self:refresh(s)
end
function UI:reveal(s,id,caret)
  local _,map=B.display(self:layout(s),s.zoom,s.ox,s.oy);local v=map[id];if not v then return end
  local b=v.box;local x,y=v.x,v.y
  if x<12 then s.ox=s.ox+12-x elseif x+v.w>(s.width or 660)-12 then s.ox=s.ox+(s.width or 660)-12-x-v.w end
  if y<12 then s.oy=s.oy+12-y elseif y+math.min(v.h,160)>(s.height or 410)-12 then s.oy=s.oy+(s.height or 410)-12-y-math.min(v.h,160) end
  if caret and s.inline then
    local row=1;for i,v in ipairs(b.rows) do if s.inline.cursor>=v.start then row=i end end
    local _,ry=S.rowPosition(b,row)
    local _,current=B.display(self:layout(s),s.zoom,s.ox,s.oy)
    local cy=current[id].y+ry*v.scale
    if cy<12 then s.oy=s.oy+12-cy elseif cy+b.lineHeight*v.scale>(s.height or 410)-12 then s.oy=s.oy+(s.height or 410)-12-cy-b.lineHeight*v.scale end
  end
end
function UI:add(s,kind,style,point,image)
  if s.inline then return self:finishInline(s,function() self:add(s,kind,style,point,image) end) end
  point=point or {x=math.floor(((s.width or 660)/2-S.width*B.visualScale(s.zoom)/2-s.ox)/s.zoom),y=math.floor(((s.height or 410)/2-s.oy)/s.zoom)}
  local c=N.newCard('','',clamp(point.x),clamp(point.y));c.kind=kind or 'text';c.listStyle=style or 'check';c.color=F.colors[c.kind=='image' and 7 or c.kind=='list' and 2 or 1];c.image=image or false
  self:action(s,{action='patch',patches={{id=c.id,expected=false,value=c}}},function(ok,message)
    if ok then s.selected=c.id;s.selection={[c.id]=true};if c.kind~='image' then self:edit(s,c.id) end;self:reveal(s,c.id)
    else app.tip(message or 'Element konnte nicht erstellt werden.',5) end
  end)
end
function UI:import(s,point)
  local picker=Dialog{title='Referenzbild auswählen'}
  picker:file{id='path',title='Referenzbild',open=true,entry=false,filetypes={'png','jpg','jpeg','webp','gif','bmp'},onchange=function()
    local path=picker.data.path
    if path and path~='' then picker:close();self:run(function() self:add(s,'image',nil,point,I.load(path)) end) end
  end}:button{text='Abbrechen'}
  L.show(picker)
end
function UI:draftValue(d) return d.value end
function UI:endInline(s,d)
  local c=self:session(s);if c and c.connected then c:noteLock(d.id,d.field,true) end
  s.drafts[d.id..':'..d.field]=nil;if s.inline==d then s.inline=nil end;self:refresh(s)
end
function UI:finishInline(s,after)
  local d=s.inline;if not d then if after then after() end;return true end
  if after then d.after=after end
  if d.sending then return false end
  if not d.dirty then local fn=d.after;self:endInline(s,d);if fn then fn() end;return true end
  d.commitRequested=true
  local c=self:session(s)
  if not self:editable(s) then d.error='Verbindung fehlt · Entwurf bleibt hier.';d.commitRequested=false;return false end
  if c then
    if c.notePending or s.ack then return false end
    local owner
    for _,l in ipairs(c.noteLocks or {}) do if l.id==d.id and l.field==d.field then owner=l;break end end
    if not owner then
      if not d.requested or os.time()-d.requested>=3 then c:noteLock(d.id,d.field);d.requested=os.time() end
      return false
    end
    if owner.author~=c.author then d.error=owner.name..' bearbeitet diesen Text.';d.commitRequested=false;return false end
  end
  local current=N.card(s.board,d.id)
  if not current or current.versions.text~=d.base.versions.text or current.versions.title~=d.base.versions.title then
    d.error='Text wurde geändert · Rechtsklick zum Vergleichen.';d.commitRequested=false;self:refresh(s);return false
  end
  if not N.field('text',d.value) or (current.kind=='list' and select(2,d.value:gsub('\n',''))>=128) then d.error='Text zu lang (4096 Bytes / 128 Listenpunkte).';d.commitRequested=false;return false end
  local patches={N.patch(d.base,'text',d.value)}
  if d.base.title~='' then patches[#patches+1]=N.patch(d.base,'title','') end
  if current.kind=='list' then patches[#patches+1]=N.patch(current,'checks',S.checks(current,d.value)) end
  d.sending=true;d.commitRequested=false
  local ok,err=pcall(function() self:action(s,{action='patch',patches=patches},function(accepted,message)
    d.sending=false
    if not accepted then d.error=message or 'Entwurf bleibt erhalten.';d.after=nil;self:refresh(s);return end
    local card=N.card(s.board,d.id)
    if not card then d.error='Element gelöscht · Entwurf kopieren.';return end
    d.base=N.copy(card);d.dirty=d.value~=S.text(card)
    if d.dirty then d.commitRequested=true
    else local fn=d.after;self:endInline(s,d);if fn then fn() end end
  end) end)
  if not ok then d.sending=false;d.error=tostring(err);d.after=nil;self:refresh(s) end
  return not s.inline
end
function UI:edit(s,id)
  if s.inline then if s.inline.id==id then return end;return self:finishInline(s,function() self:edit(s,id) end) end
  local card=N.card(s.board,id);if not card or card.kind=='image' then return end
  if not self:editable(s) then app.tip('Notizen sind gerade nur lesbar.',4);return end
  local key=id..':text';local d=s.drafts[key]
  if not d then d=T.new(S.text(card));d.id=id;d.field='text';d.base=N.copy(card);d.dirty=false;s.drafts[key]=d end
  s.inline=d;s.selected=id
  local c=self:session(s);if c then c:noteLock(id,'text');d.renewed=os.time() end
  self:reveal(s,id);self:refresh(s)
end
function UI:inlineKey(s,ev)
  local d=s.inline;if not d then return end;ev:stopPropagation()
  if ev.code=='Escape' or ((ev.ctrlKey or ev.metaKey) and (ev.code=='Enter' or ev.code=='NumpadEnter')) then self:finishInline(s)
  elseif ev.code=='Enter' or ev.code=='NumpadEnter' then
    if not T.replace(d,'\n',4096) then d.error='Text zu lang.' end;d.dirty=d.value~=S.text(d.base)
  elseif ev.code~='Tab' then
    local previous=d.value;local err=T.key(d,ev,'text',app.clipboard)
    if err then d.error=err elseif previous~=d.value then d.dirty=d.value~=S.text(d.base) end
  end
  if s.inline then self:reveal(s,s.inline.id,true) end;self:refresh(s)
end
function UI:toggle(s,id,index)
  local c=assert(N.card(s.board,id));local value=c.checks..string.rep('0',math.max(0,index-#c.checks))
  value=value:sub(1,index-1)..(value:sub(index,index)=='1' and '0' or '1')..value:sub(index+1)
  self:action(s,{action='patch',patches={N.patch(c,'checks',value)}})
end
function UI:remove(s,id,tail)
  local c=N.card(s.board,id);if c then self:action(s,{action='delete',id=id,versions=N.copy(c.versions),revision=s.board.revision,children=tail}) end
end
function UI:chosen(s,id)
  if id and s.selection[id] then return N.copy(s.selection) end
  return id and {[id]=true} or N.copy(s.selection)
end
function UI:copy(s,id,tail)
  local text=tail and B.copyTail(s.board,id) or B.copy(s.board,id and {[id]=true} or s.selection)
  app.clipboard.text=text
end
function UI:paste(s,x,y)
  local clipboard=app.clipboard.content
  local text=clipboard and clipboard.text
  local image=clipboard and clipboard.image
  local point={x=clamp(((x or (s.width or 660)/2)-s.ox)/s.zoom),y=clamp(((y or (s.height or 410)/2)-s.oy)/s.zoom)}
  local operation,created
  if type(text)=='string' and text:find('"idea-board-elements-v1"',1,true) then
    operation,created=B.paste(s.board,text,point.x,point.y)
  elseif image then
    local c=N.newCard('','',point.x,point.y)
    c.kind='image';c.image=I.pack(image,clipboard.palette,0);c.color=F.colors[7]
    operation={action='patch',patches={{id=c.id,expected=false,value=c}}};created={c}
  elseif type(text)=='string' and text~='' then
    text=text:gsub('\r\n','\n'):gsub('\r','\n')
    assert(N.field('text',text),'Text aus Zwischenablage ist zu lang (4096 Bytes).')
    local c=N.newCard('','',point.x,point.y);c.text=text;c.color=F.colors[1]
    operation={action='patch',patches={{id=c.id,expected=false,value=c}}};created={c}
  else app.tip('Zwischenablage enthält keinen Text oder kein Bild.',4);return end
  self:action(s,operation,function(ok,message)
    if ok then
      s.selection={};for _,c in ipairs(created) do s.selection[c.id]=true end
      s.selected=created[1].id;self:reveal(s,created[1].id)
    else app.tip(message or 'Einfügen fehlgeschlagen.',5) end
  end)
end
function UI:duplicate(s,id,tail)
  local selected=id and {[id]=true} or s.selection
  local copied=tail and B.copyTail(s.board,id) or B.copy(s.board,selected)
  local _,map=self:layout(s)
  local minx,miny=1e6,1e6
  for key in pairs(selected) do if map[key] then minx=math.min(minx,map[key].x);miny=math.min(miny,map[key].y) end end
  local op,cards=B.paste(s.board,copied,minx+22,miny+22)
  self:action(s,op,function(ok,message)
    if ok then s.selection={};for _,c in ipairs(cards) do s.selection[c.id]=true end;s.selected=cards[1].id;self:reveal(s,cards[1].id)
    else app.tip(message or 'Duplizieren fehlgeschlagen.',5) end
  end)
end
function UI:deleteSelected(s)
  local selected=self:chosen(s,s.selected)
  if not next(selected) then return end
  local count=0;for _ in pairs(selected) do count=count+1 end
  if count==1 then
    local id=next(selected);local c=N.card(s.board,id)
    self:action(s,{action='delete',id=id,versions=N.copy(c.versions),revision=s.board.revision,children=false},function(ok,message)
      if ok then s.selection={};s.selected=nil else app.tip(message or 'Element wurde inzwischen verändert.',5) end
    end)
    return
  end
  self:action(s,B.delete(s.board,selected),function(ok,message)
    if ok then s.selection={};s.selected=nil else app.tip(message or 'Auswahl wurde inzwischen verändert.',5) end
  end)
end
function UI:menu(s,id,x,y,page)
  local items={};local function item(label,fn) items[#items+1]={label=label,fn=fn} end
  local c=id and N.card(s.board,id);local draft=s.inline
  local function submenu(label,nextPage) item(label..' >',function() self:menu(s,id,x,y,nextPage) end) end
  if page then item('Zurück',function() self:menu(s,id,x,y) end) end
  if draft and draft.error then
    -- A conflicting unsent draft must remain recoverable even when the normal
    -- element menu is deliberately reduced to four actions.
    item('Entwurf kopieren',function() app.clipboard.text=draft.value end)
    item('Gemeinsamen Text ansehen',function() local now=N.card(s.board,draft.id);self:compare(s,now and S.text(now) or 'Element wurde gelöscht.') end)
    item('Meinen Text übernehmen',function()
      local now=N.card(s.board,draft.id);if not now then return end
      draft.base=N.copy(now);draft.error=nil;draft.dirty=draft.value~=S.text(now);self:finishInline(s)
    end)
    item('Entwurf verwerfen',function() if not draft.sending then self:endInline(s,draft) end end)
  elseif page=='copy' and c then
    item('Nur Element',function() self:copy(s,id,false) end)
    if #S.tail(s.board,id)>1 then item('Stapel ab hier',function() self:copy(s,id,true) end) end
    if s.selection[id] and next(s.selection,next(s.selection)) then
      item('Auswahl',function() self:copy(s,nil,false) end)
    end
  else
    if not c then
      item('Einfügen',function() self:paste(s,x,y) end)
    else
      item('Löschen',function()
        if s.selection[id] and next(s.selection,next(s.selection)) then self:deleteSelected(s)
        else self:remove(s,id,false) end
      end)
      submenu('Kopieren','copy')
      item('Duplizieren',function() self:duplicate(s,id,false) end)
      items[#items+1]={label='Farbe',section=true}
      items[#items+1]={colors=true,id=id}
    end
  end
  local width=160
  for _,v in ipairs(items) do if v.label then width=math.max(width,F.measure(v.label,false)+26) end end
  s.menu={x=x,y=y,w=width,items=items,offset=0};s.menuHover=nil
  self:refresh(s)
end
function UI:compare(s,text)
  local d=Dialog{title='Gemeinsamer Text'};local w,h=L.canvas(510,300)
  local rows=S.lines(text,false,w-24);local offset=0
  d:canvas{width=w,height=h,autoscaling=false,onpaint=function(ev)
    local gc=ev.context;gc.color=F.color('#2B2C30');gc:fillRect(Rectangle(0,0,gc.width,gc.height))
    for i=offset+1,math.min(#rows,offset+math.floor((gc.height-16)/20)) do F.draw(gc,rows[i].text,12,8+(i-offset-1)*20,1,false,true) end
  end,onwheel=function(ev) offset=math.max(0,math.min(math.max(0,#rows-1),offset+ev.deltaY*3));d:repaint() end}
    :newrow():button{text='Schließen'}
  L.show(d)
end
function UI:paint(s,ev)
  local gc=ev.context;s.width=gc.width;s.height=gc.height;s.hits={}
  gc.antialias=true;gc.opacity=255;gc.color=Color{r=39,g=40,b=43};gc:fillRect(Rectangle(0,0,gc.width,gc.height))
  local function hit(id,kind,r,extra) s.hits[#s.hits+1]={id=id,kind=kind,r=r,extra=extra} end
  local boxes=self:layout(s)
  local moving=s.drag and s.drag.moved and (s.drag.group and s.drag.selection or {[s.drag.id]=true})
  local displays,displayMap=B.display(boxes,s.zoom,s.ox,s.oy,moving)
  for _,v in ipairs(displays) do
    local b=v.box;local c=b.card;local x,y,w,h,z=v.x,v.y,v.w,v.h,v.scale
    if x+w>0 and y+h>0 and x<gc.width and y<gc.height then
      local d=s.inline and s.inline.id==c.id and s.inline or nil
      F.box(gc,x,y+2,w,h,Color{r=23,g=24,b=26,a=120},5*z)
      local border=d and d.error and '#CF6F7E' or s.selection[c.id] and '#A9D6CA' or '#5D6268'
      F.box(gc,x-1,y-1,w+2,h+2,F.color(border),6*z)
      F.box(gc,x,y,w,h,F.paper(c.color),5*z)
      hit(c.id,'drag',rect(x,y,w,h),b)
      if c.kind=='image' then
        local cached=s.images[c.id]
        if cached then
          local scale=math.min((b.w-20)/c.image.width,210/c.image.height)*z
          local iw,ih=c.image.width*scale,c.image.height*scale
          gc:drawImage(cached.image,Rectangle(0,0,c.image.width,c.image.height),Rectangle(math.floor(x+(w-iw)/2),math.floor(y+12*z),math.max(1,math.floor(iw)),math.max(1,math.floor(ih))))
        end
      else
        local rows=b.rows
        hit(c.id,'text',rect(x+12*z,y+8*z,w-24*z,h-16*z),b)
        if d then d.draw={lines={},heading=b.heading,z=z} end
        local a,finish=0,0;if d then a,finish=T.selection(d) end
        for i,row in ipairs(rows) do
          local text=row.text
          local placeholder=text=='' and #rows==1
          local shown=placeholder and (c.kind=='list' and 'Listenpunkt …' or 'Text …') or text
          local rx,top=S.rowPosition(b,i,placeholder and not d and shown or text)
          local tx,ry=x+rx*z,y+top*z
          if d then
            local left=math.max(0,a-row.start);local right=math.min(T.length(text),finish-row.start)
            if right>left then
              gc.color=Color{r=113,g=156,b=187,a=100};gc:fillRect(Rectangle(math.floor(tx+F.measure(T.slice(text,0,left),b.heading)*z),math.floor(ry),math.max(1,math.floor((F.measure(T.slice(text,0,right),b.heading)-F.measure(T.slice(text,0,left),b.heading))*z)),math.floor(b.lineHeight*z)))
            end
            local widths={};for n=0,T.length(text) do widths[n]=F.measure(T.slice(text,0,n),b.heading)*z end
            d.draw.lines[#d.draw.lines+1]={r=rect(tx,ry,math.max(1,F.measure(text,b.heading))*z,b.lineHeight*z),widths=widths,start=row.start,length=T.length(text)}
            if d.cursor>=row.start and d.cursor<=row.start+T.length(text) then
              local cx=tx+widths[d.cursor-row.start];gc.color=Color{r=43,g=66,b=82};gc:fillRect(Rectangle(math.floor(cx),math.floor(ry+3*z),math.max(1,math.floor(z)),math.floor((b.lineHeight-5)*z)))
            end
          end
          if c.kind=='list' and row.first then
            if c.listStyle=='check' then
              local done=c.checks:sub(row.index,row.index)=='1';local cr=rect(tx-24*z,ry+4*z,13*z,13*z)
              F.box(gc,cr.x,cr.y,cr.w,cr.h,F.color(done and '#7EAC97' or '#839A8D'),3*z)
              if not done then F.box(gc,cr.x+z,cr.y+z,cr.w-2*z,cr.h-2*z,F.paper(c.color),2*z)
              else gc.color=Color{r=250,g=255,b=251};gc:beginPath();gc:moveTo(cr.x+3*z,cr.y+6*z);gc:lineTo(cr.x+6*z,cr.y+9*z);gc:lineTo(cr.x+11*z,cr.y+3*z);gc:stroke() end
              hit(c.id,'check',cr,row.index)
            elseif c.listStyle=='number' then F.draw(gc,row.index..'.',tx-24*z,ry,z,false)
            else F.box(gc,tx-19*z,ry+8*z,4*z,4*z,F.color('#526559'),2*z) end
          end
          if placeholder then gc.opacity=110;if not d then text=shown end end
          F.draw(gc,text,tx,ry,z,b.heading);gc.opacity=255
          if c.kind=='list' and c.listStyle=='check' and c.checks:sub(row.index,row.index)=='1' and text~='' and not placeholder then
            gc.color=Color{r=43,g=57,b=62,a=230}
            gc:fillRect(Rectangle(math.floor(tx),math.floor(ry+10*z+0.5),math.max(1,math.floor(F.measure(text,b.heading)*z+0.5)),math.max(1,math.floor(z+0.5))))
          end
        end
      end
      if s.selection[c.id] or s.hover==c.id then F.box(gc,x+w/2-10*z,y+3*z,20*z,2*z,Color{r=103,g=114,b=121,a=100},z) end
      if d and (d.error or d.sending) then F.box(gc,x+w-10*z,y+7*z,4*z,4*z,F.color(d.error and '#B74158' or '#7295AB'),2*z) end
    end
  end
  if s.drag and s.drag.target then local v=displayMap[s.drag.target.card.id];if v then
    F.box(gc,v.x,v.y+v.h+2*v.scale,v.w,3*v.scale,F.color('#B7DBC7'),v.scale)
  end end
  if s.marquee then
    local a=s.marquee;local x,y=math.min(a.x1,a.x2),math.min(a.y1,a.y2)
    local w,h=math.abs(a.x2-a.x1),math.abs(a.y2-a.y1)
    if w>2 and h>2 then
      F.box(gc,x,y,w,h,Color{r=138,g=199,b=190,a=42},3)
      gc.color=F.color('#8ECFC6');gc:strokeRect(Rectangle(x,y,w,h))
    end
  end
  -- A small floating island replaces creation commands in the context menu.
  local tools={
    {label='Text',icon='T',run=function() self:add(s,'text') end},
    {label='Checkliste',icon='✓',run=function() self:add(s,'list','check') end},
    {label='Punktliste',icon='•',run=function() self:add(s,'list','bullet') end},
    {label='Nummeriert',icon='1',run=function() self:add(s,'list','number') end},
    {label='Bild',icon='▣',run=function() self:import(s) end},
  }
  local button=26;local gap=4;local islandW=5*button+6*gap;local islandX=math.floor((gc.width-islandW)/2);local islandY=7
  F.box(gc,islandX+1,islandY+2,islandW,button+8,F.color('#17191C'),10)
  F.box(gc,islandX,islandY,islandW,button+8,F.color('#3E4249'),10)
  for i,tool in ipairs(tools) do
    local tx=islandX+gap+(i-1)*(button+gap);local ty=islandY+4
    local active=s.toolHover==i
    F.box(gc,tx,ty,button,button,F.color(active and '#606F75' or '#34383E'),6)
    if i==2 then
      F.box(gc,tx+5,ty+6,5,5,F.color('#BDDAD4'),1);F.box(gc,tx+5,ty+15,5,5,F.color('#BDDAD4'),1)
      F.box(gc,tx+12,ty+8,9,2,F.color('#E4E9EB'),1);F.box(gc,tx+12,ty+17,9,2,F.color('#E4E9EB'),1)
    elseif i==3 then
      F.box(gc,tx+5,ty+8,4,4,F.color('#BDDAD4'),2);F.box(gc,tx+5,ty+17,4,4,F.color('#BDDAD4'),2)
      F.box(gc,tx+12,ty+9,9,2,F.color('#E4E9EB'),1);F.box(gc,tx+12,ty+18,9,2,F.color('#E4E9EB'),1)
    elseif i==4 then
      F.draw(gc,'1',tx+5,ty+1,0.75,false,true);F.draw(gc,'2',tx+5,ty+11,0.75,false,true)
      F.box(gc,tx+13,ty+8,8,2,F.color('#E4E9EB'),1);F.box(gc,tx+13,ty+18,8,2,F.color('#E4E9EB'),1)
    elseif i==5 then
      gc.color=F.color('#E4E9EB');gc:strokeRect(Rectangle(tx+5,ty+6,16,14))
      gc:beginPath();gc:moveTo(tx+7,ty+18);gc:lineTo(tx+12,ty+13);gc:lineTo(tx+16,ty+16);gc:lineTo(tx+20,ty+10);gc:stroke()
    else F.draw(gc,tool.icon,tx+9,ty+4,1,false,true) end
    hit(nil,'tool',rect(tx,ty,button,button),{index=i,run=tool.run})
  end
  if s.toolHover then
    local label=tools[s.toolHover].label;local w=F.measure(label,false)+18
    F.box(gc,islandX+(islandW-w)/2,islandY+button+11,w,22,F.color('#3E4249'),6)
    F.draw(gc,label,islandX+(islandW-w)/2+9,islandY+button+13,1,false,true)
  end
  local fitW=26;local footerY=gc.height-34;local fitX=gc.width-fitW-9
  local percent=math.floor(s.zoom*100+0.5)..' %';local labelW=F.measure(percent,false)+14
  F.box(gc,fitX-labelW-4,footerY,labelW,25,F.color('#393D43'),7)
  F.draw(gc,percent,fitX-labelW+3,footerY+3,1,false,true)
  F.box(gc,fitX,footerY,fitW,25,F.color(s.fitHover and '#60756E' or '#47524F'),7)
  gc.color=F.color('#E6F0EC');gc:beginPath()
  for _,corner in ipairs({{6,10,6,6,10,6},{20,10,20,6,16,6},{6,15,6,19,10,19},{20,15,20,19,16,19}}) do
    gc:moveTo(fitX+corner[1],footerY+corner[2]);gc:lineTo(fitX+corner[3],footerY+corner[4]);gc:lineTo(fitX+corner[5],footerY+corner[6])
  end
  gc:stroke()
  hit(nil,'fit',rect(fitX,footerY,fitW,25),function() self:fit(s) end)
  if s.fitHover then
    local label='Alle Boxen';local tooltipW=F.measure(label,false)+18
    F.box(gc,fitX+fitW-tooltipW,footerY-27,tooltipW,22,F.color('#3E4249'),6)
    F.draw(gc,label,fitX+fitW-tooltipW+9,footerY-25,1,false,true)
  end
  if s.menu then
    local m=s.menu;local rowHeight=22
    m.w=math.min(m.w,gc.width-8);m.visible=math.max(1,math.min(#m.items,math.floor((gc.height-18)/rowHeight)))
    m.offset=math.min(m.offset,#m.items-m.visible);local mh=m.visible*rowHeight+10
    m.x=math.max(4,math.min(m.x,gc.width-m.w-4));m.y=math.max(4,math.min(m.y,gc.height-mh-4))
    F.box(gc,m.x+2,m.y+3,m.w,mh,F.color('#191A1C'),4)
    F.box(gc,m.x-1,m.y-1,m.w+2,mh+2,F.color('#62636A'),4)
    F.box(gc,m.x,m.y,m.w,mh,F.color('#333438'),3)
    for i=m.offset+1,math.min(#m.items,m.offset+m.visible) do
      local item=m.items[i];local r=rect(m.x+5,m.y+5+(i-m.offset-1)*rowHeight,m.w-10,rowHeight)
      if item.colors then
        local step=r.w/#F.colors
        local current=N.card(s.board,item.id)
        for n,color in ipairs(F.colors) do
          local cr=rect(r.x+2+(n-1)*step,r.y+2,step-4,18)
          if current and current.color==color then F.box(gc,cr.x-1,cr.y-1,cr.w+2,cr.h+2,F.color('#E8F0F4'),4) end
          F.box(gc,cr.x,cr.y,cr.w,cr.h,F.color(color),3);hit(item.id,'color',cr,color)
        end
      else
        if s.menuHover==i and not item.section then F.box(gc,r.x,r.y,r.w,r.h,F.color('#50535B'),2) end
        F.draw(gc,item.label,r.x+8,r.y+2,1,false,true)
        if not item.section then hit(nil,'menu',r,item.fn) end
      end
    end
    if m.offset>0 then F.box(gc,m.x+m.w/2-8,m.y,16,2,F.color('#AEBECD'),1) end
    if m.offset+m.visible<#m.items then F.box(gc,m.x+m.w/2-8,m.y+mh-2,16,2,F.color('#AEBECD'),1) end
  end
end
function UI:hit(s,x,y)
  for i=#(s.hits or {}),1,-1 do local h=s.hits[i];if inside(h.r,x,y) then return h.id,h end end
end
function UI:placeCaret(d,x,y)
  if not d.draw then return end
  local rows=d.draw.lines;local row=rows[#rows]
  for _,r in ipairs(rows) do if y<r.r.y+r.r.h then row=r;break end end
  local pos=0;for n=1,row.length do if x-row.r.x>=(row.widths[n-1]+row.widths[n])/2 then pos=n else break end end
  d.cursor=row.start+pos
end
function UI:pointerDown(s,ev)
  s.pointerDown=true;local id,h=self:hit(s,ev.x,ev.y)
  if ev.button==MouseButton.RIGHT then
    if id and not s.selection[id] then s.selection={[id]=true};s.selected=id end
    if s.inline and not s.inline.error then self:finishInline(s,function() self:menu(s,id,ev.x,ev.y) end)
    else self:menu(s,id,ev.x,ev.y) end;return
  end
  if s.menu then
    s.menu=nil
    if h and h.kind=='menu' then h.extra();self:refresh(s);return
    elseif h and h.kind=='color' then local c=N.card(s.board,h.id);if c then self:action(s,{action='patch',patches={N.patch(c,'color',h.extra)}}) end;return end
    self:refresh(s);return
  end
  if ev.button==MouseButton.MIDDLE then s.drag={startX=ev.x,startY=ev.y,ox=s.ox,oy=s.oy};return end
  if ev.button~=MouseButton.LEFT then return end
  local d=s.inline
  if h and (h.kind=='tool' or h.kind=='fit') then
    local fn=h.kind=='tool' and h.extra.run or h.extra
    if d then self:finishInline(s,fn) else fn() end
    return
  end
  if d and id==d.id and h.kind=='text' then self:placeCaret(d,ev.x,ev.y);if not ev.shiftKey then d.anchor=d.cursor end;s.selecting=true;self:refresh(s);return end
  local function activate()
    if not s.pointerDown then return end
    s.selected=id
    if h and h.kind=='text' and not (s.selection[id] and next(s.selection,next(s.selection))) then
      s.selection={[id]=true};self:edit(s,id);return
    end
    if h and h.kind=='check' then self:toggle(s,id,h.extra);return end
    if id and self:editable(s) then
      local b=h.extra
      if not s.selection[id] then s.selection={[id]=true} end
      local group=next(s.selection,next(s.selection))~=nil
      s.drag={id=id,group=group,selection=N.copy(s.selection),board=N.copy(s.board),
        startX=ev.x,startY=ev.y,x=b.x,y=b.y,baseX=b.x,baseY=b.y,dx=0,dy=0}
    elseif not id then
      s.marquee={x1=ev.x,y1=ev.y,x2=ev.x,y2=ev.y,previous=ev.shiftKey and N.copy(s.selection) or {}}
    end
    self:refresh(s)
  end
  if d then self:finishInline(s,activate) else activate() end
end
function UI:pointerMove(s,ev)
  if s.pointerDown and s.selecting and s.inline then self:placeCaret(s.inline,ev.x,ev.y);self:refresh(s);return end
  if s.pointerDown and s.marquee then s.marquee.x2=ev.x;s.marquee.y2=ev.y end
  local a=s.drag
  if a then
    if a.id then
      a.dx=math.floor((ev.x-a.startX)/s.zoom+0.5);a.dy=math.floor((ev.y-a.startY)/s.zoom+0.5)
      a.x=clamp(a.baseX+a.dx);a.y=clamp(a.baseY+a.dy)
      a.moved=a.moved or math.abs(ev.x-a.startX)+math.abs(ev.y-a.startY)>4
      if a.moved and not a.group then a.target=B.target(a.board,self:layout(s),a,s.zoom,s.ox,s.oy) end
    else s.ox=a.ox+ev.x-a.startX;s.oy=a.oy+ev.y-a.startY end
  end
  local id,h=self:hit(s,ev.x,ev.y);s.hover=id
  s.toolHover=h and h.kind=='tool' and h.extra.index or nil
  s.fitHover=h and h.kind=='fit' or false
  if s.menu then s.menuHover=s.menu.offset+math.floor((ev.y-s.menu.y-5)/22)+1 end
  self:refresh(s)
end
function UI:pointerUp(s)
  local a=s.drag;local marquee=s.marquee;s.drag=nil;s.marquee=nil;s.pointerDown=false;s.selecting=false
  if marquee then
    s.selection=marquee.previous
    local selected=B.selectDisplay(B.display(self:layout(s),s.zoom,s.ox,s.oy),marquee.x1,marquee.y1,marquee.x2,marquee.y2)
    for id in pairs(selected) do s.selection[id]=true end
    s.selected=next(s.selection)
  end
  if a and a.id and a.moved then
    local b=a.target
    local operation=a.group and B.move(a.board,a.selection,a.dx,a.dy) or
      S.move(a.board,a.id,b and b.x or a.x,b and b.y+b.h+S.gap or a.y,b and b.card.id or nil)
    self:action(s,operation,function(ok,message) if not ok then app.tip(message or 'Stapel wurde inzwischen verändert.',5) end end)
  end
  self:refresh(s)
end
function UI:show(sprite)
  sprite=sprite or app.sprite;if not sprite then app.tip('Bitte zuerst ein Bild öffnen.',4);return end
  local s=self:state(sprite);s.seen=true;if s.dialog then return end
  self:prepare(s)
  s.dialog=Dialog{title='Ideenwand · '..L.short(app.fs.fileTitle(sprite.filename~='' and sprite.filename or 'Bild'),32),onclose=function()
    s.dialog=nil;s.pointerDown=false;s.selecting=false;s.drag=nil;s.marquee=nil;s.menu=nil;self:run(function() self:finishInline(s) end)
  end}
  local d=s.dialog
  local width,height=L.canvas(900,600);s.width=width;s.height=height
  d:canvas{id='board',width=width,height=height,autoscaling=false,focus=true,
    onpaint=function(ev) self:paint(s,ev) end,
    onmousedown=function(ev) self:run(function() self:pointerDown(s,ev) end) end,
    onmousemove=function(ev) self:pointerMove(s,ev) end,
    onmouseup=function() self:run(function() self:pointerUp(s) end) end,
    onwheel=function(ev)
      if s.menu then s.menu.offset=math.max(0,math.min(#s.menu.items-(s.menu.visible or 1),s.menu.offset+ev.deltaY));self:refresh(s);return end
      if ev.shiftKey then s.oy=s.oy-ev.deltaY*30
      else local old=s.zoom;s.zoom=math.max(0.01,math.min(3,s.zoom*(ev.deltaY>0 and 0.85 or 1.18)));s.ox=ev.x-(ev.x-s.ox)*s.zoom/old;s.oy=ev.y-(ev.y-s.oy)*s.zoom/old end
      self:refresh(s)
    end,
    onkeydown=function(ev)
      ev:stopPropagation()
      self:run(function()
        if ev.code=='Escape' and s.menu then s.menu=nil;self:refresh(s);return end
        if s.inline then self:inlineKey(s,ev);return end
        if ev.ctrlKey or ev.metaKey then
          if ev.code=='KeyZ' or ev.code=='KeyY' then self:action(s,{action=(ev.code=='KeyY' or ev.shiftKey) and 'redo' or 'undo'})
          elseif ev.code=='KeyA' then s.selection={};for _,c in ipairs(s.board.cards) do s.selection[c.id]=true end;s.selected=next(s.selection);self:refresh(s)
          elseif ev.code=='KeyC' and s.selected then self:copy(s,nil,false)
          elseif ev.code=='KeyV' then self:paste(s)
          elseif ev.code=='KeyD' and s.selected then self:duplicate(s,nil,false) end
        elseif (ev.code=='Delete' or ev.code=='Backspace') and s.selected then self:deleteSelected(s)
        elseif ev.code=='Enter' and s.selected then self:edit(s,s.selected) end
      end)
    end}
  self:fit(s);L.show(d);self:refresh(s)
end
function UI:tick()
  if self.failed then return end
  self.ticks=(self.ticks or 0)+1;if self.ticks%6~=0 then return end
  local current=app.sprite
  if current then local s=self:state(current);local c=self:session(s);if not s.seen and ((c and c.connected) or #s.board.cards>0) then self:show(current) end end
  for id,s in pairs(self.states) do
    if not s.sprite.isValid then if s.dialog then s.dialog:close() end;if not next(s.drafts) then self.states[id]=nil end
    else
      local c=self:session(s)
      if not c then local raw=s.sprite.properties(N.key).board
        if raw~=s.raw then s.raw=raw;local board=N.read(s.sprite);if not N.equal(board,s.board) then s.board=board;s.history={undo={},redo={}} end end
      end
      local d=s.inline
      if d and c and c.connected and os.time()-(d.renewed or 0)>=5 then c:noteLock(d.id,d.field);d.renewed=os.time() end
      if d and d.commitRequested and not d.sending then self:finishInline(s) end
      if s.renderedBoard~=s.board or (c and s.renderedLocks~=c.noteLocks) then s.renderedBoard=s.board;s.renderedLocks=c and c.noteLocks;self:refresh(s) end
    end
  end
end
function UI:close() for _,s in pairs(self.states) do if s.dialog then s.dialog:close() end end end
return UI
