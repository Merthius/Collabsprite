-- Batch-mode regression test for the stack-safe Lua JSON decoder.
local root=assert(app.params.root,'Missing root parameter')
local Client=dofile(root..'/extension/client.lua')
local mainChunk,mainError=loadfile(root..'/extension/main.lua')
assert(mainChunk,mainError)
mainChunk()
local Json=dofile(root..'/extension/json.lua')
local decode=Json.decode
local normalized=decode('{"type":"welcome","snapshot":{"layers":[{"name":"Pixel","parent":0}],"frames":[100],"cels":[{"layer":1,"frame":1,"runs":[0,1,4278190335]}]}}')
assert(normalized.type=='welcome' and normalized.snapshot.layers[1].name=='Pixel' and
  normalized.snapshot.cels[1].runs[3]==4278190335,'Aseprite JsonValue normalization failed')
local snapshot=decode('{"format":1,"name":"Join test","width":2,"height":2,"layers":[{"name":"Pixel","group":false,"parent":0,"opacity":255,"blend":0,"visible":true,"editable":true,"continuous":false}],"frames":[100],"cels":[{"layer":1,"frame":1,"runs":[0,4,4278190335],"opacity":255,"z":0}],"palette":[]}')
local Codec=dofile(root..'/extension/codec.lua')
local sprite,mapping=Codec.create(snapshot,Codec.decode(snapshot))
assert(sprite.width==2 and sprite.height==2 and #mapping==1 and #sprite.frames==1,
  'Aseprite welcome snapshot could not create a session sprite')
local quoted=decode('{"label":"M\\u00e4rchen \\uD83C\\uDF1F","numbers":[-1,0,1.25,2e3],"nil":null}')
assert(quoted.label=='Märchen 🌟' and quoted.numbers[4]==2000 and quoted['nil']==Json.null,
  'JSON escapes, numbers or null were not parsed correctly')
local deep='0'
for _=1,40 do deep='{"child":'..deep..'}' end
local ok,err=pcall(decode,deep)
assert(not ok and tostring(err):find('maximum nesting depth',1,true),
  'Deep JSON should fail with a bounded error')
local Diagnostics=dofile(root..'/extension/diagnostics.lua')
local diagPath=app.fs.joinPath(os.getenv('TEMP'),'Collabsprite-diagnostics-test-'..os.time()..'-'..math.random(10000,99999)..'.log')
local diagnostics=Diagnostics.new(diagPath)
assert(diagnostics:clear(),'Could not initialize temporary diagnostic log')
diagnostics:log('TEST','join requested; code=192.168.1.4:8766,26.1.2.3:8766/12345678/0123456789abcdef0123456789abcdef')
diagnostics:log('TEST','trace at C:\\Users\\friend\\AppData\\Roaming\\Aseprite')
diagnostics:log('TEST','websocket failure at 192.168.2.36:8766')
local report=diagnostics:export()
assert(report:find('join requested',1,true) and report:find('[invite redacted]',1,true),
  'Diagnostic event or invitation-code redaction missing')
assert(not report:find('0123456789abcdef',1,true),'Invitation token leaked into diagnostic log')
assert(report:find('C:\\Users\\[USER]',1,true),'User-profile path redaction missing')
assert(not report:find('192.168.2.36:8766',1,true) and report:find('[address:port]',1,true),
  'Network address was not redacted')
assert(diagnostics:stats().lines==3,'Diagnostic line count mismatch')
local oversized=assert(io.open(diagPath,'wb'))
oversized:write(string.rep('x',512*1024+1));oversized:close()
diagnostics:log('LONG_EVENT','rotation check')
assert(diagnostics:stats().bytes<=512*1024,'Diagnostic log exceeded its size limit')
assert(diagnostics:clear() and diagnostics:stats().lines==0,'Diagnostic reset failed')
os.remove(diagPath)
print('PASS: stack-safe JSON decoder, welcome snapshot, and safe diagnostics')
io.stdout:flush()
app.exit()
