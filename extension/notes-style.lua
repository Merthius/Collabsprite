-- Native UI text for normal cards; a sharp, larger OFL bitmap for main titles.
local dir=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local metrics=dofile(app.fs.joinPath(dir,'notes-heading-data.lua'))
local F={}
local context
local measured={}
local headingGlyphs={}
function F.load() end
function F.bind(gc) context=gc end
function F.unbind() context=nil end
function F.measure(text,heading)
  text=tostring(text or '')
  if heading==true then
    local width=0
    for _,cp in utf8.codes(text) do
      local glyph=metrics.glyphs[cp] or metrics.glyphs[63]
      width=width+glyph[1]
    end
    return width
  end
  local width
  if context and context.measureText then
    local ok,size=pcall(function() return context:measureText(text) end)
    if ok and size and size.width and size.width>0 then width=size.width;measured[text]=width end
  end
  if not width then width=measured[text] end
  if not width then
    width=0
    for _,cp in utf8.codes(text) do
      local ch=utf8.char(cp)
      width=width+(measured[ch] or (cp<128 and 7 or 8))
    end
  end
  return width
end
function F.draw(gc,text,x,y,scale,heading,light)
  text=tostring(text or '')
  gc.color=F.color(light and '#E6E8EB' or '#25272C')
  x=math.floor(x+0.5);y=math.floor(y+0.5)
  if heading==true then
    for _,cp in utf8.codes(text) do
      local glyph=metrics.glyphs[cp] or metrics.glyphs[63]
      local image=headingGlyphs[cp]
      if not image then
        image=Image(glyph[2],metrics.height,ColorMode.RGB)
        local bytes={}
        for row=1,metrics.height do
          local bits=tonumber(glyph[3][row],16)
          for column=0,glyph[2]-1 do
            bytes[#bytes+1]=math.floor(bits/2^column)%2==1 and string.char(40,48,58,255) or string.char(0,0,0,0)
          end
        end
        image.bytes=table.concat(bytes)
        headingGlyphs[cp]=image
      end
      gc:drawImage(image,x-2,y)
      x=x+glyph[1]
    end
    return
  end
  gc:fillText(text,x,y)
end
function F.inkCenter(heading) return heading==true and 13 or 6 end
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
function F.box(gc,x,y,w,h,color)
  gc.color=color
  gc:fillRect(Rectangle(math.floor(x+0.5),math.floor(y+0.5),math.max(1,math.floor(w+0.5)),math.max(1,math.floor(h+0.5))))
end
function F.panel(gc,x,y,w,h,color)
  F.box(gc,x+2,y,w-4,h,color)
  F.box(gc,x,y+2,w,h-4,color)
  F.box(gc,x+1,y+1,w-2,h-2,color)
end
-- A simple pixel-perfect left/right arrow, shared by both histories.
function F.arrow(gc,x,y,right,color)
  F.box(gc,x+2,y+6,12,2,color)
  for step=0,4 do
    local xx=right and x+13-step or x+2+step
    F.box(gc,xx,y+6-step,2,2,color)
    F.box(gc,xx,y+6+step,2,2,color)
  end
end
return F
