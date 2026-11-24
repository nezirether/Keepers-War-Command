-- KWC 2.0 minimap button: emblem disc on an ember ring.
-- Left-click: War Room. Right-click: Command Table for authorized officers with
-- KWCC loaded, otherwise Settings. Drag to move around the minimap edge.
local K=KWC
local Kit,S=K.Kit,K.WarRoomSkin
local M={};K.Minimap=M
local button

local function settings() return KWCDB and KWCDB.settings or {} end
local function place()
 if not button or not Minimap then return end
 local angle=math.rad(tonumber(settings().ui2MinimapAngle) or 205)
 local r=(Minimap:GetWidth() or 140)/2+10
 button:ClearAllPoints()
 button:SetPoint('CENTER',Minimap,'CENTER',math.cos(angle)*r,math.sin(angle)*r)
end
local function officer() return K.Officer and K.Officer.Open and K.IsOfficer and K.IsOfficer() end

local function build()
 if button or not Minimap then return end
 button=CreateFrame('Button','KWC2_MinimapButton',Minimap)
 button:SetSize(32,32);button:SetFrameStrata('MEDIUM');button:SetFrameLevel(8)
 button:RegisterForClicks('LeftButtonUp','RightButtonUp');button:RegisterForDrag('LeftButton')
 local icon=button:CreateTexture(nil,'ARTWORK');icon:SetAllPoints();icon:SetTexture(Kit.MEDIA..'Emblem')
 local glow=button:CreateTexture(nil,'HIGHLIGHT');glow:SetAllPoints();glow:SetTexture(Kit.MEDIA..'Emblem');glow:SetBlendMode('ADD');glow:SetAlpha(0.35)
 button:SetScript('OnClick',function(_,mouse)
  if mouse=='RightButton' then
   if officer() then Kit.Safe(K.Officer.Open) else K.UI.Open('settings') end
  else K.UI.Toggle() end
 end)
 button:SetScript('OnDragStart',function(self)
  self:SetScript('OnUpdate',function()
   local mx,my=Minimap:GetCenter()
   local cx,cy=GetCursorPosition()
   local scale=Minimap:GetEffectiveScale()
   settings().ui2MinimapAngle=math.deg(math.atan2(cy/scale-my,cx/scale-mx))
   place()
  end)
 end)
 button:SetScript('OnDragStop',function(self) self:SetScript('OnUpdate',nil) end)
 button:SetScript('OnEnter',function(self)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self,'ANCHOR_LEFT')
  GameTooltip:SetText('Keepers War Command',1,1,1)
  GameTooltip:AddLine('Left-click: War Room',0.9,0.85,0.75)
  GameTooltip:AddLine(officer() and 'Right-click: Command Table (officers)' or 'Right-click: Settings',0.9,0.85,0.75)
  GameTooltip:AddLine('Drag: move around the minimap',0.6,0.6,0.6)
  GameTooltip:Show()
 end)
 button:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
 place()
end
function M.IsVisible() return settings().ui2MinimapHidden~=true end
function M.SetVisible(v)
 settings().ui2MinimapHidden=not v
 build()
 if button then button:SetShown(v and true or false) end
end
function M.Reset() settings().ui2MinimapAngle=nil;settings().ui2MinimapHidden=nil;build();if button then button:Show();place() end end
K.On('PLAYER_LOGIN',function() build();if button then button:SetShown(M.IsVisible()) end end)
