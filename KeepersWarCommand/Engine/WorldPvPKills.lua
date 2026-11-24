-- World PvP kill broadcasts (V4.8). The killer's addon reports its own
-- honorable kills only; guildmates show the same kind of popup as a guild death.
--
-- Mirrors WorldPvPDeaths.lua: same open-world gate (InstanceAlerts.lua), guild
-- scope checks, popup, sound, chat, combat suppression, Smart Mode, size,
-- duration and screen position. Settings use their own pvpKill* keys.
--
-- Detection never uses the restricted combat log. A kill is proven by a rise in
-- the client's honorable-kill count (GetPVPSessionStats, else
-- GetPVPLifetimeStats) after PLAYER_PVP_KILLS_CHANGED or
-- CHAT_MSG_COMBAT_HONOR_GAIN. The victim is named only when the honor chat line
-- or the event's unit can be read; otherwise the alert says the victim is
-- unknown rather than guessing.
local K=KWC
local A={};K.WorldPvPKills=A
local SETTINGS_KEY='pvpKill'
local function alertsAllowed(token) local P=K.InstanceAlerts;return P~=nil and P.Allowed(token) end
local function settings() return KWCDB and KWCDB.settings end
local lastDecision='No kill processed this session'
local lastSignalAt=0
local function decision(reason,token)
 lastDecision=reason
 local v=settings()
 if v and v.pvpKillDebug and alertsAllowed(token) then K.Say('Kill alert diagnostic: '..reason) end
end

-- ------------------------------------------------------------ Smart Mode
local recentKills={}
local battleUntil=0
local battleOptions={
 threshold={key='pvpKillThreshold',min=2,max=20,default=5},
 window={key='pvpKillWindow',min=15,max=180,default=60},
 quiet={key='pvpKillQuiet',min=15,max=300,default=90},
}
local function battleValue(option,value)
 local n=tonumber(value)
 if not n or n~=n then return option.default end
 return math.floor(math.max(option.min,math.min(option.max,n)))
end
function A.GetBattleSettings()
 local v=settings() or {}
 local result={}
 for name,option in pairs(battleOptions) do result[name]=battleValue(option,v[option.key]) end
 return result
end
function A.SetBattleSettings(values)
 local v=settings()
 if not v then return end
 for name,option in pairs(battleOptions) do v[option.key]=battleValue(option,values[name]) end
end
function A.ResetBattleSettings()
 A.SetBattleSettings({})
 A.SetSmart(true)
end
local function countKills(now,window)
 local count=0
 for _,stamp in pairs(recentKills) do if now-stamp<=window then count=count+1 end end
 return count
end
local function battleState(identity,now,enabled,config)
 for name,stamp in pairs(recentKills) do
  if now-stamp>battleOptions.window.max then recentKills[name]=nil end
 end
 recentKills[identity]=now
 local count=countKills(now,config.window)
 if enabled and (count>=config.threshold or battleUntil>now) then battleUntil=now+config.quiet end
 return enabled and battleUntil>now,count
end

-- ------------------------------------------------------------ helpers
local function accessible(value)
 if issecretvalue and issecretvalue(value) then return nil end
 return value
end
local function cleanName(name)
 name=accessible(name)
 if type(name)~='string' or name=='' or #name>48 or name:find('[%c;|]') then return nil end
 if not name:find('%S') then return nil end
 return name
end
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
local function zoneName()
 local z=GetRealZoneText and accessible(GetRealZoneText()) or nil
 if type(z)~='string' or z=='' then z='Unknown zone' end
 return (K.Clean(z,65):gsub(';',' '))
end

-- ------------------------------------------------------------ toast (2.0)
local toast=K.Toast.Channel({key=SETTINGS_KEY,label='Enemy slain',icon='kill',tone='good',defaultSlot=1,
 durationKey='pvpKillDuration',enabledKey='pvpKillAlerts'})
local banner=toast.frame
local placement=toast.placement
local function applyLock() end
local function kills(count) return count>1 and (count..' honorable kills') or 'Honorable kill' end
local function showDetails(killer,victim,count,zone,automatic)
 toast:Present({kicker='Enemy slain  |  World PvP',title=victim and (killer..' slew '..victim) or (killer..' scored a kill'),
  detail=victim and kills(count) or (kills(count)..' - victim not identified'),meta=zone,tone='good'},automatic)
end
local function playSound(v)
 if PlaySound and not K.Celebrations and v and v.pvpKillSound~=false and (not K.QOL or K.QOL.Enabled('alertSound')) then
  pcall(PlaySound,(SOUNDKIT and SOUNDKIT.UI_PVP_HONOR_PRESTIGE_RANK_UP) or 888,'Master')
 end
end
local function remember(killer,victim,count,zone,method)
 if not KWCDB then return end
 KWCDB.worldPvPKills=KWCDB.worldPvPKills or {}
 local records=KWCDB.worldPvPKills
 table.insert(records,1,{killer=killer,victim=victim,count=count,zone=zone,at=K.Now and K.Now() or time(),method=method})
 while #records>75 do table.remove(records) end
end
local function chatEnabled() local v=settings();return v and v.pvpKillChat~=false end
local function display(killer,victim,count,zone,method,identity,automatic,token)
 local v=settings()
 if not v then return end
 local now=time()
 local config=A.GetBattleSettings()
 remember(killer,victim,count,zone,method)
 local gate=nil
 if automatic then gate=token end
 if automatic and not alertsAllowed(token) then decision('Instance alert suppression: chat, popup and sound withheld',gate);return end
 local suppressed,recent=battleState(identity or (killer:lower()..':'..now),now,v.pvpKillSmart~=false,config)
 if chatEnabled() then
  if victim then K.Say('WORLD PVP: '..killer..' slew '..victim..' in '..zone..'.'..(count>1 and (' ('..count..' kills)') or ''))
  else K.Say('WORLD PVP: '..killer..' earned '..(count>1 and (count..' honorable kills') or 'an honorable kill')..' in '..zone..'.') end
 end
 if v.pvpKillAlerts==false then decision('Popup disabled in settings',gate);return end
 if suppressed then decision('Smart Mode: '..recent..' guild kills within '..config.window..'s; popup suppressed',gate);return end
 if v.pvpKillSuppressInCombat and UnitAffectingCombat and UnitAffectingCombat('player') then decision('Personal combat suppression active',gate);return end
 showDetails(killer,victim,count,zone,automatic==true)
 decision('Popup shown for '..killer,gate)
 playSound(v)
end

-- ------------------------------------------------------------ detection
local function readFirst(fn)
 if type(fn)~='function' then return nil end
 local ok,n=pcall(fn)
 n=ok and accessible(n) or nil
 if type(n)=='number' and n>=0 then return math.floor(n) end
end
local function readCounts() return readFirst(GetPVPSessionStats),readFirst(GetPVPLifetimeStats) end
local baseSession,baseLifetime
local settleUntil=0
local function rebaseline()
 baseSession,baseLifetime=readCounts()
 settleUntil=time()+10
end
A.lastSource='none'
-- Victim names seen on recent honor chat lines or kill events, oldest first.
local hints={}
local function addHint(name)
 name=cleanName(name)
 if not name then return end
 local now=time()
 for i=#hints,1,-1 do
  if now-hints[i].t>3 then break end
  if hints[i].name==name then return end
 end
 hints[#hints+1]={t=now,name=name}
 while #hints>12 do table.remove(hints,1) end
end
local function takeHints(n)
 local now,out=time(),{}
 while #hints>0 and #out<n do
  local h=table.remove(hints,1)
  if now-h.t<=15 then out[#out+1]=h.name end
 end
 return out
end
local honorPatterns
local function honorVictim(text)
 text=accessible(text)
 if type(text)~='string' then return nil end
 if not honorPatterns then
  honorPatterns={}
  for _,key in ipairs({'COMBATLOG_HONORGAIN','COMBATLOG_HONORGAIN_NO_RANK','COMBATLOG_HONORGAIN_EXHAUSTION1'}) do
   local fmt=_G[key]
   if type(fmt)=='string' and fmt:find('%%s') then
    local pattern='^'..fmt:gsub('([%%%(%)%.%+%-%*%?%[%]%^%$])','%%%1')
    pattern=pattern:gsub('%%%%s','(.-)',1):gsub('%%%%s','.-'):gsub('%%%%d','%%d+')
    honorPatterns[#honorPatterns+1]=pattern
   end
  end
  honorPatterns[#honorPatterns+1]='^(.-) dies, honorable kill'
 end
 for _,pattern in ipairs(honorPatterns) do
  local ok,victim=pcall(string.match,text,pattern)
  if ok and victim and victim~='' then return victim end
 end
end
local function unitVictim(unit)
 unit=accessible(unit)
 if type(unit)~='string' or unit=='' or unit=='player' then return nil end
 local name
 pcall(function()
  if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
  if UnitIsUnit and UnitIsUnit(unit,'player') then return end
  if UnitIsEnemy and accessible(UnitIsEnemy('player',unit))~=true then return end
  name=accessible(UnitName(unit))
 end)
 return name
end

local pending=false
local pendingToken,pendingOutdoors,pendingScope
local namedSignals=0
local lastSendAt=0
local function check()
 pending=false
 local token,wasOutdoors,scope=pendingToken,pendingOutdoors,pendingScope
 local named=namedSignals;namedSignals=0
 local session,lifetime=readCounts()
 local delta
 -- V4.9: the count source is sticky. Lifetime HKs are used only while session HKs
 -- were unreadable at the baseline and still are, because the lifetime total can
 -- lag the session count; switching sources mid-stream could count a kill twice.
 if session and baseSession then
  -- A daily session reset lowers the count: everything since the reset is new.
  delta=session>=baseSession and session-baseSession or session
  A.lastSource='session HKs'
 elseif not session and not baseSession and lifetime and baseLifetime and lifetime>=baseLifetime then
  delta=lifetime-baseLifetime;A.lastSource='lifetime HKs'
 elseif not session and not lifetime then delta=named;A.lastSource='honor chat' end
 -- Baselines follow what is readable now (nil included), so a source that
 -- becomes unreadable is re-established cleanly instead of mixing sources.
 baseSession=session
 baseLifetime=lifetime
 if not delta or delta<=0 then decision('Kill signal without a new honorable kill',token);return end
 if time()<settleUntil then decision('Kill count settled after login or zoning; not reported',token);return end
 if delta>10 then decision('Honorable kill count jumped by '..delta..'; treated as catch-up, not reported',token);return end
 if not wasOutdoors then decision('Kill outside the open world; not reported',token);return end
 local v=settings()
 if not v or v.pvpKillBroadcast==false then decision('Guild broadcast disabled in settings',token);return end
 local currentScope=guildScope()
 if not IsInGuild() or scope==nil or currentScope~=scope then decision('Guild scope changed; not reported',token);return end
 local killer=cleanName(K.CharacterDisplayName(accessible(UnitName and UnitName('player')),true))
 if not killer then return end
 local names=takeHints(delta)
 local victim=names[1]
 local zone=zoneName()
 local now=time()
 lastSendAt=now
 K.EventEvidence.Send('WORLDKILL',(victim or '-')..';'..delta..';'..zone)
 display(killer,victim,delta,zone,'Honorable kill: '..A.lastSource,nil,true,token)
end
local function signal()
 lastSignalAt=time()
 if pending then return end
 pending=true
 -- The open-world decision and guild scope are captured at the kill.
 local policy=K.InstanceAlerts
 pendingToken=policy and policy.Token()
 pendingOutdoors=outdoors()
 pendingScope=guildScope()
 local function run() if not pcall(check) then pending=false;decision('Kill report aborted after an unexpected error',pendingToken) end end
 if C_Timer and C_Timer.After and pcall(C_Timer.After,1.2,run) then return end
 run()
end
K.On('PLAYER_PVP_KILLS_CHANGED',function(unit)
 addHint(unitVictim(unit))
 signal()
end)
K.On('CHAT_MSG_COMBAT_HONOR_GAIN',function(text)
 local victim=honorVictim(text)
 if victim then addHint(victim);namedSignals=namedSignals+1 end
 signal()
end)
K.On('PLAYER_LOGIN',rebaseline)
-- Zoning drops queued victim names, so a battleground kill's name can never be
-- attached to a later open-world kill.
K.On('PLAYER_ENTERING_WORLD',function() rebaseline();for i=#hints,1,-1 do hints[i]=nil end;placement.Initialize();applyLock() end)

-- ------------------------------------------------------------ receiving
local seen={}
K.EventEvidence.On('WORLDKILL',function(prefix,msg,channel,sender,eventID)
 if prefix~='KWC3' or channel~='GUILD' or type(msg)~='string' or type(sender)~='string' then return end
 local victim,count,zone=msg:match('^2;WORLDKILL;([^;]+);(%d+);([^;]+)$')
 if not victim or not zone or #victim>48 or #zone>65 then return end
 if victim:find('[%c|]') or zone:find('[%c|]') then return end
 count=tonumber(count)
 if not count or count<1 or count>10 then return end
 if not K.IsMember(sender) then return end
 local killer=cleanName(K.CharacterDisplayName(sender))
 if not killer then return end
 local key=sender:lower()
 local player,realm=UnitName('player')
 realm=realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
 if realm then realm=realm:gsub('%s','') end
 local short=player and player:lower()
 local full=short and realm and realm~='' and (short..'-'..realm:lower()) or short
 if K.IsLocalSender(sender) or key==short or key==full then return end
 if victim=='-' then victim=nil end
 local now=time()
 local dedupe=key..'|'..(victim or '-')..'|'..count
 if not eventID and seen[dedupe] and now-seen[dedupe]<4 then return end
 for id,at in pairs(seen) do if now-at>=4 then seen[id]=nil end end
 seen[dedupe]=now
 display(killer,victim,count,zone,'Reported by killer',key..':'..(victim or now),true)
end)

-- ------------------------------------------------------------ killing blows (2.0)
-- Forever delivers PARTY_KILL(attackerGUID, targetGUID) - not the combat-log
-- tuple - and COMBAT_LOG_EVENT_UNFILTERED must never be registered (it taints).
-- Evidence: WAIE Forever API observation index (WarlordsForever Kills.lua) and
-- the archived ForeverKillingBlows / Brothers Keeper sources (studied, not copied).
-- Uses:
--  1. Our own (or our pet's) killing blow names the victim for the honor path.
--  2. A killing blow on an enemy player that earns no honorable kill is shared as
--     WORLDKB (new message kind; 1.8.2 clients ignore unknown KWC3 kinds).
-- Party members' kills, secret or missing GUIDs, non-players, guildmates and
-- anything outside the confirmed open world are skipped.
A.KB_HONOR_WINDOW=3
local ownKB,seenKB={},{}
local kbStats={seen=0,secret=0,notMine=0,reported=0,honorCovered=0}
A.KillingBlowStats=function() return kbStats end
local function killMode() local v=settings();return v and v.pvpKillMode=='all' and 'all' or 'honor' end
A.KillMode=killMode
function A.SetKillMode(mode) local v=settings();if v then v.pvpKillMode=(mode=='all') and 'all' or 'honor' end end
local function victimNameFromGUID(guid)
 if type(GetPlayerInfoByGUID)~='function' then return nil end
 local ok,_,_,_,_,_,name=pcall(GetPlayerInfoByGUID,guid)
 if not ok then return nil end
 return cleanName(accessible(name))
end
local function showKB(killer,victim,zone,automatic,token)
 local v=settings();if not v then return end
 remember(killer,victim,0,zone,'Killing blow (no honor)')
 if killMode()~='all' then decision('Killing blow recorded; popup only in All killing blows mode',automatic and token or nil);return end
 if automatic and not alertsAllowed(token) then return end
 local suppressed=battleState((killer:lower()..':kb:'..(victim or time())),time(),v.pvpKillSmart~=false,A.GetBattleSettings())
 if chatEnabled() then K.Say('WORLD PVP: '..killer..' landed a killing blow on '..(victim or 'an enemy player')..' in '..zone..' (no honor).') end
 if v.pvpKillAlerts==false or suppressed then return end
 if v.pvpKillSuppressInCombat and UnitAffectingCombat and UnitAffectingCombat('player') then return end
 toast:Present({level='Heroic',evidence='Reported own killing blow',kicker='Killing blow  |  World PvP',title=victim and (killer..' killed '..victim) or (killer..' landed a killing blow'),
  detail='No honor awarded (enemy too low or recently killed)',meta=zone,tone='good'},automatic)
 playSound(v)
end
K.On('PARTY_KILL',function(attacker,target)
 attacker,target=accessible(attacker),accessible(target)
 if type(attacker)~='string' or type(target)~='string' then kbStats.secret=kbStats.secret+1;return end
 local me=accessible(UnitGUID and UnitGUID('player'))
 local pet=accessible(UnitGUID and UnitGUID('pet'))
 if attacker~=me and (type(pet)~='string' or attacker~=pet) then kbStats.notMine=kbStats.notMine+1;return end
 if not target:match('^Player%-') then return end
 if K.Identity and K.Identity.RosterName and K.Identity.RosterName(target) then return end -- a guildmate
 local now=time()
 local observedAt=GetTime and GetTime() or now
 if ownKB[target] and observedAt-ownKB[target]<0.1 then return end
 for g,t in pairs(ownKB) do if observedAt-t>60 then ownKB[g]=nil end end
 ownKB[target]=observedAt
 kbStats.seen=kbStats.seen+1
 if K.Celebrations then K.Celebrations.KillingBlow(target,attacker..':'..target..':'..observedAt) end
 local victim=victimNameFromGUID(target)
 if victim then addHint(victim) end
 -- Open-world decision, guild scope and alert token are captured at the kill.
 local wasOutdoors=outdoors()
 local scope=guildScope()
 local token=K.InstanceAlerts and K.InstanceAlerts.Token()
 local zone=zoneName()
 local function settle()
  -- Any honor signal (HK counter or honor chat) after this kill means it was an
  -- honorable kill: the honor path owns it, whatever it decided.
  if lastSignalAt>=now or lastSendAt>=now then kbStats.honorCovered=kbStats.honorCovered+1;return end
  if not wasOutdoors then decision('Killing blow outside the open world; not reported',token);return end
  local v=settings()
  if not v or v.pvpKillBroadcast==false then return end
  if not IsInGuild() or scope==nil or guildScope()~=scope then return end
  local killer=cleanName(K.CharacterDisplayName(accessible(UnitName and UnitName('player')),true))
  if not killer then return end
  kbStats.reported=kbStats.reported+1
  K.EventEvidence.Send('WORLDKB',(victim or '-')..';'..zone)
  showKB(killer,victim,zone,true,token)
 end
 if C_Timer and C_Timer.After and pcall(C_Timer.After,A.KB_HONOR_WINDOW,function() pcall(settle) end) then return end
 pcall(settle)
end)
K.EventEvidence.On('WORLDKB',function(prefix,msg,channel,sender,eventID)
 if prefix~='KWC3' or channel~='GUILD' or type(msg)~='string' or type(sender)~='string' then return end
 local victim,zone=msg:match('^2;WORLDKB;([^;]+);([^;]+)$')
 if not victim or #victim>48 or #zone>65 or victim:find('[%c|]') or zone:find('[%c|]') then return end
 if not K.IsMember(sender) then return end
 local me=UnitName and UnitName('player')
 if K.IsLocalSender(sender) or (me and K.SameGuildMember(sender,me)) then return end
 local killer=cleanName(K.CharacterDisplayName(sender));if not killer then return end
 if victim=='-' then victim=nil end
 local now=time();local key=sender:lower()..'|'..(victim or '-')
 if not eventID and seenKB[key] and now-seenKB[key]<8 then return end
 for id,at in pairs(seenKB) do if now-at>=8 then seenKB[id]=nil end end
 seenKB[key]=now
 showKB(killer,victim,zone,true)
end)

-- ------------------------------------------------------------ settings API (same shape as WorldPvPDeaths)
function A.SetEnabled(enabled)
 local v=settings();if v then v.pvpKillAlerts=not not enabled end
 K.Say('World PvP kill popups '..(enabled and 'ON' or 'OFF'))
end
local function preview()
 showDetails('Guildmate','Alliance Rogue (preview)',1,'Hillsbrad Foothills',false)
end
toast.demo=preview
function A.Demo()
 preview()
 playSound(settings())
end
function A.SetChat(value) local v=settings();if v then v.pvpKillChat=not not value end end
function A.SetSmart(value)
 local v=settings()
 if not v then return end
 v.pvpKillSmart=not not value
 if not value then battleUntil=0 end
end
function A.SetCombatSuppression(value) local v=settings();if v then v.pvpKillSuppressInCombat=not not value end end
function A.SetBroadcast(value) local v=settings();if v then v.pvpKillBroadcast=not not value end end
function A.SetSound(value) local v=settings();if v then v.pvpKillSound=not not value end end
function A.GetBattleStatus()
 local now=time()
 local config=A.GetBattleSettings()
 local v=settings()
 local remaining=v and v.pvpKillSmart~=false and math.max(0,battleUntil-now) or 0
 return {active=remaining>0,unique=countKills(now,config.window),quietRemaining=remaining,
  threshold=config.threshold,window=config.window,quiet=config.quiet}
end
function A.SetUnlocked(value)
 placement.SetUnlocked(value)
 applyLock()
 if value then preview() else banner:Hide() end
end
A.SetScale=placement.SetScale
function A.SetDuration(value)
 local v=settings();if v then v.pvpKillDuration=math.max(3,math.min(30,tonumber(value) or 8)) end
end
A.ResetPosition=placement.Reset
function A.GetSettings() return settings() or {} end
function A.SetDebug(value) local v=settings();if v then v.pvpKillDebug=not not value end end
function A.Status()
 local v=settings() or {}
 local b=A.GetBattleStatus()
 local session,lifetime=readCounts()
 K.Say('Kill alert: popup='..(v.pvpKillAlerts==false and 'OFF' or 'ON')..' chat='..(v.pvpKillChat==false and 'OFF' or 'ON')..' broadcast='..(v.pvpKillBroadcast==false and 'OFF' or 'ON')..' smart='..(v.pvpKillSmart==false and 'OFF' or 'ON')..' combat-hide='..(v.pvpKillSuppressInCombat and 'ON' or 'OFF'))
 K.Say('HK counts: session='..tostring(session or 'unreadable')..' lifetime='..tostring(lifetime or 'unreadable')..'; last source: '..A.lastSource)
 K.Say('Battle: '..(b.active and 'ACTIVE' or 'inactive')..' kills='..b.unique..'/'..b.threshold..' quiet='..b.quietRemaining..'s')
 K.Say('Last decision: '..lastDecision..'; last kill signal='..(lastSignalAt>0 and tostring(math.max(0,time()-lastSignalAt))..'s ago' or 'not observed'))
end
-- Instance-suppression dismissal of automatic toasts is handled by K.Toast.HookSuppression().
