-- Full-resolution sketch sheets with compact, bounded storage.
local dir=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local I=dofile(app.fs.joinPath(dir,'notes-image.lua'))
local P={width=1000,height=1000}
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local lookup={}
for i=1,#alphabet do lookup[alphabet:sub(i,i)]=i-1 end
local function hexPixel(pixel)
  return (pixel:gsub('.',function(ch) return string.format('%02x',ch:byte()) end))
end
local function pixelBytes(hex)
  return (hex:gsub('%x%x',function(pair) return string.char(tonumber(pair,16)) end))
end
local function base64(raw)
  local out={}
  for i=1,#raw,3 do
    local a,b,c=raw:byte(i,i+2);b=b or 0;c=c or 0
    out[#out+1]=alphabet:sub(math.floor(a/4)+1,math.floor(a/4)+1)..
      alphabet:sub((a%4)*16+math.floor(b/16)+1,(a%4)*16+math.floor(b/16)+1)..
      (i+1<=#raw and alphabet:sub((b%16)*4+math.floor(c/64)+1,(b%16)*4+math.floor(c/64)+1) or '=')..
      (i+2<=#raw and alphabet:sub(c%64+1,c%64+1) or '=')
  end
  return table.concat(out)
end
local function unbase64(encoded)
  local out={}
  for i=1,#encoded,4 do
    local a,b,c,d=encoded:sub(i,i+3):match('(.)(.)(.)(.)')
    a,b,c,d=lookup[a],lookup[b],lookup[c],lookup[d]
    out[#out+1]=string.char(a*4+math.floor(b/16))
    if c then out[#out+1]=string.char((b%16)*16+math.floor(c/4)) end
    if d then out[#out+1]=string.char((c%4)*64+d) end
  end
  return table.concat(out)
end
function P.blank()
  local out={};local left=P.width*P.height
  while left>0 do local count=math.min(left,65535);out[#out+1]=string.format('%04x00000000',count);left=left-count end
  return {width=P.width,height=P.height,encoding='rle',pixels=table.concat(out)}
end
function P.unpack(data)
  if data.width==128 and data.height==128 and not data.encoding then
    local raw=I.unpack(data).bytes;local rows={}
    for y=0,127 do
      local cells={};local start=y*128*4
      for x=0,P.width-1 do local sx=math.floor(x*128/P.width);cells[x+1]=raw:sub(start+sx*4+1,start+sx*4+4) end
      rows[y+1]=table.concat(cells)
    end
    local expanded={}
    for y=0,P.height-1 do expanded[y+1]=rows[math.floor(y*128/P.height)+1] end
    local image=Image(P.width,P.height,ColorMode.RGB);image.bytes=table.concat(expanded);return image
  end
  assert(data.width==P.width and data.height==P.height,'Falsche Skizzenblattgröße')
  local raw
  if data.encoding=='rle' then
    local runs={}
    for count,pixel in data.pixels:gmatch('(%x%x%x%x)(%x%x%x%x%x%x%x%x)') do
      runs[#runs+1]=string.rep(pixelBytes(pixel),tonumber(count,16))
    end
    raw=table.concat(runs)
  elseif data.encoding=='b64' then raw=unbase64(data.pixels)
  else error('Unbekannte Skizzenblattkodierung') end
  assert(#raw==P.width*P.height*4,'Unvollständiges Skizzenblatt')
  local image=Image(P.width,P.height,ColorMode.RGB);image.bytes=raw;return image
end
function P.pack(image)
  assert(image.width==P.width and image.height==P.height and image.colorMode==ColorMode.RGB,'Falsche Skizzenblattgröße')
  local raw=image.bytes
  assert(#raw==P.width*P.height*4,'Unerwartete Skizzenblatt-Zeilenbreite')
  local out,previous,count={},nil,0;local maxRle=math.ceil(#raw/3)*4
  for i=1,#raw,4 do
    local pixel=raw:sub(i,i+3)
    if pixel~=previous or count==65535 then
      if previous then out[#out+1]=string.format('%04x',count)..hexPixel(previous) end
      previous=pixel;count=1
      if #out*12>maxRle then return {width=P.width,height=P.height,encoding='b64',pixels=base64(raw)} end
    else count=count+1 end
  end
  out[#out+1]=string.format('%04x',count)..hexPixel(previous)
  local encoded=table.concat(out)
  if #encoded>maxRle then return {width=P.width,height=P.height,encoding='b64',pixels=base64(raw)} end
  return {width=P.width,height=P.height,encoding='rle',pixels=encoded}
end
function P.palette(sprite)
  local result={};local source=sprite.palettes and sprite.palettes[1]
  if not source then return result end
  for index=0,math.min(#source,256)-1 do
    local color=source:getColor(index)
    if color and color.alpha>0 then result[#result+1]={index=index,color=Color{r=color.red,g=color.green,b=color.blue,a=255}} end
  end
  return result
end
-- Preserve even one-pixel marks when the 1000px sheet becomes a small card.
-- Nearest-neighbour shrinking can miss them entirely.
function P.thumbnail(image,size)
  assert(image.width==P.width and image.height==P.height,'Falsche Skizzenblattgröße')
  size=size or 124
  assert(size>=1 and size<=250 and size==math.floor(size),'Ungültige Vorschaugröße')
  local raw=image.bytes;local pixels={};local transparent=string.char(0,0,0,0)
  for yy=0,size-1 do
    local top=math.floor(yy*P.height/size)
    local bottom=math.floor((yy+1)*P.height/size)-1
    for xx=0,size-1 do
      local left=math.floor(xx*P.width/size)
      local right=math.floor((xx+1)*P.width/size)-1
      local bestAlpha=0;local best=transparent
      for sy=top,bottom do
        for sx=left,right do
          local offset=(sy*P.width+sx)*4+1
          local alpha=raw:byte(offset+3)
          if alpha>bestAlpha then
            bestAlpha=alpha;best=raw:sub(offset,offset+3)
            if alpha==255 then break end
          end
        end
        if bestAlpha==255 then break end
      end
      pixels[#pixels+1]=best
    end
  end
  local thumbnail=Image(size,size,ColorMode.RGB)
  thumbnail.bytes=table.concat(pixels)
  return thumbnail
end
function P.paint(image,x,y,size,color,erase)
  size=math.max(1,math.min(200,math.floor(size+0.5)))
  local left,top=math.floor(x-(size-1)/2),math.floor(y-(size-1)/2)
  local cx,cy=left+size/2,top+size/2;local radius=size/2-0.1
  local pixel=erase and app.pixelColor.rgba(0,0,0,0) or color.rgbaPixel
  for yy=top,top+size-1 do for xx=left,left+size-1 do
    if xx>=0 and yy>=0 and xx<image.width and yy<image.height and
      (erase or (xx+0.5-cx)^2+(yy+0.5-cy)^2<=radius^2) then image:drawPixel(xx,yy,pixel) end
  end end
end
function P.stroke(image,x1,y1,x2,y2,size,color,erase)
  local length=math.max(math.abs(x2-x1),math.abs(y2-y1))
  -- Square eraser stamps cover a whole block. Space them by less than half
  -- their width so fast diagonal strokes cannot leave holes between blocks.
  local steps=erase and math.max(1,math.ceil(length/math.max(1,size*0.4))) or
    math.max(1,math.ceil(length*1.5))
  for n=0,steps do local t=n/steps;P.paint(image,x1+(x2-x1)*t,y1+(y2-y1)*t,size,color,erase) end
end
function P.source(sprite,card,frame)
  if card.kind=='image' then return I.unpack(card.image) end
  if card.kind=='paper' then return P.unpack(card.image) end
  if card.kind~='animation' then return nil end
  if sprite.width*sprite.height>4*1024*1024 then return nil end
  local image=Image(sprite.width,sprite.height,ColorMode.RGB)
  image:drawSprite(sprite,frame or card.frame)
  return image
end
function P.overlay(paper,source)
  assert(source and source.width>0 and source.height>0,'Bild fehlt')
  local scale=math.min(paper.width/source.width,paper.height/source.height)
  local w,h=math.max(1,math.floor(source.width*scale)),math.max(1,math.floor(source.height*scale))
  local copy=Image(source)
  if copy.width~=w or copy.height~=h then copy:resize{width=w,height=h,method='nearest'} end
  paper:drawImage(copy,Point(math.floor((paper.width-w)/2),math.floor((paper.height-h)/2)))
  return P.pack(paper)
end
return P
