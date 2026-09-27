-- Bundled OFL bitmap type, independent of OS fonts and Aseprite's small UI font.
local dir=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local metrics=dofile(app.fs.joinPath(dir,'notes-font-data.lua'))
local F={};local atlas;local cache={};local cacheOrder={}
function F.load()
  if not atlas then
    atlas=Image(metrics.width,metrics.height,ColorMode.RGB)
    atlas.bytes=metrics.alpha:gsub('%x%x',function(v) return string.char(40,48,58,tonumber(v,16)) end)
    metrics.alpha=nil
  end
end
function F.measure(text,heading)
  local font=heading and metrics.heading or metrics.body;local width=0
  for _,cp in utf8.codes(text) do local g=font.glyphs[cp] or font.glyphs[63];width=width+g[5] end
  return width
end
function F.draw(gc,text,x,y,scale,heading,light)
  local font=heading and metrics.heading or metrics.body
  -- Rasterize from a 4x source at the actual display size, not from Aseprite's
  -- low-resolution UI font. Keep only the most recently used zoom levels.
  local key=string.format('%.3f:%s:%s',scale,tostring(heading),tostring(light))
  if not cache[key] then
    cache[key]={};cacheOrder[#cacheOrder+1]=key
    if #cacheOrder>8 then cache[table.remove(cacheOrder,1)]=nil end
  end
  local glyphs=cache[key];local factor=metrics.factor or 1
  for _,cp in utf8.codes(text) do
    local g=font.glyphs[cp] or font.glyphs[63]
    local image=glyphs[cp]
    if not image then
      image=Image(g[3]*factor,g[4]*factor,ColorMode.RGB)
      image:drawImage(atlas,Point(-g[1]*factor,-g[2]*factor))
      image:resize{width=math.max(1,math.floor(g[3]*scale+0.5)),height=math.max(1,math.floor(g[4]*scale+0.5)),method='bilinear'}
      -- At overview sizes bilinear filtering leaves half-transparent, muddy
      -- six-pixel letters. Keep the supersampled outlines but snap coverage
      -- to fully opaque/clear pixels so each surviving stroke is distinct.
      if scale<=0.6 then
        image.bytes=image.bytes:gsub('(...)(.)',function(rgb,a)
          return rgb..string.char(a:byte()>=82 and 255 or 0)
        end)
      end
      if light then image.bytes=image.bytes:gsub('...([%z\1-\255])',function(a) return string.char(226,228,231)..a end) end
      glyphs[cp]=image
    end
    gc:drawImage(image,math.floor(x-2*scale+0.5),math.floor(y+0.5))
    x=x+g[5]*scale
  end
end
-- Visible ink is slightly above the middle of the font's line box.
function F.inkCenter(heading) return heading and 13 or 9 end
F.colors={'#F1D56A','#91CFAE','#90C1E9','#BC9CE5','#EAA1B5','#EEBA88','#B8C4CE'}
local oldColors={'#F3E6BB','#D4E8DB','#D6E4F4','#E5DDF2','#F0D8DC','#F4DFCC','#E4E7E8'}
function F.color(hex) return Color{r=tonumber(hex:sub(2,3),16),g=tonumber(hex:sub(4,5),16),b=tonumber(hex:sub(6,7),16)} end
function F.paper(hex)
  if hex=='' then return F.color(F.colors[1]) end
  for _,preset in ipairs(F.colors) do if hex:upper()==preset then return F.color(preset) end end
  -- Do not recolor notes saved with the previous seven presets.
  for _,preset in ipairs(oldColors) do if hex:upper()==preset then return F.color(preset) end end
  -- Older cards allowed arbitrary dark HEX colors. Tint their display only;
  -- preserve stored metadata while keeping the new dark lettering readable.
  local c=F.color(hex)
  return Color{r=math.floor(c.red*0.3+178.5),g=math.floor(c.green*0.3+178.5),b=math.floor(c.blue*0.3+178.5)}
end
function F.box(gc,x,y,w,h,color,radius)
  gc.color=color;gc:beginPath();gc:roundedRect(Rectangle(math.floor(x),math.floor(y),math.max(1,math.floor(w)),math.max(1,math.floor(h))),radius or 7);gc:fill()
end
return F
