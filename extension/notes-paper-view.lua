-- A sketch-sheet mode inside the existing ideas-board canvas, not a dialog.
local dir=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local N=dofile(app.fs.joinPath(dir,'notes.lua'))
local P=dofile(app.fs.joinPath(dir,'notes-paper.lua'))
local F=dofile(app.fs.joinPath(dir,'notes-style.lua'))
local V={}
local SIDE,HEADER=62,24
local SIZE_X,SIZE_W=7,44
local STRENGTH_X,STRENGTH_W=7,44
local SWATCH_Y,SWATCH_STEP=268,21
local MAX_HISTORY=8
local function box(x,y,w,h) return {x=x,y=y,w=w,h=h} end
local function inside(r,x,y) return r and x>=r.x and y>=r.y and x<r.x+r.w and y<r.y+r.h end
local function clamp(value,lo,hi) return math.max(lo,math.min(hi,value)) end
local function paletteVisible(height)
  if height<310 then return 0 end
  return 2*math.max(1,math.floor((height-288)/SWATCH_STEP))
end
local function sizeRange(pv) return 5,pv.tool=='eraser' and 100 or 20 end
local function setSize(pv,size)
  local lo,hi=sizeRange(pv)
  pv.size=clamp(math.floor(size+0.5),lo,hi)
  if pv.tool=='eraser' then pv.eraserSize=pv.size else pv.penSize=pv.size end
end
local function remember(stack,image)
  stack[#stack+1]=Image(image)
  if #stack>MAX_HISTORY then table.remove(stack,1) end
end
local function commitSize(pv)
  if not pv.sizeInput then return end
  setSize(pv,tonumber(pv.sizeInput.value) or pv.size)
  pv.sizeInput=nil
end
local function button(gc,x,y,w,h,active)
  F.panel(gc,x,y,w,h,F.color(active and '#587E72' or '#40464C'))
end
local function checkbox(gc,x,y,selected)
  F.box(gc,x,y,12,12,F.color('#AEB8BB'))
  F.box(gc,x+2,y+2,8,8,F.color('#2A2E32'))
  if selected then
    F.box(gc,x+3,y+5,2,3,F.color('#D7EFE3'))
    F.box(gc,x+5,y+7,2,2,F.color('#D7EFE3'))
    F.box(gc,x+7,y+3,2,5,F.color('#D7EFE3'))
  end
end
function V.open(ui,s,id,image)
  local card=N.card(s.board,id)
  if not card or card.kind~='paper' then return end
  if ui.async and not s.paperDrafts[id] and not image then
    ui:task(s,'Skizzenblatt öffnen',function() return P.unpack(card.image) end,function(ok,decoded)
      local current=N.card(s.board,id)
      if ok and current and current.kind=='paper' and current.versions.image==card.versions.image then V.open(ui,s,id,decoded) end
    end,'open-paper:'..id)
    return
  end
  local pv=s.paperDrafts[id] or {image=image or P.unpack(card.image),baseVersion=card.versions.image,
    dirty=false,tool='pen',size=8,pressure=false,stabilizer=false,strength=50,colorIndex=1,paletteOffset=0}
  pv.undo=pv.undo or {};pv.redo=pv.redo or {}
  setSize(pv,pv.size)
  pv.palette=P.palette(s.sprite);pv.id=id;pv.origin=N.copy(card);s.paperDrafts[id]=pv;s.paper=pv
  if #pv.palette==0 then app.tip('Die Bildpalette enthält keine deckende Farbe.',4) end
  ui:refresh(s)
end
function V.close(ui,s)
  local pv=s.paper;if not pv then return end
  commitSize(pv)
  if pv.drawing then V.up(ui,s) end
  pv.commitError=nil
  pv.finishRequested=true
  V.commit(ui,s,pv,true)
  ui:refresh(s)
end
function V.paint(ui,s,ev)
  local gc=ev.context;local pv=s.paper
  s.width=gc.width;s.height=gc.height;s.hits={}
  F.bind(gc);gc.antialias=false
  F.box(gc,0,0,gc.width,gc.height,F.color('#23262A'))
  -- Use the whole square beside the sidebar, never scaling beyond that square.
  local display=math.max(0,math.floor(math.min(gc.width-SIDE-8,gc.height-HEADER-8)))
  if display>0 then
    local x=SIDE+math.floor((gc.width-SIDE-display)/2)
    local y=HEADER+math.floor((gc.height-HEADER-display)/2)
    pv.paperRect=box(x,y,display,display)
    pv.paperScale=display/P.width
    F.box(gc,x-1,y-1,display+2,display+2,F.color('#A4B0B0'))
    F.box(gc,x,y,display,display,F.color('#FFFFFF'))
    gc:drawImage(pv.image,Rectangle(0,0,P.width,P.height),Rectangle(x,y,display,display))
  else
    pv.paperRect=nil;pv.paperScale=nil
  end
  -- Paint controls last so the paper can never obscure the sidebar.
  F.box(gc,0,HEADER,SIDE,gc.height-HEADER,F.color('#2A2F33'))
  F.box(gc,SIDE-1,HEADER,1,gc.height-HEADER,F.color('#596166'))
  F.box(gc,0,0,gc.width,24,F.color('#30353A'))
  F.draw(gc,'Blatt',SIDE+5,5,1,'ui',true)
  button(gc,gc.width-44,2,19,19,false)
  F.box(gc,gc.width-41,6,13,11,F.color('#DEE9E5'))
  F.box(gc,gc.width-39,8,9,7,F.color('#40464C'))
  F.box(gc,gc.width-37,9,2,2,F.color('#DEE9E5'))
  F.box(gc,gc.width-36,12,5,2,F.color('#A9CDBE'))
  button(gc,gc.width-22,2,19,19,false)
  F.box(gc,gc.width-18,10,2,3,F.color('#D7EFE3'))
  F.box(gc,gc.width-16,12,2,3,F.color('#D7EFE3'))
  F.box(gc,gc.width-14,10,2,3,F.color('#D7EFE3'))
  F.box(gc,gc.width-12,8,2,3,F.color('#D7EFE3'))
  F.box(gc,gc.width-10,6,2,3,F.color('#D7EFE3'))
  button(gc,5,29,23,22,pv.tool=='pen')
  F.box(gc,10,33,10,2,F.color('#E4ECEB'))
  F.box(gc,14,35,3,9,F.color('#E4ECEB'))
  F.box(gc,13,44,5,2,F.color('#88A99E'))
  button(gc,33,29,23,22,pv.tool=='eraser')
  -- A slanted eraser with a colored lower edge, centered in its button.
  gc.color=F.color('#E7E4DB')
  gc:beginPath();gc:moveTo(37,41);gc:lineTo(44,33);gc:lineTo(52,38)
  gc:lineTo(45,47);gc:lineTo(37,41);gc:fill()
  F.box(gc,40,46,6,2,F.color('#B7929A'))
  for i,x in ipairs({5,33}) do
    button(gc,x,56,23,21,false)
    local enabled=(i==1 and #pv.undo>0 or i==2 and #pv.redo>0) and not pv.sending
    local color=F.color(enabled and '#D9E6E2' or '#778185')
    F.arrow(gc,x+3,59,i==2,color)
  end
  F.draw(gc,'Größe',7,82,1,'ui',true)
  F.box(gc,SIZE_X,102,SIZE_W,3,F.color('#829398'))
  local lo,hi=sizeRange(pv)
  local thumb=SIZE_X+math.floor((pv.size-lo)/(hi-lo)*(SIZE_W-1))
  F.box(gc,thumb-2,97,5,12,F.color('#CDE8DA'))
  F.box(gc,5,114,50,19,F.color(pv.sizeInput and '#A9D6CA' or '#5C676A'))
  F.box(gc,7,116,46,15,F.color('#23282C'))
  F.draw(gc,pv.sizeInput and pv.sizeInput.value or tostring(pv.size),11,118,1,'ui',true)
  F.draw(gc,'px',38,118,1,'ui',true)
  checkbox(gc,6,141,pv.pressure)
  F.draw(gc,'Druck',22,142,1,'ui',true)
  local pen=pv.tool=='pen'
  checkbox(gc,6,164,pen and pv.stabilizer)
  if pen then F.draw(gc,'Stabi',22,165,1,'ui',true)
  else gc.color=F.color('#879195');gc:fillText('Stabi',22,165) end
  F.box(gc,STRENGTH_X,196,STRENGTH_W,3,F.color(pen and '#829398' or '#586065'))
  F.box(gc,STRENGTH_X+math.floor(pv.strength/100*(STRENGTH_W-1))-2,191,5,12,
    F.color(pen and '#CDE8DA' or '#6F777B'))
  if pen then F.draw(gc,tostring(pv.strength)..'%',7,205,1,'ui',true)
  else gc.color=F.color('#879195');gc:fillText(tostring(pv.strength)..'%',7,205) end
  button(gc,4,223,54,26,false)
  F.draw(gc,'Alles',11,224,1,'ui',true)
  F.draw(gc,'löschen',6,235,1,'ui',true)
  F.box(gc,6,249,50,1,F.color('#596166'))
  local visible=paletteVisible(gc.height)
  pv.paletteOffset=clamp(pv.paletteOffset,0,math.max(0,#pv.palette-visible))
  F.draw(gc,'▲',26,251,1,'ui',true)
  for index=pv.paletteOffset+1,math.min(#pv.palette,pv.paletteOffset+visible) do
    local position=index-pv.paletteOffset-1
    local x=7+(position%2)*24;local y=SWATCH_Y+math.floor(position/2)*SWATCH_STEP
    F.box(gc,x-1,y-1,20,20,F.color(index==pv.colorIndex and '#E9F4ED' or '#596166'))
    F.box(gc,x+1,y+1,16,16,pv.palette[index].color)
  end
  F.draw(gc,'▼',26,gc.height-18,1,'ui',true)
  ui:busyLabel(s,gc);F.unbind()
end
local function sliderValue(x,start,width,max)
  return clamp(math.floor((x-start)/math.max(1,width-1)*max+0.5),0,max)
end
local function draw(ui,s,ev)
  local pv=s.paper;local r=pv.paperRect
  if not inside(r,ev.x,ev.y) then return end
  local x=clamp(math.floor((ev.x-r.x)/pv.paperScale),0,P.width-1)
  local y=clamp(math.floor((ev.y-r.y)/pv.paperScale),0,P.height-1)
  if pv.tool=='pen' and pv.stabilizer and pv.drawing then
    local factor=1/(1+pv.strength/10)
    x=pv.drawing.x+(x-pv.drawing.x)*factor
    y=pv.drawing.y+(y-pv.drawing.y)*factor
  end
  local selected=pv.palette[pv.colorIndex]
  if pv.tool~='eraser' and not selected then return end
  local pressure=pv.pressure and tonumber(ev.pressure) or 1
  if not pressure or pressure<=0 then pressure=1 end
  local size=pv.size*(pv.pressure and clamp(pressure,0.15,1) or 1)
  local prev=pv.drawing or {x=x,y=y}
  pv.commitError=nil
  P.stroke(pv.image,prev.x,prev.y,x,y,size,selected and selected.color or Color{r=0,g=0,b=0,a=0},pv.tool=='eraser')
  pv.drawing={x=x,y=y};pv.dirty=true;pv.previewRevision=(pv.previewRevision or 0)+1;ui:refresh(s)
end
function V.down(ui,s,ev)
  local pv=s.paper;if ev.button~=MouseButton.LEFT then return end
  local x,y=ev.x,ev.y;local w=s.width or 160
  if pv.sizeInput and not (x>=5 and x<55 and y>=114 and y<134) then commitSize(pv) end
  if y<HEADER then
    if x>=w-24 then V.close(ui,s)
    elseif x>=w-46 and not pv.finishRequested then ui:import(s) end
    return
  end
  if s.importing or pv.loading or pv.finishRequested then return end
  if x<SIDE then
    if y>=29 and y<51 then
      if x>=5 and x<28 then pv.tool='pen';setSize(pv,pv.penSize or 8)
      elseif x>=33 and x<56 then pv.tool='eraser';setSize(pv,pv.eraserSize or 20) end
    elseif y>=56 and y<78 then
      if x>=5 and x<28 then V.undo(ui,s)
      elseif x>=33 and x<56 then V.redo(ui,s) end
    elseif y>=96 and y<111 and x>=SIZE_X and x<SIZE_X+SIZE_W then
      local lo,hi=sizeRange(pv);setSize(pv,sliderValue(x,SIZE_X,SIZE_W,hi-lo)+lo);pv.sliding='size'
    elseif y>=114 and y<134 and x>=5 and x<55 then
      pv.sizeInput={value=tostring(pv.size),replace=true}
    elseif y>=139 and y<158 then pv.pressure=not pv.pressure
    elseif y>=162 and y<181 then
      if pv.tool=='pen' then pv.stabilizer=not pv.stabilizer end
    elseif y>=190 and y<204 and x>=STRENGTH_X and x<STRENGTH_X+STRENGTH_W then
      if pv.tool=='pen' then
        pv.strength=sliderValue(x,STRENGTH_X,STRENGTH_W,100);pv.sliding='strength'
      end
    elseif y>=223 and y<249 and x>=4 and x<58 then V.clear(ui,s)
    elseif y>=250 and y<SWATCH_Y then
      pv.paletteOffset=clamp(pv.paletteOffset-2,0,math.max(0,#pv.palette-paletteVisible(s.height or 350)))
    elseif y>=SWATCH_Y and y<(s.height or 350)-20 then
      local row=math.floor((y-SWATCH_Y)/SWATCH_STEP)
      local column=x<30 and 0 or 1
      local index=pv.paletteOffset+row*2+column+1
      if index<=pv.paletteOffset+paletteVisible(s.height or 350) and pv.palette[index] then pv.colorIndex=index end
    elseif y>=(s.height or 350)-20 then
      pv.paletteOffset=clamp(pv.paletteOffset+2,0,math.max(0,#pv.palette-paletteVisible(s.height or 350)))
    end
    ui:refresh(s);return
  end
  if pv.sending or s.ack then app.tip('Vorigen Strich kurz bestätigen lassen.',3);return end
  if inside(pv.paperRect,x,y) then pv.before=Image(pv.image) end
  draw(ui,s,ev)
end
function V.move(ui,s,ev)
  local pv=s.paper
  if pv.sliding=='size' then
    local lo,hi=sizeRange(pv);setSize(pv,sliderValue(ev.x,SIZE_X,SIZE_W,hi-lo)+lo);ui:refresh(s)
  elseif pv.sliding=='strength' and pv.tool=='pen' then
    pv.strength=sliderValue(ev.x,STRENGTH_X,STRENGTH_W,100);ui:refresh(s)
  elseif pv.drawing then draw(ui,s,ev) end
end
function V.key(ui,s,ev)
  local pv=s.paper
  if pv.sizeInput then
    local input=pv.sizeInput
    if ev.code=='Escape' then pv.sizeInput=nil
    elseif ev.code=='Enter' or ev.code=='NumpadEnter' then commitSize(pv)
    elseif ev.code=='Backspace' then input.value=input.replace and '' or input.value:sub(1,-2);input.replace=false
    elseif not ev.ctrlKey and not ev.metaKey and ev.key and ev.key:match('^%d$') then
      local value=(input.replace and '' or input.value)..ev.key
      if #value<=3 then input.value=value end
      input.replace=false
    end
    ui:refresh(s);return
  end
  if ev.ctrlKey or ev.metaKey then
    if ev.code=='KeyZ' then if ev.shiftKey then V.redo(ui,s) else V.undo(ui,s) end
    elseif ev.code=='KeyY' then V.redo(ui,s) end
  elseif ev.code=='Escape' then V.close(ui,s) end
end
function V.commit(ui,s,pv,finish)
  local pv=pv or s.paper;if not pv then return end
  pv.finishRequested=pv.finishRequested or finish
  if (not pv.dirty and not pv.finishRequested) or pv.sending or s.ack or pv.commitError then return end
  local card=N.card(s.board,pv.id)
  if not card then
    if pv.finishRequested and pv.origin then card=pv.origin;pv.preserveAsNew=true
    else return end
  end
  if card.versions.image~=pv.baseVersion then
    if pv.finishRequested then pv.preserveAsNew=true
    else
      if not pv.conflictShown then app.tip('Blatt wurde inzwischen geändert. Dein Entwurf bleibt erhalten; Häkchen übernimmt ihn als separates Bild.',6);pv.conflictShown=true end
      return
    end
  end
  if not ui:editable(s) then return end
  pv.sending=true
  local dirty,revision=pv.dirty,pv.previewRevision
  -- Later strokes may arrive while a cooperative pack job is yielding.
  -- Only the complete image at this mouse-up belongs to this submission.
  local snapshot=dirty and Image(pv.image)
  ui:task(s,pv.finishRequested and 'Skizze übernehmen' or 'Skizze speichern',function()
    return dirty and P.pack(snapshot) or card.image
  end,function(prepared,packed,error)
  if not prepared then pv.sending=false;pv.commitError=true;app.tip('Skizze bleibt als Entwurf erhalten: '..tostring(error),6);return end
  if not ui:editable(s) then pv.sending=false;return end
  local patches={}
  local newCard
  if pv.preserveAsNew then
    newCard=N.newCard('','',math.min(10000,card.x+190),card.y)
    newCard.kind='image';newCard.image=packed;newCard.color=card.color
    patches={{id=newCard.id,expected=false,value=newCard}}
  else
    if dirty then patches[#patches+1]=N.patch(card,'image',packed) end
    if pv.finishRequested then patches[#patches+1]=N.patch(card,'kind','image') end
  end
  local submitted,problem=pcall(function() ui:action(s,{action='patch',patches=patches},function(ok,message)
    pv.sending=false
    if ok then
      pv.dirty=(pv.previewRevision~=revision)
      local updated=N.card(s.board,newCard and newCard.id or pv.id);if updated then pv.baseVersion=updated.versions.image end
      if updated and updated.kind=='image' then
        pv.finishRequested=nil
        if s.paper==pv then s.paper=nil end
        s.paperDrafts[pv.id]=nil
        if s.dialog then ui:reveal(s,updated.id) end
      elseif pv.finishRequested then V.commit(ui,s,pv,true) end
    else pv.commitError=true;app.tip(message or 'Skizze nicht gespeichert. Entwurf bleibt erhalten.',5) end
    ui:refresh(s)
  end)
  end)
  if not submitted then pv.sending=false;pv.commitError=true;app.tip('Skizze bleibt als Entwurf erhalten: '..tostring(problem):match('[^\r\n]+'),7) end
  end)
end
function V.up(ui,s)
  local pv=s.paper;if not pv then return end
  pv.sliding=nil
  if pv.drawing then
    pv.drawing=nil
    if pv.before then
      pv.undo[#pv.undo+1]=pv.before
      if #pv.undo>MAX_HISTORY then table.remove(pv.undo,1) end
      pv.before=nil;pv.redo={}
    end
    V.commit(ui,s)
  end
end
local function historyStep(ui,s,redo)
  local pv=s.paper;local card=N.card(s.board,pv.id)
  if pv.drawing or pv.sending or s.ack then return end
  if not card or card.versions.image~=pv.baseVersion or not ui:editable(s) then
    app.tip('Blatt wurde inzwischen geändert oder ist nicht erreichbar.',4);return
  end
  local from=redo and pv.redo or pv.undo
  if #from==0 then return end
  remember(redo and pv.undo or pv.redo,pv.image)
  pv.image=table.remove(from);pv.dirty=true;pv.commitError=nil;pv.previewRevision=(pv.previewRevision or 0)+1
  V.commit(ui,s)
  ui:refresh(s)
end
function V.undo(ui,s) historyStep(ui,s,false) end
function V.redo(ui,s) historyStep(ui,s,true) end
function V.clear(ui,s)
  local pv=s.paper;local card=N.card(s.board,pv.id)
  if pv.drawing or pv.sending or s.ack then return end
  if not card or card.versions.image~=pv.baseVersion or not ui:editable(s) then
    app.tip('Blatt wurde inzwischen geändert oder ist nicht erreichbar.',4);return
  end
  if pv.image:isEmpty() then return end
  remember(pv.undo,pv.image);pv.redo={}
  pv.image=Image(P.width,P.height,ColorMode.RGB);pv.dirty=true;pv.commitError=nil
  pv.previewRevision=(pv.previewRevision or 0)+1
  V.commit(ui,s);ui:refresh(s)
end
function V.replace(ui,s,pv,image)
  remember(pv.undo,pv.image);pv.redo={}
  pv.image=image;pv.dirty=true;pv.commitError=nil;pv.previewRevision=(pv.previewRevision or 0)+1
  V.commit(ui,s,pv);ui:refresh(s)
end
function V.wheel(ui,s,ev)
  local pv=s.paper
  if ev.x<SIDE and ev.y>=250 then
    local visible=paletteVisible(s.height or 350)
    pv.paletteOffset=clamp(pv.paletteOffset+ev.deltaY*2,0,math.max(0,#pv.palette-visible))
    ui:refresh(s)
  end
end
return V
