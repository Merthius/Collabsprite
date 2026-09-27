-- Dialog bounds and non-autoscaled canvases use Aseprite window coordinates.
-- Do not multiply these by app.uiScale a second time.
local L={}
local natural=setmetatable({},{__mode='k'})
function L.viewport()
  local w=app.window
  return w and w.width or 1100,w and w.height or 760
end
function L.canvas(width,height)
  local w,h=L.viewport();local scale=app.uiScale or 1
  return math.max(160,math.floor(math.min(width,w*0.72)-16*scale)),
    math.max(100,math.floor(math.min(height,h*0.70)-32*scale))
end
function L.bounds(width,height)
  local w,h=L.viewport()
  width=math.max(100,math.floor(math.min(width,w*0.76)))
  height=math.max(80,math.floor(math.min(height,h*0.76)))
  return Rectangle(math.floor((w-width)/2),math.floor((h-height)/2),width,height)
end
function L.show(dialog)
  local hint=dialog.sizeHint
  natural[dialog]={width=hint.width,height=hint.height}
  dialog:show{wait=false,bounds=L.bounds(hint.width,hint.height),autoscrollbars=true}
end
function L.fit(dialog,minWidth,minHeight)
  -- Once shown with autoscrollbars, Aseprite reports the scroll VIEW's minimum,
  -- not its contents. Reusing that hint collapses the dialog to 100x80.
  local old=dialog.bounds;local hint=natural[dialog] or old
  local b=L.bounds(math.max(hint.width,minWidth or 0),math.max(hint.height,minHeight or 0))
  local w,h=L.viewport();b.x=math.max(0,math.min(old.x,w-b.width));b.y=math.max(0,math.min(old.y,h-b.height))
  dialog.bounds=b
end
function L.short(text,limit)
  text=tostring(text or '')
  local n=utf8.len(text)
  if n and n>limit then return text:sub(1,utf8.offset(text,limit)-1)..'…' end
  return text
end
function L.lines(text,limit)
  limit=limit or math.max(24,math.min(48,math.floor(select(1,L.viewport())*0.65/(7*(app.uiScale or 1)))))
  local lines={}
  for line in (tostring(text)..'\n'):gmatch('(.-)\n') do
    local part=''
    for _,cp in utf8.codes(line) do
      if utf8.len(part)>=limit then lines[#lines+1]=part;part='' end
      part=part..utf8.char(cp)
    end
    lines[#lines+1]=part
  end
  return lines
end
function L.alert(text)
  local lines=L.lines(text)
  if #lines>8 then
    while #lines>7 do table.remove(lines) end
    lines[8]='Weitere Details im Diagnoseprotokoll.'
  end
  app.alert{title='Collabsprite',text=lines}
end
return L
