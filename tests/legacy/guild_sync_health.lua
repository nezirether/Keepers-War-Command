local network,packet=assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
local n=network(4,false)
local a,b,c,d=n.client(1,nil,{scoped=true}),n.client(2,nil,{scoped=true}),
 n.client(3,nil,{scoped=true}),n.client(4,nil,{scoped=true,legacy=true})
local E=a.e
local names={a.name,b.name,"Righteous Bonez","SingleName"}
E.GetGuildRosterInfo=function(i) return names[i],"Member",i<=2 and 1 or 3,60,"Warrior","","","",true end
c.name=names[3];d.name=names[4]
for i=1,6 do packet(a,"KWC4","Q|"..E.time(),c) end
for i=1,12 do packet(a,"KWC4","S|bad",c) end
for i=1,12 do packet(a,"KWC4","S|B|unknown|"..b.name.."|ACTIVE|1|"..E.time().."|fake",c) end
local h=E.KWC.Sync.Health()
assert(h.received==30 and h.applied==0 and h.rejected==24)
local outcomes,recent=E.KWC.Sync.Outcomes()
assert(outcomes.KWC4["Request (no record change)"]==6)
assert(outcomes.KWC4["Invalid board snapshot"]==12 and outcomes.KWC4["Missing record provenance"]==12)
assert(#recent==24 and recent[1].payload==nil)
packet(a,"KWC3","3;HONOR;999",c)
assert(outcomes["KWC3 PvP"]["Unsupported PvP protocol"]==1)
assert(not E.KWCDB.pvp[c.name])
packet(a,"KWC3","2;HONOR;72",c)
packet(a,"KWC3","2;HONOR;90",d)
packet(a,"KWC3","2;HONOR;72",c)
packet(a,"KWC3","2;HONOR;1",d)
packet(a,"KWC3","2;HKAREA;17;"..E.time()..";-1;0",c)
assert(E.KWCDB.pvp[c.name].honor.lifetime==72 and E.KWCDB.pvp[d.name].honor.lifetime==90)
assert(E.KWCDB.pvp[c.name].honorByArea.world.value==17 and not E.KWCDB.pvp[c.name].honorByArea.battleground)
assert(#E.KWC.PvP.Rankings("lifetime")==3)
assert(outcomes["KWC3 PvP"]["Duplicate honor record"]==1 and outcomes["KWC3 PvP"]["Stale honor total"]==1)
local saved=E.KWCDB
a.guildID=false;a.event("PLAYER_GUILD_UPDATE")
packet(a,"KWC3","2;HONOR;99",c)
assert(not E.KWCDB.pvp[c.name] and outcomes.KWC3["Guild identity unavailable"]==1)
a.guildID=1;a.event("INITIAL_CLUBS_LOADED")
assert(E.KWCDB.pvp[c.name].honor.lifetime==72)
a.online=false
local reload=n.client(1,saved,{scoped=true})
assert(reload.e.KWCDB.pvp[c.name].honor.lifetime==72 and reload.e.KWCDB.pvp[d.name].honor.lifetime==90)
print("PASS: 30 board packets / 24 rejected / 0 applied, safe diagnostics, two verified PvP peers, duplicates, unsupported version, delayed scope, reload")
