local root=assert(app.params.root)
local P=dofile(root..'/extension/notes-paper.lua')
local I=dofile(root..'/extension/notes-image.lua')
local J=dofile(root..'/extension/json.lua')
local function time(label,fn)
  local start=os.clock();local result=fn()
  print(label..' '..string.format('%.3f',os.clock()-start)..' s');io.stdout:flush()
  return result
end
local image=Image(1000,1000,ColorMode.RGB)
image:drawPixel(987,998,app.pixelColor.rgba(20,90,140,255))
local packed=time('pack sparse sheet',function() return P.pack(image) end)
time('thumbnail sparse sheet',function() return P.thumbnail(image,124) end)
time('unpack sparse sheet',function() return P.unpack(packed) end)
local dense=Image(1000,1000,ColorMode.RGB)
local rows={};for y=0,999 do
  local cells={};for x=0,999 do cells[#cells+1]=string.char(x%256,y%256,(x+y)%256,255) end
  rows[#rows+1]=table.concat(cells)
end
dense.bytes=table.concat(rows)
packed=time('pack dense sheet',function() return P.pack(dense) end)
time('unpack dense sheet',function() return P.unpack(packed) end)
time('pack reference',function() return I.pack(dense) end)
time('decode 5 MiB json string',function() return J.decode(json.encode{image=packed}) end)
print('PASS notes performance probe');io.stdout:flush();app.exit()
