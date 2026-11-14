-- Check directed PvP cache recovery and delayed signup replies via production handlers.
local network, packet = assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
local n=network(4,false)
local author,officer,receiver,member=n.client(1,nil,{scoped=true}),n.client(2,nil,{scoped=true}),
    n.client(3,nil,{scoped=true}),n.client(4,nil,{scoped=true})
receiver.online=false
author.e.KWC.RaidSignup.Create("Test raid","Tomorrow")
n.run(15)
officer.e.KWCDB.pvp[author.name].achievementPoints=71
author.online=false
receiver.online=true
local R=receiver.e
assert(R.KWC.PvP.RequestGuildHonor(true))
n.run(30)
local cached=assert(R.KWCDB.pvp[author.name])
assert(cached.honor.lifetime==author.honor and cached.honorByArea.world.value==author.world)
local token,legacyCache
for _,p in ipairs(n.packets) do
    if p.from==receiver.name then token=p.message:match("^2;PVPREQ2;1;([^;]+);") or token end
    if p.message:match("^2;PVPREPLY;") then assert(p.from==officer.name and p.target==receiver.name.."-Realm") end
    local name,points=p.message:match(";2;PVPCACHE;([^;]+);%d+;%d+;(-?%d+)$")
    if name==author.name then legacyCache=points end
end
assert(token and legacyCache=="-1" and not cached.achievementPoints)
assert(officer.e.KWCDB.pvp[author.name].achievementPoints==71)
local forged=("2;PVPREPLY;1;%s;2;PVPCACHE;%s;99999;%d;0"):format(token,author.name,R.time())
packet(receiver,"KWC3",forged,member,"WHISPER")
assert(cached.honor.lifetime==author.honor)
receiver.guildID=2
receiver.event("PLAYER_GUILD_UPDATE")
packet(receiver,"KWC3",forged,officer,"WHISPER")
assert(not R.KWCDB.pvp[author.name])

-- A raid request schedules a delayed reply, then the officer changes guilds.
author.online=true
packet(author,"KWRS1","REQ|"..member.name,member)
author.guildID=2
author.event("PLAYER_GUILD_UPDATE")
local first=#n.packets
n.run(10)
for i=first+1,#n.packets do assert(not n.packets[i].message:match("^EV|")) end
print("PASS: directed PvP catch-up, forged relay rejection, guild partition, and delayed raid reply isolation")
