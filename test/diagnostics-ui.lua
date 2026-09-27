-- Exercise the real diagnostic canvas callbacks with an in-memory log.
local root=assert(app.params.root)
local callbacks,dialogs={},{}
local entries={}
for i=1,40 do entries[i]=string.format('2026-09-28 | old event %02d',i) end
local lastOffset=0
local diagnostic={}
function diagnostic:log() end
function diagnostic:window(count,skip)
  local maximum=math.max(0,#entries-count)
  local offset=math.min(maximum,math.max(0,skip or 0));lastOffset=offset
  local result={}
  for i=math.max(1,#entries-offset-count+1),#entries-offset do result[#result+1]=entries[i] end
  return result,#entries,maximum,offset
end
function diagnostic:export() return 'current session only' end
function diagnostic:clear() entries={};return true end
local fakeApp={isUIAvailable=true,version='test',clipboard={},
  fs={joinPath=function(a,b) return a..'/'..b end},
  events={on=function() return {} end,off=function() end},tip=function() end}
local painted={}
local context={width=360,height=200,fillRect=function() end,
  fillText=function(_,text) painted[#painted+1]=text end}
local function dialog(spec)
  local d={buttons={},canvasSpec=nil,onclose=spec.onclose}
  function d:repaint()
    if self.canvasSpec then painted={};self.canvasSpec.onpaint{context=context} end
  end
  function d:show() self:repaint() end
  function d:close() if self.onclose then self.onclose() end end
  setmetatable(d,{__index=function(_,key)
    if key=='canvas' then return function(self,item) self.canvasSpec=item;return self end end
    if key=='button' then return function(self,item) self.buttons[item.text]=item.onclick;return self end end
    return function(self) return self end
  end})
  dialogs[#dialogs+1]=d
  return d
end
local layout={canvas=function() return 360,200 end,show=function(d) d:show() end,
  alert=function() end,fit=function() end,short=function(s) return s end}
local env=setmetatable({app=fakeApp,Dialog=dialog,
  Timer=function() return {start=function() end,stop=function() end} end,
  dofile=function(path)
    if path:find('ui-layout.lua',1,true) then return layout end
    if path:find('diagnostics.lua',1,true) then return {new=function() return diagnostic end} end
    if path:find('json.lua',1,true) then return {decode=function() return {} end} end
    if path:find('notes-ui.lua',1,true) then return {new=function() return {states={},tick=function() end,close=function() end} end} end
    if path:find('update-ui.lua',1,true) then return {new=function() return {tick=function() end,close=function() end} end} end
    return {blockGuestSave=function() end}
  end},{__index=_G})
assert(loadfile(root..'/extension/main.lua','t',env))()
local plugin={path='test',version='0.11.0',preferences={},
  newMenuGroup=function() end,newMenuSeparator=function() end,
  newCommand=function(_,spec) callbacks[spec.id]=spec.onclick end}
env.init(plugin)
callbacks.CollabspriteDebugConsole()
local d=dialogs[#dialogs];assert(d and d.canvasSpec and lastOffset==0,'Diagnostic view did not open at newest entry')
d.canvasSpec.onwheel{deltaY=-1};assert(lastOffset==3,'Wheel cannot scroll to older entries')
d.canvasSpec.onkeydown{code='PageUp',stopPropagation=function() end}
assert(lastOffset>3,'PageUp cannot scroll the log')
d.canvasSpec.onmousedown{x=350,y=15};d.canvasSpec.onmousemove{x=350,y=0};d.canvasSpec.onmouseup{}
assert(lastOffset>=20,'Scrollbar drag cannot reach older entries')
assert(table.concat(painted,'\n'):find('old event 01',1,true),'Older entries were not painted after scrolling')
d.buttons['Protokoll kopieren']();assert(fakeApp.clipboard.text=='current session only','Copy included old history')
assert(lastOffset>=20,'Copying unexpectedly reset scroll position')
d.buttons['Leeren']();assert(#entries==0 and lastOffset==0,'New capture did not reset the view')
env.exit(plugin)
print('PASS diagnostic wheel, PageUp, scrollbar drag and current-session copy')
io.stdout:flush();app.exit()
