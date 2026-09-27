-- Native Aseprite documents, bounded deterministic network / clock. No user art.
local root=assert(app.params.root)
local Codec=dofile(root..'/extension/codec.lua')
local Json=dofile(root..'/extension/json.lua')
local clock,tips=1000,{}
local fakeApp=setmetatable({tip=function(text) tips[#tips+1]=text end},{__index=function(_,key) return app[key] end})
local env=setmetatable({app=fakeApp,os={time=function() return clock end}},{__index=_G})
local Client=assert(loadfile(root..'/extension/client.lua','t',env))()
local source=Sprite(4,4,ColorMode.RGB)
local snapshot=Codec.capture(source)
local function copy() return Json.decode(json.encode(snapshot)) end
local function expectInvalid(edit)
  local invalid=copy();edit(invalid)
  assert(not pcall(Codec.decode,invalid),'Malformed snapshot accepted')
end
expectInvalid(function(s) s.width=2147483647 end)
expectInvalid(function(s) s.frames[1]=-1 end)
expectInvalid(function(s) s.layers[1].parent=1 end)
expectInvalid(function(s) s.cels[2]=s.cels[1] end)
expectInvalid(function(s) s.cels[1].runs={0,2147483647,1} end)
expectInvalid(function(s) s.cels[1].runs={0,1,-1} end)
expectInvalid(function(s) s.cels[1].runs={0,1,1,0,1,2} end)
assert(not pcall(Codec.applyRuns,string.rep('\0',16),{0,1.5,7}),'Fractional runs accepted')

local c=Client.new();c.inboxBytes=128*1024*1024
c:enqueue{type='_text',data='x'}
assert(c.inboxOverflow and #c.inbox==0,'Queue byte bound failed')
c:tick();assert(c.closed,'Overflow did not disconnect safely')
c=Client.new()
for i=1,2048 do c:enqueue{type='pong',nonce=i} end
c:enqueue{type='pong'}
assert(c.inboxOverflow and #c.inbox==2048,'Queue count bound failed')
c=Client.new()
for i=1,150 do c:enqueue{type='_text',data='{"type":"pong"}'} end
c:tick();assert(#c.inbox==86 and c.inboxBytes==86*15,'Receive batch not bounded')
c:tick();assert(#c.inbox==22)
c:tick();assert(#c.inbox==0 and c.inboxBytes==0 and not c.closed)
c=Client.new();c.pendingBytes=64*1024*1024
c.ws={sendText=function() error('Over-budget edit was sent') end}
local sent,problem=pcall(function() c:send{type='paint',seq=1,structure=0,patches={}} end)
assert(not sent and tostring(problem):find('unbestätigte',1,true),'Unconfirmed outbound budget missing')

local host=Client.new()
host:receive{type='welcome',protocol=7,host=true,author='host',room='test',snapshot=copy(),revision=0,structure=0}
host.ws={sendText=function() end,close=function() end}
host:receive{type='admission',open=false}
assert(host:syncStatusText():find('Beitritt gesperrt',1,true),'Admission status missing')
local before=#tips
host:receive{type='backup',state='error',revision=0}
host:receive{type='backup',state='error',revision=0}
assert(#tips==before+1 and host:syncStatusText():find('Sicherung fehlgeschlagen',1,true),'Backup warning missing/repeated')
host:receive{type='backup',state='saved',revision=0}
assert(not host.backupError and #tips==before+2,'Backup recovery not reported')
host:receive{type='rejected',message='Aktion erneut ausführen'}
assert(host.connected and #tips==before+3,'Expected rejection disconnected client')
clock=1016;host:tick()
assert(host.syncStatus=='Host antwortet nicht ...' and host.connected,'Silent socket not indicated')
clock=1061;host:tick()
assert(host.closed and host.sprite.isValid,'Dead socket did not preserve document')
host.sprite:close();source:close()
print('PASS: bounded receive batches, snapshot validation, admission/backup status, silent socket timeout')
io.stdout:flush();app.exit()
