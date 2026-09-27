-- Small UTF-8 text buffer for editing directly on the idea-board canvas.
-- Positions are codepoints, never byte offsets; no document shortcuts escape.
local T={}
function T.length(s) return utf8.len(s) or 0 end
function T.slice(s,a,b)
  local n=T.length(s);a=math.max(0,math.min(n,a));b=math.max(a,math.min(n,b or n))
  return s:sub(utf8.offset(s,a+1) or #s+1,(utf8.offset(s,b+1) or #s+1)-1)
end
function T.new(value) return {value=value,cursor=T.length(value),anchor=T.length(value),undo={},redo={}} end
function T.selection(d) return math.min(d.cursor,d.anchor),math.max(d.cursor,d.anchor) end
function T.remember(d)
  d.undo[#d.undo+1]={value=d.value,cursor=d.cursor,anchor=d.anchor}
  if #d.undo>40 then table.remove(d.undo,1) end;d.redo={}
end
function T.replace(d,text,limit)
  if not utf8.len(text) then return false end
  local a,b=T.selection(d);local value=T.slice(d.value,0,a)..text..T.slice(d.value,b)
  if #value>limit then return false end
  if value==d.value then return true end
  T.remember(d);d.value=value;d.cursor=a+T.length(text);d.anchor=d.cursor;return true
end
function T.history(d,redo)
  local from,to=redo and d.redo or d.undo,redo and d.undo or d.redo
  if #from==0 then return end
  to[#to+1]={value=d.value,cursor=d.cursor,anchor=d.anchor}
  local old=table.remove(from);d.value=old.value;d.cursor=old.cursor;d.anchor=old.anchor
end
function T.key(d,ev,field,clipboard)
  local code=ev.code;local ctrl=ev.ctrlKey or ev.metaKey;local n=T.length(d.value)
  if ctrl and not ev.altKey then
    if code=='KeyA' then d.anchor=0;d.cursor=n
    elseif code=='KeyC' or code=='KeyX' then
      local a,b=T.selection(d);if a~=b then clipboard.text=T.slice(d.value,a,b);if code=='KeyX' then T.replace(d,'',4096) end end
    elseif code=='KeyV' then
      local value=(clipboard.text or ''):gsub('\r\n','\n'):gsub('\r','\n'):gsub('[%z\1-\8\11-\31]','')
      if field=='title' then value=value:gsub('[\n\t]',' ') end
      if not T.replace(d,value,field=='title' and 120 or 4096) then return 'Text zu lang oder ungültig.' end
    elseif code=='KeyZ' or code=='KeyY' then T.history(d,code=='KeyY' or ev.shiftKey)
    end
    return
  end
  if code=='Backspace' or code=='Delete' then
    if d.cursor==d.anchor then d.anchor=code=='Backspace' and math.max(0,d.cursor-1) or math.min(n,d.cursor+1) end
    T.replace(d,'',4096)
  elseif code=='ArrowLeft' or code=='ArrowRight' or code=='Home' or code=='End' or code=='ArrowUp' or code=='ArrowDown' then
    local position=d.cursor;local before=T.slice(d.value,0,position)
    local lineStart=T.length(before:match('^(.*\n)') or '')
    local tail=T.slice(d.value,position);local rest=tail:match('^[^\n]*') or tail
    if code=='Home' then position=lineStart
    elseif code=='End' then position=position+T.length(rest)
    elseif code=='ArrowUp' then
      local previous=T.slice(d.value,0,math.max(0,lineStart-1));local start=T.length(previous:match('^(.*\n)') or '')
      position=math.min(math.max(0,lineStart-1),start+position-lineStart)
    elseif code=='ArrowDown' then
      local nextStart=math.min(n,position+T.length(rest)+1)
      local nextLine=T.slice(d.value,nextStart):match('^[^\n]*') or ''
      position=nextStart+math.min(T.length(nextLine),position-lineStart)
    elseif not ev.shiftKey and d.anchor~=position then local a,b=T.selection(d);position=code=='ArrowLeft' and a or b
    else position=position+(code=='ArrowLeft' and -1 or 1) end
    d.cursor=math.max(0,math.min(n,position));if not ev.shiftKey then d.anchor=d.cursor end
  elseif ev.key and ev.key~='' and not ev.key:find('[%z\1-\31]') then
    if not T.replace(d,ev.key,field=='title' and 120 or 4096) then return 'Text zu lang (Titel 120, Notiz 4096 Bytes).' end
  end
end
return T
