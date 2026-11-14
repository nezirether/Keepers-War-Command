-- Run from the repository root with Lua 5.1: lua tests/alert_placement.lua
local noop=function() end

local function near(actual,expected,label)
 assert(math.abs(actual-expected)<1e-6,('%s: expected %g, got %g'):format(label,expected,actual))
end

local function newSession(settings,artLoads)
 local env=setmetatable({}, {__index=_G})
 local frames,events={},{}
 local mouseX,mouseY,mouseDown=0,0,false
 local now=1000
 local enemy=true
 local sounds=0
 local messages={}
 local uiScale=0.8
 env.UIParent={
  GetWidth=function() return 1920 end,
  GetHeight=function() return 1080 end,
  GetEffectiveScale=function() return uiScale end,
 }
 env.KWCDB={settings=settings,bounties={
  {status='ACTIVE',details={target='Rival',reward='5g'},sightings={{zone='Last Sighting'}}},
 }}
 env.KWC={
  On=function(event,handler)
   events[event]=events[event] or {}
   table.insert(events[event],handler)
  end,
  IsMember=function() return true end,
  Say=function(message) table.insert(messages,message) end,
  Now=function() return 'now' end,
 }
 env.time=function() return now end
 env.UnitName=function(unit) if unit=='player' then return 'Player' end;return 'Rival','OtherRealm' end
 env.UnitExists=function() return true end
 env.UnitIsPlayer=function() return true end
 env.UnitCanAttack=function() return enemy end
 env.PlaySound=function() sounds=sounds+1 end
 env.IsInGuild=function() return true end
 env.wipe=function(t) for k in pairs(t) do t[k]=nil end end
 env.GetCursorPosition=function() return mouseX*uiScale,mouseY*uiScale end
 env.IsMouseButtonDown=function() return mouseDown end

 local frameMethods={}
 function frameMethods:SetSize(w,h) self.w,self.h=w,h end
 function frameMethods:GetWidth() return self.w end
 function frameMethods:GetHeight() return self.h end
 function frameMethods:SetScale(scale) self.scale=scale end
 function frameMethods:GetEffectiveScale() return self.scale*uiScale end
 function frameMethods:GetCenter()
  if self.x then return self.x,self.y end
 end
 function frameMethods:ClearAllPoints() self.x,self.y=nil,nil end
 function frameMethods:SetPoint(point,parent,origin,x,y)
  if self.name~='KWC_BountyAlertBanner' and self.name~='KWC_WorldPvPDeathBanner' then return end
  assert(point=='CENTER' and parent==env.UIParent and origin=='BOTTOMLEFT')
  self.x,self.y=x,y
  self.anchors=self.anchors+1
 end
 function frameMethods:SetDontSavePosition(value) self.dontSavePosition=value end
 function frameMethods:SetScript(event,fn) self.scripts[event]=fn end
 function frameMethods:SetEnabled(enabled) self.enabled=enabled end
 function frameMethods:SetAlpha(alpha) self.alpha=alpha end
 function frameMethods:HookScript(event,fn) self.hooks[event]=fn end
 function frameMethods:IsShown() return self.shown end
 function frameMethods:Show() self.shown=true end
 function frameMethods:Hide()
  if self.shown then
   self.shown=false
   if self.scripts.OnHide then self.scripts.OnHide(self) end
   if self.hooks.OnHide then self.hooks.OnHide(self) end
  end
 end
 function frameMethods:SetShown(value)
  if value then self:Show() else self:Hide() end
 end
 function frameMethods:CreateTexture(_,layer)
  if self.name~='KWC_BountyAlertBanner' and self.name~='KWC_WorldPvPDeathBanner' then
   return setmetatable({},{__index=function()return noop end})
  end
  assert(layer=='BACKGROUND')
  local region={
   SetAllPoints=function(self) self.fillFrame=true end,
   SetTexture=function(self,path) self.path=path end,
   SetTexCoord=function(self,...) self.coords={...} end,
   IsObjectLoaded=function() return artLoads end,
  }
  self.art=region
  return region
 end
 function frameMethods:GetFrameLevel() return 100 end
 function frameMethods:GetChildren() return unpack(self.children) end
 function frameMethods:GetRegions() return unpack(self.text) end
 function frameMethods:CreateFontString(_,layer)
  assert(layer=='OVERLAY')
  local region=setmetatable({
   SetText=function(self,text) self.text=text end,
   SetShown=function(self,value) self.shown=not not value end,
   Hide=function(self) self.shown=false end,
  },{__index=function() return noop end})
  table.insert(self.text,region)
  return region
 end
 env.CreateFrame=function(kind,name,parent)
  local frame=setmetatable({kind=kind,name=name,parent=parent,scale=1,shown=true,anchors=0,scripts={},hooks={},text={},children={}}, {
   __index=function(_,key) return frameMethods[key] end,
  })
  if parent and parent.children then table.insert(parent.children,frame) end
  for _,method in ipairs({'SetPoint','SetWidth','SetHeight','SetAllPoints','EnableMouseWheel','SetScrollChild','SetVerticalScroll'}) do
   if not frame[method] then frame[method]=noop end
  end
  frame.SetText=function(self,value) self.value=value end
  frame.GetText=function(self) return self.value end
  for _,method in ipairs({'SetAutoFocus','EnableKeyboard','SetFont','SetTextColor','SetTextInsets','SetNumeric'}) do
   frame[method]=noop
  end
  frame.SetFrameStrata=noop
  frame.SetFrameLevel=noop
  frame.SetClampedToScreen=noop
  frame.SetMovable=noop
  frame.EnableMouse=noop
  frame.RegisterForDrag=noop
  if name then frames[name]=frame end
  table.insert(frames,frame)
  return frame
 end

 for _,name in ipairs({'AlertFrameControls','BountyAlerts','WorldPvPDeaths'}) do
  setfenv(assert(loadfile('KeepersWarCommand/'..name..'.lua')),env)()
 end

 local session={env=env,frames=frames,events=events}
 function session.setEnemy(value) enemy=value end
 function session.soundCount() return sounds end
 function session.messages() return messages end
 function session.setTime(value) now=value end
 session.alerts={
  {api=env.KWC.WorldPvPDeaths,frame=frames.KWC_WorldPvPDeathBanner,key='worldPvPDeath',defaultY=540},
  {api=env.KWC.BountyAlerts,frame=frames.KWC_BountyAlertBanner,key='bountyAlert',defaultY=750},
 }
 function session.fire(event,...)
  for _,handler in ipairs(events[event] or {}) do handler(...) end
 end
 function session.pointer(x,y,down)
  mouseX,mouseY,mouseDown=x,y,down
 end
 function session.updateDrag()
  for _,frame in ipairs(frames) do
   if frame:IsShown() and frame.w==nil and frame.scripts.OnUpdate then
    frame.scripts.OnUpdate(frame,0)
   end
  end
 end
 function session.display(alert)
  now=now+100
  if alert.key=='bountyAlert' then
   session.fire('PLAYER_TARGET_CHANGED')
  else
   session.fire('CHAT_MSG_ADDON','KWC3','2;WORLDDEATH;Rival;Hillsbrad','GUILD','Guildmate-Realm')
  end
 end
 return session
end

local function at(alert,x,y)
 local frame=alert.frame
 local cx,cy=frame:GetCenter()
 near(cx*frame.scale,x,alert.key..' center x')
 near(cy*frame.scale,y,alert.key..' center y')
end

local function saved(settings,alert,x,y)
 local position=settings[alert.key..'Position']
 near(position.nx,x/1920,alert.key..' saved x')
 near(position.ny,y/1080,alert.key..' saved y')
end

local function start(session,alert)
 session.pointer(960,540,true)
 alert.frame.scripts.OnMouseDown(alert.frame,'LeftButton')
 alert.frame.scripts.OnDragStart(alert.frame,'LeftButton')
end

for _,scale in ipairs({0.5,1,1.5,2}) do
 local settings={
  worldPvPDeathPosition={nx=0.5,ny=0.5},
  bountyAlertPosition={nx=0.5,ny=0.6},
  worldPvPDeathScale=scale,bountyAlertScale=scale,
 }
 local session=newSession(settings,true)
 session.fire('PLAYER_ENTERING_WORLD')

 for i,alert in ipairs(session.alerts) do
  local frame,api=alert.frame,alert.api
  local other=session.alerts[3-i]
  local otherPosition=settings[other.key..'Position']
  local positionKey=alert.key..'Position'
  local initial=settings[positionKey]
  local x,y=initial.nx*1920,initial.ny*1080
  local dx=i==1 and 40 or -40
  assert(frame.dontSavePosition)
  near(frame.scale,scale,'scale from SavedVariables')
  at(alert,x,y)

  api.Demo()
  start(session,alert)
  session.pointer(960+dx,555,true)
  session.updateDrag()
  at(alert,x,y)
  assert(settings[positionKey]==initial)

  api.SetUnlocked(true)
  start(session,alert)
  session.pointer(960+dx,555,true)
  session.updateDrag()
  at(alert,x+dx,y+15)
  assert(settings[positionKey]==initial)
  local anchors=frame.anchors
  api.Demo()
  session.display(alert)
  api.SetUnlocked(true)
  session.fire('PLAYER_ENTERING_WORLD')
  assert(frame.anchors==anchors and settings[positionKey]==initial)
  at(alert,x+dx,y+15)

  local newScale=scale==2 and 0.5 or 2
  api.SetScale(newScale)
  at(alert,x+dx,y+15)
  assert(settings[positionKey]==initial)
  session.pointer(960+dx+10,565,false)
  frame.scripts.OnMouseUp(frame,'RightButton')
  assert(settings[positionKey]==initial)
  if i==1 then
   frame.scripts.OnDragStop(frame)
   frame.scripts.OnMouseUp(frame,'LeftButton')
  else
   frame.scripts.OnMouseUp(frame,'LeftButton')
   frame.scripts.OnDragStop(frame)
  end
  x,y=x+dx+10,y+25
  at(alert,x,y)
  saved(settings,alert,x,y)
  session.pointer(1100,600,false)
  session.updateDrag()
  at(alert,x,y)

  local dropped=settings[positionKey]
  api.SetScale(scale)
  at(alert,x,y)
  assert(settings[positionKey]==dropped)

  start(session,alert)
  session.pointer(970,550,true)
  session.updateDrag()
  x,y=x+10,y+10
  at(alert,x,y)
  anchors=frame.anchors
  api.SetUnlocked(false)
  assert(not frame:IsShown() and frame.anchors==anchors)
  saved(settings,alert,x,y)
  api.SetUnlocked(true)
  at(alert,x,y)

  start(session,alert)
  session.pointer(955,550,true)
  session.updateDrag()
  x,y=x-5,y+10
  frame:Hide()
  saved(settings,alert,x,y)
  session.pointer(1100,600,true)
  session.updateDrag()
  api.Demo()
  at(alert,x,y)

  -- Release outside the banner, where OnMouseUp may be missed.
  start(session,alert)
  session.pointer(970,550,false)
  session.updateDrag()
  x,y=x+10,y+10
  at(alert,x,y)
  saved(settings,alert,x,y)
  assert(settings[other.key..'Position']==otherPosition)
 end

 -- Simulate the client loading persisted values into a new UI session.
 local restoredSettings={}
 for k,v in pairs(settings) do
  restoredSettings[k]=type(v)=='table' and {nx=v.nx,ny=v.ny} or v
 end
 local reload=newSession(restoredSettings,true)
 reload.fire('PLAYER_ENTERING_WORLD')
 for _,alert in ipairs(reload.alerts) do
  local position=restoredSettings[alert.key..'Position']
  local x,y=position.nx*1920,position.ny*1080
  alert.api.Demo()
  at(alert,x,y)
  near(alert.frame.scale,scale,'scale after reload')
  alert.api.ResetPosition()
  at(alert,960,alert.defaultY)
  assert(restoredSettings[alert.key..'Position']==nil)
 end
 print('PASS: both alert lifecycles at scale '..scale)
end

for _,artLoads in ipairs({true,false}) do
 local session=newSession({},artLoads)
 for _,alert in ipairs(session.alerts) do
  alert.api.Demo()
  local frame=alert.frame
  local art=frame.art
  assert(art.fillFrame and art:IsObjectLoaded()==artLoads)
  local name=alert.key=='bountyAlert' and 'BountyAlertFrame' or 'DeathAlertFrame'
  assert(art.path==([[Interface\AddOns\KeepersWarCommand\Textures\]]..name..'.tga'))
  assert(art.coords[1]==0 and art.coords[2]==1 and art.coords[3]==0 and art.coords[4]==410/512)
  assert(frame:IsShown())
  if alert.key=='bountyAlert' then
   assert(frame.text[1].text=='BOUNTY TARGET SPOTTED')
   assert(frame.text[2].text=='Example Target' and frame.text[3].text=='Reward: 1g')
  else
   assert(frame.text[2].text=='GUILDMATE SLAIN' and frame.text[3].text=='IN WORLD PVP')
   assert(frame.text[4].text=='Guildmate was slain')
   assert(frame.text[5].text=='Suspected: Alliance Rogue' and frame.text[6].text=='Hillsbrad Foothills')
   assert(not frame.children[2]:IsShown())
   frame.children[1].scripts.OnClick()
   assert(not frame:IsShown())
  end
 end
end
print('PASS: artwork paths, crop and independent text overlays with simulated texture success and failure')


local legacy={bountyAlertScale=0.75,bountyAlertPosition={nx=0.6,ny=0.6},
 worldPvPDeathDuration=12,bountySound=false,alertSound=false,guildmateAlerts=true,guildmateSound=true}
local session=newSession(legacy,true)
local env=session.env
local bounty=session.alerts[2]
local death=session.alerts[1]
env.KWC.QOL={
 Enabled=function(key) return legacy[key]~=false end,
 Toggle=function(key) legacy[key]=legacy[key]==false end,
}
session.fire('PLAYER_ENTERING_WORLD')
assert(legacy.bountyAlertDuration==nil and bounty.api.GetDuration()==7)
near(bounty.frame.scale,0.75,'legacy bounty scale')
at(bounty,1152,648)
assert(legacy.worldPvPDeathDuration==12 and legacy.bountySound==false)
assert(legacy.guildmateAlerts and legacy.guildmateSound)
assert(not env.KWC.GuildmateAlerts and not session.frames.KWC_GuildmateAlertBanner)
for _,event in ipairs({'PLAYER_TARGET_CHANGED','UPDATE_MOUSEOVER_UNIT','NAME_PLATE_UNIT_ADDED'}) do
 assert(#session.events[event]==1,event..' retains only the bounty listener')
end
session.setEnemy(false)
session.display(bounty)
assert(not bounty.frame:IsShown() and session.soundCount()==0)
bounty.api.SetTestMode(true)
assert(bounty.frame:IsShown() and bounty.frame.text[1].text=='FRIENDLY BOUNTY TEST')
bounty.frame:Hide()
bounty.api.SetTestMode(false)
session.setEnemy(true)
session.display(bounty)
assert(bounty.frame.text[2].text=='Rival-OtherRealm')
assert(bounty.frame.text[3].text=='Reward: 5g' and bounty.frame.text[4].text=='Last Sighting')
env.GetRealZoneText=function() return 'Current Zone' end
session.display(bounty)
assert(bounty.frame.text[4].text=='Current Zone')
assert(session.soundCount()==0)
bounty.api.SetDuration(3)
bounty.frame.scripts.OnUpdate(bounty.frame,2)
assert(bounty.frame:IsShown())
bounty.frame.scripts.OnUpdate(bounty.frame,1)
assert(not bounty.frame:IsShown() and legacy.bountyAlertDuration==3)
bounty.api.Demo()
local close=bounty.frame.children[1]
close.scripts.OnClick(close)
assert(not bounty.frame:IsShown())
death.api.Demo()
assert(session.soundCount()==0)
print('PASS: legacy settings, full bounty name, reward, location fallback, duration, sound, close and proximity removal')

-- Drive the real navigation and settings callbacks using mock widgets.
env.KWC.GuildServices={Context=function() end}
env.KWC.GuildReadiness=function() return 'Not currently in a guild' end
setfenv(assert(loadfile('KeepersWarCommand/MinimapLauncher.lua')),env)()
setfenv(assert(loadfile('KeepersWarCommand/UITheme.lua')),env)()
setfenv(assert(loadfile('KeepersWarCommand/UI.lua')),env)()
local function currentControl(text)
 for i=#session.frames,1,-1 do
  local f=session.frames[i]
  if f.kind=='Button' and f:IsShown() and f.text[1] and f.text[1].text==text then
   return f
  end
 end
end
local function click(text)
 local f=assert(currentControl(text),text)
 f.scripts.OnClick(f)
end
env.KWC.UI.Toggle('Settings')
assert(not currentControl('Popup: ON') and not currentControl('Incoming Calls to Arms: ON'))
assert(currentControl('Alerts').kwcPage=='Alerts')
click('Alerts')
assert(currentControl('All alert sounds: OFF'))
assert(currentControl('Ready-check notifications') and currentControl('Combat displays'))
click('Incoming Calls to Arms: ON')
assert(legacy.alerts==false)
click('Report reminders: OFF')
assert(legacy.autoGuildReports==true)
click('Time +')
assert(legacy.bountyAlertDuration==4 and legacy.worldPvPDeathDuration==12)
click('Sound: OFF')
assert(legacy.bountySound==true)
click('All alert sounds: OFF')
click('Test alert')
assert(bounty.frame:IsShown() and session.soundCount()==1)
click('Popup: ON')
assert(legacy.bountyAlerts==false and legacy.worldPvPDeathAlerts==nil)
bounty.frame:Hide()
session.display(bounty)
assert(not bounty.frame:IsShown())
click('Preferences')
assert(not currentControl('Popup: OFF'))
env.KWC.UI.Toggle('Alert Settings')
assert(currentControl('Popup: OFF'))
print('PASS: Alerts sidebar, Preferences separation, legacy navigation and actual settings callbacks')

local fields={}
for _,widget in ipairs(session.frames) do
 if widget.kind=='EditBox' and widget.parent:IsShown() then fields[#fields+1]=widget end
end
assert(#fields==3)
fields[1]:SetText('3')
fields[2]:SetText('15')
fields[3]:SetText('30')
click('Apply Smart Mode settings')
assert(legacy.worldPvPDeathThreshold==3 and legacy.worldPvPDeathWindow==15 and legacy.worldPvPDeathQuiet==30)
env.StaticPopupDialogs={}
local resetDialog
env.StaticPopup_Show=function(key,_,_,action)
 resetDialog=function() env.StaticPopupDialogs[key].OnAccept(nil,action) end
end
click('Reset Defaults')
assert(resetDialog)
resetDialog()
assert(legacy.worldPvPDeathThreshold==5 and legacy.worldPvPDeathWindow==60 and legacy.worldPvPDeathQuiet==90)
assert(legacy.worldPvPDeathSmart==true)
print('PASS: Smart Mode settings controls, Apply and Reset Defaults')

local smartSettings={}
local battle=newSession(smartSettings,true)
local api=battle.alerts[1].api
local banner=battle.alerts[1].frame
local function report(at,who)
 battle.setTime(at)
 battle.fire('CHAT_MSG_ADDON','KWC3','2;WORLDDEATH;Rival;Hillsbrad','GUILD',who)
end
local defaults=api.GetBattleSettings()
assert(defaults.threshold==5 and defaults.window==60 and defaults.quiet==90)
api.SetBattleSettings({threshold=2,window=15,quiet=30})
report(1000,'One-Realm')
assert(banner:IsShown() and battle.soundCount()==1)
banner:Hide()
report(1005,'ONE-REALM')
assert(not banner:IsShown() and #battle.messages()==1 and api.GetBattleStatus().unique==1)
report(1015,'Two-Realm')
assert(api.GetBattleStatus().active and api.GetBattleStatus().unique==2)
assert(not banner:IsShown() and battle.soundCount()==1 and #battle.messages()==2)
report(1030,'Three-Realm')
assert(api.GetBattleStatus().quietRemaining==30)
report(1035,'Three-Realm')
assert(api.GetBattleStatus().quietRemaining==25 and #battle.messages()==3)
battle.display(battle.alerts[2])
assert(battle.alerts[2].frame:IsShown())
battle.setTime(1060)
assert(not api.GetBattleStatus().active)
report(1061,'Four-Realm')
assert(banner:IsShown() and #battle.messages()==5)
banner:Hide()
report(1077,'Five-Realm')
assert(banner:IsShown() and not api.GetBattleStatus().active and api.GetBattleStatus().unique==1)
report(1080,'Five-OtherRealm')
assert(api.GetBattleStatus().active and api.GetBattleStatus().unique==2)
api.SetSmart(false)
assert(not api.GetBattleStatus().active)
report(1082,'Six-Realm')
assert(banner:IsShown() and not api.GetBattleStatus().active)
api.SetBattleSettings({threshold=200,window=0,quiet='bad'})
local restored=newSession(smartSettings,true).alerts[1].api.GetBattleSettings()
assert(restored.threshold==20 and restored.window==15 and restored.quiet==90)
api.ResetBattleSettings()
assert(smartSettings.worldPvPDeathSmart and api.GetBattleSettings().threshold==5)
print('PASS: Smart Mode limits, inclusive window, deduplication, rolling expiry, independent chat and bounty, persistence')

local life=newSession({},true)
life.env.UnitIsDeadOrGhost=function() return true end
life.env.KWC.Send=function() end
life.env.KWC.Clean=function(text) return text end
life.alerts[1].api.Report('Rival')
assert(#life.env.KWCDB.worldPvPDeaths==1)
life.setTime(1030)
life.alerts[1].api.Report('Rival')
assert(#life.env.KWCDB.worldPvPDeaths==1)
life.env.UnitIsDeadOrGhost=function() return false end
life.fire('PLAYER_UNGHOST')
life.env.UnitIsDeadOrGhost=function() return true end
life.alerts[1].api.Report('Rival')
assert(#life.env.KWCDB.worldPvPDeaths==2)
print('PASS: local death reports deduplicate until resurrection')

local artwork=newSession({},true)
local deathBanner=artwork.alerts[1].frame
local selected
artwork.env.KWC.UI={OpenBountyForName=function(name) selected=name end}
artwork.display(artwork.alerts[1])
assert(deathBanner.text[4].text=='Guildmate was slain')
assert(deathBanner.text[5].text=='Reported attacker: Rival' and deathBanner.text[6].text=='Hillsbrad')
local bountyAction=deathBanner.children[2]
assert(bountyAction:IsShown())
bountyAction.scripts.OnClick()
assert(selected=='Rival')
artwork.setTime(1200)
artwork.fire('CHAT_MSG_ADDON','KWC3','2;WORLDDEATH;Suspected: Scout;Arathi','GUILD','ScoutFriend-Realm')
assert(deathBanner.text[5].text=='Suspected attacker: Scout' and deathBanner.text[6].text=='Arathi')
assert(not bountyAction:IsShown())


-- Actual production death handlers; forbidden APIs are intentionally absent.
local function deathSession()
 local s=newSession({},true)
 s.sent={}
 s.env.UnitIsDeadOrGhost=function() return true end
 s.env.GetRealZoneText=function() return 'Hillsbrad Foothills' end
 s.env.KWC.Clean=function(text) return text end
 s.env.KWC.Send=function(kind,payload) table.insert(s.sent,{kind,payload}) end
 s.env.C_DeathRecap={GetRecapEvents=function() return s.recap end}
 s.api=s.alerts[1].api
 s.banner=s.alerts[1].frame
 return s
end
local function hit(name,stamp,flags,event)
 return {sourceName=name,sourceGUID='Player-123',sourceFlags=flags or 0x540,
  timestamp=stamp or 1000,amount=100,event=event or 'SWING_DAMAGE'}
end
local confirmed=deathSession()
confirmed.recap={hit('Enemy-Realm'),hit('Other-Realm')}
confirmed.fire('PLAYER_DEAD')
assert(#confirmed.sent==1 and confirmed.sent[1][1]=='WORLDDEATH')
assert(confirmed.banner.text[5].text=='Killed by: Enemy-Realm')
assert(confirmed.sent[1][2]=='Killed by: Enemy-Realm;Hillsbrad Foothills')
confirmed.fire('PLAYER_DEAD')
assert(#confirmed.sent==1)
local receiving=deathSession()
receiving.fire('CHAT_MSG_ADDON','KWC3','2;WORLDDEATH;'..confirmed.sent[1][2],'GUILD','Victim-Realm')
assert(receiving.banner.text[5].text=='Killed by: Enemy-Realm')
receiving.fire('CHAT_MSG_ADDON','KWC3','2;WORLDDEATH;'..confirmed.sent[1][2],'GUILD','Victim-Realm')
assert(#receiving.env.KWCDB.worldPvPDeaths==1)
assert(#receiving.env.KWCDB.bounties==1) -- no automatic bounty creation
confirmed.env.UnitIsDeadOrGhost=function() return false end
confirmed.setTime(1001);confirmed.fire('PLAYER_UNGHOST')
confirmed.env.UnitIsDeadOrGhost=function() return true end
confirmed.recap={hit('Dot-Realm',1001,nil,'SPELL_PERIODIC_DAMAGE')}
confirmed.fire('PLAYER_DEAD')
assert(#confirmed.sent==2 and confirmed.banner.text[5].text=='Killed by: Dot-Realm')
for _,flags in ipairs({0x240,0,0x510}) do
 local s=deathSession()
 s.recap={hit('NPC',1000,flags),hit('Enemy-Realm')}
 s.fire('PLAYER_DEAD')
 assert(#s.sent==0,'NPC/environment/friendly finishing damage must not report PvP')
end
for _,flags in ipairs({0x1140,0x2140}) do
 local s=deathSession()
 s.recap={hit('Pet',1000,flags),hit('Other-Realm')}
 s.fire('PLAYER_DEAD')
 assert(#s.sent==1 and s.banner.text[5].text=='Attacker unidentified')
end
local suspected=deathSession()
suspected.recap={hit(nil),hit('Recent-Realm')}
suspected.fire('PLAYER_DEAD')
assert(suspected.banner.text[5].text=='Suspected attacker: Recent-Realm')
local unknown=deathSession()
unknown.recap={hit(nil)}
unknown.fire('PLAYER_DEAD')
assert(unknown.banner.text[5].text=='Attacker unidentified')
for _,recap in ipairs({{}, {hit('Old',999)}, {hit('Future',1100)}, {hit('NPC',1000,0,'ENVIRONMENTAL_DAMAGE')}}) do
 local s=deathSession();s.recap=recap;s.fire('PLAYER_DEAD');assert(#s.sent==0)
end
local absent=deathSession()
absent.env.C_DeathRecap=nil;absent.fire('PLAYER_DEAD');assert(#absent.sent==0)
absent.api.Report('Manual');assert(#absent.sent==1,'Manual fallback remains available')
local restricted=deathSession()
restricted.env.C_DeathRecap.GetRecapEvents=function() error('restricted') end
restricted.fire('PLAYER_DEAD');assert(#restricted.sent==0)
local bg=deathSession()
bg.env.IsInInstance=function() return true,'pvp' end
bg.recap={hit('Enemy')};bg.fire('PLAYER_DEAD');assert(#bg.sent==0)
local async=deathSession()
local timers={}
async.env.C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
async.fire('PLAYER_DEAD');async.fire('PLAYER_DEAD')
assert(#timers==1)
table.remove(timers,1)();assert(#timers==1 and #async.sent==0)
async.recap={hit('Delayed')}
table.remove(timers,1)();assert(#async.sent==1)
local cancelled=deathSession()
cancelled.env.C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
cancelled.fire('PLAYER_DEAD')
cancelled.env.UnitIsDeadOrGhost=function() return false end
cancelled.fire('PLAYER_UNGHOST')
cancelled.recap={hit('Stale')};table.remove(timers,1)();assert(#cancelled.sent==0)
local reloaded=deathSession()
reloaded.setTime(1100);reloaded.env.UnitIsDeadOrGhost=function() return false end
reloaded.fire('PLAYER_ALIVE');reloaded.recap={hit('Old')};reloaded.fire('PLAYER_DEAD')
assert(#reloaded.sent==0)
local secret=deathSession()
secret.env.issecretvalue=function(v) return v=='SECRET' end
secret.recap={hit('SECRET')};secret.fire('PLAYER_DEAD')
assert(secret.banner.text[5].text=='Attacker unidentified')
assert(not confirmed.events.COMBAT_LOG_EVENT_UNFILTERED and not confirmed.events.COMBAT_LOG_EVENT)
print('PASS: death recap evidence, confidence, DoT, pets, NPC/environment, retries, reset, wire compatibility, no auto bounty')

local invalid=deathSession()
invalid.recap={hit('Enemy',1000,nil,'SPELL_HEAL')}
invalid.fire('PLAYER_DEAD');assert(#invalid.sent==0)
local enriched=deathSession()
enriched.env.UnitGUID=function() return 'Player-123' end
enriched.env.UnitClass=function() return 'Rogue' end
enriched.env.UnitFactionGroup=function() return 'Alliance' end
enriched.recap={hit('Real-Realm')};enriched.fire('PLAYER_DEAD')
local evidence=enriched.env.KWCDB.worldPvPDeaths[1].evidence
assert(evidence.name=='Real-Realm' and evidence.class=='Rogue' and evidence.faction=='Alliance')
local malformed=deathSession()
malformed.recap={hit('Bad;Name')};malformed.fire('PLAYER_DEAD')
assert(malformed.banner.text[5].text=='Attacker unidentified')
malformed.fire('CHAT_MSG_ADDON','KWC3','2;WORLDDEATH;|cBad;Zone','GUILD','Peer')
assert(#malformed.env.KWCDB.worldPvPDeaths==1)
local bounded=deathSession();bounded.recap={}
for i=1,50 do bounded.recap[i]=hit('Enemy'..i) end
bounded.fire('PLAYER_DEAD');assert(#bounded.api.recentDamage==32 and #bounded.sent==1)
print('PASS: malformed names/messages, non-damage events, GUID-matched metadata, bounded history')
