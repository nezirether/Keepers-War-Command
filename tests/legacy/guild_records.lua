local network,packet=assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
local n=network(4,false)
n.roster["player01 example"].online=false
local officer=n.client(2)
local player=n.client(3)
local recipient=n.client(4)
local stats={ [60]="1,200",[114]=0,[115]="--",[922]="1,2345",[108]=13,[1067]=5,
    [57]="--",[59]=7,[56]=35,[64182]="--",[593]=11,[1501]=66,[318]=65 }
local killingBlowReads=0
local function loadRecords(client, values)
 local env=client.e
 local native=env.GetStatistic
 env.GetStatistic=function(id,index)
  if index then return native(id,index) end
  if id==1487 or id==1488 or id==1491 then
   killingBlowReads=killingBlowReads+1
   return 99
  end
  return values[id]
 end
 setfenv(assert(loadfile("KeepersWarCommand/GuildRecords.lua")),env)()
 return env.KWC.GuildRecords
end
local savedRevision=officer.e.time()-1
officer.e.KWCDB.guildRecords={sharing={},members={
 [player.name:lower()]={withdrawn=0,groups={
  [1]={rev=savedRevision,week=2969,body="legacy",rows={{total=1199,base=1190,previous=8}}},
 }},
}}
local P=loadRecords(player,stats)
local O=loadRecords(officer,{})
local R=loadRecords(recipient,{})
local function deaths(records) return records.Rankings(1,1)[1] end
assert(deaths(O).value==1199)
local migrated=officer.e.KWCDB.guildRecords.members[player.name:lower()].groups[1]
assert(migrated.rows[1]==1199 and migrated.week==nil and migrated.body==nil and migrated.rev==savedRevision)
assert(P.Sharing() and P.Readable(1,1) and not P.Readable(1,3) and not P.Readable(3,3))
recipient.online=false
player.event("PLAYER_LOGIN")
n.run(18)
assert(deaths(O).value==1200)
assert(O.DeathRankings("total")[1].value==1200)
assert(O.DeathRankings("battleground")[1].value==42)
assert(O.DeathRankings("pvp")[1].value==66)
assert(O.DeathRankings("estimate")[1].value==24)
local legacyBlows=("1|%s|7|%d|0|2r,2r,-;2r,2r,-;2r,2r,-"):format(player.name:lower(),officer.e.time())
packet(officer,"KWREC1",legacyBlows,player)
assert(not officer.e.KWCDB.guildRecords.members[player.name:lower()].groups[7])
local oldDeaths=("1|%s|5|%d|0|1,1,-;16,16,-"):format(player.name:lower(),officer.e.time()+20)
packet(officer,"KWREC1",oldDeaths,player)
local mapTotals=officer.e.KWCDB.guildRecords.members[player.name:lower()].groups[5].rows
assert(mapTotals[1]==nil and mapTotals[2]==42)
assert(O.Rankings(1,2)[1].value==0)
assert(O.Rankings(3,7)[1].value==13 and O.Rankings(3,10)[1].value==5)
local old
for _,p in ipairs(n.packets) do if p.prefix=="KWREC1" and p.message:match("^%d+|[^|]+|1|") then old=p.message end end
assert(old and old:match("|xc,xc,%-;0,0,%-;"))
local legacyPacket=old:gsub("|xc,xc,%-;", "|xd,xa,2;")
legacyPacket=legacyPacket:gsub("^(%d+|[^|]+|1|)(%d+)",function(prefix,rev)
 return prefix..(tonumber(rev)+1)
end)
packet(officer,"KWREC1",legacyPacket,player)
assert(deaths(O).value==1201)
stats[60]=1203
P.Sample()
n.run(5)
assert(deaths(O).value==1203)
packet(officer,"KWREC1",old,player)
packet(officer,"KWREC1",old,recipient)
assert(deaths(O,"all").value==1203)
player.online=false
recipient.online=true
assert(recipient.e.KWC.Sync.Request(true))
n.run(20)
assert(deaths(R,"all").value==1203)
assert(R.DeathRankings("battleground")[1].value==42)
assert(R.DeathRankings("pvp")[1].value==66)
assert(R.DeathRankings("estimate")[1].value==24)
assert(R.Rankings(3,7)[1].value==13)
player.online=true
stats[60]=1210
P.Sample()
n.run(5)
assert(deaths(O).value==1210)
stats[1501]=40
assert(P.WorldDeathEstimate()==nil)
P.Sample()
n.run(5)
assert(O.DeathRankings("pvp")[1].value==40 and not O.DeathRankings("estimate")[1])
stats[1501]=66
P.Sample()
n.run(5)
assert(O.DeathRankings("estimate")[1].value==24)
local OStats={[60]=999}
local previousGetStatistic=officer.e.GetStatistic
officer.e.GetStatistic=function(id,index)
 if index then return previousGetStatistic(id,index) end
 return OStats[id]
end
O.SetSharing(true)
local sorted=O.Rankings(1,1,"all")
assert(#sorted==2 and sorted[1].value==1210 and sorted[2].value==999)
OStats[60]=1210
O.Sample()
assert(O.Rankings(1,1,"all")[1].name==officer.name:lower())
O.SetSharing(false)
P.SetSharing(false)
n.run(5)
assert(not deaths(O,"all"))
assert(not O.DeathRankings("battleground")[1])
assert(not O.DeathRankings("pvp")[1])
assert(not O.Rankings(3,7)[1])
packet(officer,"KWREC1",old,player)
assert(not deaths(O,"all"))
P.SetSharing(true)
n.run(5)
assert(deaths(O,"all").value==1210)
officer.guildID=2
officer.event("PLAYER_GUILD_UPDATE")
assert(not deaths(O,"all") and O.Sharing())
officer.guildID=1
officer.event("PLAYER_GUILD_UPDATE")
assert(deaths(O,"all").value==1210)
assert(not O.Sharing())
local restored=n.client(2,officer.e.KWCDB)
local restoredRecords=loadRecords(restored,{[108]=21})
assert(not restoredRecords.Sharing())
restored.event("PLAYER_LOGIN")
n.run(18)
local restoredRanks=restoredRecords.Rankings(3,7)
assert(#restoredRanks==1 and restoredRanks[1].name==player.name:lower())
assert(killingBlowReads==0, "retired Killing Blows statistics were sampled")
print("PASS: Guild Records migration, automatic sharing, new boards, ranking, offline recovery, withdrawal and guild isolation")
