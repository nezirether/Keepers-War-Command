-- Open World Death Ledger (V4.3-TEST): the player's own deaths, counted from the
-- moment tracking starts, saved per character.
--
-- Local persistence lives here. Guild sharing of the count is DeathLedgerSync.lua
-- (its own prefix); this module itself never sends anything.
--
-- Storage (the only SavedVariables key this module reads or writes):
--   KWCDB.deathLedger = { version=1, characters={ [guid]={ since=epoch,
--     openWorld=n, instanced=n, unknown=n, resets=n, lastDeath=epoch|nil } } }
--   * Keyed by validated player GUID, so characters never share a record.
--   * A character's record is created when that character is first confirmed
--     alive, which fixes the tracking start date; later logins never change it.
--   * Loading never writes. A malformed record is left untouched on disk and that
--     character counts for this session only. An unknown version, or a root or
--     characters value that is not a table, makes the whole ledger read-only.
--
-- Counting rules:
--   * A death is classified at PLAYER_DEAD, before spirit release or resurrection.
--   * Open world: the instance classifier (InstanceAlerts.State) reads 'open'. It
--     does not depend on alert preferences. Instanced and unknown/unverifiable
--     locations are tallied separately and never counted as open world.
--   * Every cause counts: enemy players, NPCs, falling, drowning, environment.
--   * Duplicate protection: the ledger arms only when the character is confirmed
--     alive and disarms on each counted death, so duplicate PLAYER_DEAD events,
--     spirit release and reloading or logging in while dead never count twice.
--     The saved lastDeath also rejects a second death within 2 seconds.
--   * No historical seeding: lifetime statistics are never used.
local K=KWC
local L={};K.DeathLedger=L
local VERSION=1
local MAX_COUNT=1000000
local DUPLICATE_WINDOW=2
local FIELDS={'openWorld','instanced','unknown'}
L.PERSISTENT=false
-- 'pending' until ADDON_LOADED; then 'ready' (writable) or 'readonly'.
local storeState,storeReason='pending','saved data not loaded yet'
local invalid={}   -- [guid]=reason: malformed saved record, never overwritten
local session={}   -- [guid]=record kept in memory when saving is impossible
local armed=false
local lastDecision='No death observed this session'
local function secret(value)
 if not issecretvalue then return false end
 local ok,result=pcall(issecretvalue,value)
 return not ok or result==true
end
-- true = dead or ghost, false = confirmed alive, nil = unknown.
local function deadOrGhost()
 if type(UnitIsDeadOrGhost)~='function' then return nil end
 local ok,value=pcall(UnitIsDeadOrGhost,'player')
 if not ok or secret(value) then return nil end
 if value==true then return true end
 if value==false then return false end
 return nil
end
local function validGUID(guid)
 return type(guid)=='string' and not secret(guid) and guid:match('^Player%-%w+%-%w+$')~=nil
end
local function playerGUID()
 if type(UnitGUID)~='function' then return nil end
 local ok,guid=pcall(UnitGUID,'player')
 if not ok or not validGUID(guid) then return nil end
 return guid
end
-- 'openWorld', 'instanced' or 'unknown'.
local function classify()
 local P=K.InstanceAlerts
 if type(P)~='table' or type(P.State)~='function' then return 'unknown' end
 local ok,state=pcall(P.State)
 if not ok then return 'unknown' end
 if state=='open' then return 'openWorld' end
 if state=='instance' then return 'instanced' end
 return 'unknown'
end
local function count(value)
 return type(value)=='number' and value>=0 and value<=MAX_COUNT and value%1==0
end
local function stamp(value)
 return type(value)=='number' and value>0 and value<1e11 and value%1==0
end
-- Why a saved record is unusable, or nil when it is valid.
local function problem(r)
 if type(r)~='table' then return 'record is not a table' end
 if not stamp(r.since) then return 'invalid tracking start date' end
 for _,field in ipairs(FIELDS) do
  if not count(r[field]) then return 'invalid '..field..' count' end
 end
 if r.resets~=nil and not count(r.resets) then return 'invalid reset count' end
 if r.lastDeath~=nil and not (stamp(r.lastDeath) and r.lastDeath>=r.since) then return 'invalid last death time' end
end
-- Runs once, after SavedVariables exist. Reads only; never writes.
local function load()
 local db=type(KWCDB)=='table' and KWCDB or nil
 invalid={}
 if not db then storeState,storeReason='readonly','saved data unavailable';return end
 local root=db.deathLedger
 if root==nil then storeState,storeReason='ready',nil;return end
 if type(root)~='table' then storeState,storeReason='readonly','saved ledger is not a table';return end
 if root.version~=VERSION then
  storeState,storeReason='readonly','saved ledger version '..tostring(root.version)..' is not supported by this build'
  return
 end
 if type(root.characters)~='table' then storeState,storeReason='readonly','saved character list is not a table';return end
 for guid,r in pairs(root.characters) do
  if not validGUID(guid) then
   -- Not ours to interpret; it is never read or replaced.
  else
   local why=problem(r)
   if why then invalid[guid]=why end
  end
 end
 storeState,storeReason='ready',nil
end
K.On('ADDON_LOADED',function(addon) if addon=='KeepersWarCommand' then load() end end)
-- The record to use for this character, and whether it is saved. Creates the
-- saved record only when create is true and writing is safe.
local function record(guid,create)
 if storeState=='ready' and not invalid[guid] and type(KWCDB)=='table' then
  local root=KWCDB.deathLedger
  local r=type(root)=='table' and type(root.characters)=='table' and root.characters[guid] or nil
  if r then return r,true end
  if not create then return nil,true end
  if root==nil then root={version=VERSION,characters={}};KWCDB.deathLedger=root end
  if type(root)~='table' or root.version~=VERSION or type(root.characters)~='table' then return nil,false end
  r={since=time(),openWorld=0,instanced=0,unknown=0,resets=0}
  root.characters[guid]=r
  return r,true
 end
 local r=session[guid]
 if not r and create then
  r={since=time(),openWorld=0,instanced=0,unknown=0,resets=0}
  session[guid]=r
 end
 return r,false
end
local function tryArm()
 if deadOrGhost()~=false then return end
 armed=true
 local guid=playerGUID()
 if guid then record(guid,true) end
end
K.On('PLAYER_ENTERING_WORLD',tryArm)
K.On('PLAYER_ALIVE',tryArm)
K.On('PLAYER_UNGHOST',tryArm)
K.On('PLAYER_DEAD',function()
 if not armed then lastDecision='Not counted: not armed (duplicate event, reload while dead, or alive state unconfirmed)';return end
 armed=false
 local guid=playerGUID()
 if not guid then lastDecision='Not counted: character identity unavailable';return end
 local r,saved=record(guid,true)
 if not r then lastDecision='Not counted: saved ledger could not be written';return end
 local now=time()
 if r.lastDeath and math.abs(now-r.lastDeath)<DUPLICATE_WINDOW then
  lastDecision='Not counted: duplicate of the death recorded '..math.abs(now-r.lastDeath)..'s earlier'
  return
 end
 local class=classify()
 r[class]=r[class]+1
 r.lastDeath=now
 lastDecision='Counted as '..class..(saved and '' or ' (this session only)')
 if saved and class=='openWorld' and type(L.OnCounted)=='function' then pcall(L.OnCounted) end
end)
-- Snapshot for the current character (nil when the identity is unavailable).
-- V4.9: the saved Open World Death Ledger is the default board again (V4.5
-- behaviour). The V4.6 lifetime figure (WoW Statistics total minus the four
-- battleground maps) is kept beside it as its own field and board; the two are
-- never added together, which would double count.
function L.Get()
 local guid=playerGUID()
 if not guid then return nil end
 local r,saved=record(guid,false)
 local reason
 if not saved then reason=invalid[guid] and ('saved record unreadable: '..invalid[guid]) or storeReason end
 local lifetime=K.GuildRecords and K.GuildRecords.LifetimeDeathsExcludingBG and K.GuildRecords.LifetimeDeathsExcludingBG()
 return {openWorld=r and r.openWorld or 0,instanced=r and r.instanced or 0,unknown=r and r.unknown or 0,
  since=r and r.since,armed=armed,persistent=saved,reason=reason,lifetime=lifetime}
end
local function day(epoch)
 if type(date)=='function' then return date('%Y-%m-%d',epoch) end
 return tostring(epoch)
end
-- Two lines for the Death Leaderboard: the count and an honest scope note.
-- view 'lifetime' describes the V4.6 lifetime-excluding-battlegrounds figure;
-- anything else describes the Open World Death Ledger.
function L.Display(view)
 local s=L.Get()
 if view=='lifetime' then
  if not s or s.lifetime==nil then
   return 'Your lifetime deaths (excluding BGs): unavailable','Waiting for complete WoW Statistics; no installation-date reset.'
  end
  local shared=K.DeathLedgerSync and K.DeathLedgerSync.Sharing and K.DeathLedgerSync.Sharing()
  return ('Your lifetime deaths (excluding BGs): %d'):format(s.lifetime),
   shared and 'All-time WoW Statistics, including dungeons and raids. Guild sharing on.' or
   'All-time WoW Statistics, including dungeons and raids. Guild sharing off.'
 end
 if not s or not s.since then
  return 'Your open-world deaths: not tracked yet','Tracking starts once this character is confirmed alive. Not shared.'
 end
 if s.persistent then
  local sync=K.OpenWorldDeathSync
  local shared=sync and sync.Sharing and sync.Sharing()
  return ('Your open-world deaths since %s: %d'):format(day(s.since),s.openWorld),
   shared and 'Saved for this character. Shared with your guild.' or 'Saved for this character. Not shared: Share My Records is off.'
 end
 return ('Your open-world deaths this session: %d'):format(s.openWorld),
  'This session only, not saved ('..tostring(s.reason)..'). Not shared.'
end
function L.Summary()
 local s=L.Get()
 if not s then return 'Death Ledger: character identity unavailable; nothing counted.' end
 return ('Death Ledger (%s): open-world deaths %d | instanced %d | unknown location %d | tracking %s | armed=%s | lifetime excluding BGs %s')
  :format(s.persistent and 'saved per character, not shared' or ('this session only, not saved: '..tostring(s.reason)),
   s.openWorld,s.instanced,s.unknown,s.since and ('since '..day(s.since)) or 'not started (alive state unconfirmed)',
   s.armed and 'yes' or 'no',s.lifetime~=nil and tostring(s.lifetime) or 'unavailable')
end
function L.LastDecision() return lastDecision end
local function readable(value)
 if secret(value) or type(value)~='string' or value=='' then return nil end
 return value
end
-- Open World Deaths guild board. Only verified counts are numbers: this
-- character's saved ledger count, and counts guildmates' own clients shared
-- (DeathLedgerSync). Anyone else is untracked (value=nil), never zero and never
-- from lifetime statistics.
-- Rows: {name, display, value=number|nil, tracked=bool, self=bool}; tracked rows
-- first by count (highest first), then untracked rows by name.
function L.GuildRankings(view)
 local rows={}
 local mine=L.Get()
 -- Open world (default): this character's saved ledger count, guildmates' KWCOW1
 -- reports. 'lifetime': the WoW Statistics figure, guildmates' KWCOW2 reports.
 local lifetime=view=='lifetime'
 local myCount=mine and (lifetime and mine.lifetime or (not lifetime and mine.since and mine.openWorld)) or nil
 local sync=lifetime and K.DeathLedgerSync or K.OpenWorldDeathSync
 local myGUID=playerGUID()
 local me
 if K.LocalGuildMember then
  local ok,name=pcall(K.LocalGuildMember)
  if ok then me=readable(name) end
 end
 me=me and me:lower()
 local selfListed=false
 local total=0
 if IsInGuild and IsInGuild() and type(GetNumGuildMembers)=='function' and type(GetGuildRosterInfo)=='function' then
  local ok,n=pcall(GetNumGuildMembers)
  total=ok and type(n)=='number' and not secret(n) and n or 0
 end
 for i=1,math.min(total,2000) do
  -- GetGuildRosterInfo: name is the 1st return, the member GUID the 17th.
  local info={pcall(GetGuildRosterInfo,i)}
  local ok=info[1]
  local name=ok and readable(info[2]) or nil
  local guid=ok and info[18] or nil
  if name then
   local isSelf=not selfListed and ((myGUID and readable(guid)==myGUID) or (me~=nil and name:lower()==me))
   if isSelf then selfListed=true end
   local value
   if isSelf then value=myCount
   elseif sync and sync.CountFor then value=sync.CountFor(name) end
   rows[#rows+1]={name=name,display=name:match('^[^-]+') or name,value=value,tracked=value~=nil,self=isSelf}
  end
 end
 if not selfListed and myCount and type(UnitName)=='function' then
  local ok,name=pcall(UnitName,'player')
  name=ok and readable(name) or nil
  if name then rows[#rows+1]={name=name,display=name,value=myCount,tracked=true,self=true} end
 end
 table.sort(rows,function(a,b)
  if a.tracked~=b.tracked then return a.tracked end
  if a.tracked and a.value~=b.value then return a.value>b.value end
  return a.name:lower()<b.name:lower()
 end)
 return rows
end
