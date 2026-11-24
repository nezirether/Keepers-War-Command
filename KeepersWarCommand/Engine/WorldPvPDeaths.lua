-- World PvP death broadcasts. Victim's addon reports their own death only.
local K=KWC
local A={};K.WorldPvPDeaths=A
-- Automatic alerts follow the central instance policy (InstanceAlerts.lua).
-- A missing policy suppresses rather than allows.
local function alertsAllowed(token) local P=K.InstanceAlerts;return P~=nil and P.Allowed(token) end
local lastReportAt=0
local seen={}
local reportedCurrentDeath=false
local pendingDeath=false
local deathGeneration=0
local aliveSince=time()
local lastRecapStamp=0
local lastDecision='No death report processed this session'
local lastDetectedAt=0
-- Automatic diagnostic chat follows the instance policy. Delayed callers pass the
-- alert token taken at their trigger, so a stale decision never prints after a
-- transition. lastDecision is always kept for the manual /kt deathalert status.
local function decision(reason,token)
 lastDecision=reason
 if KWCDB and KWCDB.settings and KWCDB.settings.worldPvPDeathDebug and alertsAllowed(token) then
  K.Say('Death alert diagnostic: '..reason)
 end
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
-- Own-death reporting needs the confirmed open world. The shared policy guards
-- every instance API call, so unavailable, throwing, secret, unexpected or
-- loading-screen states are not eligible.
-- Current guild scope, protected and validated. Returns nil unless the scope is
-- a readable, nonempty string or a number.
local function guildScope()
 if type(K.GuildScope)~='function' then return nil end
 local ok,scope=pcall(K.GuildScope)
 if not ok or scope==nil or (issecretvalue and issecretvalue(scope)) then return nil end
 if type(scope)=='number' or (type(scope)=='string' and scope~='') then return scope end
 return nil
end
local function outdoors()
 if not IsInGuild() then return false end
 return alertsAllowed()
end
local function cleanName(name)
 if issecretvalue and issecretvalue(name) then return nil end
 if type(name)~='string' then return nil end
 if #name>48 or name:find('[%c;|]') then return nil end
 if name=='' then return nil end
 return name
end
-- 2.0: presentation moved to the War Room toast system (UI/Toast.lua).
local function settings() return KWCDB and KWCDB.settings end
local toast=K.Toast.Channel({key='worldPvPDeath',label='Guildmate slain',icon='death',tone='danger',defaultSlot=0,
 durationKey='worldPvPDeathDuration',enabledKey='worldPvPDeathAlerts'})
local banner=toast.frame
local placement=toast.placement
local function applyLock() end
local function remember(victim,killer,zone,method,evidence)
 if not KWCDB then return end
 KWCDB.worldPvPDeaths=KWCDB.worldPvPDeaths or {}
 local records=KWCDB.worldPvPDeaths
 -- 2.0: coordinates are recorded only for the local player's own death (read
 -- locally from public map APIs). Guildmates' packets carry no coordinates.
 local map,x,y
 local me=K.CharacterDisplayName(UnitName and UnitName('player'),true)
 if type(me)=='string' and type(victim)=='string' and victim:lower()==me:lower() and K.Geo then map,x,y=K.Geo.PlayerPosition() end
 table.insert(records,1,{victim=victim,killer=killer,zone=zone,at=K.Now(),epoch=time(),method=method or 'Recent player damage',evidence=evidence,map=map,x=x,y=y})
 while #records>75 do table.remove(records) end
end
local function playSound(v)
 if PlaySound and not K.Celebrations and v and v.worldPvPDeathSound~=false and (not K.QOL or K.QOL.Enabled('alertSound')) then
  pcall(PlaySound,8959,'Master')
 end
end
local function showDetails(victim,enemy,zone,killer,automatic,record)
 local actions={}
 if killer then actions[#actions+1]={label='Post bounty',fn=function() toast:Hide();if K.UI and K.UI.OpenBountyForName then K.UI.OpenBountyForName(killer) end end} end
 actions[#actions+1]={label='Death log',fn=function() toast:Hide();if K.UI and K.UI.Toggle then K.UI.Toggle('Deaths & Records') end end}
 if record and record.x and record.y and K.Geo then
  local coordinates=K.Geo.Format(record.x,record.y)
  zone=zone..'  '..coordinates
  actions[#actions+1]={label='Drop Pin',fn=function() K.Geo.DropPin(record.map,record.x,record.y) end}
  actions[#actions+1]={label='Copy Coordinates',fn=function() K.Kit.CopyBox(K.WarRoomSkin.OWNER,'Death location',record.zone..' '..coordinates) end}
 end
 toast:Present({kicker='Guildmate slain  |  World PvP',title=victim..' was slain',detail=enemy,meta=zone,tone='danger',actions=actions},automatic)
end
local function display(victim,killer,zone,method,identity,evidence,automatic,token)
 local v=settings()
 if not v then return end
 local confirmed=killer:match('^Killed by: (.+)')
 local now=time()
 local config=A.GetBattleSettings()
 -- Record once regardless of popup or chat preference.
 remember(victim,killer,zone,method,evidence)
 -- Diagnostics for automatic alerts are bound to the same token as the alert.
 -- Keep the exact token: false (ineligible at the trigger) must stay false.
 local gate=nil
 if automatic then gate=token end
 if automatic and not alertsAllowed(token) then decision('Instance alert suppression: chat, popup and sound withheld',gate);return end
 -- Smart Mode counts only deaths that could be shown, so deaths withheld in an
 -- instance cannot start a quiet period that hides the next outdoor alert.
 local suppressed,count=battleState(identity or victim:lower(),now,v.worldPvPDeathSmart~=false,config)
 if deathChatEnabled() then
  if confirmed then K.Say('WORLD PVP: '..victim..' was killed by '..confirmed..' in '..zone..'.')
  else K.Say('WORLD PVP: '..victim..' died in '..zone..'. '..killer) end
 end
 -- Popups and sounds are independent from chat and guild broadcasts.
 if v.worldPvPDeathAlerts==false then decision('Popup disabled in settings',gate);return end
 if suppressed then decision('Smart Mode: '..count..' unique guild deaths within '..config.window..'s; popup suppressed',gate);return end
 if v.worldPvPDeathSuppressInCombat and UnitAffectingCombat and UnitAffectingCombat('player') then decision('Personal combat suppression active',gate);return end
 local suspected=killer:match('^Suspected: (.+)')
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
 showDetails(victim,enemy,zone,action,automatic==true,KWCDB.worldPvPDeaths and KWCDB.worldPvPDeaths[1])
 decision('Popup shown for '..victim,gate)
 playSound(v)
end
-- Forever's public death recap is the available damage evidence. Never register
-- restricted combat-log events or infer a killer from nearby unit selection.
local function accessible(value)
 if issecretvalue and issecretvalue(value) then return nil end
 return value
end
local function attackerName(value)
 local name=cleanName(accessible(value))
 if name and name~=COMBATLOG_UNKNOWN_UNIT and name~=UNKNOWN and name:find('%S') then return name end
end
local unitTokens={'target','focus','mouseover'}
local function unitValue(api,unit)
 if not api then return nil end
 local ok,value=pcall(api,unit)
 if ok then return accessible(value) end
end

local function playerNameByGUID(guid)
 if not GetPlayerInfoByGUID then return nil end
 local ok,_,_,_,_,_,name,realm=pcall(GetPlayerInfoByGUID,guid)
 if not ok then return nil end
 name=attackerName(name)
 realm=cleanName(accessible(realm))
 if name and realm and not name:find('-',1,true) then return cleanName(name..'-'..realm) end
 return name
end

-- An owner is usable only when the owner's controlled unit has the recap GUID.
local function matchingPlayerUnit(guid,pet)
 if not guid then return nil end
 for _,unit in ipairs(unitTokens) do
  local source=pet and unit..'pet' or unit
  if unitValue(UnitGUID,source)==guid and (not pet or unitValue(UnitIsPlayer,unit)==true) then
   return unit
  end
 end
end

local damageEvents={SWING_DAMAGE=true,RANGE_DAMAGE=true,SPELL_DAMAGE=true,
 SPELL_PERIODIC_DAMAGE=true,DAMAGE_SHIELD=true,DAMAGE_SPLIT=true}
local function hasFlag(flags,flag)
 return type(flags)=='number' and flags>=0 and math.floor(flags/flag)%2==1
end

local function resolveAttacker(hit,history,stamp)
 if not damageEvents[hit.event] or not (hit.player or hit.pet) then return false end
 if hit.hideCaster then return {confidence='unknown',stamp=stamp} end
 local unit=matchingPlayerUnit(hit.guid,hit.pet)
 local guid=hit.guid
 if hit.pet then guid=unit and unitValue(UnitGUID,unit) end
 local victimGUID=unitValue(UnitGUID,'player')
 local faction=unit and unitValue(UnitFactionGroup,unit)
 local playerFaction=unitValue(UnitFactionGroup,'player')
 if (guid and guid==victimGUID) or
    (type(faction)=='string' and faction==playerFaction) then return false end
 local name=not hit.pet and hit.name or nil
 if not name and guid and not hit.pet then
  for _,recent in ipairs(history) do
   if recent.player and recent.guid==guid and damageEvents[recent.event] and recent.name then
    name=recent.name
    break
   end
  end
 end
 name=name or (unit and attackerName(unitValue(UnitName,unit))) or (guid and playerNameByGUID(guid))
 local victim=cleanName(unitValue(UnitName,'player'))
 if name and victim and not (guid and victimGUID) and
    name:match('^[^-]+'):lower()==victim:match('^[^-]+'):lower() then return false end
 return {name=name,guid=guid or nil,class=unit and unitValue(UnitClass,unit),faction=faction,
  confidence=name and 'confirmed' or 'unknown',stamp=stamp}
end

function A.ReadDeathEvidence(deathAt)
 local api=C_DeathRecap
 if not api or type(api.GetRecapEvents)~='function' then return nil end
 local ok,events=pcall(api.GetRecapEvents)
 if not ok or accessible(events)==nil or type(events)~='table' or #events==0 then return nil end
 local history={}
 local latest=0
 local first,lethal
 for i=1,math.min(#events,32) do
  local hit=accessible(events[i])
  if type(hit)=='table' then
   local stamp=accessible(hit.timestamp)
   local amount=accessible(hit.amount)
   if type(stamp)=='number' and stamp>=aliveSince and stamp>lastRecapStamp and
      stamp>=deathAt-15 and stamp<=deathAt+2 and type(amount)=='number' and amount>0 then
    latest=math.max(latest,stamp)
    local flags=accessible(hit.sourceFlags)
    local guid=accessible(hit.sourceGUID)
    local overkill=accessible(hit.overkill)
    local hostile=hasFlag(flags,0x40)
    local casterVisibility=hit.hideCaster
    local hideCaster=accessible(casterVisibility)==true or
     (issecretvalue and issecretvalue(casterVisibility))
    local entry={name=not hideCaster and attackerName(hit.sourceName) or nil,
     guid=type(guid)=='string' and guid or nil,hideCaster=hideCaster,
     timestamp=stamp,amount=amount,event=accessible(hit.event),
     player=hostile and hasFlag(flags,0x400),
     pet=hostile and hasFlag(flags,0x100) and (hasFlag(flags,0x1000) or hasFlag(flags,0x2000)),
     overkill=overkill}
    history[#history+1]=entry
    if i==1 then first=entry end
    if type(overkill)=='number' and overkill>=0 and (not lethal or stamp>lethal.timestamp) then
     lethal=entry
    end
   end
  end
 end
 if latest==0 then return nil end
 A.recentDamage=history
 -- Prefer the client's explicit killing blow. Older recap rows can omit
 -- overkill, in which case Blizzard's recap layout puts the fatal damage first.
 if lethal then
  if lethal.timestamp==latest then return resolveAttacker(lethal,history,latest) end
  return nil
 end
 if first and first.overkill==nil then return resolveAttacker(first,history,latest) end
 -- Recap may still be incomplete. Retry rather than reporting an earlier hit.
 return nil
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
 local victim=cleanName(unitValue(UnitName,'player'))
 if not victim then return end
 -- A report needs a validated guild scope captured at the moment of death.
 local deathScope=guildScope()
 if deathScope==nil then return end
 pendingDeath=true
 -- Pending death record. outdoors() above confirmed the open world at the moment
 -- of death; that classification decides the guild report and is never
 -- re-evaluated from the player's later location. Instanced or unknown deaths
 -- returned before this point and are never reported.
 local openWorldDeath=true
 -- Local notifications use the alert token from the moment of death and the
 -- current policy; a later transition drops them.
 local policy=K.InstanceAlerts
 local alertToken=policy and policy.Token()
 deathGeneration=deathGeneration+1
 local generation=deathGeneration
 local deathAt=time()
 local zone=K.Clean((GetRealZoneText and GetRealZoneText()) or 'Unknown zone',65):gsub(';',' ')
 local attempt=0
 local resolve
 local function step()
  if generation~=deathGeneration then return end
  -- A duplicate callback after the report was sent does nothing.
  if reportedCurrentDeath then pendingDeath=false;return end
  -- Send-time checks: captured location, same guild scope, still in a guild,
  -- broadcasting still enabled. The current location is not consulted.
  local currentScope=guildScope()
  if not openWorldDeath or not IsInGuild() or currentScope==nil or currentScope~=deathScope
     or not settings() or settings().worldPvPDeathBroadcast==false then
   pendingDeath=false;return
  end
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
   K.EventEvidence.Send('WORLDDEATH',report..';'..zone)
   display(victim,report,zone,'Death recap: '..evidence.confidence,nil,evidence,true,alertToken)
  elseif ok and evidence==false then
   pendingDeath=false
   decision('Death recap identifies no attributable player death',alertToken)
  elseif attempt<3 and C_Timer and C_Timer.After then
   C_Timer.After(0.7,resolve)
  else
   pendingDeath=false
   decision('Death recap unavailable or restricted; automatic attribution unavailable',alertToken)
  end
 end
 -- An error in a delayed attempt must never leave pendingDeath stuck.
 resolve=function()
  if not pcall(step) and generation==deathGeneration then
   pendingDeath=false
   decision('Death report aborted after an unexpected error',alertToken)
  end
 end
 -- Scheduling can fail too; never leave this death pending. Only this
 -- generation is cleared, and the death is not marked reported.
 local scheduled
 if C_Timer and C_Timer.After then scheduled=pcall(C_Timer.After,0.3,resolve) else resolve();scheduled=true end
 if not scheduled and generation==deathGeneration and not reportedCurrentDeath then
  pendingDeath=false
  decision('Death report could not be scheduled',alertToken)
 end
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
 local name=cleanName(K.CharacterDisplayName(UnitName('player'),true))
 if not name then return end
 reportedCurrentDeath=true
 local zone=K.Clean((GetRealZoneText and GetRealZoneText()) or 'Unknown zone',65):gsub(';',' ')
 lastReportAt=now
 K.EventEvidence.Send('WORLDDEATH',killer..';'..zone)
 display(name,killer,zone,'Manually reported by victim')
end
K.EventEvidence.On('WORLDDEATH',function(prefix,msg,channel,sender,eventID)
 if prefix~='KWC3' or channel~='GUILD' or not K.IsMember(sender) or type(msg)~='string' then return end
 local killer,zone=msg:match('^2;WORLDDEATH;([^;]+);([^;]+)$')
 if not killer or not zone or #killer>64 or #zone>65 then return end
 if killer:find('[%c|]') or zone:find('[%c|]') then return end
 local victim=cleanName(K.CharacterDisplayName(sender))
 if not victim then return end
 local now=time()
 local key=sender:lower()
 local player,realm=UnitName('player')
 realm=realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
 if realm then realm=realm:gsub('%s','') end
 local short=player and player:lower()
 local full=short and realm and realm~='' and (short..'-'..realm:lower()) or short
 if K.IsLocalSender(sender) or key==short or key==full then return end
 -- Legacy WORLDDEATH messages have no event ID; retain the short repeat filter.
 if not eventID and seen[key] and now-seen[key]<12 then return end
 for id,at in pairs(seen) do if now-at>=12 then seen[id]=nil end end
 seen[key]=now
 display(victim,killer,zone,'Reported by victim',key,nil,true)
end)
function A.SetEnabled(enabled)
 if KWCDB then KWCDB.settings.worldPvPDeathAlerts=not not enabled end
 K.Say('World PvP death popups '..(enabled and 'ON' or 'OFF'))
end
local function preview()
 showDetails('Guildmate','Suspected attacker: Alliance Rogue (preview)','Hillsbrad Foothills','Example Rogue',false)
end
toast.demo=preview
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
K.On('PLAYER_ENTERING_WORLD',function() placement.Initialize() end)
-- Instance-suppression dismissal of automatic toasts is handled by K.Toast.HookSuppression().
