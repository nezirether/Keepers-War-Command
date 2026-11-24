local K=KWC;K.PvP={}
local lastHonorRequest=0
local lastHonorReply=0
local diagnostics={sent=0,received=0,rejected=0,pending=0,lastPeer=nil,lastReason='none',lastSentAt=nil,lastReceivedAt=nil}
local pendingHonor={}
local pendingArea={}
local nativeStatus={world='not read',battleground='not read'}
-- Cached PvP recovery: reports are historical, never impersonated as live self reports.
local lastCacheReply=0
local cacheRequest, cacheCursor = nil, 0
local cacheGuild
local function guildScope() return K.GuildScope and K.GuildScope() end
local function requestCache()
 local guild=guildScope()
 if not guild then return K.Send and K.Send('PVPREQ','1') end
 local peers=K.Sync and K.Sync.RecoveryOfficers and K.Sync.RecoveryOfficers()
 if not peers or #peers==0 then return false end
 if cacheGuild~=guild then cacheGuild=guild;cacheCursor=0 end
 cacheCursor=cacheCursor+1
 local target=peers[(cacheCursor-1)%#peers+1]
 local token=tostring(time())..'-'..tostring(math.random(100000,999999))
 cacheRequest={guild=guild,target=target,token=token,expires=time()+90}
 return K.Net.Send('KWC3','2;PVPREQ2;'..guild..';'..token..';'..(math.floor((cacheCursor-1)/#peers)%100),'WHISPER',target)
end
local function cachePacket(msg,channel,sender)
 if channel=='GUILD' and not guildScope() then return msg end
 local request=cacheRequest
 if channel~='WHISPER' or not request or request.guild~=guildScope()
  or time()>request.expires or not K.SameGuildMember(request.target,sender)
  or not K.IsSenderOfficer(sender) then return end
 local guild,token,body=msg:match('^2;PVPREPLY;(%d+);(%d+%-%d+);(.+)$')
 if guild==request.guild and token==request.token then return body end
end

function K.PvP.Diagnostics() return diagnostics end
local function outcome(reason)
 if K.Sync and K.Sync.RecordOutcome then K.Sync.RecordOutcome('KWC3 PvP',reason) end
end
local function reject(reason,sender)
 outcome(reason)
 diagnostics.rejected=diagnostics.rejected+1;diagnostics.lastPeer=sender;diagnostics.lastReason=reason
end
-- PvP-only canonical identity: require Forever's two-part character name.
-- Bounty and alert name resolution is intentionally untouched.
local function plain(n)
 if type(n)~='string' then return nil end
 return (n:match('^[^-]+') or n):match('^%s*(.-)%s*$')
end
local function two(n) return type(n)=='string' and n:match('^%S+%s+%S+$')~=nil end
local function rosterFull(n)
 n=plain(n);if not n then return nil end
 local found=nil
 for _,r in pairs((KWCDB and KWCDB.roster) or {}) do
  local full=type(r)=='table' and plain(r.name) or nil
  if two(full) then
   local same=full:lower()==n:lower()
   if not same and not n:find('%s') then same=full:lower():sub(1,#n+1)==n:lower()..' ' end
   if same then
    if found and found:lower()~=full:lower() then return nil end
    found=full
   end
  end
 end
 return found
end
-- PvP-only recovery for Forever clients that expose the local player's
-- given name but do not expose the surname in UnitName/UnitFullName.
-- This is deliberately NOT a general authorization or guild rank fallback.
local localIdentityReason='not checked'
local function verifiedLocalRosterName()
 if not GetNumGuildMembers or not GetGuildRosterInfo then
  return nil,'guild roster API unavailable'
 end
 local first=UnitName and plain(UnitName('player'))
 if not first or first=='' then return nil,'local player name unavailable' end
 -- Never guess if UnitName is ambiguous or contains a different full name.
 local candidates={}
 local guid=UnitGUID and UnitGUID('player')
 if type(guid)~='string' or guid=='' then guid=nil end
 for i=1,(GetNumGuildMembers() or 0) do
  local name,_,_,_,_,_,_,_,online,_,_,_,_,_,_,_,memberGUID=GetGuildRosterInfo(i)
  local current=plain(name)
  if two(current) and (current:lower()==first:lower() or
    current:lower():match('^%S+')==first:lower()) then
   if type(memberGUID)=='string' and memberGUID~='' and guid and memberGUID~=guid then
    -- A conflicting roster GUID rules out this candidate.
   else
    candidates[#candidates+1]={name=current,online=online,guid=memberGUID}
   end
  end
 end
 if #candidates~=1 then return nil,#candidates==0 and 'no unique roster surname match' or 'ambiguous roster surname' end
 local match=candidates[1]
 -- If the roster has no GUID for this character, require a current online
 -- roster entry. Do not use this fallback to authorize officer actions.
 if not (type(match.guid)=='string' and guid and match.guid==guid) and match.online~=true then
  return nil,'roster candidate not verified online'
 end
 return match.name,'unique live roster name'
end
local function key()
 if K.LocalGuildMember then
  local id,_,_,reason=K.LocalGuildMember()
  if id then
   for i=1,(GetNumGuildMembers and GetNumGuildMembers() or 0) do
    local name=GetGuildRosterInfo(i)
    if type(name)=='string' and name:lower()==id then
     localIdentityReason='verified by core ('..tostring(reason)..')'
     return plain(name)
    end
   end
   localIdentityReason='core identity missing roster display'
   return nil
  end
  local fallback,why=verifiedLocalRosterName()
  localIdentityReason=fallback and ('PvP local-only fallback: '..why) or ('core: '..tostring(reason)..'; fallback: '..why)
  return fallback
 end
 if type(UnitFullName)=='function' then
  local ok,n=pcall(UnitFullName,'player');if ok and two(plain(n)) then return plain(n) end
 end
 local n=UnitName and UnitName('player')
 if two(plain(n)) then return plain(n) end
 return rosterFull(n)
end
local function isSelf(n)
 local full=key()
 if not full or type(n)~='string' then return false end
 if K.CurrentGuildMember then
  local current=K.CurrentGuildMember(n)
  local me=K.CurrentGuildMember(full)
  return current~=nil and me~=nil and current==me
 end
 n=plain(n)
 return n~=nil and full:lower()==n:lower()
end
-- These are the character Statistics pane IDs in Forever's Achievement data.
local areaKeys={'world','battleground'}
local areaIDs={[381]='world',[382]='battleground'}
local statSlots={}
local lastAreaSignature,lastAreaBroadcast
local publishedGuild
local function validKills(value)
 return type(value)=='number' and value>=0 and value<=100000000 and value%1==0
end
local function areaSnapshot(record,area)
 local stats=type(record)=='table' and record.honorByArea
 local value=type(stats)=='table' and stats[area]
 if type(value)=='table' and validKills(value.value) and type(value.at)=='number' and value.at>0 and value.at<=time()+300 then return value end
end
local function newer(snapshot,previous)
 return snapshot and (not previous or snapshot.at>previous.at or
  (snapshot.at==previous.at and snapshot.value>previous.value))
end
local function storeArea(record,area,snapshot)
 local previous=areaSnapshot(record,area)
 if not newer(snapshot,previous) then return false end
 record.honorByArea=record.honorByArea or {}
 record.honorByArea[area]=snapshot
 return not previous or previous.value~=snapshot.value
end
local function areaPayload(record)
 local world,bg=areaSnapshot(record,'world'),areaSnapshot(record,'battleground')
 if not world and not bg then return nil end
 return table.concat({world and world.value or -1,world and world.at or 0,
  bg and bg.value or -1,bg and bg.at or 0},';')
end
local function merge(dst,src)
 if type(src)~='table' then return dst end
 dst=dst or {};dst.weekly=dst.weekly or {}
 for w,n in pairs(src.weekly or {}) do if type(n)=='number' then dst.weekly[w]=math.max(dst.weekly[w] or 0,n) end end
 local a,b=dst.honor,src.honor
 if type(b)=='table' and (type(a)~='table' or not a.available or (a.peerReported and not b.peerReported) or (a.peerReported==b.peerReported and (b.lastRead or 0)>(a.lastRead or 0))) then dst.honor=b end
 for _,area in ipairs(areaKeys) do storeArea(dst,area,areaSnapshot(src,area)) end
 -- Preserve retired points when consolidating local SavedVariables aliases.
 if not dst.achievementPoints then dst.achievementPoints=src.achievementPoints end
 return dst
end
-- 2.0: exported for verified-rename migration (Engine/Identity.lua).
K.PvP.Merge=merge
function K.PvP.PlayerName() return key() end
function K.PvP.CanonicalDisplayName(n)
 n=plain(n)
 if two(n) then return n end
 if isSelf(n) then return key() end
 return rosterFull(n)
end
function K.PvP.CleanupSelfEchoes()
 if not KWCDB or type(KWCDB.pvp)~='table' then return end
 local full=key();if not full then return end
 local record=KWCDB.pvp[full]
 for n,p in pairs(KWCDB.pvp) do
  if n~=full and isSelf(n) then record=merge(record,p);KWCDB.pvp[n]=nil end
 end
 if record then KWCDB.pvp[full]=record end
end
local function peerCanonical(sender)
 if K.Identity and K.Identity.Current then sender=K.Identity.Current(sender) end
 -- A verified roster entry is sufficient for a direct, sender-bound report.
 -- Do not require a surname or infer a roster identity from a saved alias.
 if K.CurrentGuildMember then
  local verified=K.CurrentGuildMember(sender)
  if not verified then return end
  for i=1,GetNumGuildMembers() or 0 do
   local current=GetGuildRosterInfo(i)
   if type(current)=='string' and current:lower()==verified then
    return current
   end
  end
  return verified
 end
 return K.PvP.CanonicalDisplayName(sender)
end
function K.PvP.PeerCanonical(sender) return peerCanonical(sender) end
local function week() return date('%Y-W%W') end
local function day() return date('%Y-%m-%d') end
local function entry()
 local id=key();if not id then return nil end;local p=KWCDB.pvp[id] or {kills=0,deaths=0,weekly={},targets={},seen={}}
 p.weekly=p.weekly or {};p.targets=p.targets or {};p.seen=p.seen or {};KWCDB.pvp[id]=p;return p
end
-- Read the same native counters as Blizzard's Statistics pane. Cache the
-- category/index lookup, but recheck the returned ID before using a slot.
local function isSecret(value)
 if type(issecretvalue)~='function' then return false end
 local ok,result=pcall(issecretvalue,value)
 return not ok or result==true
end
local function nativeCount(raw)
 if isSecret(raw) then return end
 if type(raw)=='string' then
  raw=raw:match('^%s*(.-)%s*$')
  if not raw:match('^%d+$') then
   raw=raw:gsub('\194\160',' '):gsub('\226\128\175',' ')
   local separator=raw:match('^%d%d?%d?([,%. ])')
   if not separator then return end
   local first=raw:find(separator,1,true)
   for i=first,#raw,4 do
    if raw:sub(i,i)~=separator or not raw:sub(i+1,i+3):match('^%d%d%d$') then return end
   end
   raw=raw:gsub('[,%. ]','')
  end
  raw=tonumber(raw)
 end
 if validKills(raw) then return raw end
end
local function readAreaStats()
 local values,found={},{}
 nativeStatus={world='native statistic not found',battleground='native statistic not found'}
 if type(GetStatistic)~='function' then
  nativeStatus.world='statistics API unavailable';nativeStatus.battleground=nativeStatus.world
  return values
 end
 local function read(category,index)
  -- A missing category or restricted row must not discard other valid rows.
  local ok,quantity,skip,id=pcall(GetStatistic,category,index)
  if not ok or isSecret(id) or isSecret(skip) then return end
  local area=areaIDs[id]
  if area then
   found[area]={category,index}
   local count=skip~=true and nativeCount(quantity) or nil
   if count~=nil then values[area]=count;nativeStatus[area]='available'
   elseif values[area]==nil then nativeStatus[area]='native statistic unreadable or skipped' end
  end
 end
 -- Blizzard's Statistics display reads individual IDs directly; enumeration
 -- is the compatible discovery fallback when that overload is unavailable.
 for id,area in pairs(areaIDs) do
  local ok,raw=pcall(GetStatistic,id)
  local count=ok and nativeCount(raw) or nil
  if count~=nil then values[area]=count;nativeStatus[area]='available' end
 end
 for _,slot in pairs(statSlots) do read(slot[1],slot[2]) end
 if (values.world==nil or values.battleground==nil) and
    type(GetStatisticsCategoryList)=='function' and type(GetCategoryNumAchievements)=='function' then
  local ok,categories=pcall(GetStatisticsCategoryList)
  if ok and not isSecret(categories) and type(categories)=='table' then
   local categoriesRead=0
   for _,category in pairs(categories) do
    if categoriesRead>=256 then break end
    categoriesRead=categoriesRead+1
    if not isSecret(category) and type(category)=='number' then
     local readable,size=pcall(GetCategoryNumAchievements,category)
     if readable and not isSecret(size) and type(size)=='number' and size>=0 then
      for index=1,math.min(size,1000) do read(category,index) end
     end
    end
   end
  end
 end
 statSlots=found
 return values
end
local function refreshArea(record)
 local ok,values=pcall(readAreaStats)
 if not ok then
  statSlots={}
  return false
 end
 local now,changed=time(),false
 local observed={}
 local valueKey={}
 for _,area in ipairs(areaKeys) do
  local value=values[area]
  if value~=nil then
   local previous=areaSnapshot(record,area)
   record.honorByArea=record.honorByArea or {}
   record.honorByArea[area]={value=value,at=now}
   observed[area]=record.honorByArea[area]
   changed=(not previous or previous.value~=value) or changed
  end
  valueKey[#valueKey+1]=value or -1
 end
 local signature=table.concat(valueKey,';')
 if next(observed) and K.Send and
    (signature~=lastAreaSignature or not lastAreaBroadcast or now-lastAreaBroadcast>600) then
  if K.Send('HKAREA',areaPayload({honorByArea=observed})) then
   diagnostics.sent=diagnostics.sent+1;diagnostics.lastSentAt=now
   lastAreaSignature,lastAreaBroadcast=signature,now
  end
 end
 return changed
end
-- Resolve both cached records and live members through the shared verified identity.
function K.PvP.Rankings(metric)
 local players,byName={},{}
 local function identity(name)
  local current=K.Identity and K.Identity.Current(name) or name
  if K.CurrentGuildMember then
   local id=K.CurrentGuildMember(current)
   if not id then return end
   return id,peerCanonical(current) or current
  end
  local display=K.PvP.CanonicalDisplayName(current) or current
  return display:lower(),display
 end
 for name,record in pairs((KWCDB and KWCDB.pvp) or {}) do
  local id,display=identity(name)
  local snapshot
  if type(record)=='table' then
   local honor=record.honor
   if metric=='lifetime' then
    if honor and honor.available and validKills(honor.lifetime) then
     snapshot={value=honor.lifetime,at=honor.lastRead or 0}
    end
   else snapshot=areaSnapshot(record,metric) end
  end
  if id and type(snapshot)=='table' and validKills(snapshot.value) and
     type(snapshot.at)=='number' and snapshot.at>=0 and snapshot.at<=time()+300 then
   local previous=byName[id]
   if not previous or newer(snapshot,previous.snapshot) then
    byName[id]={name=display,value=snapshot.value,snapshot=snapshot,status=time()-snapshot.at>86400 and 'Stale' or 'Available'}
   end
  end
 end
 -- Never seed scores from a missing cache. Only a live, verified roster member
 -- may receive an unranked Awaiting Stats row.
 if K.CurrentGuildMember and GetNumGuildMembers and GetGuildRosterInfo then
  for i=1,GetNumGuildMembers() or 0 do
   local name=GetGuildRosterInfo(i)
   local id,display=identity(name)
   if id and not byName[id] then byName[id]={name=display,status='Awaiting Stats'} end
  end
 end
 for _,player in pairs(byName) do players[#players+1]=player end
 table.sort(players,function(a,b)
  if (a.value~=nil)~=(b.value~=nil) then return a.value~=nil end
  if a.value~=nil and a.value~=b.value then return a.value>b.value end
  return a.name:lower()<b.name:lower()
 end)
 return players
end
-- Explicit local diagnostic only. No broadcast and no unrelated member dump.
function K.PvP.MemberDiagnostic(name,metric)
 if type(name)~='string' or #name>100 or name:find('[%c|]') then return 'PvP member diagnostic: invalid name' end
 metric=metric or 'world'
 local current=K.Identity and K.Identity.Current(name) or name
 if not K.CurrentGuildMember or not K.CurrentGuildMember(current) then
  return 'PvP member diagnostic: pending current guild identity verification; no score attached.'
 end
 local guid=K.Identity and K.Identity.RosterGUID(current)
 for _,row in ipairs(K.PvP.Rankings(metric)) do
  if K.SameGuildMember(current,row.name) then
   local self=isSelf(row.name)
   local result='PvP member: '..row.name..' | GUID='..tostring(guid or 'unavailable')..' | roster=verified'
   if current~=name then result=result..' | verified alias='..name end
   result=result..' | source='..(self and 'local native' or 'received snapshot')..' | '..metric..' | '..row.status
   if row.value~=nil then result=result..'='..row.value..' | age='..math.max(0,time()-row.snapshot.at)..'s'
   else result=result..': no valid cached statistic; compatible self-publication or officer cache required' end
   if self then
    result=result..' | native read='..nativeStatus.world..' | published='..tostring(lastAreaBroadcast or 'not yet')
   else
    result=result..' | local identity='..tostring(localIdentityReason)
   end
   return result
  end
 end
 return 'PvP member diagnostic: roster is still loading.'
end
function K.PvP.RefreshMyStats()
 local result=K.PvP.RefreshHonor()
 K.PvP.RequestGuildHonor(true)
 local reason=result and result.reason or 'guild identity or storage not ready'
 if K.Say then K.Say(result and result.world and 'World PvP native statistic refreshed.' or ('Awaiting Stats: '..reason..'. Last valid values are preserved.')) end
 return result
end
-- ForeverAPI (1.60.1): COMBAT_LOG_EVENT_UNFILTERED registration is forbidden.
-- Do not register it or infer killing blows/deaths from inaccessible combat logs.
-- Official lifetime HK snapshots below are the supported baseline.

-- Blizzard's authoritative character honor totals. These are not combat-log estimates.
-- Snapshotting preserves pre-install lifetime HKs without inventing past kill details.
function K.PvP.RefreshHonor()
 if not KWCDB or not KWCDB.pvp then return {world=false,reason='PvP storage not initialized'} end
 local guild=guildScope()
 if guild and KWCDB.guildPartitionBound~=guild then return {world=false,reason='guild partition not bound'} end
 if publishedGuild~=guild then lastAreaSignature,lastAreaBroadcast=nil,nil;publishedGuild=guild end
 if K.Identity and K.Identity.Scan then K.Identity.Scan() end
 K.PvP.CleanupSelfEchoes()
 local p=entry()
 if not p then return {world=false,reason='local identity pending: '..localIdentityReason} end
 local function read(fn)
  if type(fn)~='function' then return nil end
  local ok,n=pcall(fn)
  if ok then return nativeCount(n) end
  return nil
 end
 local lifetime=read(GetPVPLifetimeStats)
 local today=nil -- Not exposed by the supplied ForeverAPI reference
 local yesterday=read(GetPVPYesterdayStats)
 p.honor=p.honor or {}
 if lifetime~=nil then
  local previous=p.honor.lifetime
  -- Daily/weekly counts are observed lifetime-HK deltas, never invented history.
  -- If a character was offline across a date boundary, assign the increase to
  -- the first day/week observed; actual kill timestamps are unavailable.
  p.honor.daily=p.honor.daily or {}
  p.weekly=p.weekly or {}
  local todayKey=day()
  local weekKey=week()
  if type(previous)=='number' and lifetime>previous then
   local delta=lifetime-previous
   p.honor.daily[todayKey]=(p.honor.daily[todayKey] or 0)+delta
   p.weekly[weekKey]=(p.weekly[weekKey] or 0)+delta
  end
  -- Cap stored daily history without affecting current values.
  local days={};for k in pairs(p.honor.daily) do days[#days+1]=k end
  table.sort(days)
  for i=1,math.max(0,#days-35) do p.honor.daily[days[i]]=nil end
  p.honor.lifetime=lifetime
  p.honor.available=true
  p.honor.lastRead=time();p.honor.originAt=p.honor.lastRead
  p.honor.firstObserved=p.honor.firstObserved or lifetime
  if K.Send and (p.honor.lastBroadcast~=lifetime or not p.honor.lastBroadcastAt or time()-p.honor.lastBroadcastAt>600) then
   if K.Send('HONOR2',table.concat({lifetime,weekKey,p.weekly[weekKey] or 0,todayKey,p.honor.daily[todayKey] or 0},';')) then p.honor.lastBroadcast=lifetime;p.honor.lastBroadcastAt=time();diagnostics.sent=diagnostics.sent+1;diagnostics.lastSentAt=time() end
  end
 end
 if today~=nil then p.honor.today=today end
 if yesterday~=nil then p.honor.yesterday=yesterday end
 refreshArea(p)
 if K.UI and K.UI.Refresh then K.UI.Refresh() end
 return {world=nativeStatus.world=='available',reason=nativeStatus.world}
end
-- Request current self-reported honor snapshots from online compatible clients.
-- Older clients can ignore this safely; never fabricate missing peer statistics.
function K.PvP.RequestGuildHonor(silent)
 local now=time()
 if now-lastHonorRequest<30 then return false end
 if not IsInGuild() then return false end
 lastHonorRequest=now
 local sent=K.Send and K.Send('HONORREQ','1')
 if sent then requestCache() end
 if not silent and sent then K.Say('Requested honor updates from online guildmates. Older clients may not reply.') end
 return sent
end
local function replyHonor()
 if time()-lastHonorReply<15 then return end
 lastHonorReply=time()
 -- Force a fresh broadcast even if HK count is unchanged.
 local p=entry()
 if not p then return end
 p.honor=p.honor or {}
 p.honor.lastBroadcastAt=nil
 lastAreaBroadcast=nil
 K.PvP.RefreshHonor()
 -- A temporary native API outage does not invalidate our previously observed
 -- snapshot. Re-advertise that original timestamp in response to a request.
 if nativeStatus.world~='available' and nativeStatus.battleground~='available' then
  local payload=areaPayload(p)
  if payload and K.Send then K.Send('HKAREA',payload) end
 end
end
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~='KWC3' or channel~='GUILD' or type(msg)~='string' then return end
 if msg~='2;HONORREQ;1' then return end
 if not K.IsMember(sender) or isSelf(sender) then return end
 replyHonor()
end)
K.On('PLAYER_ENTERING_WORLD',function()
 if C_Timer and C_Timer.After then
  C_Timer.After(18,function()if KWCDB and KWCDB.pvp then K.PvP.RequestGuildHonor(true) end end)
 end
end)
local refreshGeneration=0
local function refreshOnLogin()
 refreshGeneration=refreshGeneration+1
 local generation=refreshGeneration
 K.PvP.RefreshHonor()
 if C_Timer and C_Timer.After then
  for _,delay in ipairs({1,3,10,30,60}) do
   C_Timer.After(delay,function()
    if generation==refreshGeneration then K.PvP.RefreshHonor() end
   end)
  end
 end
end
K.On('PLAYER_LOGIN',refreshOnLogin)
K.On('PLAYER_ENTERING_WORLD',refreshOnLogin)
K.On('PLAYER_PVP_KILLS_CHANGED',function() K.PvP.RefreshHonor() end)
K.On('HONOR_XP_UPDATE',function() K.PvP.RefreshHonor() end)

local areaRefreshPending=false
K.On('CRITERIA_UPDATE',function()
 if areaRefreshPending or not C_Timer or not C_Timer.After then return end
 areaRefreshPending=true
 C_Timer.After(1,function()
  areaRefreshPending=false
  if not KWCDB or not KWCDB.pvp then return end
  K.PvP.RefreshHonor()
 end)
end)

-- Honor messages can arrive before the local roster knows the Forever surname.
-- Hold only bounded, recent packets and resolve them after roster scans. This
-- avoids dropping a valid two-name player just because the roster was late.
local function acceptHonor(sender,msg,fromQueue)
 local value=msg:match('^2;HONOR;(%d+)$')
 local total,wk,wval,dk,dval=msg:match('^2;HONOR2;(%d+);(%d%d%d%d%-W%d%d);(%d+);(%d%d%d%d%-%d%d%-%d%d);(%d+)$')
 if not value and not total then reject('Invalid honor payload',sender);return false end
 local n=tonumber(total or value)
 if not n or n>100000000 then reject('invalid lifetime',sender);return true end
 if total and (tonumber(wval)>n or tonumber(dval)>n) then reject('invalid period totals',sender);return true end
 local id=peerCanonical(sender)
 if not id then
  if not fromQueue then
   pendingHonor[sender]={message=msg,at=time(),guild=guildScope()}
   local count=0
   for _ in pairs(pendingHonor) do count=count+1 end
   if count>30 then
    local oldest,stamp
    for k,v in pairs(pendingHonor) do if not stamp or v.at<stamp then oldest,stamp=k,v.at end end
    if oldest then pendingHonor[oldest]=nil end
   end
  end
  diagnostics.lastPeer=sender;diagnostics.lastReason='waiting for two-part roster name'
  return true
 end
 if isSelf(sender) or isSelf(id) then pendingHonor[sender]=nil;return true end
 local raw=sender:match('^[^-]+') or sender
 if id~=raw and KWCDB.pvp[raw] then
  KWCDB.pvp[id]=merge(KWCDB.pvp[id],KWCDB.pvp[raw]);KWCDB.pvp[raw]=nil
 end
 local p=KWCDB.pvp[id] or {weekly={},honor={}}
 p.honor=p.honor or {};p.weekly=p.weekly or {}
 -- Legacy direct totals carry no observation timestamp. Lifetime counts
 -- are cumulative, so a smaller packet cannot establish newer state.
 if p.honor.available and n<(tonumber(p.honor.lifetime) or 0) then
  pendingHonor[sender]=nil
  outcome('Stale honor total')
  return true
 end
 if p.honor.available and n==p.honor.lifetime and not p.honor.cached
  and (not total or ((p.weekly[wk] or 0)>=tonumber(wval) and ((p.honor.daily or {})[dk] or 0)>=tonumber(dval))) then
  pendingHonor[sender]=nil;outcome('Duplicate honor record');return true
 end
 p.honor.lifetime=n;p.honor.available=true;p.honor.peerReported=true;p.honor.cached=nil;p.honor.lastRead=time();p.honor.originAt=p.honor.lastRead
 if total then
  p.weekly[wk]=math.max(tonumber(p.weekly[wk]) or 0,tonumber(wval));p.honor.daily=p.honor.daily or {};p.honor.daily[dk]=math.max(tonumber(p.honor.daily[dk]) or 0,tonumber(dval))
 end
 KWCDB.pvp[id]=p
 pendingHonor[sender]=nil
 outcome('Honor record applied')
 diagnostics.received=diagnostics.received+1;diagnostics.lastReceivedAt=time()
 diagnostics.lastPeer=sender;diagnostics.lastReason='accepted as '..id
 if K.UI and K.UI.Refresh then K.UI.Refresh() end
 return true
end
function K.PvP.ReconcilePending()
 if not KWCDB or not KWCDB.pvp then return end
 for sender,v in pairs(pendingHonor) do
  if v.guild~=guildScope() or not K.IsMember(sender) or time()-v.at>300 then pendingHonor[sender]=nil;reject('roster name unresolved after 5 min',sender)
  else acceptHonor(sender,v.message,true) end
 end
 local n=0;for _ in pairs(pendingHonor) do n=n+1 end;diagnostics.pending=n
end
local function onGuildReady()
 local guild=guildScope()
 if guild then K.PvP.RefreshHonor() end
 K.PvP.ReconcilePending()
end
K.On('GUILD_ROSTER_UPDATE',onGuildReady)
K.On('INITIAL_CLUBS_LOADED',onGuildReady)
K.On('PLAYER_GUILD_UPDATE',onGuildReady)
K.On('CLUB_UPDATED',onGuildReady)
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~='KWC3' or channel~='GUILD' or type(msg)~='string' or type(sender)~='string' then return end
 local version,kind=msg:match('^(%d+);([A-Z0-9]+);')
 if kind~='HONOR' and kind~='HONOR2' and kind~='HKAREA' then return end
 if not K.IsMember(sender) then reject('Sender not verified',sender);return end
 if version~='2' then reject('Unsupported PvP protocol',sender);return end
 if kind=='HKAREA' then return end
 outcome('Honor packet received')
 acceptHonor(sender,msg,false)
 K.PvP.ReconcilePending()
end)


local function applyArea(sender,payload,subject)
 if not KWCDB or not KWCDB.pvp then return false end
 local current=subject and K.Identity and K.Identity.Current(subject) or subject
 local name=peerCanonical(current or sender)
 if not name then return false end
 if isSelf(name) then return true end
 local world,worldAt,bg,bgAt=payload:match('^(-?%d+);(%d+);(-?%d+);(%d+)$')
 if not world then return true end
 local now=time()
 local function decode(value,at)
  value,at=tonumber(value),tonumber(at)
  if validKills(value) and at>0 and at<=now+300 then return {value=value,at=at} end
 end
 world,bg=decode(world,worldAt),decode(bg,bgAt)
 if not world and not bg then return true end
 local p=KWCDB.pvp[name] or {weekly={}}
 local changed=storeArea(p,'world',world)
 changed=storeArea(p,'battleground',bg) or changed
 KWCDB.pvp[name]=p
 diagnostics.received=diagnostics.received+1
 diagnostics.lastPeer=name;diagnostics.lastReceivedAt=now;diagnostics.lastReason='area snapshot accepted'
 if changed and K.UI and K.UI.Refresh then K.UI.Refresh() end
 return true
end
local function queueArea(sender,payload,subject)
 local key=sender..';'..(subject or '')
 pendingArea[key]={sender=sender,payload=payload,subject=subject,guild=guildScope(),at=time()}
 local count=0;local oldest,stamp
 for k,v in pairs(pendingArea) do
  count=count+1;if not stamp or v.at<stamp then oldest,stamp=k,v.at end
 end
 if count>100 then pendingArea[oldest]=nil end
end
local reconcileHonor=K.PvP.ReconcilePending
function K.PvP.ReconcilePending()
 reconcileHonor()
 for key,item in pairs(pendingArea) do
  if item.guild~=guildScope() or time()-item.at>300 then pendingArea[key]=nil
  elseif item.subject and not K.IsSenderOfficer(item.sender) then pendingArea[key]=nil
  elseif applyArea(item.sender,item.payload,item.subject) then pendingArea[key]=nil end
 end
 local count=0;for _ in pairs(pendingArea) do count=count+1 end
 diagnostics.pending=diagnostics.pending+count
end
-- Preserve the existing direct and token-bound officer recovery packet formats.
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~='KWC3' or type(msg)~='string' or #msg>250 or type(sender)~='string' then return end
 local direct=channel=='GUILD' and msg:match('^2;HKAREA;(.+)$')
 local snapshot=cachePacket(msg,channel,sender)
 local subject,cached
 if snapshot then subject,cached=snapshot:match('^2;HKAREACACHE;([^;]+);(.+)$') end
 local payload=direct or cached
 if not payload or isSelf(sender) then return end
 if not direct and not K.IsMember(sender) then return end
 if not guildScope() then return end
 if not applyArea(sender,payload,subject) then queueArea(sender,payload,subject) end
end)

-- Each online peer can relay its last-known two-name PvP snapshots, including
-- records for offline members. Keep the original observed timestamp; never
-- replace a fresher record or overwrite the local player's own statistics.
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~='KWC3' or type(msg)~='string' or #msg>250
  or (msg~='2;PVPREQ;1' and not msg:match('^2;PVPREQ2;')) then return end
 if not K.IsMember(sender) or isSelf(sender) then return end
 local guild=guildScope()
 local requested,token,page=msg:match('^2;PVPREQ2;(%d+);(%d+%-%d+);(%d%d?)$')
 local targeted=channel=='WHISPER' and guild and requested==guild and token and #token<=24
 if targeted then
  if not K.IsSenderOfficer(K.LocalGuildMember and K.LocalGuildMember() or UnitName('player')) then return end
 else
  if guild or channel~='GUILD' or msg~='2;PVPREQ;1' then return end
 end
 if time()-lastCacheReply<(targeted and 8 or 25) then return end
 lastCacheReply=time()
 local function reply(kind,payload)
  if guild~=guildScope() or not K.IsMember(sender) then return end
  if targeted then
   if K.IsSenderOfficer(K.LocalGuildMember and K.LocalGuildMember() or UnitName('player')) then
    K.Net.Send('KWC3','2;PVPREPLY;'..guild..';'..token..';2;'..kind..';'..payload,'WHISPER',sender,'RECOVERY')
   end
  elseif K.Send then K.Send(kind,payload) end
 end
 if not C_Timer or not C_Timer.After then return end
 local records,areas={},{}
 for name,p in pairs((KWCDB and KWCDB.pvp) or {}) do
  name=K.Identity and K.Identity.Current(name) or name
  local full=K.CurrentGuildMember and peerCanonical(name) or K.PvP.CanonicalDisplayName(name)
  local areaName=type(p)=='table' and p.honorByArea and (K.CurrentGuildMember and peerCanonical(name) or rosterFull(name))
  if areaName then
   local record=areas[areaName] or {}
   for _,area in ipairs(areaKeys) do storeArea(record,area,areaSnapshot(p,area)) end
   areas[areaName]=record
  end
  local h=type(p)=='table' and p.honor
  if full and type(h)=='table' and h.available and
     type(h.lifetime)=='number' and h.lifetime>=0 and h.lifetime<=100000000 then
   local at=tonumber(h.originAt or h.lastRead) or 0
   if at>0 and at<=time()+300 then
    records[#records+1]={name=full,kills=math.floor(h.lifetime),at=math.floor(at)}
   end
  end
 end
 table.sort(records,function(a,b)return a.name:lower()<b.name:lower() end)
 -- Each message stays well below the addon message size limit.
 local limit=targeted and 12 or 100
 local function startOf(rows)
  if not targeted or #rows==0 then return 1 end
  return (tonumber(page)%math.ceil(#rows/limit))*limit+1
 end
 local first=startOf(records)
 for i=first,math.min(#records,first+limit-1) do
  local r=records[i]
  C_Timer.After((i-first)*0.18,function()
   -- Keep the legacy packet shape. The final field denotes unavailable points.
   reply('PVPCACHE',table.concat({r.name,r.kills,r.at,-1},';'))
  end)
 end
 local names={}
 for name in pairs(areas) do names[#names+1]=name end
 table.sort(names,function(a,b) return a:lower()<b:lower() end)
 local offset=math.min(#records,limit)*0.18
 local firstArea=startOf(names)
 for i=firstArea,math.min(#names,firstArea+limit-1) do
  local name=names[i]
  local payload=name..';'..areaPayload(areas[name])
  C_Timer.After(offset+(i-firstArea)*0.18,function()
   reply('HKAREACACHE',payload)
  end)
 end
end)
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~='KWC3' or type(msg)~='string' or #msg>250
  or (not msg:match('^2;PVPCACHE;') and not msg:match('^2;PVPREPLY;')) then return end
 if not K.IsMember(sender) or isSelf(sender) then return end
 msg=cachePacket(msg,channel,sender)
 if not msg or not msg:match('^2;PVPCACHE;') then return end
 local name,kills,stamp,points=msg:match('^2;PVPCACHE;([^;]+);(%d+);(%d+);(-?%d+)$')
 if not name then reject('invalid cache packet',sender);return end
 local full=K.CurrentGuildMember and peerCanonical(name) or K.PvP.CanonicalDisplayName(name)
 local n,at,pts=tonumber(kills),tonumber(stamp),tonumber(points)
 if not full or not n or n>100000000 or not at or
    at<=0 or at>time()+300 or pts<-1 or pts>10000000 then
  reject('invalid cached record',sender);return
 end
 if isSelf(full) then return end
 -- Only accept records for characters known to our guild roster. An online
 -- sender is a transport peer, not proof of the original player's identity.
 if not (K.CurrentGuildMember and K.CurrentGuildMember(full) or (not K.CurrentGuildMember and rosterFull(full))) then return end
 local p=KWCDB.pvp[full] or {weekly={},honor={}}
 p.honor=p.honor or {}
 local oldAt=tonumber(p.honor.originAt or p.honor.lastRead) or 0
 if not p.honor.available or (n>=(tonumber(p.honor.lifetime) or 0) and at>oldAt) then
  p.honor.lifetime=n;p.honor.available=true;p.honor.peerReported=true
  p.honor.cached=true;p.honor.originAt=at;p.honor.lastRead=at
  KWCDB.pvp[full]=p
  diagnostics.received=diagnostics.received+1
  diagnostics.lastPeer=sender;diagnostics.lastReason='cached '..full
  if K.UI and K.UI.Refresh then K.UI.Refresh() end
 end
end)
-- Refresh local stats periodically even if no PvP event fires.
if C_Timer and C_Timer.NewTicker then
 C_Timer.NewTicker(300,function()
  if KWCDB and KWCDB.pvp then K.PvP.RefreshHonor();K.PvP.ReconcilePending();K.PvP.RequestGuildHonor(true) end
 end)
end
