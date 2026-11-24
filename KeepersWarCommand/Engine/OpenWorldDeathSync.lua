-- Open World Deaths guild sharing (restored in V4.9 from V4.5; module K.OpenWorldDeathSync).
--
-- V4.6 reused DeathLedgerSync.lua for lifetime totals on KWCOW2. This file brings
-- back the V4.5 Open World Deaths sync unchanged on its own prefix, KWCOW1, so
-- both boards share independently. Sharing follows Share My Records.
--
-- Each KWC client broadcasts its own character's saved Death Ledger count to the
-- guild on a dedicated prefix. Older KWC builds never register the prefix, so they
-- never see these messages. No officer relay, no record groups, no global revisions.
--
-- Wire (GUILD channel, prefix KWCOW1, about 40 bytes):
--   <guildId>|1|C|<openWorldCount>|<sinceDay>|<rev>   count report
--   <guildId>|1|W|<rev>                               withdrawal (sharing turned off)
--   either may end in |H ("hello"): sent on login, it asks online guildmates to
--   answer with their own report (rate-limited). Answers never carry |H.
--   sinceDay = floor(trackingStart/86400); rev = sender clock in seconds, rising.
-- The message never names a character: the owner is the verified sender, so a
-- client can only ever report its own count.
--
-- Storage (additive key, per guild):
--   KWCDB.openWorldDeaths = { version=1, guilds={ [guildId]={ members={
--     [rosterName lowercased]={count=n, sinceDay=d, rev=r} | {withdrawn=true, rev=r} } } } }
-- An unknown version or malformed root is never overwritten; received counts are
-- then simply not kept.
local K=KWC
local S={};K.OpenWorldDeathSync=S
local PREFIX='KWCOW1'
local VERSION=1
local MAX_COUNT=1000000
local FUTURE=300                -- reject reports from more than 5 minutes ahead
local STALE=7*86400             -- reject reports sent more than 7 days ago (replays)
local HIDE_AFTER=60*86400       -- a count not refreshed for 60 days shows as Untracked
local RESEND=900                -- an unchanged report is re-sent at most every 15 minutes
local SEND_DELAY=10             -- sends are coalesced, at most one per 10 seconds
local REPLY_GAP=120             -- replies to newly seen guildmates at most every 2 minutes
S.PREFIX=PREFIX
local lastRev=0
local lastSent={}
local pending=false
local pendingHello=false
local lastReply=-REPLY_GAP
local replyPending=false
local announced=false
local heard={}
local publishedGuild
local stats={sent=0,accepted=0,rejected=0,withdrawals=0}
local lastReject='none'
local function secret(value)
 if not issecretvalue then return false end
 local ok,result=pcall(issecretvalue,value)
 return not ok or result==true
end
local function readable(value)
 if secret(value) or type(value)~='string' or value=='' then return nil end
 return value
end
local function int(value,min,max)
 return type(value)=='number' and value%1==0 and value>=min and value<=max
end
local function scope()
 if not K.GuildScope then return nil end
 local ok,guild=pcall(K.GuildScope)
 return ok and readable(guild) or nil
end
local function ready()
 if not K.GuildReadiness then return false end
 local ok,state=pcall(K.GuildReadiness)
 return ok and state=='Ready'
end
local function me()
 if not K.LocalGuildMember then return nil end
 local ok,name=pcall(K.LocalGuildMember)
 name=ok and readable(name) or nil
 return name and name:lower()
end
function S.Sharing()
 local R=K.GuildRecords
 if type(R)~='table' or type(R.Sharing)~='function' then return false end
 local ok,value=pcall(R.Sharing)
 return ok and value==true
end
-- Guild table for reading (create=false) or writing (create=true); nil when unusable.
local function store(guild,create)
 local db=type(KWCDB)=='table' and KWCDB or nil
 if not db or not guild then return nil end
 local root=db.openWorldDeaths
 if root==nil then
  if not create then return nil end
  root={version=VERSION,guilds={}}
  db.openWorldDeaths=root
 end
 if type(root)~='table' or root.version~=VERSION or type(root.guilds)~='table' then return nil end
 local g=root.guilds[guild]
 if g==nil then
  if not create then return nil end
  g={members={}}
  root.guilds[guild]=g
 end
 if type(g)~='table' or type(g.members)~='table' then return nil end
 return g
end
local function validEntry(e)
 if type(e)~='table' or not int(e.rev,1,1e11) then return false end
 if e.withdrawn==true then return true end
 return int(e.count,0,MAX_COUNT) and int(e.sinceDay,1,1e7)
end
-- Verified shared count for a guild member in the current guild, or nil (untracked).
function S.CountFor(name)
 name=readable(name)
 local g=name and store(scope(),false)
 local e=g and g.members[name:lower()]
 if not validEntry(e) or e.withdrawn or time()-e.rev>HIDE_AFTER then return nil end
 return e.count,e.sinceDay
end
local function refresh()
 if K.UI and K.UI.GuildRecordsRefresh then pcall(K.UI.GuildRecordsRefresh) end
end
-- Own report body, or nil when there is nothing verified to share.
local function report()
 local L=K.DeathLedger
 if type(L)~='table' or type(L.Get)~='function' then return nil end
 local ok,s=pcall(L.Get)
 if not ok or type(s)~='table' or not s.since or s.persistent~=true then return nil end
 return 'C|'..s.openWorld..'|'..math.floor(s.since/86400)
end
local function send(body,force,hello)
 local guild=scope()
 if not guild or not K.Net or type(K.Net.Send)~='function' then return false end
 local now=time()
 local key=guild..'|'..body
 if not force and lastSent.key==key and now-lastSent.at<RESEND then return false end
 lastRev=math.max(now,lastRev+1)
 local ok,queued=pcall(K.Net.Send,PREFIX,guild..'|'..VERSION..'|'..body..'|'..lastRev..(hello and '|H' or ''),'GUILD')
 if ok and queued then
  lastSent={key=key,at=now}
  stats.sent=stats.sent+1
  publishedGuild=guild
  return true
 end
 return false
end
-- Send this character's count, or a withdrawal when Share My Records is off.
-- hello=true marks a login announcement (always sent, asks guildmates to answer).
function S.Publish(force,hello)
 if not ready() then return false end
 if hello then force=true end
 if S.Sharing() then
  local body=report()
  if not body then return false end
  return send(body,force,hello)
 end
 return send('W',force,hello)
end
local function schedule(delay,hello)
 if hello then pendingHello=true end
 if pending then return end
 local function run() pending=false;local h=pendingHello;pendingHello=false;S.Publish(h,h) end
 if not C_Timer or type(C_Timer.After)~='function' then run();return end
 pending=true
 C_Timer.After(delay,run)
end
S.Schedule=schedule
local function reject(reason) stats.rejected=stats.rejected+1;lastReject=reason end
local function receive(prefix,message,channel,sender)
 if prefix~=PREFIX then return end
 if channel~='GUILD' then return reject('not the guild channel') end
 message,sender=readable(message),readable(sender)
 if not message or not sender or #message>120 then return reject('unreadable or oversized') end
 local guild,version,body=message:match('^(%d+)|(%d+)|(.+)$')
 if not guild then return reject('malformed') end
 local current=scope()
 if not current or guild~=current then return reject('another guild') end
 if version~='1' then return reject('unsupported version') end
 local member=K.CurrentGuildMember and K.CurrentGuildMember(sender)
 member=readable(member)
 if not member then return reject('sender is not a current guild member') end
 member=member:lower()
 if member==me() then return end
 local hello=false
 if body:sub(-2)=='|H' then hello=true;body=body:sub(1,-3) end
 local count,day,rev=body:match('^C|(%d%d?%d?%d?%d?%d?%d?)|(%d%d?%d?%d?%d?%d?%d?)|(%d%d?%d?%d?%d?%d?%d?%d?%d?%d?%d?)$')
 local withdraw
 if not count then
  rev=body:match('^W|(%d%d?%d?%d?%d?%d?%d?%d?%d?%d?%d?)$')
  if not rev then return reject('malformed') end
  withdraw=true
 end
 local now=time()
 rev=tonumber(rev)
 if rev>now+FUTURE then return reject('from the future') end
 if rev<now-STALE then return reject('stale') end
 if not withdraw then
  count,day=tonumber(count),tonumber(day)
  if not int(count,0,MAX_COUNT) then return reject('invalid count') end
  if day<1 or day>math.floor((now+FUTURE)/86400) or day*86400>rev+FUTURE then return reject('invalid tracking start') end
 end
 local g=store(guild,true)
 if not g then return reject('saved table unusable') end
 local old=g.members[member]
 if validEntry(old) and rev<=old.rev then return reject('duplicate or older') end
 if withdraw then
  g.members[member]={withdrawn=true,rev=rev}
  stats.withdrawals=stats.withdrawals+1
 else
  g.members[member]={count=count,sinceDay=day,rev=rev}
 end
 stats.accepted=stats.accepted+1
 refresh()
 -- Answer a login announcement, or a guildmate seen for the first time this
 -- session, so they receive this character's report too (rate-limited).
 local seen=guild..'|'..member
 if hello or not heard[seen] then
  heard[seen]=true
  -- One answer per REPLY_GAP: a request inside the gap is answered when it ends,
  -- never dropped. The answer is a guild broadcast, so it serves every newcomer.
  if not replyPending then
   local function answer() replyPending=false;lastReply=time();S.Publish(true) end
   if C_Timer and type(C_Timer.After)=='function' then
    replyPending=true
    C_Timer.After(math.max(SEND_DELAY,lastReply+REPLY_GAP-now),answer)
   elseif now-lastReply>=REPLY_GAP then
    answer()
   end
  end
 end
end
K.On('CHAT_MSG_ADDON',receive)
K.On('ADDON_LOADED',function(addon)
 if addon=='KeepersWarCommand' and C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  pcall(C_ChatInfo.RegisterAddonMessagePrefix,PREFIX)
 end
end)
-- Announce once per session (login or /reload). Later loading screens fire the same
-- event but only refresh the report, so zoning never makes the guild answer.
K.On('PLAYER_ENTERING_WORLD',function() schedule(15,not announced);announced=true end)
K.On('GUILD_ROSTER_UPDATE',function()
 local guild=scope()
 if guild and guild~=publishedGuild and ready() then schedule(SEND_DELAY) end
end)
K.On('PLAYER_GUILD_UPDATE',function() lastSent={};heard={};schedule(SEND_DELAY) end)
-- A counted death is shared after a short delay (coalesced with other changes).
-- Chain onto any existing hook (DeathLedgerSync.lua sets one) rather than replace it.
if K.DeathLedger then
 local previous=K.DeathLedger.OnCounted
 K.DeathLedger.OnCounted=function()
  if type(previous)=='function' then pcall(previous) end
  schedule(SEND_DELAY)
 end
end
-- Share My Records toggles publish at once: the count when turned on, a withdrawal
-- when turned off, so guildmates stop showing a count that is no longer shared.
if type(K.GuildRecords)=='table' and type(K.GuildRecords.SetSharing)=='function' then
 local setSharing=K.GuildRecords.SetSharing
 K.GuildRecords.SetSharing=function(...)
  local result=setSharing(...)
  S.Publish(true)
  return result
 end
end
function S.Diagnostics()
 return ('Open World Deaths sharing: %s | sent %d | accepted %d | rejected %d (last: %s) | withdrawals received %d')
  :format(S.Sharing() and 'on' or 'off',stats.sent,stats.accepted,stats.rejected,lastReject,stats.withdrawals)
end
