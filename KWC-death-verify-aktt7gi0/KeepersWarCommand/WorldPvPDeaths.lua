-- World PvP death broadcasts. Victim's addon reports their own death only.
local K=KWC
local A={};K.WorldPvPDeaths=A
local lastReportAt=0
local seen={}
local reportedCurrentDeath=false
local pendingDeath=false
local deathGeneration=0
local aliveSince=time()
local lastRecapStamp=0
local lastDecision='No death report processed this session'
local lastDetectedAt=0
local function decision(reason)
 lastDecision=reason
 if KWCDB and KWCDB.settings and KWCDB.settings.worldPvPDeathDebug then K.Say('Death alert diagnostic: '..reason) end
end
-- Keep enough history for the largest configurable window.
local recentDeaths={}
local battleUntil=0
local battleOptions={
 threshold={key='worldPvPDeathThreshold',min=2,max=20,default=5},
 window={key='worldPvPDeathWindow',min=15,max=180,default=60},
 quiet={key='worldPvPDeathQuiet',min=15,max=300,default=90},
}
local function battleValue(option,value)
 local n=tonumber(value)
 if not n or n~=n then return option.default end
 return math.floor(math.max(option.min,math.min(option.max,n)))
end
function A.GetBattleSettings()
 local settings=KWCDB and KWCDB.settings or {}
 local result={}
 for name,option in pairs(battleOptions) do
  result[name]=battleValue(option,settings[option.key])
 end
 return result
end
function A.SetBattleSettings(values)
 local settings=KWCDB and KWCDB.settings
 if not settings then return end
 for name,option in pairs(battleOptions) do
  settings[option.key]=battleValue(option,values[name])
 end
end
function A.ResetBattleSettings()
 A.SetBattleSettings({})
 A.SetSmart(true)
end
local function countDeaths(now,window)
 local count=0
 for _,stamp in pairs(recentDeaths) do
  if now-stamp<=window then count=count+1 end
 end
 return count
end
local function battleState(identity,now,enabled,config)
 for name,stamp in pairs(recentDeaths) do
  if now-stamp>battleOptions.window.max then recentDeaths[name]=nil end
 end
 recentDeaths[identity]=now
 local count=countDeaths(now,config.window)
 if enabled and (count>=config.threshold or battleUntil>now) then
  battleUntil=now+config.quiet
 end
 return enabled and battleUntil>now,count
end
local function deathChatEnabled()
 local v=KWCDB and KWCDB.settings
 return v and v.worldPvPDeathChat~=false
end
local function outdoors()
 if not IsInGuild() then return false end
 if IsInInstance then
  local inside,kind=IsInInstance()
  if kind=='pvp' or kind=='arena' then return false end
  -- Instances are excluded: the feature is for open-world PvP.
  if inside then return false end
 end
 return true
end
local function cleanName(name)
 if issecretvalue and issecretvalue(name) then return nil end
 if type(name)~='string' then return nil end
 if #name>48 or name:find('[%c;|]') then return nil end
 if name=='' then return nil end
 return name
end
local banner=CreateFrame('Frame','KWC_WorldPvPDeathBanner',UIParent)
banner:SetSize(800,320)
banner:SetFrameStrata('FULLSCREEN_DIALOG');banner:SetFrameLevel(200);banner:SetClampedToScreen(true);banner:Hide()
local function settings() return KWCDB and KWCDB.settings end
local placement=K.AlertFrameControls.Attach(banner,settings,'worldPvPDeath',0)
local moveHint=banner:CreateFontString(nil,'OVERLAY','GameFontNormal')
moveHint:SetPoint('BOTTOM',banner,'TOP',0,4);moveHint:SetText('DRAG TO MOVE  -  /kt deathalert lock')
local function applyLock()
 local v=settings();local unlocked=v and v.worldPvPDeathUnlocked
 moveHint:SetShown(unlocked and true or false)
end
local bg=banner:CreateTexture(nil,'BACKGROUND')
bg:SetAllPoints()
bg:SetTexture('Interface\\AddOns\\KeepersWarCommand\\Textures\\DeathAlertFrame.tga')
-- Sample the artwork above the transparent padding.
bg:SetTexCoord(0,1,0,410/512)
local function alertLine(text,size,y,r,g,b)
 local line=banner:CreateFontString(nil,'OVERLAY')
 line:SetFont(STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF',size,'OUTLINE')
 line:SetTextColor(r,g,b)
 line:SetPoint('TOP',banner,'TOP',0,-y)
 line:SetWidth(540)
 line:SetJustifyH('CENTER')
 line:SetMaxLines(1)
 line:SetText(text)
 return line
end
alertLine('GUILDMATE SLAIN',29,145,1,0.94,0.89)
alertLine('IN WORLD PVP',17,175,1,0.53,0.51)
local victimText=alertLine('',24,195,1,0.94,0.89)
local detail=alertLine('',19,221,0.95,0.86,0.86)
local locationText=alertLine('',18,242,0.85,0.9,1)
local close=CreateFrame('Button',nil,banner,'UIPanelCloseButton')
close:SetPoint('CENTER',banner,'TOPLEFT',755,-86)
close:SetScript('OnClick',function() banner:Hide() end)
close:SetScript('OnEnter',function(self) if GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:SetText('Close alert');GameTooltip:Show() end end)
close:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
local bountyButton=CreateFrame('Button',nil,banner,'UIPanelButtonTemplate')
bountyButton:SetSize(160,23);bountyButton:SetPoint('TOP',banner,'TOP',186,-238)
bountyButton:SetText('Add to Bounty Board')
local shownKiller=nil
bountyButton:SetScript('OnClick',function()
 if shownKiller and K.UI and K.UI.OpenBountyForName then K.UI.OpenBountyForName(shownKiller) end
end)
local shown=0
banner:SetScript('OnUpdate',function(self,dt)
 if settings() and settings().worldPvPDeathUnlocked then return end
 shown=shown+dt
 if shown>=math.max(3,math.min(30,tonumber(settings() and settings().worldPvPDeathDuration) or 8)) then self:Hide() end
end)
local function remember(victim,killer,zone,method,evidence)
 if not KWCDB then return end
 KWCDB.worldPvPDeaths=KWCDB.worldPvPDeaths or {}
 local records=KWCDB.worldPvPDeaths
 table.insert(records,1,{victim=victim,killer=killer,zone=zone,at=K.Now(),method=method or 'Recent player damage',evidence=evidence})
 while #records>75 do table.remove(records) end
end
local function playSound(v)
 if PlaySound and v and v.worldPvPDeathSound~=false and (not K.QOL or K.QOL.Enabled('alertSound')) then
  pcall(PlaySound,8959,'Master')
 end
end
local function showDetails(victim,enemy,zone,killer)
 victimText:SetText(victim..' was slain')
 detail:SetText(enemy)
 locationText:ClearAllPoints()
 locationText:SetWidth(killer and 365 or 540)
 locationText:SetPoint('TOP',banner,'TOP',killer and -84 or 0,-242)
 locationText:SetText(zone)
 shownKiller=killer
 bountyButton:SetShown(killer~=nil)
end
local function display(victim,killer,zone,method,identity,evidence)
 local v=settings()
 if not v then return end
 local now=time()
 local config=A.GetBattleSettings()
 local suppressed,count=battleState(identity or victim:lower(),now,v.worldPvPDeathSmart~=false,config)
 -- Record once regardless of popup or chat preference.
 remember(victim,killer,zone,method,evidence)
 if deathChatEnabled() then
  K.Say('WORLD PVP: '..victim..' died in '..zone..'. '..killer)
 end
 -- Popups and sounds are independent from chat and guild broadcasts.
 if v.worldPvPDeathAlerts==false then decision('Popup disabled in settings');return end
 if suppressed then decision('Smart Mode: '..count..' unique guild deaths within '..config.window..'s; popup suppressed');return end
 if v.worldPvPDeathSuppressInCombat and UnitAffectingCombat and UnitAffectingCombat('player') then decision('Personal combat suppression active');return end
 local suspected=killer:match('^Suspected: (.+)')
 local confirmed=killer:match('^Killed by: (.+)')
 local unknown=killer=='Unknown Alliance attacker' or killer=='Unidentified Alliance attacker'
 local enemy,action
 if suspected then
  enemy='Suspected attacker: '..suspected
 elseif confirmed then
  enemy='Killed by: '..confirmed
  action=confirmed
 elseif unknown then
  enemy='Attacker unidentified'
 else
  enemy='Reported attacker: '..killer
  action=killer
 end
 showDetails(victim,enemy,zone,action)
 placement.Initialize();applyLock();shown=0;banner:Show()
 decision('Popup shown for '..victim)
 playSound(v)
end
-- Forever's public death recap is the available damage evidence. Never register
-- restricted combat-log events or infer a killer from nearby unit selection.
local function accessible(value)
 if issecretvalue and issecretvalue(value) then return nil end
 return value
end
-- Optional identity enrichment requires the exact recap GUID, never proximity.
local function unitDetails(guid)
 if type(guid)~='string' or not UnitGUID then return end
 for _,unit in ipairs({'target','focus','mouseover'}) do
  local ok,id=pcall(UnitGUID,unit)
  if ok and accessible(id)==guid then
   local class,faction
   if UnitClass then
    local success,value=pcall(UnitClass,unit)
    if success and type(accessible(value))=='string' then class=value end
   end
   if UnitFactionGroup then
    local success,value=pcall(UnitFactionGroup,unit)
    if success and type(accessible(value))=='string' then faction=value end
   end
   return class,faction
  end
 end
end
local damageEvents={SWING_DAMAGE=true,RANGE_DAMAGE=true,SPELL_DAMAGE=true,
 SPELL_PERIODIC_DAMAGE=true,DAMAGE_SHIELD=true,DAMAGE_SPLIT=true}
local function hasFlag(flags,flag)
 return type(flags)=='number' and flags>=0 and math.floor(flags/flag)%2==1
end
function A.ReadDeathEvidence(deathAt)
 local api=C_DeathRecap
 if not api or type(api.GetRecapEvents)~='function' then return nil end
 local ok,events=pcall(api.GetRecapEvents)
 if not ok or accessible(events)==nil or type(events)~='table' or #events==0 then return nil end
 local history={}
 local latest=0
 for i=1,math.min(#events,32) do
  local hit=accessible(events[i])
  if type(hit)=='table' then
   local stamp=accessible(hit.timestamp)
   local amount=accessible(hit.amount)
   local event=accessible(hit.event)
   local flags=accessible(hit.sourceFlags)
   local guid=accessible(hit.sourceGUID)
   local name=cleanName(accessible(hit.sourceName))
   local class,faction=unitDetails(guid)
   if type(stamp)=='number' and stamp>=aliveSince and stamp>lastRecapStamp and
      stamp>=deathAt-15 and stamp<=deathAt+2 and type(amount)=='number' and amount>0 then
    latest=math.max(latest,stamp)
    local hostile=hasFlag(flags,0x40)
    local player=hostile and hasFlag(flags,0x400) and hasFlag(flags,0x100)
    local pet=hostile and hasFlag(flags,0x100) and (hasFlag(flags,0x1000) or hasFlag(flags,0x2000))
    history[#history+1]={name=name,guid=type(guid)=='string' and guid or nil,
     timestamp=stamp,amount=amount,event=event,player=player,pet=pet,class=class,faction=faction,
     lethal=i==1,overkill=accessible(hit.overkill)}
   end
  end
 end
 if latest==0 then return nil end
 A.recentDamage=history
 local first=history[1]
 -- The recap's first entry is the lethal event in Blizzard's own display.
 -- NPC/environmental finishing damage must not become a player killing blow.
 if first and first.lethal and not damageEvents[first.event] then return false end
 if first and first.lethal and not first.player and not first.pet then return false end
 if first and first.lethal and first.pet then return {confidence='unknown',stamp=latest} end
 local choice
 for _,hit in ipairs(history) do
  if hit.player and damageEvents[hit.event] and hit.name then
   if not choice or hit.timestamp>choice.timestamp then choice=hit end
   if hit.lethal then choice=hit;break end
  end
 end
 if choice then
  return {name=choice.name,guid=choice.guid,class=choice.class,faction=choice.faction,
   confidence=choice.lethal and 'confirmed' or 'suspected',stamp=latest}
 end
 if first and first.lethal and first.player then return {confidence='unknown',stamp=latest} end
 return false
end
local function resetDeath()
 if UnitIsDeadOrGhost and UnitIsDeadOrGhost('player') then return end
 deathGeneration=deathGeneration+1
 reportedCurrentDeath=false
 pendingDeath=false
 aliveSince=time()
 A.recentDamage={}
end
K.On('PLAYER_ALIVE',resetDeath)
K.On('PLAYER_UNGHOST',resetDeath)
K.On('PLAYER_DEAD',function()
 lastDetectedAt=time()
 if reportedCurrentDeath or pendingDeath or not outdoors() or not settings() or settings().worldPvPDeathBroadcast==false then return end
 pendingDeath=true
 deathGeneration=deathGeneration+1
 local generation=deathGeneration
 local deathAt=time()
 local victim=cleanName(UnitName('player'))
 if not victim then return end
 local zone=K.Clean((GetRealZoneText and GetRealZoneText()) or 'Unknown zone',65):gsub(';',' ')
 local attempt=0
 local function resolve()
  if generation~=deathGeneration then return end
  if not outdoors() or not settings() or settings().worldPvPDeathBroadcast==false then pendingDeath=false;return end
  attempt=attempt+1
  local ok,evidence=pcall(A.ReadDeathEvidence,deathAt)
  if ok and evidence then
   lastRecapStamp=evidence.stamp
   pendingDeath=false
   reportedCurrentDeath=true
   local report='Unidentified Alliance attacker'
   if evidence.name then
    report=(evidence.confidence=='confirmed' and 'Killed by: ' or 'Suspected: ')..evidence.name
   end
   lastReportAt=time()
   K.Send('WORLDDEATH',report..';'..zone)
   display(victim,report,zone,'Death recap: '..evidence.confidence,nil,evidence)
  elseif ok and evidence==false then
   pendingDeath=false
   decision('Death recap identifies no attributable player death')
  elseif attempt<3 and C_Timer and C_Timer.After then
   C_Timer.After(0.7,resolve)
  else
   pendingDeath=false
   decision('Death recap unavailable or restricted; automatic attribution unavailable')
  end
 end
 if C_Timer and C_Timer.After then C_Timer.After(0.3,resolve) else resolve() end
end)
-- WoW Forever Interface 16001 forbids COMBAT_LOG_EVENT_UNFILTERED.
-- Do not register it: registration taints Blizzard's protected UI.
-- Automatic alerts read the public death recap after PLAYER_DEAD.
-- Missing or restricted recap data cannot establish a killer.
function A.Report(killer)
 if not outdoors() then K.Say('Death reports are for open-world PvP only.');return end
 killer=cleanName(killer)
 if not killer then K.Say('Usage: /kt deathreport AlliancePlayerName');return end
 if not UnitIsDeadOrGhost('player') then K.Say('Death report available only while dead or a ghost.');return end
 if not KWCDB or not KWCDB.settings or KWCDB.settings.worldPvPDeathBroadcast==false then return end
 local now=time()
 if pendingDeath then K.Say('Waiting for the death recap.');return end
 if reportedCurrentDeath then K.Say('This death has already been reported.');return end
 if now-lastReportAt<12 then K.Say('Please wait before reporting another death.');return end
 local name=cleanName(UnitName('player'))
 if not name then return end
 reportedCurrentDeath=true
 local zone=K.Clean((GetRealZoneText and GetRealZoneText()) or 'Unknown zone',65):gsub(';',' ')
 lastReportAt=now
 K.Send('WORLDDEATH',killer..';'..zone)
 display(name,killer,zone,'Manually reported by victim')
end
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~='KWC3' or channel~='GUILD' or not K.IsMember(sender) or type(msg)~='string' then return end
 local killer,zone=msg:match('^2;WORLDDEATH;([^;]+);([^;]+)$')
 if not killer or not zone or #killer>64 or #zone>65 then return end
 if killer:find('[%c|]') or zone:find('[%c|]') then return end
 local victim=cleanName(sender:match('^[^-]+'))
 if not victim then return end
 local now=time()
 local key=sender:lower()
 local player,realm=UnitName('player')
 realm=realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
 if realm then realm=realm:gsub('%s','') end
 local short=player and player:lower()
 local full=short and realm and realm~='' and (short..'-'..realm:lower()) or short
 if key==short or key==full then return end
 -- Legacy WORLDDEATH messages have no event ID; retain the short repeat filter.
 if seen[key] and now-seen[key]<12 then return end
 seen[key]=now
 display(victim,killer,zone,'Reported by victim',key)
end)
function A.SetEnabled(enabled)
 if KWCDB then KWCDB.settings.worldPvPDeathAlerts=not not enabled end
 K.Say('World PvP death popups '..(enabled and 'ON' or 'OFF'))
end
local function preview()
 showDetails('Guildmate','Suspected: Alliance Rogue','Hillsbrad Foothills')
 placement.Initialize();applyLock();shown=0;banner:Show()
end
function A.Demo()
 preview()
 playSound(settings())
end
function A.SetChat(value) if settings() then settings().worldPvPDeathChat=not not value end end
function A.SetSmart(value)
 local v=settings()
 if not v then return end
 v.worldPvPDeathSmart=not not value
 if not value then battleUntil=0 end
end
function A.SetCombatSuppression(value) if settings() then settings().worldPvPDeathSuppressInCombat=not not value end end
function A.GetBattleStatus()
 local now=time()
 local config=A.GetBattleSettings()
 local v=settings()
 local remaining=v and v.worldPvPDeathSmart~=false and math.max(0,battleUntil-now) or 0
 return {active=remaining>0,unique=countDeaths(now,config.window),quietRemaining=remaining,
  threshold=config.threshold,window=config.window,quiet=config.quiet}
end
function A.SetSound(value) if settings() then settings().worldPvPDeathSound=not not value end end
function A.SetUnlocked(value)
 placement.SetUnlocked(value)
 applyLock()
 if value then preview() else banner:Hide() end
end
A.SetScale=placement.SetScale
function A.SetDuration(value)
 if settings() then settings().worldPvPDeathDuration=math.max(3,math.min(30,tonumber(value) or 8)) end
end
A.ResetPosition=placement.Reset
function A.GetSettings() return settings() or {} end
function A.Status()
 local v=settings() or {}
 local b=A.GetBattleStatus()
 K.Say('Death alert: popup='..(v.worldPvPDeathAlerts==false and 'OFF' or 'ON')..' chat='..(v.worldPvPDeathChat==false and 'OFF' or 'ON')..' smart='..(v.worldPvPDeathSmart==false and 'OFF' or 'ON')..' combat-hide='..(v.worldPvPDeathSuppressInCombat and 'ON' or 'OFF'))
 K.Say('Battle: '..(b.active and 'ACTIVE' or 'inactive')..' unique='..b.unique..'/'..b.threshold..' quiet='..b.quietRemaining..'s')
 K.Say('Last decision: '..lastDecision..'; last PLAYER_DEAD='..(lastDetectedAt>0 and tostring(math.max(0,time()-lastDetectedAt))..'s ago' or 'not observed'))
end
function A.SetDebug(value) if settings() then settings().worldPvPDeathDebug=not not value end end
K.On('PLAYER_ENTERING_WORLD',function() placement.Initialize();applyLock() end)
