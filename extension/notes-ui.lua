-- One free surface: context insertion, inline text and magnetic pastel boxes.
local dir=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local N=dofile(app.fs.joinPath(dir,'notes.lua'))
local T=dofile(app.fs.joinPath(dir,'notes-input.lua'))
local S=dofile(app.fs.joinPath(dir,'notes-stack.lua'))
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
  if not self.states[sprite.id] then self.states[sprite.id]={sprite=sprite,board=N.read(sprite),history={undo={},redo={}},zoom=1,ox=24,oy=24,drafts={},seen=false,images={}} end
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
    for _,c in ipairs(s.board.cards) do if c.kind=='image' then
      local old=s.images[c.id];images[c.id]=old and N.equal(old.data,c.image) and old or {data=c.image,image=I.unpack(c.image)}
    end end
    s.images=images;s.cachedBoard=s.board
  end
  if s.dialog then s.dialog:repaint() end
end
function UI:layout(s) return S.layout(s.board,s.inline,s.drag) end
function UI:prepare(s) F.load();self:refresh(s) end
function UI:fit(s)
  local boxes=self:layout(s);if #boxes==0 then s.zoom=1;s.ox=24;s.oy=24;return end
  local minx,miny,maxx,maxy=1e6,1e6,-1e6,-1e6
  for _,b in ipairs(boxes) do minx=math.min(minx,b.x);miny=math.min(miny,b.y);maxx=math.max(maxx,b.x+b.w);maxy=math.max(maxy,b.y+b.h) end
  s.zoom=math.max(0.25,math.min(1,((s.width or 660)-48)/(maxx-minx),((s.height or 410)-48)/(maxy-miny)))
  s.ox=24-minx*s.zoom;s.oy=24-miny*s.zoom;self:refresh(s)
end
function UI:reveal(s,id,caret)
  local _,map=self:layout(s);local b=map[id];if not b then return end
  local x,y=s.ox+b.x*s.zoom,s.oy+b.y*s.zoom
  if x<12 then s.ox=s.ox+12-x elseif x+b.w*s.zoom>(s.width or 660)-12 then s.ox=s.ox+(s.width or 660)-12-x-b.w*s.zoom end
  if y<12 then s.oy=s.oy+12-y elseif y+math.min(b.h,160)*s.zoom>(s.height or 410)-12 then s.oy=s.oy+(s.height or 410)-12-y-math.min(b.h,160)*s.zoom end
  if caret and s.inline then
    local row=1;for i,v in ipairs(b.rows) do if s.inline.cursor>=v.start then row=i end end
    local _,ry=S.rowPosition(b,row)
    local cy=s.oy+(b.y+ry)*s.zoom
    if cy<12 then s.oy=s.oy+12-cy elseif cy+b.lineHeight*s.zoom>(s.height or 410)-12 then s.oy=s.oy+(s.height or 410)-12-cy-b.lineHeight*s.zoom end
  end
end
function UI:add(s,kind,style,point,image)
  if s.inline then return self:finishInline(s,function() self:add(s,kind,style,point,image) end) end
  point=point or {x=math.floor((40-s.ox)/s.zoom),y=math.floor((40-s.oy)/s.zoom)}
  local c=N.newCard('','',clamp(point.x),clamp(point.y));c.kind=kind or 'text';c.listStyle=style or 'check';c.color=F.colors[c.kind=='image' and 7 or c.kind=='list' and 2 or 1];c.image=image or false
  self:action(s,{action='patch',patches={{id=c.id,expected=false,value=c}}},function(ok,message)
    if ok then s.selected=c.id;if c.kind~='image' then self:edit(s,c.id) end;self:reveal(s,c.id)
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
function UI:menu(s,id,x,y,page)
  local items={};local function item(label,fn) items[#items+1]={label=label,fn=fn} end
  local point={x=clamp((x-s.ox)/s.zoom),y=clamp((y-s.oy)/s.zoom)}
  local c=id and N.card(s.board,id);local draft=s.inline
  local function submenu(label,nextPage) item(label..' →',function() self:menu(s,id,x,y,nextPage) end) end
  if page then item('Zurück',function() self:menu(s,id,x,y) end) end
  if page=='list' then
    item('Checkliste',function() self:add(s,'list','check',point) end)
    item('Punktliste',function() self:add(s,'list','bullet',point) end)
    item('Nummerierte Liste',function() self:add(s,'list','number',point) end)
  elseif page=='style' and c then
    for _,style in ipairs({{'check','Checkliste'},{'bullet','Punktliste'},{'number','Nummeriert'}}) do item(style[2],function() self:action(s,{action='patch',patches={N.patch(N.card(s.board,id),'listStyle',style[1])}}) end) end
  elseif draft and draft.error then
    item('Entwurf kopieren',function() app.clipboard.text=draft.value end)
    item('Gemeinsamen Text ansehen',function() local now=N.card(s.board,draft.id);self:compare(s,now and S.text(now) or 'Element wurde gelöscht.') end)
    item('Meinen Text übernehmen',function()
      local now=N.card(s.board,draft.id);if not now then return end
      draft.base=N.copy(now);draft.error=nil;draft.dirty=draft.value~=S.text(now);self:finishInline(s)
    end)
    item('Entwurf verwerfen',function() if not draft.sending then self:endInline(s,draft) end end)
  else
    if not c or page=='add' then
      item('Text',function() self:add(s,'text',nil,point) end)
      submenu('Liste','list')
      item('Referenzbild …',function() self:import(s,point) end)
    else
      items[#items+1]={colors=true,id=id}
      if c.kind~='image' then item('Text bearbeiten',function() self:edit(s,id) end) end
      if c.kind=='list' then submenu('Listenart','style') end
      submenu('Neues Element','add')
      item('Element löschen',function() self:remove(s,id,false) end)
      if #S.tail(s.board,id)>1 then item('Teilstapel löschen',function() self:remove(s,id,true) end) end
    end
    if not page then
      item('Rückgängig  ·  Strg+Z',function() self:action(s,{action='undo'}) end)
      if #s.board.trash>0 then item('Löschung wiederherstellen',function() self:action(s,{action='restore',id=s.board.trash[#s.board.trash].id}) end) end
      item('Alles einpassen',function() self:fit(s) end)
    end
  end
  local width=216
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
  local z=s.zoom;local boxes=self:layout(s)
  for _,b in ipairs(boxes) do
    local c=b.card;local x,y=s.ox+b.x*z,s.oy+b.y*z;local w,h=b.w*z,b.h*z
    if x+w>0 and y+h>0 and x<gc.width and y<gc.height then
      local d=s.inline and s.inline.id==c.id and s.inline or nil
      F.box(gc,x,y+2,w,h,Color{r=23,g=24,b=26,a=120},5*z)
      local border=d and d.error and '#CF6F7E' or s.selected==c.id and '#AAC6D4' or '#5D6268'
      F.box(gc,x-1,y-1,w+2,h+2,F.color(border),6*z)
      F.box(gc,x,y,w,h,F.paper(c.color),5*z)
      hit(c.id,'drag',rect(x,y,w,h),b)
      if c.kind=='image' then
        local cached=s.images[c.id]
        if cached then
          local scale=math.min((b.w-24)/c.image.width,260/c.image.height)*z
          local iw,ih=c.image.width*scale,c.image.height*scale
          gc:drawImage(cached.image,Rectangle(0,0,c.image.width,c.image.height),Rectangle(math.floor(x+(w-iw)/2),math.floor(y+14*z),math.max(1,math.floor(iw)),math.max(1,math.floor(ih))))
        end
      else
        local rows=b.rows
        hit(c.id,'text',rect(x+14*z,y+10*z,w-28*z,h-20*z),b)
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
        end
      end
      if s.selected==c.id or s.hover==c.id then F.box(gc,x+w/2-10*z,y+4*z,20*z,2*z,Color{r=103,g=114,b=121,a=100},z) end
      if d and (d.error or d.sending) then F.box(gc,x+w-10*z,y+7*z,4*z,4*z,F.color(d.error and '#B74158' or '#7295AB'),2*z) end
    end
  end
  if s.drag and s.drag.target then local b=s.drag.target;F.box(gc,s.ox+b.x*z,s.oy+(b.y+b.h+2)*z,S.width*z,3*z,F.color('#B7DBC7'),z) end
  if s.menu then
    local m=s.menu;local rowHeight=25
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
        for n,color in ipairs(F.colors) do local cr=rect(r.x+3+(n-1)*step,r.y+4,step-6,17);F.box(gc,cr.x,cr.y,cr.w,cr.h,F.color(color),3);hit(item.id,'color',cr,color) end
      else
        if s.menuHover==i then F.box(gc,r.x,r.y,r.w,r.h,F.color('#50535B'),2) end
        F.draw(gc,item.label,r.x+8,r.y+2,1,false,true);hit(nil,'menu',r,item.fn)
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
  if d and id==d.id and h.kind=='text' then self:placeCaret(d,ev.x,ev.y);if not ev.shiftKey then d.anchor=d.cursor end;s.selecting=true;self:refresh(s);return end
  local function activate()
    if not s.pointerDown then return end
    s.selected=id
    if h and h.kind=='text' then self:edit(s,id);return end
    if h and h.kind=='check' then self:toggle(s,id,h.extra);return end
    if id and self:editable(s) then local b=h.extra;s.drag={id=id,board=N.copy(s.board),startX=ev.x,startY=ev.y,x=b.x,y=b.y,baseX=b.x,baseY=b.y}
    elseif not id then s.drag={startX=ev.x,startY=ev.y,ox=s.ox,oy=s.oy} end
    self:refresh(s)
  end
  if d then self:finishInline(s,activate) else activate() end
end
function UI:pointerMove(s,ev)
  if s.pointerDown and s.selecting and s.inline then self:placeCaret(s.inline,ev.x,ev.y);self:refresh(s);return end
  local a=s.drag
  if a then
    if a.id then
      a.x=clamp(a.baseX+(ev.x-a.startX)/s.zoom);a.y=clamp(a.baseY+(ev.y-a.startY)/s.zoom)
      a.moved=a.moved or math.abs(ev.x-a.startX)+math.abs(ev.y-a.startY)>4
      if a.moved then a.target=S.target(a.board,self:layout(s),a) end
    else s.ox=a.ox+ev.x-a.startX;s.oy=a.oy+ev.y-a.startY end
  end
  s.hover=self:hit(s,ev.x,ev.y);if s.menu then s.menuHover=s.menu.offset+math.floor((ev.y-s.menu.y-5)/25)+1 end
  self:refresh(s)
end
function UI:pointerUp(s)
  local a=s.drag;s.drag=nil;s.pointerDown=false;s.selecting=false
  if a and a.id and a.moved then
    local b=a.target
    self:action(s,S.move(a.board,a.id,b and b.x or a.x,b and b.y+b.h+S.gap or a.y,b and b.card.id or nil),function(ok,message) if not ok then app.tip(message or 'Stapel wurde inzwischen verändert.',5) end end)
  end
  self:refresh(s)
end
function UI:show(sprite)
  sprite=sprite or app.sprite;if not sprite then app.tip('Bitte zuerst ein Bild öffnen.',4);return end
  local s=self:state(sprite);s.seen=true;if s.dialog then return end
  self:prepare(s)
  s.dialog=Dialog{title='Ideenwand · '..L.short(app.fs.fileTitle(sprite.filename~='' and sprite.filename or 'Bild'),32),onclose=function()
    s.dialog=nil;s.pointerDown=false;s.selecting=false;s.drag=nil;s.menu=nil;self:run(function() self:finishInline(s) end)
  end}
  local d=s.dialog
  local width,height=L.canvas(740,490);s.width=width;s.height=height
  d:canvas{id='board',width=width,height=height,autoscaling=false,focus=true,
    onpaint=function(ev) self:paint(s,ev) end,
    onmousedown=function(ev) self:run(function() self:pointerDown(s,ev) end) end,
    onmousemove=function(ev) self:pointerMove(s,ev) end,
    onmouseup=function() self:run(function() self:pointerUp(s) end) end,
    onwheel=function(ev)
      if s.menu then s.menu.offset=math.max(0,math.min(#s.menu.items-(s.menu.visible or 1),s.menu.offset+ev.deltaY));self:refresh(s);return end
      if ev.shiftKey then s.oy=s.oy-ev.deltaY*30
      else local old=s.zoom;s.zoom=math.max(0.25,math.min(2,s.zoom*(ev.deltaY>0 and 0.85 or 1.18)));s.ox=ev.x-(ev.x-s.ox)*s.zoom/old;s.oy=ev.y-(ev.y-s.oy)*s.zoom/old end
      self:refresh(s)
    end,
    onkeydown=function(ev)
      ev:stopPropagation()
      self:run(function()
        if ev.code=='Escape' and s.menu then s.menu=nil;self:refresh(s);return end
        if s.inline then self:inlineKey(s,ev);return end
        if ev.ctrlKey or ev.metaKey then
          if ev.code=='KeyZ' or ev.code=='KeyY' then self:action(s,{action=(ev.code=='KeyY' or ev.shiftKey) and 'redo' or 'undo'}) end
        elseif (ev.code=='Delete' or ev.code=='Backspace') and s.selected then self:remove(s,s.selected,false)
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
