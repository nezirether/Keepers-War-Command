local K=KWC
local M={}
K.MinimapLauncher=M

local button
local dragging,suppressClick
local DEFAULT_ANGLE=225

local function settings()
 return KWCDB.settings
end

local function anchor()
 local angle=math.rad(tonumber(settings().minimapAngle) or DEFAULT_ANGLE)
 local x=math.cos(angle)*(Minimap:GetWidth()/2+4)
 local y=math.sin(angle)*(Minimap:GetHeight()/2+4)
 button:ClearAllPoints()
 button:SetPoint('CENTER',Minimap,'CENTER',x,y)
end

local function followCursor()
 local centerX,centerY=Minimap:GetCenter()
 if not centerX or not centerY then return end
 local x,y=GetCursorPosition()
 local scale=Minimap:GetEffectiveScale()
 if not scale or scale<=0 then return end
 x,y=x/scale-centerX,y/scale-centerY
 if x==0 and y==0 then return end
 settings().minimapAngle=math.deg(math.atan2(y,x))%360
 anchor()
end

local function stopDrag()
 dragging=false
 button:SetScript('OnUpdate',nil)
end

function M.IsVisible()
 return settings().minimapVisible~=false
end

function M.SetVisible(value)
 settings().minimapVisible=not not value
 if button then button:SetShown(M.IsVisible()) end
end

function M.ResetPosition()
 settings().minimapAngle=nil
 if button then anchor() end
end

local function initialize()
 if button or not Minimap then return end
 button=CreateFrame('Button','KWCMinimapLauncher',Minimap)
 button:SetSize(30,30)
 button:SetFrameLevel(Minimap:GetFrameLevel()+5)
 button:SetNormalTexture('Interface\\AddOns\\KeepersWarCommand\\Textures\\TrogdorMinimap.tga')
 button:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight','ADD')
 button:RegisterForClicks('LeftButtonUp','RightButtonUp')
 button:RegisterForDrag('LeftButton')
 button:SetScript('OnMouseDown',function() suppressClick=false end)
 button:SetScript('OnClick',function(_,mouse)
  if dragging or suppressClick then return end
  if mouse=='RightButton' then K.UI.Toggle('Settings')
  elseif mouse=='LeftButton' then K.UI.Toggle() end
 end)
 button:SetScript('OnDragStart',function(self)
  dragging,suppressClick=true,true
  GameTooltip:Hide()
  self:SetScript('OnUpdate',followCursor)
  followCursor()
 end)
 button:SetScript('OnDragStop',function()
  if dragging then followCursor();stopDrag() end
 end)
 button:SetScript('OnHide',function()
  stopDrag()
  if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
 end)
 button:SetScript('OnEnter',function(self)
  if dragging then return end
  GameTooltip:SetOwner(self,'ANCHOR_LEFT')
  GameTooltip:SetText('Keepers War Command '..K.version)
  GameTooltip:AddLine('Left-click: Toggle War Command')
  GameTooltip:AddLine('Right-click: Open Preferences')
  GameTooltip:AddLine('Drag: Move around the minimap')
  GameTooltip:Show()
 end)
 button:SetScript('OnLeave',function()
  if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
 end)
 Minimap:HookScript('OnSizeChanged',anchor)
 anchor()
 button:SetShown(M.IsVisible())
end

K.On('PLAYER_LOGIN',initialize)
K.On('PLAYER_ENTERING_WORLD',initialize)
