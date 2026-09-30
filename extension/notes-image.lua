local dir=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local J=dofile(app.fs.joinPath(dir,'jobs.lua'))
local I={}
local hex={};local bytes={}
for i=0,255 do local h=string.format('%02x',i);hex[string.char(i)]=h;bytes[h]=string.char(i) end
function I.pack(image,palette,transparent)
  assert(image.width<=8192 and image.height<=8192,'Referenzbild ist zu groß (maximal 8192 × 8192).')
  local scale=math.min(1,512/image.width,512/image.height)
  local w,h=math.max(1,math.floor(image.width*scale)),math.max(1,math.floor(image.height*scale))
  if image.colorMode==ColorMode.RGB then
    local resized=Image(image)
    if w~=image.width or h~=image.height then resized:resize{width=w,height=h,method='nearest'} end
    local raw=resized.bytes;local parts={}
    for offset=1,#raw,16384 do
      parts[#parts+1]=(raw:sub(offset,offset+16383):gsub('.',hex));J.checkpoint(offset/#raw)
    end
    return {width=w,height=h,pixels=table.concat(parts)}
  end
  local pixels={};local pc=app.pixelColor
  for y=0,h-1 do for x=0,w-1 do
    local v=image:getPixel(math.min(image.width-1,math.floor(x/scale)),math.min(image.height-1,math.floor(y/scale)))
    local r,g,b,a
    if image.colorMode==ColorMode.RGB then r,g,b,a=pc.rgbaR(v),pc.rgbaG(v),pc.rgbaB(v),pc.rgbaA(v)
    elseif image.colorMode==ColorMode.GRAY then r=pc.grayaV(v);g=r;b=r;a=pc.grayaA(v)
    else local c=assert(palette,'Bildpalette fehlt'):getColor(v);r,g,b,a=c.red,c.green,c.blue,v==transparent and 0 or c.alpha end
    pixels[#pixels+1]=string.format('%02x%02x%02x%02x',r,g,b,a)
  end;J.checkpoint(y/h) end
  return {width=w,height=h,pixels=table.concat(pixels)}
end
function I.load(path)
  local image=assert(Image{fromFile=path},'Das Bild konnte nicht geöffnet werden.')
  if image.colorMode~=ColorMode.INDEXED then return I.pack(image) end
  local active,layer,frame=app.sprite,app.layer,app.frame
  local sprite=assert(app.open(path),'Das Bild konnte nicht geöffnet werden.')
  local source,colors,transparent=Image(sprite),{},sprite.transparentColor
  local nativePalette=sprite.palettes[1]
  for index=0,#nativePalette-1 do colors[index]=nativePalette:getColor(index) end
  local palette={getColor=function(_,index) return colors[index] end}
  sprite:close();app.sprite=active;if active then app.layer=layer;app.frame=frame end
  return I.pack(source,palette,transparent)
end
function I.unpack(data)
  local im=Image(data.width,data.height,ColorMode.RGB)
  local parts={}
  for offset=1,#data.pixels,32768 do
    parts[#parts+1]=(data.pixels:sub(offset,offset+32767):gsub('%x%x',bytes));J.checkpoint(offset/#data.pixels)
  end
  im.bytes=table.concat(parts)
  return im
end
return I
