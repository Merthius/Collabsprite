-- Linked Aseprite timeline tags. Only references are saved on the board;
-- frame pixels always come from the currently opened sprite.
local A={}
function A.tags(sprite)
  local result={}
  for _,tag in ipairs(sprite.tags) do
    local first,last=tag.fromFrame.frameNumber,tag.toFrame.frameNumber
    if first>=1 and last>=first then
      result[#result+1]={name=tag.name,first=first,last=last,tag=tag}
    end
  end
  return result
end
function A.resolve(sprite,card)
  local closest,distance
  for _,entry in ipairs(A.tags(sprite)) do
    if entry.name==card.tag then
      local d=math.abs(entry.first-card.tagStart)
      if not closest or d<distance then closest=entry;distance=d end
    end
  end
  return closest
end
function A.thumbnail(sprite,frame,width,height)
  if not sprite.isValid or sprite.width*sprite.height>4*1024*1024 then return nil end
  local image=Image(sprite.width,sprite.height,ColorMode.RGB)
  image:drawSprite(sprite,frame)
  local scale=math.min(width/sprite.width,height/sprite.height)
  -- Integer enlargement keeps every source pixel a crisp, equally sized tile.
  if scale>=1 then scale=math.floor(scale) end
  local w,h=math.max(1,math.floor(sprite.width*scale)),math.max(1,math.floor(sprite.height*scale))
  if w~=sprite.width or h~=sprite.height then image:resize(w,h) end
  return image
end
function A.next(tag,frame,direction)
  local mode=tag.tag and tag.tag.aniDir or AniDir.FORWARD
  if mode==AniDir.REVERSE then return frame<=tag.first and tag.last or frame-1,-1 end
  if mode==AniDir.PING_PONG or mode==AniDir.PING_PONG_REVERSE then
    direction=direction or (mode==AniDir.PING_PONG_REVERSE and -1 or 1)
    if tag.first==tag.last then return frame,direction end
    if frame+direction>tag.last or frame+direction<tag.first then direction=-direction end
    return frame+direction,direction
  end
  return frame>=tag.last and tag.first or frame+1,1
end
return A
