local I={}
function I.pack(image,palette,transparent)
  assert(image.width<=8192 and image.height<=8192,'Referenzbild ist zu groß (maximal 8192 × 8192).')
  local scale=math.min(1,512/image.width,512/image.height)
  local w,h=math.max(1,math.floor(image.width*scale)),math.max(1,math.floor(image.height*scale))
  local bytes={};local pc=app.pixelColor
  for y=0,h-1 do for x=0,w-1 do
    local v=image:getPixel(math.min(image.width-1,math.floor(x/scale)),math.min(image.height-1,math.floor(y/scale)))
    local r,g,b,a
    if image.colorMode==ColorMode.RGB then r,g,b,a=pc.rgbaR(v),pc.rgbaG(v),pc.rgbaB(v),pc.rgbaA(v)
    elseif image.colorMode==ColorMode.GRAY then r=pc.grayaV(v);g=r;b=r;a=pc.grayaA(v)
    else local c=assert(palette,'Bildpalette fehlt'):getColor(v);r,g,b,a=c.red,c.green,c.blue,v==transparent and 0 or c.alpha end
    bytes[#bytes+1]=string.format('%02x%02x%02x%02x',r,g,b,a)
  end end
  return {width=w,height=h,pixels=table.concat(bytes)}
end
function I.load(path)
  local active,layer,frame=app.sprite,app.layer,app.frame
  local sprite=assert(app.open(path),'Das Bild konnte nicht geöffnet werden.')
  local ok,result=pcall(function() return I.pack(Image(sprite),sprite.palettes[1],sprite.transparentColor) end)
  sprite:close();app.sprite=active;if active then app.layer=layer;app.frame=frame end
  if not ok then error(result) end;return result
end
function I.unpack(data)
  local im=Image(data.width,data.height,ColorMode.RGB)
  im.bytes=data.pixels:gsub('%x%x',function(v) return string.char(tonumber(v,16)) end)
  return im
end
return I
