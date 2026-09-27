-- Bundled OFL bitmap type, independent of OS fonts and Aseprite's small UI font.
local dir=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local metrics=dofile(app.fs.joinPath(dir,'notes-font-data.lua'))
local F={};local atlas
function F.load()
  if not atlas then
    atlas=Image(metrics.width,metrics.height,ColorMode.RGB)
    atlas.bytes=metrics.pixels:gsub('%x%x',function(v) return string.char(tonumber(v,16)) end)
  end
end
function F.measure(text,heading)
  local font=heading and metrics.heading or metrics.body;local width=0
  for _,cp in utf8.codes(text) do local g=font.glyphs[cp] or font.glyphs[63];width=width+g[5] end
  return width
end
function F.draw(gc,text,x,y,scale,heading)
  local font=heading and metrics.heading or metrics.body
  for _,cp in utf8.codes(text) do
    local g=font.glyphs[cp] or font.glyphs[63]
    gc:drawImage(atlas,Rectangle(g[1],g[2],g[3],g[4]),Rectangle(math.floor(x-2*scale),math.floor(y),math.max(1,math.floor(g[3]*scale)),math.max(1,math.floor(g[4]*scale))))
    x=x+g[5]*scale
  end
end
F.colors={'#F3E6BB','#D4E8DB','#D6E4F4','#E5DDF2','#F0D8DC','#F4DFCC','#E4E7E8'}
function F.color(hex) return Color{r=tonumber(hex:sub(2,3),16),g=tonumber(hex:sub(4,5),16),b=tonumber(hex:sub(6,7),16)} end
function F.paper(hex)
  if hex=='' then return F.color(F.colors[1]) end
  for _,preset in ipairs(F.colors) do if hex:upper()==preset then return F.color(preset) end end
  -- Older cards allowed arbitrary dark HEX colors. Tint their display only;
  -- preserve stored metadata while keeping the new dark lettering readable.
  local c=F.color(hex)
  return Color{r=math.floor(c.red*0.3+178.5),g=math.floor(c.green*0.3+178.5),b=math.floor(c.blue*0.3+178.5)}
end
function F.box(gc,x,y,w,h,color,radius)
  gc.color=color;gc:beginPath();gc:roundedRect(Rectangle(math.floor(x),math.floor(y),math.max(1,math.floor(w)),math.max(1,math.floor(h))),radius or 7);gc:fill()
end
return F
