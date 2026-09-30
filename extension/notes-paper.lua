-- Full-resolution sketch sheets with compact, bounded storage.
local dir=app.fs.filePath(debug.getinfo(1,'S').source:sub(2))
local I=dofile(app.fs.joinPath(dir,'notes-image.lua'))
local J=dofile(app.fs.joinPath(dir,'jobs.lua'))
local P={width=1000,height=1000}
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local lookup={}
local chars={}
for i=1,#alphabet do lookup[alphabet:sub(i,i)]=i-1 end
for i=0,63 do chars[i]=alphabet:sub(i+1,i+1) end
local function hexPixel(pixel)
  return (pixel:gsub('.',function(ch) return string.format('%02x',ch:byte()) end))
end
local function pixelBytes(hex)
  return (hex:gsub('%x%x',function(pair) return string.char(tonumber(pair,16)) end))
end
local function base64(raw)
  local out={}
  for start=1,#raw,12288 do
    local chunk=raw:sub(start,start+12287)
    out[#out+1]=(chunk:gsub('...',function(bytes)
      local a,b,c=bytes:byte(1,3)
      return chars[a>>2]..chars[((a&3)<<4)|(b>>4)]..chars[((b&15)<<2)|(c>>6)]..chars[c&63]
    end))
    local remaining=#chunk%3
    if remaining>0 then
      out[#out]=out[#out]:sub(1,-remaining-1)
      local a,b=chunk:byte(#chunk-remaining+1,#chunk);b=b or 0
      out[#out+1]=chars[a>>2]..chars[((a&3)<<4)|(b>>4)]..(remaining==2 and chars[(b&15)<<2] or '=')..'='
    end
    J.checkpoint(start/#raw)
  end
  return table.concat(out)
end
local function unbase64(encoded)
  local out={}
  for start=1,#encoded,16384 do
    out[#out+1]=(encoded:sub(start,start+16383):gsub('....',function(bytes)
      local a,b,c,d=lookup[bytes:sub(1,1)],lookup[bytes:sub(2,2)],lookup[bytes:sub(3,3)],lookup[bytes:sub(4,4)]
      return string.char((a<<2)|(b>>4))..(c and string.char(((b&15)<<4)|(c>>2)) or '')..
        (d and string.char(((c&3)<<6)|d) or '')
    end))
    J.checkpoint(start/#encoded)
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
      if #runs%256==0 then J.checkpoint() end
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
  -- Avoid constructing hundreds of thousands of RLE strings for photos.
  local changes=0
  for offset=1,#raw-4,4096 do if raw:sub(offset,offset+3)~=raw:sub(offset+4,offset+7) then changes=changes+1 end end
  if changes>math.ceil(#raw/4096)*0.55 then
    return {width=P.width,height=P.height,encoding='b64',pixels=base64(raw)}
  end
  for i=1,#raw,4 do
    local pixel=raw:sub(i,i+3)
    if pixel~=previous or count==65535 then
      if previous then out[#out+1]=string.format('%04x',count)..hexPixel(previous) end
      previous=pixel;count=1
      if #out*12>maxRle then return {width=P.width,height=P.height,encoding='b64',pixels=base64(raw)} end
    else count=count+1 end
    if i%16384==1 then J.checkpoint(i/#raw) end
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
    J.checkpoint(yy/size)
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
  if card.kind=='image' then return card.image.encoding and P.unpack(card.image) or I.unpack(card.image) end
  if card.kind=='paper' then return P.unpack(card.image) end
  if card.kind~='animation' then return nil end
  if sprite.width*sprite.height>4*1024*1024 then return nil end
  local image=Image(sprite.width,sprite.height,ColorMode.RGB)
  image:drawSprite(sprite,frame or card.frame)
  return image
end
function P.overlay(paper,source,deferPack)
  assert(source and source.width>0 and source.height>0,'Bild fehlt')
  local scale=math.min(paper.width/source.width,paper.height/source.height)
  local w,h=math.max(1,math.floor(source.width*scale)),math.max(1,math.floor(source.height*scale))
  local copy=Image(source)
  if copy.width~=w or copy.height~=h then copy:resize{width=w,height=h,method='nearest'} end
  paper:drawImage(copy,Point(math.floor((paper.width-w)/2),math.floor((paper.height-h)/2)))
  return deferPack and paper or P.pack(paper)
end
return P
