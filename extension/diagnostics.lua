-- Crash-persistent, bounded diagnostics for Collabsprite.
-- Payload bodies, pixels, invitation codes, and user names are never passed here.
local M={}
local MAX_BYTES=512*1024
local KEEP_BYTES=384*1024
local MAX_LINE=1800

local function readFile(path)
  local ok,file=pcall(io.open,path,'rb')
  if not ok or not file then return '' end
  local text=file:read('*a') or ''
  file:close()
  return text
end

local function sanitize(value)
  local text=tostring(value or '')
  text=text:gsub('\r\n','\n'):gsub('\r','\n'):gsub('\n+',' | ')
  text=text:gsub('[%z\1-\8\11\12\14-\31]','?')
  text=text:gsub('([%d%.]+:%d+/%x+/%x+)','[invite redacted]')
  text=text:gsub('%x%x%x%x%x%x%x%x/%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x','[invite redacted]')
  text=text:gsub('%d+%.%d+%.%d+%.%d+:%d+','[address:port]')
  text=text:gsub('[%w%-]+:%d+','[host:port]')
  text=text:gsub('([A-Za-z]:\\Users\\)[^\\]+','%1[USER]')
  text=text:gsub('([A-Za-z]:/Users/)[^/]+','%1[USER]')
  if #text>MAX_LINE then text=text:sub(1,MAX_LINE)..' …[truncated]' end
  return text
end

local function tailBytes(text,limit)
  if #text<=limit then return text end
  local tail=text:sub(-limit)
  local newline=tail:find('\n',1,true)
  return newline and tail:sub(newline+1) or tail
end

function M.new(path)
  assert(type(path)=='string' and path~='','A diagnostics path is required')
  local self={path=path,memory={},lastError=nil,writing=false}
  local initial=readFile(path)
  for line in tailBytes(initial,KEEP_BYTES):gmatch('[^\n]+') do
    self.memory[#self.memory+1]=line
    if #self.memory>200 then table.remove(self.memory,1) end
  end

  local function writeLog(self,event,detail)
    local entry=sanitize(event)..' | '..sanitize(detail)
    if #entry>MAX_LINE then entry=entry:sub(1,MAX_LINE)..' …[truncated]' end
    local line=os.date('%Y-%m-%d %H:%M:%S')..' | '..entry
    self.memory[#self.memory+1]=line
    if #self.memory>200 then table.remove(self.memory,1) end
    local ok,file=pcall(io.open,self.path,'ab')
    if not ok or not file then self.lastError='Log file could not be opened';return false end
    local wrote=pcall(function() file:write(line,'\n');file:flush() end)
    pcall(function() file:close() end)
    if not wrote then self.lastError='Log file write failed';return false end
    self.lastError=nil
    local check=io.open(self.path,'rb')
    if check then
      local size=check:seek('end') or 0
      if size>MAX_BYTES then
        check:seek('set',0)
        local text=check:read('*a') or ''
        check:close()
        local trimOk=pcall(function()
          local output=assert(io.open(self.path,'wb'))
          output:write(tailBytes(text,KEEP_BYTES))
          output:flush();output:close()
        end)
        if not trimOk then self.lastError='Log rotation failed' end
      else check:close() end
    end
    return true
  end

  function self:log(event,detail)
    if self.writing then return false end
    self.writing=true
    local ok,result=pcall(writeLog,self,event,detail)
    self.writing=false
    if not ok then self.lastError='Log file operation failed';return false end
    return result
  end

  function self:memoryTail(maxLines)
    local result={}
    for i=math.max(1,#self.memory-(maxLines or 15)+1),#self.memory do result[#result+1]=self.memory[i] end
    return result
  end

  function self:read()
    local text=readFile(self.path)
    if text~='' then return text end
    return table.concat(self.memory,'\n')
  end

  function self:tail(maxLines)
    local lines={}
    for line in self:read():gmatch('[^\n]+') do lines[#lines+1]=line end
    local first=math.max(1,#lines-(tonumber(maxLines) or 18)+1)
    local result={}
    for i=first,#lines do result[#result+1]=lines[i] end
    return result
  end

  function self:stats()
    local text=self:read()
    local lines=0
    for _ in text:gmatch('[^\n]+') do lines=lines+1 end
    local latest=text:match('([^\n]+)\n?$') or 'Noch keine Einträge'
    return {lines=lines,bytes=#text,latest=latest,error=self.lastError}
  end

  function self:export()
    return 'Collabsprite-Diagnoseprotokoll (max. 512 KiB; ältere Einträge werden rotiert)\n'..
      'Es enthält technische Ereignisse und Fehler, keine Pixel-/Bilddaten oder Einladungscodes.\n\n'..self:read()
  end

  function self:clear()
    local ok,file=pcall(io.open,self.path,'wb')
    if not ok or not file then self.lastError='Log file could not be cleared';return false end
    local wrote=pcall(function() file:write('');file:flush() end)
    pcall(function() file:close() end)
    if not wrote then self.lastError='Log file clear failed';return false end
    self.memory={};self.lastError=nil
    return true
  end

  function self:recent(maxLines)
    return table.concat(self:tail(maxLines), '\n')
  end

  return self
end

M._sanitizeForTest=sanitize
return M
