local K=KWC;K.PvP={}
local lastHonorRequest=0
local lastHonorReply=0
local diagnostics={sent=0,received=0,rejected=0,pending=0,lastPeer=nil,lastReason='none',lastSentAt=nil,lastReceivedAt=nil}
local pendingHonor={}
function K.PvP.Diagnostics() return diagnostics end
local function reject(reason,sender)
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
local function key()
 if type(UnitFullName)=='function' then
  local ok,n=pcall(UnitFullName,'player');if ok and two(plain(n)) then return plain(n) end
 end
 local n=UnitName and UnitName('player')
 if two(plain(n)) then return plain(n) end
 return rosterFull(n)
end
local function isSelf(n)
 local full=key();n=plain(n)
 if not full or not n then return false end
 return full:lower()==n:lower() or (not n:find('%s') and full:lower():sub(1,#n+1)==n:lower()..' ')
end
local function merge(dst,src)
 if type(src)~='table' then return dst end
 dst=dst or {};dst.weekly=dst.weekly or {}
 for w,n in pairs(src.weekly or {}) do if type(n)=='number' then dst.weekly[w]=math.max(dst.weekly[w] or 0,n) end end
 local a,b=dst.honor,src.honor
 if type(b)=='table' and (type(a)~='table' or not a.available or (a.peerReported and not b.peerReported) or (a.peerReported==b.peerReported and (b.lastRead or 0)>(a.lastRead or 0))) then dst.honor=b end
 if not dst.achievementPoints then dst.achievementPoints=src.achievementPoints end
 return dst
end
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
local function peerCanonical(sender) return K.PvP.CanonicalDisplayName(sender) end
function K.PvP.PeerCanonical(sender) return peerCanonical(sender) end
local function week() return date('%Y-W%W') end
local function day() return date('%Y-%m-%d') end
local function entry()
 local id=key();if not id then return nil end;local p=KWCDB.pvp[id] or {kills=0,deaths=0,weekly={},targets={},seen={}}
 p.weekly=p.weekly or {};p.targets=p.targets or {};p.seen=p.seen or {};KWCDB.pvp[id]=p;return p
end
-- ForeverAPI (1.60.1): COMBAT_LOG_EVENT_UNFILTERED registration is forbidden.
-- Do not register it or infer killing blows/deaths from inaccessible combat logs.
-- Official lifetime HK snapshots below are the supported baseline.

-- Blizzard's authoritative character honor totals. These are not combat-log estimates.
-- Snapshotting preserves pre-install lifetime HKs without inventing past kill details.
function K.PvP.RefreshHonor()
 if not KWCDB or not KWCDB.pvp then return end
 K.PvP.CleanupSelfEchoes()
 local p=entry()
 if not p then return end
 local function read(fn)
  if type(fn)~='function' then return nil end
  local ok,n=pcall(fn)
  if ok and type(n)=='number' and n>=0 then return math.floor(n) end
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
  p.honor.lastRead=time()
  p.honor.firstObserved=p.honor.firstObserved or lifetime
  if K.Send and (p.honor.lastBroadcast~=lifetime or not p.honor.lastBroadcastAt or time()-p.honor.lastBroadcastAt>600) then
   if K.Send('HONOR2',table.concat({lifetime,weekKey,p.weekly[weekKey] or 0,todayKey,p.honor.daily[todayKey] or 0},';')) then p.honor.lastBroadcast=lifetime;p.honor.lastBroadcastAt=time();diagnostics.sent=diagnostics.sent+1;diagnostics.lastSentAt=time() end
  end
 end
 if today~=nil then p.honor.today=today end
 if yesterday~=nil then p.honor.yesterday=yesterday end
 if K.UI and K.UI.Refresh then K.UI.Refresh() end
end
-- Request current self-reported honor snapshots from online compatible clients.
-- Older clients can ignore this safely; never fabricate missing peer statistics.
function K.PvP.RequestGuildHonor(silent)
 local now=time()
 if now-lastHonorRequest<30 then return false end
 if not IsInGuild() then return false end
 lastHonorRequest=now
 local sent=K.Send and K.Send('HONORREQ','1')
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
 K.PvP.RefreshHonor()
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
K.On('PLAYER_ENTERING_WORLD',function() K.PvP.RefreshHonor() end)
K.On('PLAYER_PVP_KILLS_CHANGED',function() K.PvP.RefreshHonor() end)
K.On('HONOR_XP_UPDATE',function() K.PvP.RefreshHonor() end)

-- Honor messages can arrive before the local roster knows the Forever surname.
-- Hold only bounded, recent packets and resolve them after roster scans. This
-- avoids dropping a valid two-name player just because the roster was late.
local function acceptHonor(sender,msg,fromQueue)
 local value=msg:match('^2;HONOR;(%d+)$')
 local total,wk,wval,dk,dval=msg:match('^2;HONOR2;(%d+);(%d%d%d%d%-W%d%d);(%d+);(%d%d%d%d%-%d%d%-%d%d);(%d+)$')
 if not value and not total then return false end
 local n=tonumber(total or value)
 if not n or n>100000000 then reject('invalid lifetime',sender);return true end
 if total and (tonumber(wval)>n or tonumber(dval)>n) then reject('invalid period totals',sender);return true end
 local id=peerCanonical(sender)
 if not id then
  if not fromQueue then
   pendingHonor[sender]={message=msg,at=time()}
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
 p.honor.lifetime=n;p.honor.available=true;p.honor.peerReported=true;p.honor.lastRead=time()
 if total then
  p.weekly[wk]=tonumber(wval);p.honor.daily=p.honor.daily or {};p.honor.daily[dk]=tonumber(dval)
 end
 KWCDB.pvp[id]=p
 pendingHonor[sender]=nil
 diagnostics.received=diagnostics.received+1;diagnostics.lastReceivedAt=time()
 diagnostics.lastPeer=sender;diagnostics.lastReason='accepted as '..id
 if K.UI and K.UI.Refresh then K.UI.Refresh() end
 return true
end
function K.PvP.ReconcilePending()
 if not KWCDB or not KWCDB.pvp then return end
 for sender,v in pairs(pendingHonor) do
  if time()-v.at>300 then pendingHonor[sender]=nil;reject('roster name unresolved after 5 min',sender)
  else acceptHonor(sender,v.message,true) end
 end
 local n=0;for _ in pairs(pendingHonor) do n=n+1 end;diagnostics.pending=n
end
K.On('GUILD_ROSTER_UPDATE',function() K.PvP.ReconcilePending() end)
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~='KWC3' or channel~='GUILD' or type(msg)~='string' or type(sender)~='string' then return end
 if not msg:match('^2;HONOR2?;') then return end
 if not K.IsMember(sender) then
  -- A roster scan may still be in progress. Never accept an unverified sender.
  reject('sender not in guild roster',sender);return
 end
 acceptHonor(sender,msg,false)
 K.PvP.ReconcilePending()
end)

-- Refresh local stats periodically even if no PvP event fires.
if C_Timer and C_Timer.NewTicker then
 C_Timer.NewTicker(300,function()
  if KWCDB and KWCDB.pvp then K.PvP.RefreshHonor();K.PvP.ReconcilePending() end
 end)
end
