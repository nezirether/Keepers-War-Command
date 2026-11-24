-- Passive target/mouseover bounty notifications with a manual sighting action.
local K=KWC
local A={};K.BountyAlerts=A
-- Automatic alerts follow the central instance policy (InstanceAlerts.lua).
-- A missing policy suppresses rather than allows.
local function alertsAllowed(token) local P=K.InstanceAlerts;return P~=nil and P.Allowed(token) end
local seen={}
-- 2.0: presentation moved to the War Room toast system (UI/Toast.lua).
local function alertSettings() return KWCDB and KWCDB.settings end
local toast=K.Toast.Channel({key='bountyAlert',label='Bounty target',icon='bounty',tone='warn',defaultSlot=2,
 durationKey='bountyAlertDuration',enabledKey='bountyAlerts',defaultDuration=7})
local banner=toast.frame
local placement=toast.placement
local function refreshLock() end
-- Guild scope lookups must never break detection; failures read as no scope.
local function guildScope()
 if type(K.GuildScope)~='function' then return nil end
 local ok,scope=pcall(K.GuildScope)
 return ok and scope or nil
end
local function showSighting(name,reward,zone,friendly,bountyId,observedZone,automatic)
 local guild=bountyId and guildScope() or nil
 local actions
 if guild~=nil then
  actions={{label='Report sighting',fn=function()
   if guild==guildScope() and K.UI and K.UI.OpenBountySighting and K.UI.OpenBountySighting(bountyId,observedZone) then toast:Hide() end
  end}}
 end
 toast:Present({kicker=friendly and 'Friendly bounty test' or 'Bounty target spotted',title=name,
  detail=reward~='' and ('Reward: '..reward) or 'Reward unspecified',meta=zone or '',tone='warn',actions=actions},automatic==true)
 if PlaySound and not K.Celebrations and (not K.QOL or (K.QOL.Enabled('bountySound') and K.QOL.Enabled('alertSound'))) then
  pcall(PlaySound,8959,'Master')
 end
end
-- WoW Forever can return "secret" values from unit and zone APIs. They must
-- never be compared, concatenated, or stored, so treat them as unknown.
local function isSecret(value)
 if not issecretvalue then return false end
 local ok,result=pcall(issecretvalue,value)
 return not ok or result==true
end
-- Call an optional API; any error or secret return becomes nil.
local function safe(fn,...)
 if type(fn)~='function' then return nil end
 local ok,a,b=pcall(fn,...)
 if not ok then return nil end
 if isSecret(a) then a=nil end
 if isSecret(b) then b=nil end
 return a,b
end
local function text(value)
 if type(value)~='string' then return nil end
 value=value:gsub('[%c|]',' '):match('^%s*(.-)%s*$')
 if value=='' then return nil end
 return value
end
local function normalized(name)
 if type(name)~='string' then return '' end
 return (name:lower():match('^%s*(.-)%s*$') or ''):match('^([^%-]+)') or ''
end
local function realmKey(realm)
 if type(realm)~='string' then return nil end
 realm=realm:lower():gsub("[%s%-']",'')
 if realm=='' then return nil end
 return realm
end
-- Match the actual character name against either a bare target name or
-- a display name containing a surname/title (e.g. "Cliveanna Vine").
-- Do not use substring matching: "Ann" must not match "Anna".
-- When both the bounty and the observed unit carry a realm, they must agree.
local function bountyMatches(target, playerName, playerRealm)
 local player=normalized(playerName)
 local stored=normalized(target)
 if player=='' or stored=='' then return false end
 if stored~=player and stored:match('^([^%s]+)%s+')~=player then return false end
 -- Only treat a space-separated suffix as a display surname/title.
 -- A hyphen remains reserved for the optional realm suffix.
 local storedRealm=type(target)=='string' and realmKey(target:match('^%s*[^%s%-]+%-(.+)$'))
 if not storedRealm then return true end
 local observedRealm=realmKey(playerRealm) or realmKey(playerName:match('^[^%-]+%-(.+)$'))
 -- Same-realm units report no realm; compare against the player's own realm.
 if not observedRealm then observedRealm=realmKey((safe(GetRealmName))) end
 if storedRealm and observedRealm and storedRealm~=observedRealm then return false end
 return true
end
-- Automatic alerts follow the global instance policy (InstanceAlerts.lua). The
-- retired battleground opt-in (settings.bountyAlertsInPvPInstances) is never read
-- or written; any saved value is left untouched.
local function mutedHere() return not alertsAllowed() end
local function policyState()
 local P=K.InstanceAlerts
 return P and P.State() or 'unavailable'
end
local function bountyUsable(b)
 if type(b)~='table' or (b.status or 'ACTIVE')~='ACTIVE' then return false end
 if b.id and KWCDB.deletions and KWCDB.deletions['BOUNTY:'..tostring(b.id)] then return false end
 return type(b.details)=='table'
end
-- Live zone is only what the client reports now; saved locations are
-- labelled so they are never mistaken for the target's current position.
local function locationFor(b)
 local live=text((safe(GetRealZoneText)))
 if live then return live,live,true end
 local sighting=type(b.sightings)=='table' and b.sightings[1]
 local saved=type(sighting)=='table' and text(sighting.zone)
 if saved then return 'Last sighted: '..saved,nil,false,saved end
 local posted=text(b.details.location)
 if posted then return 'Posted location: '..posted,nil,false,posted end
 return 'Location unavailable',nil,false
end
-- One alert per sighting episode: a target that stays visible (target,
-- mouseover or nameplate polls keep refreshing lastSeen) is not re-alerted.
-- A new episode alerts again once the cooldown has also elapsed.
local COOLDOWN,VISIBLE_GRACE,SEEN_LIMIT=90,10,64
A.COOLDOWN,A.VISIBLE_GRACE=COOLDOWN,VISIBLE_GRACE
local seenCount,seenGuild=0,nil
local function resetSeen() wipe(seen);seenCount=0 end
local function suppressed(key,now)
 -- Suppression belongs to one guild's board; a guild change starts fresh.
 local scope=guildScope()
 if scope~=seenGuild then resetSeen();seenGuild=scope end
 local rec=seen[key]
 if rec then
  local continuous=now-rec.lastSeen<=VISIBLE_GRACE
  rec.lastSeen=now
  if continuous or now-rec.alerted<COOLDOWN then return true end
  rec.alerted=now
  return false
 end
 if seenCount>=SEEN_LIMIT then
  -- Entries idle for longer than the cooldown no longer suppress anything.
  for k,r in pairs(seen) do
   if now-r.lastSeen>COOLDOWN then seen[k]=nil;seenCount=seenCount-1 end
  end
  if seenCount>=SEEN_LIMIT then return true end
 end
 seen[key]={alerted=now,lastSeen=now};seenCount=seenCount+1
 return false
end
-- True when at least one usable bounty names a target the poll could match.
local function hasTargets()
 for _,b in ipairs(KWCDB.bounties or {}) do
  if bountyUsable(b) and normalized(b.details.target)~='' then return true end
 end
 return false
end
local function check(unit,manual)
 if not KWCDB or not KWCDB.settings or KWCDB.settings.bountyAlerts==false then return end
 if type(unit)~='string' or isSecret(unit) then return end
 if not manual and mutedHere() then return end
 if not safe(UnitExists,unit) then return end
 if not safe(UnitIsPlayer,unit) then return end
 if UnitIsUnit and safe(UnitIsUnit,unit,'player') then return end
 local friendlyTest=KWCDB.settings.bountyAlertTest==true
 local enemy
 if UnitCanAttack then
  local ok,result=pcall(UnitCanAttack,'player',unit)
  -- Unknown hostility never alerts, not even as a friendly test.
  if not ok or isSecret(result) then return end
  enemy=result and true or false
 end
 if not enemy and not friendlyTest then return end
 local name,realm=safe(UnitName,unit)
 name=text(name);realm=text(realm)
 local key=normalized(name);if key=='' then return end
 for _,b in ipairs(KWCDB.bounties or {}) do
  -- Legacy bounties only have free-form text; do not guess a target from that text.
  if bountyUsable(b) and bountyMatches(b.details.target,name,realm) then
   -- Instances and unknown instance state drop the alert before it is recorded
   -- as shown, so a target seen inside cannot be suppressed outdoors later.
   if not manual and not alertsAllowed() then return end
   if suppressed(key,time()) then return end
   local details=b.details
   local fullName=realm and not name:find('-',1,true) and name..'-'..realm or name
   local shown,observedZone,live,savedZone=locationFor(b)
   showSighting(fullName,tostring(details.reward or ''),shown,not enemy,enemy and b.id or nil,observedZone,not manual)
   local where=' (current zone unknown)'
   if live then where=' in '..observedZone
   elseif savedZone then where=' (current zone unknown; '..shown:sub(1,1):lower()..shown:sub(2)..')' end
   K.Say((enemy and 'BOUNTY SPOTTED: ' or 'TEST FRIENDLY BOUNTY: ')..name..where..'.')
   return
  end
 end
end
A.Matches=bountyMatches
K.On('PLAYER_TARGET_CHANGED',function() check('target') end)
K.On('UPDATE_MOUSEOVER_UNIT',function() check('mouseover') end)
-- Detect enemy player nameplates as they become visible to the client.
-- Only the event-provided unit token is inspected; no automated targeting.
K.On('NAME_PLATE_UNIT_ADDED',function(unitToken)
 if type(unitToken)=='string' then check(unitToken) end
end)
function A.SetEnabled(enabled)
 if not KWCDB then return end
 KWCDB.settings.bountyAlerts=enabled and true or false
 K.Say('Bounty spotting alerts '..(enabled and 'enabled' or 'disabled')..'.')
 if enabled then resetSeen();check('target') end
end
function A.Status() return not KWCDB or not KWCDB.settings or KWCDB.settings.bountyAlerts~=false end
-- Retired: /kt bountyalert bg on|off. Explains the change; the saved value is untouched.
function A.SetPvPInstanceAlerts()
 K.Say('Bounty alerts in battlegrounds are no longer a separate option. KWC now suppresses '
  ..'automatic alerts in every dungeon, raid, battleground and other instance, and resumes '
  ..'them in the open world. Your previous setting is kept but no longer has any effect.')
end
-- Automatic bounty alerts never appear inside instances.
function A.PvPInstanceAlerts() return false end
function A.Muted() return mutedHere() end

function A.SetTestMode(enabled)
 if not KWCDB then return end
 KWCDB.settings.bountyAlertTest=enabled and true or false
 resetSeen()
 K.Say('Friendly bounty detection TEST MODE '..(enabled and 'ON (Horde + Alliance)' or 'OFF (enemy only)')..'.')
 if enabled then check('target') end
end
function A.TestMode() return KWCDB and KWCDB.settings and KWCDB.settings.bountyAlertTest==true end

function A.Diagnose()
 if not KWCDB then K.Say('Diagnostics: database not initialized');return end
 local unit='target'
 local exists=safe(UnitExists,unit) and true or false
 local player=exists and safe(UnitIsPlayer,unit) and true or false
 local name,realm
 if exists then name,realm=safe(UnitName,unit);name=text(name);realm=text(realm) end
 local enemy=exists and safe(UnitCanAttack,'player',unit) and true or false
 local matches=0
 for _,b in ipairs(KWCDB.bounties or {}) do
  if bountyUsable(b) and bountyMatches(b.details.target,name,realm) then matches=matches+1 end
 end
 K.Say('Bounty diagnostic: target='..tostring(name or (exists and 'unavailable') or nil)..', exists='..tostring(exists)..', player='..tostring(player)..', enemy='..tostring(enemy)..', enabled='..tostring(A.Status())..', friendlyTest='..tostring(A.TestMode())..', instancePolicy='..policyState()..', automaticAllowed='..tostring(not mutedHere())..', activeMatches='..matches)
 if exists then check(unit,true) end
end
local function duration(value)
 return math.max(3,math.min(30,tonumber(value) or 7))
end
function A.GetDuration()
 local v=alertSettings()
 return duration(v and v.bountyAlertDuration)
end
function A.SetDuration(value)
 local v=alertSettings()
 if v then v.bountyAlertDuration=duration(value) end
end
function A.Demo() showSighting('Example Target','1g (preview)','Hillsbrad Foothills',false) end
toast.demo=function() A.Demo() end
function A.SetUnlocked(value)
 local v=alertSettings();if not v then return end
 placement.SetUnlocked(value)
 if value then A.Demo() else banner:Hide() end
 refreshLock()
end
A.SetScale=placement.SetScale
A.ResetPosition=placement.Reset
K.On('PLAYER_ENTERING_WORLD',function() placement.Initialize();refreshLock() end)
-- Instance-suppression dismissal of automatic toasts is handled by K.Toast.HookSuppression().

-- Some client builds do not consistently fire nameplate events for already-visible units.
-- Scan only exposed units, never perform automated targeting or hidden-player discovery.
local poll=CreateFrame('Frame')
local pollElapsed=0
poll:SetScript('OnUpdate',function(_,dt)
 pollElapsed=pollElapsed+dt
 if pollElapsed<1.5 then return end
 pollElapsed=0
 -- Skip the scan when alerts are off, muted here, or no active bounty names a target.
 if not KWCDB or not KWCDB.settings or KWCDB.settings.bountyAlerts==false then return end
 if mutedHere() or not hasTargets() then return end
 check('target');check('mouseover')
 if C_NamePlate and C_NamePlate.GetNamePlates then
  local ok,plates=pcall(C_NamePlate.GetNamePlates)
  if ok and type(plates)=='table' then
   for _,plate in ipairs(plates) do
    local unit=plate and (plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
    if type(unit)=='string' then check(unit) end
   end
  end
 end
end)
