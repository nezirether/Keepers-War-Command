-- Run from the repository root with Lua 5.1 or LuaJIT: luajit tests/death_ledger.lua
-- Open World Death Ledger (KeepersWarCommand/DeathLedger.lua): counting rules and,
-- since V4.3 (owner approval A1), per-character persistence in KWCDB.deathLedger.
local SECRET=setmetatable({},{})
local function session(opts)
 opts=opts or {}
 local env=setmetatable({},{__index=_G})
 local events={}
 local s={env=env,inside=false,kind='none',dead=opts.dead or false,guid=opts.guid or 'Player-1234-00ABCDEF',now=opts.now or 1000}
 env.KWCDB=opts.db or {settings={}}
 env.KWC={On=function(e,fn) events[e]=events[e] or {};table.insert(events[e],fn);return true end,
  Send=function() error('the death ledger must not send guild traffic') end}
 env.time=function() return s.now end
 env.IsInInstance=function() return s.inside,s.kind end
 env.GetInstanceInfo=function() return 'Zone',s.kind end
 env.UnitIsDeadOrGhost=function() return s.dead end
 env.UnitGUID=function() return s.guid end
 -- Guild roster: {name, guid}. GetGuildRosterInfo returns the GUID 17th.
 s.roster=opts.roster
 env.IsInGuild=function() return s.roster~=nil end
 env.GetNumGuildMembers=function() return s.roster and #s.roster or 0 end
 env.GetGuildRosterInfo=function(i) local m=s.roster[i];return m[1],'Rank',1,80,'Warrior','Zone','','',true,0,'WARRIOR',0,0,false,false,0,m[2] end
 setfenv(assert(loadfile('KeepersWarCommand/InstanceAlerts.lua')),env)()
 setfenv(assert(loadfile('KeepersWarCommand/DeathLedger.lua')),env)()
 s.L=env.KWC.DeathLedger
 function s.fire(e,...) for _,fn in ipairs(events[e] or {}) do fn(...) end end
 -- The client loads SavedVariables after every addon file has run, then fires ADDON_LOADED.
 if not opts.noAddonLoaded then s.fire('ADDON_LOADED','KeepersWarCommand') end
 function s.login() s.fire('PLAYER_ENTERING_WORLD') end
 function s.die() s.dead=true;s.fire('PLAYER_DEAD') end
 function s.release() s.fire('PLAYER_ALIVE') end -- ghost: still dead or ghost
 -- A resurrection takes real time (corpse run, spirit healer or a cast).
 function s.resurrect() s.now=s.now+30;s.dead=false;s.fire('PLAYER_ALIVE') end
 function s.get() return s.L.Get() end
 return s
end
local function snapshot(t) local r={} for k,v in pairs(t) do r[k]=v end return r end

-- Open-world deaths of every cause count; the ledger cannot see or need the cause.
do
 local s=session();s.login()
 assert(s.get().since==1000 and s.get().armed,'tracking starts once alive is confirmed')
 for i,cause in ipairs({'enemy player','hostile NPC','falling','drowning','environment'}) do
  s.die();s.resurrect()
  assert(s.get().openWorld==i,cause..' death counts as open world')
 end
 assert(s.get().instanced==0 and s.get().unknown==0 and s.get().persistent==true)
 print('PASS: open-world deaths of every cause count once each')
end
-- Battleground, dungeon, raid and other instances are excluded.
do
 local s=session();s.login()
 for _,kind in ipairs({'pvp','party','raid','scenario'}) do
  s.inside,s.kind=true,kind
  s.die();s.resurrect()
 end
 local g=s.get()
 assert(g.openWorld==0 and g.instanced==4,'instanced deaths are excluded from open world')
 print('PASS: battleground, dungeon, raid and other instance deaths excluded')
end
-- Unknown, secret, throwing or contradictory location never counts as open world.
do
 for label,breakIt in pairs({
  ['throwing IsInInstance']=function(s) s.env.IsInInstance=function() error('restricted') end end,
  ['secret type']=function(s) s.env.issecretvalue=function(v) return v==SECRET end;s.kind=SECRET end,
  ['missing GetInstanceInfo']=function(s) s.env.GetInstanceInfo=nil end,
  ['contradiction']=function(s) s.kind='party' end,
  ['loading screen']=function(s) s.fire('PLAYER_LEAVING_WORLD') end,
 }) do
  local s=session();s.login()
  breakIt(s)
  assert(pcall(s.die),label..' must not raise')
  local g=s.get()
  assert(g.openWorld==0 and g.unknown==1,label..' is counted as unknown, not open world')
 end
 print('PASS: unknown, secret, throwing, contradictory and loading states never count as open world')
end
-- One death, one count: duplicates, spirit release, reload or login while dead.
do
 local s=session();s.login()
 s.die();s.fire('PLAYER_DEAD');s.fire('PLAYER_DEAD')
 assert(s.get().openWorld==1,'duplicate PLAYER_DEAD events count once')
 s.release();s.fire('PLAYER_UNGHOST');s.fire('PLAYER_DEAD')
 assert(s.get().openWorld==1,'spirit release does not rearm')
 s.resurrect();s.die()
 assert(s.get().openWorld==2,'a confirmed resurrection rearms for the next death')
 -- Reload while dead: a fresh session starts disarmed and stays disarmed while dead.
 local r=session();r.dead=true;r.login()
 assert(r.get().armed==false and r.get().since==nil,'reload while dead starts disarmed')
 r.fire('PLAYER_DEAD');r.release();r.fire('PLAYER_DEAD')
 assert(r.get().openWorld==0,'reload or login while dead never counts')
 r.resurrect();r.die()
 assert(r.get().openWorld==1,'counting begins after the first confirmed resurrection')
 -- Unreadable alive state never arms.
 local u=session();u.env.UnitIsDeadOrGhost=function() return nil end;u.login();u.die()
 assert(u.get().openWorld==0 and u.get().armed==false,'an unconfirmed alive state never arms')
 local x=session();x.env.UnitIsDeadOrGhost=function() error('restricted') end;x.login()
 assert(x.get().armed==false,'a throwing alive check never arms')
 print('PASS: duplicates, spirit release, reload and login while dead never double count')
end
-- Identity: validated per-character GUID; records are separate per character.
do
 local s=session();s.login()
 s.die();s.resurrect()
 s.guid='Player-1234-00FEDCBA';s.die();s.resurrect();s.die();s.resurrect()
 assert(s.get().openWorld==2,'second character has its own count')
 s.guid='Player-1234-00ABCDEF'
 assert(s.get().openWorld==1,'first character keeps its own count')
 for label,bad in pairs({['nil']=false,['empty']='',['creature']='Creature-0-1-2-3',['secret']=SECRET}) do
  local b=session();b.login()
  if bad==SECRET then b.env.issecretvalue=function(v) return v==SECRET end end
  b.guid=bad or nil
  b.die()
  assert(b.get()==nil,label..' identity yields no record')
  assert(b.L.LastDecision():find('identity unavailable',1,true),label..' identity is reported, not counted')
 end
 print('PASS: validated per-character GUIDs; separate counts per character')
end
-- ------------------------------------------------------------ Persistence (A1)
local function deep(v) if type(v)~='table' then return v end local r={} for k,x in pairs(v) do r[deep(k)]=deep(x) end return r end
local function same(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~='table' then return a==b end
 for k,v in pairs(a) do if not same(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
local A,B='Player-1234-00ABCDEF','Player-1234-00FEDCBA'
-- Creation, persistence across /reload, logout and login, and unrelated data preserved.
do
 local db={settings={worldPvPDeathDebug=true},worldPvPDeaths={{victim='Old'}},guildRecords={members={}},
  guildPartitions={['1']={ops={}}},history={'x'}}
 local before=deep(db)
 local loaded=session({db=db,noAddonLoaded=true})
 assert(db.deathLedger==nil,'nothing is read or written before SavedVariables are loaded')
 loaded.fire('ADDON_LOADED','SomeOtherAddon')
 assert(db.deathLedger==nil,'another addon loading does not touch the ledger')
 local s=session({db=db,now=5000})
 assert(db.deathLedger==nil,'loading alone never creates the key')
 s.login()
 local rec=db.deathLedger and db.deathLedger.characters[A]
 assert(db.deathLedger.version==1 and rec and rec.since==5000 and rec.openWorld==0,'record created when the character is first confirmed alive')
 s.die();s.resurrect();s.inside,s.kind=true,'raid';s.die();s.resurrect()
 assert(rec.openWorld==1 and rec.instanced==1 and rec.lastDeath==5030,'deaths are written to the saved record')
 for k,v in pairs(before) do assert(same(v,db[k]),'unrelated saved data untouched: '..k) end
 for k in pairs(db) do assert(before[k]~=nil or k=='deathLedger','no saved key other than deathLedger: '..tostring(k)) end
 -- /reload: a new session on the same SavedVariables table, later in time.
 local r=session({db=db,now=9000});r.login()
 assert(r.get().openWorld==1 and r.get().instanced==1 and r.get().since==5000 and r.get().persistent,'count and start date survive /reload')
 r.die();r.resurrect()
 assert(db.deathLedger.characters[A].openWorld==2 and db.deathLedger.characters[A].since==5000,'counting continues after reload; start date unchanged')
 -- Logout and login days later.
 local l=session({db=db,now=900000});l.login()
 assert(l.get().openWorld==2 and l.get().since==5000,'count and start date survive logout and login')
 assert(l.L.Display():find('since',1,true) and select(2,l.L.Display()):find('Not shared',1,true),'display says saved, not shared')
 assert(l.L.Summary():find('saved per character, not shared',1,true),'summary states saved and not shared')
 print('PASS: persistence: created on first alive login, survives /reload, logout and login, unrelated data untouched')
end
-- Death, release, resurrection and reload transitions never double count.
do
 local db={}
 local s=session({db=db,now=100});s.login();s.die()
 assert(db.deathLedger.characters[A].openWorld==1)
 -- /reload while dead, then as a ghost after release.
 local r=session({db=db,now=130,dead=true});r.login();r.fire('PLAYER_DEAD');r.release();r.fire('PLAYER_DEAD')
 assert(db.deathLedger.characters[A].openWorld==1,'reload while dead or as a ghost never recounts')
 -- Logout as a ghost and log back in still dead.
 local g=session({db=db,now=4000,dead=true});g.login();g.fire('PLAYER_UNGHOST');g.fire('PLAYER_DEAD')
 assert(db.deathLedger.characters[A].openWorld==1,'login while dead never recounts')
 g.resurrect();g.die()
 assert(db.deathLedger.characters[A].openWorld==2,'counting resumes after a confirmed resurrection')
 -- A reload in the instant around death that reads alive: the saved lastDeath rejects the repeat.
 local q=session({db=db,now=4031});q.login();q.die()
 assert(db.deathLedger.characters[A].openWorld==2,'a second death within 2 seconds of the saved one is a duplicate')
 assert(q.L.LastDecision():find('duplicate',1,true),'the duplicate is reported')
 q.resurrect();q.die()
 assert(db.deathLedger.characters[A].openWorld==3,'a death outside the duplicate window counts')
 -- A clock that moved backwards does not block counting.
 local c=session({db=db,now=60});c.login();c.die()
 assert(db.deathLedger.characters[A].openWorld==4,'a backwards clock does not block counting')
 print('PASS: death, release, resurrection and reload transitions never double count')
end
-- Two characters never overwrite each other.
do
 local db={}
 local a=session({db=db,now=100,guid=A});a.login();a.die();a.resurrect();a.die()
 local b=session({db=db,now=200,guid=B});b.login();b.die()
 local ra,rb=db.deathLedger.characters[A],db.deathLedger.characters[B]
 assert(ra.openWorld==2 and ra.since==100 and rb.openWorld==1 and rb.since==200,'separate records per character')
 local a2=session({db=db,now=300,guid=A});a2.login()
 assert(a2.get().openWorld==2 and db.deathLedger.characters[B].openWorld==1,'logging back into the first character keeps both records')
 print('PASS: two characters keep separate records and never overwrite each other')
end
-- Malformed records are rejected without being overwritten.
do
 local bad={
  ['not a table']='junk',
  ['missing start date']={openWorld=1,instanced=0,unknown=0},
  ['negative count']={since=10,openWorld=-1,instanced=0,unknown=0},
  ['fractional count']={since=10,openWorld=1.5,instanced=0,unknown=0},
  ['string count']={since=10,openWorld='5',instanced=0,unknown=0},
  ['huge count']={since=10,openWorld=1e9,instanced=0,unknown=0},
  ['bad resets']={since=10,openWorld=1,instanced=0,unknown=0,resets='x'},
  ['last death before start']={since=10,openWorld=1,instanced=0,unknown=0,lastDeath=5},
 }
 for label,value in pairs(bad) do
  local db={deathLedger={version=1,characters={[A]=deep(value),[B]={since=50,openWorld=3,instanced=0,unknown=0}}}}
  local before=deep(db.deathLedger.characters[A])
  local s=session({db=db,now=1000,guid=A});s.login();s.die();s.resurrect();s.die()
  assert(same(db.deathLedger.characters[A],before),label..': malformed record left untouched')
  assert(s.get().openWorld==2 and s.get().persistent==false,label..': counts for this session only')
  assert(s.get().reason:find('unreadable',1,true),label..': the reason is reported')
  assert(select(2,s.L.Display()):find('not saved',1,true),label..': display says not saved')
  local b=session({db=db,now=1100,guid=B});b.login();b.die()
  assert(db.deathLedger.characters[B].openWorld==4,label..': other characters still save normally')
 end
 -- Keys that are not player GUIDs are never read or replaced.
 local db={deathLedger={version=1,characters={['Creature-0-1']={x=1},[42]='y'}}}
 local s=session({db=db,now=1000});s.login();s.die()
 assert(db.deathLedger.characters['Creature-0-1'].x==1 and db.deathLedger.characters[42]=='y','foreign keys preserved')
 assert(db.deathLedger.characters[A].openWorld==1,'valid character saves alongside foreign keys')
 print('PASS: malformed records are rejected, reported and never overwritten')
end
-- Unknown schema versions and malformed roots are read-only.
do
 for label,root in pairs({
  ['future version']={version=2,characters={[A]={since=1,openWorld=9,instanced=0,unknown=0}},extra={keep=true}},
  ['missing version']={characters={}},
  ['root not a table']='corrupt',
  ['characters not a table']={version=1,characters=7},
 }) do
  local db={deathLedger=deep(root),settings={keep=1}}
  local s=session({db=db,now=1000});s.login();s.die();s.resurrect();s.die()
  assert(same(db.deathLedger,root),label..': saved ledger left exactly as found')
  assert(db.settings.keep==1,label..': unrelated data untouched')
  assert(s.get().openWorld==2 and s.get().persistent==false,label..': counts for this session only')
  assert(s.L.Summary():find('this session only, not saved',1,true),label..': summary states not saved')
 end
 print('PASS: unknown versions and malformed roots are read-only')
end
-- No historical seeding and no guild traffic.
do
 local db={}
 local s=session({db=db,now=1000})
 s.env.GetStatistic=function() return 999 end
 s.login()
 assert(s.get().openWorld==0 and db.deathLedger.characters[A].openWorld==0,'never seeded from lifetime statistics')
 s.die()
 assert(db.deathLedger.characters[A].openWorld==1,'counts only prospective deaths; KWC.Send would have raised')
 print('PASS: no historical seeding and no guild traffic')
end
-- Open World Deaths guild board.
do
 local roster={{'Cara-Realm','Player-1234-0000CCCC'},{'Me-Realm',A},{'Bob-Realm','Player-1234-0000BBBB'}}
 local s=session({db={},roster=roster,now=1000});s.login()
 s.die();s.resurrect()
 s.inside,s.kind=true,'pvp';s.die();s.resurrect()     -- battleground
 s.kind='party';s.die();s.resurrect()                 -- dungeon
 s.kind='raid';s.die();s.resurrect()                  -- raid
 s.inside,s.kind=false,'none';s.die();s.resurrect()   -- open world again
 local rows=s.L.GuildRankings()
 assert(#rows==3,'every roster member is listed once')
 assert(rows[1].name=='Me-Realm' and rows[1].self and rows[1].tracked and rows[1].value==2,'this character ranks with its tracked open-world count only')
 assert(rows[2].name=='Bob-Realm' and rows[3].name=='Cara-Realm','untracked members follow, sorted by name')
 for i=2,3 do assert(rows[i].tracked==false and rows[i].value==nil,'guildmates without verified data are untracked, not zero') end
 assert(rows[1].display=='Me','display drops the realm')
 print('PASS: guild board ranks tracked open-world deaths; BG, dungeon and raid excluded; others untracked')
end
do
 -- A character with zero tracked deaths shows 0, which is different from untracked.
 local s=session({db={},roster={{'Me-Realm',A},{'Bob-Realm','Player-1234-0000BBBB'}}});s.login()
 local rows=s.L.GuildRankings()
 assert(rows[1].self and rows[1].tracked and rows[1].value==0 and rows[2].value==nil,'tracked zero is shown as 0; others untracked')
 -- Before tracking starts (logged in dead), this character is untracked too.
 local d=session({db={},roster={{'Me-Realm',A}},dead=true});d.login()
 assert(d.L.GuildRankings()[1].tracked==false,'not yet confirmed alive: untracked, not zero')
 -- Name match when the roster GUID is unreadable.
 local n=session({db={},roster={{'Me-Realm','x'},{'Bob-Realm','y'}}})
 n.env.KWC.LocalGuildMember=function() return 'me-realm' end
 n.login();n.die();n.resurrect()
 local r=n.L.GuildRankings()
 assert(r[1].name=='Me-Realm' and r[1].value==1 and r[2].tracked==false,'self found by roster name when GUIDs are unreadable')
 -- Not in a guild: this character alone.
 local solo=session({db={}});solo.login();solo.env.UnitName=function() return 'Me' end
 local only=solo.L.GuildRankings()
 assert(#only==1 and only[1].self and only[1].value==0,'outside a guild the board shows only this character')
 -- Secret or empty roster names are skipped, never shown.
 local sec=session({db={},roster={{SECRET,'g1'},{'','g2'},{'Me-Realm',A}}})
 sec.env.issecretvalue=function(v) return v==SECRET end
 sec.login()
 assert(#sec.L.GuildRankings()==1,'unreadable roster names are skipped')
 print('PASS: tracked zero differs from untracked; identity fallbacks; secret names skipped')
end
do
 -- Mixed addon versions: guildmates on any KWC build share only lifetime WoW
 -- statistics (KWREC1 groups 1-6). None of that may appear as an open-world count.
 local s=session({db={},roster={{'Me-Realm',A},{'Old-Realm','Player-1234-0000OOOO'},{'New-Realm','Player-1234-0000NNNN'}}})
 s.env.GetStatistic=function() return 999 end
 s.env.KWC.GuildRecords={DeathRankings=function() return {{name='old-realm',value=750},{name='new-realm',value=12}} end}
 s.login();s.die();s.resurrect()
 for _,row in ipairs(s.L.GuildRankings()) do
  if not row.self then assert(row.tracked==false and row.value==nil,row.name..': lifetime statistics never become open-world counts') end
 end
 print('PASS: mixed versions: shared lifetime statistics never appear as open-world counts')
end
print('PASS: death ledger')
