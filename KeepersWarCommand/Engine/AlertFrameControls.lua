-- Cursor-driven placement shared by the death and bounty alerts.
local K=KWC
local C={}
K.AlertFrameControls=C

local function scaleRatio(frame)
 return frame:GetEffectiveScale()/UIParent:GetEffectiveScale()
end

local function cursor()
 local scale=UIParent:GetEffectiveScale()
 local x,y=GetCursorPosition()
 return x/scale,y/scale
end

local function center(frame)
 local x,y=frame:GetCenter()
 if x and y then
  local ratio=scaleRatio(frame)
  return x*ratio,y*ratio
 end
end

local function anchor(frame,x,y)
 local ratio=scaleRatio(frame)
 frame:ClearAllPoints()
 frame:SetPoint('CENTER',UIParent,'BOTTOMLEFT',x/ratio,y/ratio)
end

local function clamp(value,min,max)
 return math.max(min,math.min(max,value))
end

function C.Attach(frame,settingsFn,key,defaultY)
 local positionKey,scaleKey,unlockKey=key..'Position',key..'Scale',key..'Unlocked'
 local initialized,moving=false,false
 local mouseX,mouseY,centerX,centerY
 local placement={}
 local driver=CreateFrame('Frame')
 driver:Hide()

 frame:SetMovable(true)
 frame:SetDontSavePosition(true)
 frame:EnableMouse(true)
 frame:RegisterForDrag('LeftButton')

 local function restore(saved)
  local w,h=UIParent:GetWidth(),UIParent:GetHeight()
  if type(saved)=='table' and type(saved.nx)=='number' and type(saved.ny)=='number' then
   anchor(frame,w*clamp(saved.nx,0,1),h*clamp(saved.ny,0,1))
  else
   anchor(frame,w/2,h/2+defaultY)
  end
 end

 function placement.Initialize()
  if initialized then return end
  local s=settingsFn()
  if not s then return end
  frame:SetScale(clamp(tonumber(s[scaleKey]) or 1,0.5,2))
  restore(s[positionKey])
  initialized=true
 end

 local function stop()
  if not moving then return end
  moving=false
  driver:Hide()
  local s=settingsFn()
  if not s then return end
  local x,y=center(frame)
  s[positionKey]={nx=(x or centerX)/UIParent:GetWidth(),ny=(y or centerY)/UIParent:GetHeight()}
 end

 local function start(_,button)
  if button and button~='LeftButton' then return end
  local s=settingsFn()
  if not s or not s[unlockKey] or moving then return end
  placement.Initialize()
  centerX,centerY=center(frame)
  if not centerX then return end
  mouseX,mouseY=cursor()
  moving=true
  driver:Show()
 end

 local function move()
  local x,y=cursor()
  local w,h=UIParent:GetWidth(),UIParent:GetHeight()
  local ratio=scaleRatio(frame)
  local halfW=math.min(frame:GetWidth()*ratio/2,w/2)
  local halfH=math.min(frame:GetHeight()*ratio/2,h/2)
  centerX=clamp(centerX+x-mouseX,halfW,w-halfW)
  centerY=clamp(centerY+y-mouseY,halfH,h-halfH)
  mouseX,mouseY=x,y
  anchor(frame,centerX,centerY)
 end

 local function release(_,button)
  if not moving or (button and button~='LeftButton') then return end
  local s=settingsFn()
  if frame:IsShown() and s and s[unlockKey] then move() end
  stop()
 end

 driver:SetScript('OnUpdate',function()
  if not moving then return end
  local s=settingsFn()
  if not frame:IsShown() or not s or not s[unlockKey] then stop();return end
  move()
  if IsMouseButtonDown and not IsMouseButtonDown('LeftButton') then stop() end
 end)
 frame:SetScript('OnDragStart',start)
 frame:SetScript('OnDragStop',release)
 frame:HookScript('OnHide',stop)
 frame:SetScript('OnMouseDown',start)
 frame:SetScript('OnMouseUp',release)

 function placement.SetUnlocked(value)
  local s=settingsFn()
  if not s then return end
  if not value then stop() end
  s[unlockKey]=not not value
 end

 function placement.SetScale(value)
  local s=settingsFn()
  if not s then return end
  placement.Initialize()
  local x,y=center(frame)
  s[scaleKey]=clamp(tonumber(value) or 1,0.5,2)
  frame:SetScale(s[scaleKey])
  if x then anchor(frame,x,y) end
  if moving then
   centerX,centerY=center(frame)
  end
 end

 function placement.Reset()
  local s=settingsFn()
  if not s then return end
  placement.Initialize()
  stop()
  s[positionKey]=nil
  restore(nil)
 end

 return placement
end
