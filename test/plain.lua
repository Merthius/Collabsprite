-- Batch-mode regression test for the Aseprite Lua JSON normalizer.
local root=assert(app.params.root,'Missing root parameter')
local Client=dofile(root..'/extension/client.lua')
local converted=Client._plainForTest({snapshot={width=2}})
assert(converted.snapshot.width==2,'Nested JSON copy failed')
local value={}
for _=1,20 do value={child=value} end
local ok,err=pcall(Client._plainForTest,value)
assert(not ok and tostring(err):find('zu tief verschachtelt',1,true),
  'Deep JSON should fail with a bounded, readable error')
print('PASS: bounded JSON normalization')
