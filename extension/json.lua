-- Small bounded JSON decoder for Aseprite's native Lua runtime.
-- Received messages become plain Lua values directly, with an explicit
-- nesting limit instead of a second recursive conversion pass.
local M={}
local NULL={}
M.null=NULL
local MAX_DEPTH=32

local function utf8char(code)
  if code<=0x7f then return string.char(code) end
  if code<=0x7ff then
    return string.char(0xc0|(code>>6),0x80|(code&0x3f))
  end
  if code<=0xffff then
    return string.char(0xe0|(code>>12),0x80|((code>>6)&0x3f),0x80|(code&0x3f))
  end
  return string.char(0xf0|(code>>18),0x80|((code>>12)&0x3f),0x80|((code>>6)&0x3f),0x80|(code&0x3f))
end

function M.decode(text)
  assert(type(text)=='string','JSON input must be a string')
  local pos,length=1,#text
  local function fail(message)
    error(('Invalid JSON at byte %d: %s'):format(pos,message),0)
  end
  local function whitespace()
    while true do
      local c=text:byte(pos)
      if c==32 or c==9 or c==10 or c==13 then pos=pos+1 else return end
    end
  end
  local function hex4()
    local digits=text:sub(pos,pos+3)
    if #digits~=4 or not digits:match('^%x%x%x%x$') then fail('invalid unicode escape') end
    pos=pos+4
    return tonumber(digits,16)
  end
  local function parseString()
    if text:sub(pos,pos)~='"' then fail('expected string') end
    pos=pos+1
    local chunks,start={},pos
    while pos<=length do
      local byte=text:byte(pos)
      if byte==34 then
        if pos>start then chunks[#chunks+1]=text:sub(start,pos-1) end
        pos=pos+1
        return table.concat(chunks)
      elseif byte==92 then
        if pos>start then chunks[#chunks+1]=text:sub(start,pos-1) end
        pos=pos+1
        local escape=text:sub(pos,pos)
        local simple={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
        if simple[escape] then
          chunks[#chunks+1]=simple[escape]
          pos=pos+1
        elseif escape=='u' then
          pos=pos+1
          local code=hex4()
          if code>=0xd800 and code<=0xdbff then
            if text:sub(pos,pos+1)~='\\u' then fail('missing low surrogate') end
            pos=pos+2
            local low=hex4()
            if low<0xdc00 or low>0xdfff then fail('invalid low surrogate') end
            code=0x10000+((code-0xd800)<<10)+(low-0xdc00)
          elseif code>=0xdc00 and code<=0xdfff then
            fail('unexpected low surrogate')
          end
          chunks[#chunks+1]=utf8char(code)
        else
          fail('invalid string escape')
        end
        start=pos
      elseif byte<32 then
        fail('unescaped control character')
      else
        pos=pos+1
      end
    end
    fail('unterminated string')
  end
  local function parseNumber()
    local start=pos
    if text:sub(pos,pos)=='-' then pos=pos+1 end
    local c=text:sub(pos,pos)
    if c=='0' then
      pos=pos+1
      if text:sub(pos,pos):match('%d') then fail('leading zero') end
    elseif c:match('[1-9]') then
      repeat pos=pos+1 until not text:sub(pos,pos):match('%d')
    else
      fail('invalid number')
    end
    if text:sub(pos,pos)=='.' then
      pos=pos+1
      if not text:sub(pos,pos):match('%d') then fail('invalid fraction') end
      repeat pos=pos+1 until not text:sub(pos,pos):match('%d')
    end
    c=text:sub(pos,pos)
    if c=='e' or c=='E' then
      pos=pos+1
      c=text:sub(pos,pos)
      if c=='+' or c=='-' then pos=pos+1 end
      if not text:sub(pos,pos):match('%d') then fail('invalid exponent') end
      repeat pos=pos+1 until not text:sub(pos,pos):match('%d')
    end
    local value=tonumber(text:sub(start,pos-1))
    if not value or value==math.huge or value==-math.huge then fail('number out of range') end
    return value
  end

  local parseValue
  local function parseArray(depth)
    pos=pos+1
    whitespace()
    local result={}
    if text:sub(pos,pos)==']' then pos=pos+1;return result end
    while true do
      result[#result+1]=parseValue(depth+1)
      whitespace()
      local delimiter=text:sub(pos,pos)
      if delimiter==']' then pos=pos+1;return result end
      if delimiter~=',' then fail('expected comma or ]') end
      pos=pos+1;whitespace()
    end
  end
  local function parseObject(depth)
    pos=pos+1
    whitespace()
    local result={}
    if text:sub(pos,pos)=='}' then pos=pos+1;return result end
    while true do
      local key=parseString()
      whitespace()
      if text:sub(pos,pos)~=':' then fail('expected colon') end
      pos=pos+1
      result[key]=parseValue(depth+1)
      whitespace()
      local delimiter=text:sub(pos,pos)
      if delimiter=='}' then pos=pos+1;return result end
      if delimiter~=',' then fail('expected comma or }') end
      pos=pos+1;whitespace()
    end
  end
  parseValue=function(depth)
    if depth>MAX_DEPTH then fail('maximum nesting depth exceeded') end
    whitespace()
    local c=text:sub(pos,pos)
    if c=='"' then return parseString() end
    if c=='{' then return parseObject(depth) end
    if c=='[' then return parseArray(depth) end
    if c=='-' or c:match('%d') then return parseNumber() end
    if text:sub(pos,pos+3)=='true' then pos=pos+4;return true end
    if text:sub(pos,pos+4)=='false' then pos=pos+5;return false end
    if text:sub(pos,pos+3)=='null' then pos=pos+4;return NULL end
    fail('unexpected token')
  end

  local result=parseValue(0)
  whitespace()
  if pos<=length then fail('trailing data') end
  return result
end

return M
