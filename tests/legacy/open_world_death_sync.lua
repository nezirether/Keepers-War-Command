-- V4.9: Open World Deaths guild sharing (OpenWorldDeathSync.lua, KWCOW1) restored
-- beside the V4.6 lifetime-excluding-battlegrounds sharing (DeathLedgerSync.lua,
-- KWCOW2). Two simulated guild clients exchange real messages through both modules.
-- Run from the repository root with Lua 5.1 or LuaJIT.
local GUILD='4242'
local function client(name,guid)
 local env=setmetatable({},{__index=_G})
 local events,timers={},{}
 local c={env=env,name=name,guid=guid,now=100000,inside=false,kind='none',dead=false,sharing=true,sent={},lifetime=40}
 env.KWCDB={settings={}}
 env.KWC={
  On=function(e,fn) events[e]=events[e] or {};table.insert(events[e],fn);return true end,
  GuildScope=function() return GUILD end,
  GuildReadiness=function() return 'Ready' end,
  LocalGuildMember=function() return name..'-Realm' end,
  CurrentGuildMember=function(sender) if type(sender)=='string' and not sender:find('^Stranger') then return sender end end,
  Net={Send=function(prefix,msg,channel) c.sent[#c.sent+1]={prefix,msg,channel};if c.route then c.route(prefix,msg,channel) end;return true end},
 }
 env.KWC.GuildRecords={
  Sharing=function() return c.sharing end,
  SetSharing=function(v) c.sharing=v end,
  LifetimeDeathsExcludingBG=function() return c.lifetime end,
 }
 env.time=function() return c.now end
 env.date=function(_,t) return 'day'..tostring(math.floor((t or 0)/86400)) end
 env.IsInInstance=function() return c.inside,c.kind end
 env.GetInstanceInfo=function() return 'Zone',c.kind end
 env.UnitIsDeadOrGhost=function() return c.dead end
 env.UnitGUID=function() return c.guid end
 env.UnitName=function() return name end
 env.IsInGuild=function() return true end
 c.roster={{'Ann-Realm','Player-1-000000A1'},{'Bea-Realm','Player-1-000000B2'},{'Cal-Realm','Player-1-000000C3'}}
 env.GetNumGuildMembers=function() return #c.roster end
 env.GetGuildRosterInfo=function(i) local m=c.roster[i];return m[1],'Rank',1,80,'Warrior','Zone','','',true,0,'WARRIOR',0,0,false,false,0,m[2] end
 env.C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
 env.C_ChatInfo={RegisterAddonMessagePrefix=function() return true end}
 for _,file in ipairs({'InstanceAlerts','DeathLedger','DeathLedgerSync','OpenWorldDeathSync'}) do
  setfenv(assert(loadfile('KeepersWarCommand/'..file..'.lua')),env)()
 end
 c.L=env.KWC.DeathLedger;c.OW=env.KWC.OpenWorldDeathSync;c.LT=env.KWC.DeathLedgerSync
 function c.fire(e,...) for _,fn in ipairs(events[e] or {}) do fn(...) end end
 function c.flush() local n=0;while #timers>0 and n<50 do n=n+1;table.remove(timers,1)() end end
 function c.die(kind) c.inside=kind~=nil;c.kind=kind or 'none';c.dead=true;c.fire('PLAYER_DEAD');c.now=c.now+30;c.dead=false;c.inside=false;c.kind='none';c.fire('PLAYER_ALIVE') end
 c.fire('ADDON_LOADED','KeepersWarCommand')
 c.fire('PLAYER_ENTERING_WORLD')
 return c
end
local function link(a,b)
 a.route=function(prefix,msg,channel) b.fire('CHAT_MSG_ADDON',prefix,msg,channel,a.name..'-Realm') end
 b.route=function(prefix,msg,channel) a.fire('CHAT_MSG_ADDON',prefix,msg,channel,b.name..'-Realm') end
end
local function prefixes(c) local p={};for _,m in ipairs(c.sent) do p[m[1]]=(p[m[1]] or 0)+1 end;return p end

local ann=client('Ann','Player-1-000000A1')
local bea=client('Bea','Player-1-000000B2')
link(ann,bea)

-- 1. Ann dies twice in the open world and once in each kind of instance.
ann.die();ann.now=ann.now+20;ann.die()
for _,kind in ipairs({'pvp','party','raid','arena'}) do ann.now=ann.now+20;ann.die(kind) end
local snap=ann.L.Get()
assert(snap.openWorld==2 and snap.instanced==4,'ledger: 2 open-world, 4 instanced')
ann.flush();bea.flush()
local p=prefixes(ann)
assert(p.KWCOW1 and p.KWCOW1>=1 and p.KWCOW2 and p.KWCOW2>=1,'both channels publish')
assert(bea.OW.CountFor('Ann-Realm')==2,'guildmate receives the open-world count over KWCOW1')
assert(bea.LT.CountFor('Ann-Realm')==40,'lifetime-excluding-BG count still shared over KWCOW2')
print('PASS: open-world deaths (instances excluded) and lifetime totals both reach guildmates on separate channels')

-- 2. The default board is Open World Deaths; the lifetime board stays separate.
local rows=bea.L.GuildRankings()
local byName={};for _,r in ipairs(rows) do byName[r.name]=r end
assert(byName['Ann-Realm'].tracked and byName['Ann-Realm'].value==2,'Ann ranks with her open-world count')
assert(byName['Bea-Realm'].self and byName['Bea-Realm'].value==0,'own tracked zero')
assert(not byName['Cal-Realm'].tracked,'guildmate without KWC data stays Untracked')
local life={};for _,r in ipairs(bea.L.GuildRankings('lifetime')) do life[r.name]=r end
assert(life['Ann-Realm'].value==40 and life['Bea-Realm'].value==40,'lifetime board uses lifetime values')
assert(bea.L.Display():find('open-world deaths since',1,true),'default personal line is the open-world ledger')
assert(bea.L.Display('lifetime'):find('lifetime deaths (excluding BGs)',1,true),'lifetime personal line kept')
print('PASS: Open World Deaths is the default ranking; lifetime ranking preserved; untracked stays untracked')

-- 3. Privacy: Share My Records off sends a withdrawal; guildmates stop showing the count.
ann.sharing=false;ann.sent={}
ann.OW.Publish(true);ann.LT.Publish(true)
for _,m in ipairs(ann.sent) do assert(m[2]:find('|W|',1,true),'sharing off sends only withdrawals: '..m[2]) end
assert(bea.OW.CountFor('Ann-Realm')==nil and bea.LT.CountFor('Ann-Realm')==nil,'withdrawn counts are hidden')
assert(bea.L.Display()~=nil)
ann.sharing=true
print('PASS: Share My Records off withdraws both shared counts')

-- 4. Safety: wrong channel, other guild, non-member, malformed, stale, own echo and older revisions are rejected.
local before=bea.OW.CountFor('Ann-Realm')
local now=bea.now
bea.fire('CHAT_MSG_ADDON','KWCOW1',GUILD..'|1|C|99|'..math.floor(now/86400)..'|'..now,'PARTY','Ann-Realm')
bea.fire('CHAT_MSG_ADDON','KWCOW1','9999|1|C|99|'..math.floor(now/86400)..'|'..now,'GUILD','Ann-Realm')
bea.fire('CHAT_MSG_ADDON','KWCOW1',GUILD..'|1|C|99|'..math.floor(now/86400)..'|'..now,'GUILD','Stranger-Realm')
bea.fire('CHAT_MSG_ADDON','KWCOW1',GUILD..'|1|C|abc|1|'..now,'GUILD','Ann-Realm')
bea.fire('CHAT_MSG_ADDON','KWCOW1',GUILD..'|1|C|99|'..math.floor(now/86400)..'|'..(now-8*86400),'GUILD','Ann-Realm')
bea.fire('CHAT_MSG_ADDON','KWCOW1',GUILD..'|2|C|99|1|'..now,'GUILD','Ann-Realm')
assert(bea.OW.CountFor('Ann-Realm')==before,'rejected reports change nothing')
assert(bea.OW.CountFor('Stranger-Realm')==nil)
print('PASS: KWCOW1 rejects other channels, guilds, non-members, malformed, stale and wrong-version reports')

-- 5. Saved data is preserved: an existing V4.5 KWCDB.openWorldDeaths table is read as-is.
local old=client('Cal','Player-1-000000C3')
old.env.KWCDB.openWorldDeaths={version=1,guilds={[GUILD]={members={['ann-realm']={count=7,sinceDay=1,rev=old.now-60}}}}}
assert(old.OW.CountFor('Ann-Realm')==7,'V4.5 saved open-world counts are still shown')
old.env.KWCDB.lifetimeDeathsExcludingBG={version=2,guilds={[GUILD]={members={['ann-realm']={count=33,sinceDay=1,rev=old.now-60}}}}}
assert(old.LT.CountFor('Ann-Realm')==33 and old.OW.CountFor('Ann-Realm')==7,'the two saved tables stay independent')
print('PASS: V4.5 and V4.6 saved sharing data are both preserved and kept apart')
print('PASS: open world death sync')
