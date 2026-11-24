-- Run from the repository root with Lua 5.1.
local function session(settings,initialGroup)
 local env=setmetatable({KWC={},KeepersRaidTools={defaults={}}},{__index=_G})
 local frames,events={},{}
 local combat,grouped,down=false,initialGroup,false
 local cursorX,cursorY=0,0
 local timer,info
 local noop=function() end
 local api=env.KeepersRaidTools
 api.Components={CreateText=function(parent) return parent:CreateFontString(nil,"OVERLAY") end}
 env.KWC.On=function(event,fn) events[event]=fn end
 function api:RegisterModule(_,module) module.eventFrame=env.CreateFrame("Frame") end
 function api:GetSetting() return settings end
 function api:RegisterApplyCallback(_,fn) self.apply=fn end
 env.UIParent={GetWidth=function() return 1000 end,GetHeight=function() return 800 end,GetEffectiveScale=function() return 0.8 end}
 env.InCombatLockdown=function() return combat end
 env.IsInGroup=function() return grouped~=nil end
 env.IsInRaid=function() return grouped=="raid" end
 env.GetCursorPosition=function() return cursorX*0.8,cursorY*0.8 end
 env.IsMouseButtonDown=function() return down end
 env.GetTime=function() return 110 end
 env.C_Spell={GetSpellCharges=function() return info end,GetSpellTexture=function() return 123 end}
 env.C_Timer={NewTicker=function(_,fn) timer=fn;return {Cancel=function() timer=nil end} end}

 local methods={}
 function methods:SetSize(w,h) self.w,self.h=w,h end
 function methods:GetWidth() return self.w end
 function methods:GetHeight() return self.h end
 function methods:GetEffectiveScale() return self.scale*0.8 end
 function methods:SetScale(value) assert(not combat,"scale during combat");self.scale=value end
 function methods:SetPoint(point,_,relative,x,y)
  if not self.main then return end
  assert(not combat,"anchor during combat")
  if point=="CENTER" and relative=="BOTTOMLEFT" then self.x,self.y=x,y
  elseif point=="TOP" and relative=="TOP" then self.x,self.y=500/self.scale+x,800/self.scale+y-self.h/2
  else error("unexpected anchor") end
 end
 function methods:ClearAllPoints() assert(not combat,"anchor during combat");self.x,self.y=nil,nil end
 function methods:GetCenter() return self.x,self.y end
 function methods:SetScript(event,fn) self.scripts[event]=fn end
 function methods:HookScript(event,fn) self.hooks[event]=fn end
 function methods:IsShown() return self.shown end
 function methods:Show() self.shown=true end
 function methods:Hide()
  local shown=self.shown
  self.shown=false
  if shown and self.hooks.OnHide then self.hooks.OnHide(self) end
 end
 function methods:SetShown(value) if value then self:Show() else self:Hide() end end
 function methods:GetRegions() return end
 function methods:GetFrameLevel() return 1 end
 function methods:SetFrameStrata(value)
  assert(not combat,"strata during combat")
  self.strata=value
 end
 function methods:SetTexture(value) self.texture=value end
 function methods:GetTexture() return self.texture end
 function methods:SetText(value) self.text=value end
 function methods:SetCooldown(start,length) self.cooldownStart,self.cooldownDuration=start,length end
 function methods:Clear() self.cooldownStart,self.cooldownDuration=nil,nil end

 local function widget(name)
  return setmetatable({scale=1,shown=true,scripts={},hooks={},main=name=="KRT_BattleResWidget"},{__index=function(_,key)
   if key=="x" or key=="y" or key=="configuring" or key=="cooldownStart" or key=="cooldownDuration" then return end
   return methods[key] or noop
  end})
 end
 function methods:CreateTexture() return widget() end
 function methods:CreateFontString() return widget() end
 env.CreateFrame=function(kind,name,_,template)
  if name=="KRT_BattleResWidget" then assert(kind=="Frame" and template==nil) end
  local frame=widget(name)
  table.insert(frames,frame)
  return frame
 end

 for _,file in ipairs({"AlertFrameControls.lua","Modules/RaidTools/Modules/BattleResCounter.lua"}) do
  setfenv(assert(loadfile("KeepersWarCommand/"..file)),env)()
 end
 for key,value in pairs(api.defaults.battleResCounter) do
  if settings[key]==nil then settings[key]=value end
 end
 local br=api.BattleResCounter
 br:Initialize()
 return br,frames[2],{
  cursor=function(x,y,value) cursorX,cursorY,down=x,y,value end,
  update=function() for _,f in ipairs(frames) do if f:IsShown() and f.scripts.OnUpdate then f.scripts.OnUpdate() end end end,
  combat=function(value) combat=value;events[value and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED"]() end,
  group=function(value) grouped=value;events.GROUP_ROSTER_UPDATE() end,
  charges=function(value) info=value;if timer then timer() end end,
  tick=function() assert(timer);timer() end,
 }
end

local function center(frame,x,y)
 local cx,cy=frame:GetCenter()
 assert(math.abs(cx*frame.scale-x)<0.0001 and math.abs(cy*frame.scale-y)<0.0001,
  ("expected %g,%g got %g,%g"):format(x,y,cx*frame.scale,cy*frame.scale))
end
local settings={}
local br,frame,game=session(settings)
assert(not settings.widgetEnabled and not frame:IsShown())
br:SetWidgetEnabled(true)
br:SetPreview(true)
br:SetWidgetUnlocked(true)
assert(not frame:IsShown() and not br:IsPreviewShown())
game.group("party")
assert(not frame:IsShown() and not br:CanConfigurePosition())
game.group("raid")
assert(frame:IsShown() and br:CanConfigurePosition())
br:SetPreview(true)
assert(frame:IsShown() and frame.strata=="FULLSCREEN_DIALOG")
game.group(nil)
assert(not frame:IsShown() and not br:IsPreviewShown())
game.group("raid")
br:SetWidgetEnabled(false)
assert(not frame:IsShown())
br:SetWidgetEnabled(true)
br:SetWidgetUnlocked(true)
assert(frame:IsShown() and frame.hint:IsShown() and frame.outline:IsShown())
game.cursor(500,650,true)
frame.scripts.OnMouseDown(frame,"LeftButton")
game.cursor(605,500,false)
frame.scripts.OnMouseUp(frame,"LeftButton")
center(frame,605,503)
assert(math.abs(settings.widgetPosition.nx-0.605)<1e-6)
br:SetWidgetUnlocked(false)
assert(frame:IsShown() and settings.lockFrames)
for _,scale in ipairs({50,100,150,200}) do
 br:SetWidgetScale(scale)
 assert(br:GetWidgetScale()==scale and frame.scale==scale/100)
 center(frame,605,503)
end
local reloaded,restored=session(settings,"raid")
center(restored,605,503)
assert(restored.scale==2 and restored:IsShown())
reloaded:SetWidgetUnlocked(true)
reloaded:SetWidgetUnlocked(false)
reloaded:ResetPosition()
assert(settings.widgetPosition==nil)
center(restored,500,653)
reloaded:SetWidgetScale(90)
reloaded:ResetWidgetDefaults()
assert(not settings.widgetEnabled and settings.lockFrames and settings.widgetScale==100 and not settings.widgetPosition)

br:SetWidgetEnabled(true)
br:SetWidgetUnlocked(true)
game.cursor(500,653,true)
frame.scripts.OnMouseDown(frame,"LeftButton")
game.cursor(980,790,true)
game.update()
game.combat(true)
local beforeX,beforeY=frame:GetCenter()
game.cursor(900,740,true)
game.update()
assert(frame.x==beforeX and frame.y==beforeY)
br:SetWidgetScale(200)
br:ResetPosition()
br:SetWidgetUnlocked(false)
assert(frame.scale==1)
game.combat(false)
assert(frame.scale==2 and settings.lockFrames and not settings.widgetPosition)
center(frame,500,653)

game.group("party")
assert(not frame:IsShown())
game.group("raid")
br:OnEnable()
br:SetWidgetEnabled(false)
settings.rosterRowEnabled=false
assert(br:GetEnabledSetting() and not frame:IsShown())
game.charges({currentCharges=0,maxCharges=2,cooldownStartTime=100,cooldownDuration=60})
local charges,inEncounter=br:GetChargeState()
assert(charges==0 and inEncounter and br:GetTimerText()=="0:50")
br:SetWidgetEnabled(true)
assert(frame:IsShown() and frame.desatOverlay:IsShown() and frame.cooldown.cooldownDuration==60)
game.charges({currentCharges=2,maxCharges=2,cooldownStartTime=100,cooldownDuration=60})
assert(br:GetTimerText()=="" and frame.icon:IsShown() and not frame.cooldown.cooldownDuration)
game.combat(true)
game.group(nil)
game.tick()
assert(not frame:IsShown())
game.combat(false)
assert(not frame:IsShown())
br.eventFrame.scripts.OnEvent(nil,"ENCOUNTER_END")
assert(not select(2,br:GetChargeState()))
br:OnDisable()

local legacy={widgetPosition={point="TOP",relativePoint="TOP",x=20,y=-100},widgetScale=100,widgetEnabled=true}
local legacyBR,legacyFrame,legacyGame=session(legacy,"raid")
center(legacyFrame,520,653)
assert(legacy.widgetPosition.nx==0.52)
legacyBR:SetWidgetUnlocked(true)
legacyGame.cursor(520,653,true)
legacyFrame.scripts.OnMouseDown(legacyFrame,"LeftButton")
legacyGame.cursor(1000,800,false)
legacyFrame.scripts.OnMouseUp(legacyFrame,"LeftButton")
center(legacyFrame,956,753)
legacyBR:SetWidgetScale(200)
center(legacyFrame,912,706)
print("PASS: Battle Resurrection visibility, preview, drag, reload, legacy anchors, bounds, defaults, combat deferral and cooldown tracking")
