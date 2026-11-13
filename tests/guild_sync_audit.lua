-- Run from the repository root with Lua 5.1 or LuaJIT.
-- Assertions pin observed baseline behavior, including reproduced failures.
local root = "KeepersWarCommand/"
local epoch = 1794592800
local modules = {
    "Core.lua","Network.lua","AutoScout.lua","Roster.lua","Operations.lua",
    "CTAJoin.lua","RaidCommand.lua","RaidSignup.lua","GuildService.lua",
    "Sync.lua","PvP.lua","AddonChecker.lua","QualityOfLife.lua",
}
local chunks = {}
local baseline = ... == "baseline"
local baselineRef = "390b208b8ab41fcb4184cd4270c8123df0d4dee5"
if not baseline then
    table.insert(modules,"GuildLFGModel.lua")
    table.insert(modules,"GuildLFG.lua")
    for _,module in ipairs({"GuildServices","GuildProfessions","GuildServicesSync"}) do
        table.insert(modules,module..".lua")
    end
end
for _,name in ipairs(modules) do
    local file=assert(baseline and io.popen("git show "..baselineRef..":"..root..name,"r") or io.open(root..name,"rb"))
    chunks[name]=file:read("*a")
    file:close()
end

-- Run mixed-capability cases against the actual pre-split PvP implementation.
local legacySource=assert(io.popen("git show 66a6194:KeepersWarCommand/PvP.lua","r"))
local legacyPvP=legacySource:read("*a")
legacySource:close()
assert(#legacyPvP>0 and not legacyPvP:find("HKAREA",1,true))

local function network(size, impaired)
    local n={now=0,clients={},jobs={},sequence=0,packets={},bytes=0,loss=0,duplicates=0,throttles=0}
    local roster={}
    for i=1,size do
        local name=("Player%02d Example"):format(i)
        roster[name:lower()]={name=name,rankIndex=i<=2 and 1 or 3,scannedAt=epoch,online=true}
    end
    n.roster=roster
    function n.schedule(delay,callback)
        local tick=n.now+math.max(1,math.ceil(delay*10-0.0001))
        local q=n.jobs[tick] or {}
        n.jobs[tick]=q
        q[#q+1]=callback
    end
    function n.run(seconds)
        for tick=n.now+1,n.now+seconds*10 do
            n.now=tick
            for _,fn in ipairs(n.jobs[tick] or {}) do fn() end
            n.jobs[tick]=nil
            for _,c in ipairs(n.clients) do
                if c.online then
                    for _,f in ipairs(c.frames) do if f.OnUpdate then f.OnUpdate(f,0.1) end end
                end
            end
        end
    end
    function n.client(i, saved, options)
        options=options or {}
        local c={name=("Player%02d Example"):format(i),frames={},online=true,guild=true,guildID=1,
            logs={},honor=100+i,world=20+i,bg=30+i}
        local e=setmetatable({SlashCmdList={},UIParent={}}, {__index=_G})
        e._G=e
        e.math=setmetatable({random=function(a,b)
            c.seed=((c.seed or i)*16807)%2147483647
            if not a then return c.seed/2147483647 end
            return a+c.seed%(b-a+1)
        end}, {__index=math})
        e.time=function() return epoch+math.floor(n.now/10) end
        e.date=os.date
        e.print=function(message) c.logs[#c.logs+1]=message end
        e.IsInGuild=function() return c.guild end
        if (not baseline and options.scoped~=false) or (baseline and options.scoped) then e.C_Club={GetGuildClubId=function() return c.guildID end} end
        e.GetNormalizedRealmName=function() return "Realm" end
        e.GetNumGuildMembers=function() return size end
        e.GetGuildRosterInfo=function(index)
            local name=("Player%02d Example"):format(index)
            local record=roster[name:lower()]
            local online=record.online
            if options.scoped then
                for _, peer in ipairs(n.clients) do
                    if peer.name==name then online=online and peer.online and peer.guildID==c.guildID end
                end
            end
            return record.name,"Rank",record.rankIndex,60,"Warrior","Zone","","",online
        end
        e.GetGuildInfo=function() return "Guild","Rank",i<=2 and 1 or 3 end
        e.UnitName=function(unit) if unit=="player" then return c.name end end
        e.UnitFullName=e.UnitName
        e.GetZoneText=function() return c.zone or "Audit Zone" end
        e.GetPVPLifetimeStats=function() return c.honor end
        e.GetStatisticsCategoryList=function() return {18} end
        e.GetCategoryNumAchievements=function() return 2 end
        e.GetStatistic=function(_,index) return index==1 and c.world or c.bg,false,380+index end
        e.CreateFrame=function()
            local f={RegisterEvent=function() end,SetScript=function(self,event,fn) self[event]=fn end}
            c.frames[#c.frames+1]=f
            return f
        end
        e.C_GuildInfo={GuildRoster=function() end}
        e.C_Timer={After=function(delay,fn)
            n.schedule(delay,function() if c.online then fn() end end)
        end}
        e.C_Timer.NewTicker=function(delay,fn)
            local function tick() if c.online then fn();e.C_Timer.After(delay,tick) end end
            e.C_Timer.After(delay,tick)
        end
        e.C_ChatInfo={RegisterAddonMessagePrefix=function() return true end}
        e.C_ChatInfo.SendChatMessage=function() error("unexpected player chat send") end
        e.C_ChatInfo.SendAddonMessage=function(prefix,message,channel,target)
            n.sequence=n.sequence+1
            local seq=n.sequence
            if impaired and seq%83==0 then n.throttles=n.throttles+1;return 1 end
            n.packets[#n.packets+1]={prefix=prefix,message=message,from=c.name,tick=n.now,target=target}
            n.bytes=n.bytes+#prefix+#message
            for j,peer in ipairs(n.clients) do
                if peer.online and c.guildID==peer.guildID and (channel=="GUILD" or (channel=="WHISPER" and (peer.name==target or peer.name.."-Realm"==target))) then
                    if impaired and (seq+j*7)%41==0 then n.loss=n.loss+1
                    else
                        local function deliver()
                            if peer.online and c.guildID==peer.guildID then
                                peer.event("CHAT_MSG_ADDON",prefix,message,channel,c.name.."-Realm")
                            end
                        end
                        n.schedule(impaired and (0.1+((seq*17+j*11)%30)/10) or 0.1,deliver)
                        if impaired and (seq+j)%47==0 then
                            n.duplicates=n.duplicates+1
                            n.schedule(4.1,deliver)
                        end
                    end
                end
            end
            return 0
        end
        e.KWCDB=saved or {roster={},settings={autoGuildSync=true,autoScout=true,dev6AutoDefaultsApplied=true}}
        for key,record in pairs(roster) do
            e.KWCDB.roster[key]={name=record.name,rankIndex=record.rankIndex,scannedAt=e.time(),online=true}
        end
        for _,name in ipairs(modules) do
            local source=options.legacy and name=="PvP.lua" and legacyPvP or chunks[name]
            if not options.noLFG or (name~="GuildLFG.lua" and name~="GuildLFGModel.lua") then
                setfenv(assert(loadstring(source,"@"..name)),e)()
            end
        end
        e.KWC.UI={Refresh=function() end}
        c.e=e
        c.legacy=options.legacy
        c.event=function(event,...)
            c.frames[1].OnEvent(c.frames[1],event,...)
        end
        c.event("ADDON_LOADED","KeepersWarCommand")

        n.clients[#n.clients+1]=c
        return c
    end
    return n
end

local function packet(c,prefix,message,sender,channel)
    c.event("CHAT_MSG_ADDON",prefix,message,channel or "GUILD",sender.name.."-Realm")
end
local function find(rows,id)
    for _,row in ipairs(rows) do if row.id==id then return row end end
end

-- Share the production-handler simulator with the corrected behavior tests.
if ... == "fixtures" then return network, packet, find end

if not baseline then
    return assert(loadfile("tests/guild_sync_release_gate.lua"))()
end

-- Ideal delivery isolates authorization and missing data paths from transport loss.
local ideal=network(4,false)
local author,holder,returning,member=ideal.client(1),ideal.client(2),ideal.client(3),ideal.client(4)
returning.online=false
local A,B,C,M=author.e,holder.e,returning.e,member.e
A.KWC.Operations.AddBounty("Audit bounty",{target="Enemy"})
A.KWC.Operations.CreateCTA("Audit CTA",{zone="Audit Zone"})
A.KWC.RaidSignup.Create("Audit raid","Tomorrow")
local bid=A.KWCDB.bounties[1].id
local cid=A.KWCDB.ops[1].id
local rid=next(A.KWCDB.raidSignups.events)
ideal.run(20)
assert(find(B.KWCDB.bounties,bid) and find(B.KWCDB.ops,cid) and B.KWCDB.raidSignups.events[rid])
assert(not find(B.KWCDB.bounties,bid).details and not find(B.KWCDB.ops,cid).details)
A.KWC.Operations.Edit("BOUNTY",bid,"Edited bounty")
A.KWC.Operations.AddSighting(bid,"Audit Zone","last seen")
A.KWC.Operations.ChangeStatus("CTA",cid,"RESOLVED")
ideal.run(20) -- Deliver the close before testing a response to a locally closed CTA.
B.KWC.Operations.Respond(cid,"Coming")
assert(find(B.KWCDB.bounties,bid).text=="Edited bounty|0")
assert(find(B.KWCDB.ops,cid).status=="RESOLVED")
assert(not B.KWCDB.responses[cid], "resolved CTA accepted response")
author.online=false
returning.online=true
returning.event("PLAYER_ENTERING_WORLD")
ideal.run(65)
assert(not find(C.KWCDB.bounties,bid) and not find(C.KWCDB.ops,cid))
assert(not C.KWCDB.responses[cid] and not (C.KWCDB.raidSignups and C.KWCDB.raidSignups.events[rid]))
assert(C.KWCDB.pvp[author.name].honorByArea.world.value==author.world)
print("Ideal: peer restores offline character HKs, cannot restore that author's bounty, CTA, response or raid sign-up")

-- A regular member's cached tombstone is rejected even for a known stale record.
author.online=true
returning.online=false
local staleBounty={id=bid,author=author.name,text="stale",status="ACTIVE"}
local staleCTA={id=cid,author=author.name,text="stale",status="ACTIVE"}
C.KWCDB.bounties[1],C.KWCDB.ops[1]=staleBounty,staleCTA
A.KWC.Operations.Delete("BOUNTY",bid)
A.KWC.Operations.Delete("CTA",cid)
ideal.run(20)
assert(not find(M.KWCDB.bounties,bid) and not find(M.KWCDB.ops,cid))
assert(M.KWCDB.deletions["B:"..bid] and M.KWCDB.deletions["C:"..cid])
local t=A.time()
packet(returning,"KWC4",("D|B|%s|%s|%d"):format(bid,author.name,t),member)
packet(returning,"KWC4",("D|C|%s|%s|%d"):format(cid,author.name,t),member)
assert(find(C.KWCDB.bounties,bid) and find(C.KWCDB.ops,cid))
packet(returning,"KWC4",("D|B|%s|%s|%d"):format(bid,author.name,t),author)
packet(returning,"KWC4",("S|B|%s|%s|ACTIVE|100|%d|old"):format(bid,author.name,t),author)
assert(not find(C.KWCDB.bounties,bid))
packet(returning,"KWC4",("D|B|%s|%s|%d"):format("unseen",author.name,t),author)
assert(not C.KWCDB.deletions["B:unseen"])
packet(returning,"KWC4",("S|B|unseen|%s|ACTIVE|1|%d|old"):format(author.name,t),author)
assert(find(C.KWCDB.bounties,"unseen"))
print("Ideal: known authorized tombstone works; ordinary relay fails and delete-before-create can resurrect")

-- Replay, conflicting revisions, and trust boundaries.
local e={id="conflict",author=author.name,text="original",status="ACTIVE",revision=0,created=t}
B.KWCDB.ops[#B.KWCDB.ops+1]=e
packet(holder,"KWC4",("S|C|conflict|%s|RESOLVED|3|%d|new"):format(author.name,t),author)
packet(holder,"KWC4",("S|C|conflict|%s|ACTIVE|3|%d|equal revision"):format(author.name,t),author)
assert(e.text=="new")
C.KWCDB.ops[#C.KWCDB.ops+1]={id="conflict",author=author.name,text="original",status="ACTIVE",revision=0,created=t}
packet(returning,"KWC4",("S|C|conflict|%s|ACTIVE|3|%d|equal revision"):format(author.name,t),author)
packet(returning,"KWC4",("S|C|conflict|%s|RESOLVED|3|%d|new"):format(author.name,t),author)
assert(find(C.KWCDB.ops,"conflict").text==e.text)
packet(holder,"KWC3","2;STATUS;CTA,conflict,ACTIVE",author)
assert(e.status=="RESOLVED" and e.revision==3, "legacy STATUS reopened a versioned CTA")
packet(holder,"KWC4",("S|C|conflict|%s|RESOLVED|3|%d|new"):format(author.name,t),author)
assert(e.status=="RESOLVED", "duplicate snapshot changed the resolved CTA")
-- Leadership checks need an active CTA after the replay check leaves this one resolved.
e={id="conflict",author=author.name,text="active fixture",status="ACTIVE",revision=3,created=t}
for i,entry in ipairs(B.KWCDB.ops) do if entry.id==e.id then B.KWCDB.ops[i]=e;break end end
packet(holder,"KWC4","E|conflict|spoof|A|"..author.name.."|",member)
assert(not B.KWC.Operations.IsCommander(e,member.name))
packet(holder,"KWC4","E|conflict|legit|L|"..author.name.."|"..member.name,author)
packet(holder,"KWC4","E|conflict|early|P|"..member.name.."|"..author.name,member)
assert(not B.KWC.Operations.IsCommander(e,member.name) and B.KWC.Operations.IsCommander(e,author.name))
local rank=ideal.roster[author.name:lower()]
rank.rankIndex=3
assert(not B.KWC.IsSenderOfficer(author.name.."-Realm"), "saved officer rank survived demotion")
packet(holder,"KWRS1",("EV|%s|Changed|Tomorrow|%s|%d|1"):format(rid,author.name,t),author)
assert(not B.KWCDB.raidSignups.events[rid].cancelled)
rank.rankIndex=1
packet(holder,"KWC4","E|conflict|foreign|A|"..author.name.."-Foreign|",{name=author.name.."-Foreign"})
assert(not e.commandEvents.foreign)
rank.online=false
B.KWCDB.roster[author.name:lower()].online=false
B.KWCDB.roster[author.name:lower()].scannedAt=t
B.KWCDB.roster[author.name:lower()].offlineScans=2
packet(holder,"KWC4","E|conflict|valid|P|"..member.name.."|"..author.name,member)
assert(B.KWC.Operations.IsCommander(e,member.name) and not B.KWC.Operations.IsCommander(e,author.name))
rank.online=true
packet(holder,"KWRS1",("RS|%s|%s|Absent|2147483647"):format(rid,author.name),member)
assert(not B.KWCDB.raidSignups.responses[rid][author.name])
packet(holder,"KWRS1",("RS|%s|%s|Attending|%d"):format(rid,member.name,t),member)
assert(B.KWCDB.raidSignups.responses[rid][member.name].status=="Attending")
packet(holder,"KWRS1",("RS|%s|%s|Absent|%d"):format(rid,member.name,t+400),member)
assert(B.KWCDB.raidSignups.responses[rid][member.name].status=="Attending")
packet(holder,"KWC3","2;SERVICE;CACHEZONE,conflict,"..author.name..","..t,member)
assert(not B.KWC.GuildService.CTARecords("conflict")[author.name])
packet(holder,"KWC3","2;HONOR;99999",member,"WHISPER")
local p=B.KWCDB.pvp[member.name]
assert(p.honor.lifetime~=99999)
packet(holder,"KWC3","2;HONOR;9000",member)
packet(holder,"KWC3","2;HONOR;10",member)
assert(p.honor.lifetime==9000, "stale honor regressed lifetime HKs")
packet(holder,"KWC3","2;ACHPTS;45",member)
packet(holder,"KWC3","2;ACHPTS;5",member)
assert(p.achievementPoints==45, "stale points regressed achievement totals")
local active={id="replayed-sight",author=author.name,text="active",status="ACTIVE"}
B.KWCDB.bounties[1]=active
for _=1,30 do packet(holder,"KWC3","2;SIGHT;replayed-sight:Audit Zone,same",member) end
assert(#active.sightings==1, "replayed sightings consumed history")
print("Ideal: equal revisions converge; stale board and statistics packets, forged RSVP, early succession and duplicate sightings rejected")

-- A reordered group assignment snapshot never repairs its lost TASK.
local group=network(2,false)
local lead,follower=group.client(1),group.client(2)
local g=follower.e
g.GetNumGroupMembers=function() return 2 end
g.IsInRaid=function() return false end
g.UnitExists=function() return true end
g.UnitIsPlayer=function() return true end
g.UnitClass=function() return "Warrior","WARRIOR" end
g.UnitIsConnected=function() return true end
g.UnitIsGroupLeader=function(unit) return unit=="party1" end
g.UnitName=function(unit) return unit=="player" and follower.name or lead.name end
packet(follower,"KWCR2","TASK|session|1|"..follower.name.."|Interrupt",lead,"PARTY")
packet(follower,"KWCR2","BEGIN|session|1|"..lead.name.."|",lead,"PARTY")
packet(follower,"KWCR2","END|session|1|"..lead.name.."|",lead,"PARTY")
assert(g.KWC.RaidCommand.CountAssignments()==0)
packet(follower,"KWCR2","TASK|session|1|"..follower.name.."|Interrupt",lead,"PARTY")
assert(g.KWC.RaidCommand.CountAssignments()==1)
packet(follower,"KWCR2","READY|session|1|"..follower.name.."|1",follower,"PARTY")
packet(follower,"KWCR2","READY|session|1|"..follower.name.."|0",follower,"PARTY")
packet(follower,"KWCR2","READY|session|1|"..follower.name.."|1",follower,"PARTY")
assert(g.KWCDB.raidCommand.ready[follower.name]==true)
print("Raid Command: TASK before BEGIN lost; older READY can overwrite current state")

-- Raid Tools attendance through its actual handler registry. The AceComm wire
-- codec and group APIs are covered separately from this handler-level fixture.
local handlers, replies = {}, {}
local comm = {
    RegisterHandler=function(_,kind,fn) handlers[kind]=fn end,
    Send=function(_,kind,data,channel,target) replies[#replies+1]={kind, data, channel, target} end,
    IsSenderPrivileged=function(_,sender) return sender=="Recorder" or sender=="Group Lead" end,
    GroupUnit=function(_,sender) return ({Recorder="player",["Group Lead"]="raid1",["Other Member"]="raid2"})[sender] end,
}
local raid = setmetatable({
    KeepersRaidTools={Comms=comm,RosterValidation={}},
    KeepersRaidToolsAttendanceDB={["2026-11-13"]={Member={status=3}}},
    Ambiguate=function(sender) return sender end,
    UnitName=function() return "Recorder" end,
    time=function() return epoch end,
}, {__index=_G})
local attendance=root.."Modules/RaidTools/Modules/Attendance/AttendanceSync.lua"
setfenv(assert(loadfile(attendance)),raid)()
local sync=raid.KeepersRaidTools.AttendanceSync
sync:RegisterHandlers()
local date="2026-11-13"
handlers.attPullRequest({day=date,request="1-1-111111"},"Outside Player","WHISPER")
handlers.attPullRequest({day=date,request="1-1-111111"},"Group Lead","RAID")
assert(#replies==0)
handlers.attPullRequest({day=date,request="1-1-111111"},"Group Lead","WHISPER")
assert(replies[1][1]=="attPullResponse" and replies[1][4]=="Group Lead")
handlers.attDayPush({day=date,records={Member=1}},"Other Member","RAID")
handlers.attDayPush({day=date,records={Member=1}},"Group Lead","WHISPER")
handlers.attPullResponse({day=date,records={Member=1}},"Group Lead","WHISPER")
assert(not sync:GetPendingDay())
sync:RequestDay("Group Lead",date)
local request=replies[#replies][2].request
handlers.attPullResponse({day=date,request=request,records={Member=1}},"Other Member","WHISPER")
handlers.attPullResponse({day="2026-11-12",request=request,records={Member=1}},"Group Lead","WHISPER")
handlers.attPullResponse({day=date,request="2-2-222222",records={Member=1}},"Group Lead","WHISPER")
assert(not sync:GetPendingDay())
handlers.attPullResponse({day=date,request=request,records={Member=1}},"Group Lead","WHISPER")
assert(sync:GetPendingDay().sender=="Group Lead")
assert(sync:AcceptPendingDay() and raid.KeepersRaidToolsAttendanceDB[date].Member.status==1)
handlers.attPullResponse({day=date,request=request,records={Member=3}},"Group Lead","WHISPER")
assert(not sync:GetPendingDay())
print("Attendance: rejected unsolicited and mismatched responses, unauthorized request and push, and replay")

-- Exercise a real reload with a fresh Lua environment and an old saved cache.
returning.online=false
local reload=ideal.client(3,C.KWCDB)
local beforeReload,bytesBeforeReload=#ideal.packets,ideal.bytes
reload.event("PLAYER_ENTERING_WORLD")
ideal.run(40)
print(("Reload with small cache: %d packets / %d bytes in 40s"):format(#ideal.packets-beforeReload,ideal.bytes-bytesBeforeReload))
assert(reload.e.KWCDB.deletions["B:"..bid] and reload.e.KWCDB.pvp[author.name].honorByArea.world.value==author.world)
local outsider=ideal.client(4)
outsider.guildID=2
reload.guildID=2
reload.event("PLAYER_GUILD_UPDATE")
assert(outsider.e.KWC.PvP.RequestGuildHonor(true))
ideal.run(65)
assert(outsider.e.KWCDB.pvp[author.name].honorByArea.world.value==author.world)
print("Ideal: SavedVariables survive reload; a guild switch exposes previous-guild PvP cache to a same-named member in the new guild")

-- Restart with only the ordinary holder and returning player after two days.
local twoDays=network(4,false)
twoDays.now=2*24*60*60*10
local cached={
    roster={},settings={autoGuildSync=true,dev6AutoDefaultsApplied=true},
    bounties={{id="two-day-bounty",author=author.name,text="Edited offline",status="ACTIVE",revision=2,created=epoch}},
    deletions={["C:two-day-cta"]={author=author.name,at=epoch,by=author.name}},
    pvp={[author.name]={honorByArea={world={value=21,at=epoch},battleground={value=31,at=epoch}}}},
}
twoDays.client(4,cached)
local afterDays=twoDays.client(3,{
    roster={},settings={autoGuildSync=true,dev6AutoDefaultsApplied=true},
    ops={{id="two-day-cta",author=author.name,text="Stale CTA",status="ACTIVE",revision=1,created=epoch}},
})
afterDays.event("PLAYER_ENTERING_WORLD")
twoDays.run(65)
local recovered=afterDays.e.KWCDB
assert(not find(recovered.bounties,"two-day-bounty"))
assert(find(recovered.ops,"two-day-cta"))
assert(recovered.pvp[author.name].honorByArea.world.value==21)
print("Two-day restart: cached HK restored; edited bounty missing and deleted CTA still visible")

-- A single requester can overflow an individual responder's actual queue.
local burst=network(2,false)
local responder,requester=burst.client(1),burst.client(2)
local d=responder.e.KWCDB
for j=1,100 do
    d.ops[j]={id="bulk-"..j,author=responder.name,text=string.rep("x",125),
        status="ACTIVE",revision=1,created=epoch}
end
d.deletions={}
for j=1,200 do d.deletions["B:bulk-"..j]={author=responder.name,at=epoch} end
d.raidSignups={events={},responses={}}
for j=1,20 do
    local id="event-"..j
    d.raidSignups.events[id]={id=id,title="Event "..j,when="Tomorrow",author=responder.name,rev=epoch}
    d.raidSignups.responses[id]={[responder.name]={status="Attending",rev=epoch}}
end
d.guildService={cta={},claims={}}
for j=1,100 do
    d.guildService.cta["bulk-"..j]={[responder.name]={zone=true,group=true,last=epoch}}
end
requester.e.KWC.Sync.RequestAll(true)
requester.e.KWC.GuildService.Request()
burst.run(70)
local pending,_,_,dropped=responder.e.KWC.Net.Status()
assert(dropped>0)
print(("Large single-request recovery with service: %d packets / %d bytes in 70s; %d responder drops, %d pending")
    :format(#burst.packets,burst.bytes,dropped,pending))

local idle=network(2,false)
idle.client(1).event("PLAYER_ENTERING_WORLD")
idle.client(2).event("PLAYER_ENTERING_WORLD")
idle.run(120)
local initialCount,initialBytes=#idle.packets,idle.bytes
idle.run(900)
print(("Empty idle baseline: %d packets / %d bytes over 15 minutes after startup")
    :format(#idle.packets-initialCount,idle.bytes-initialBytes))

local function stats(n, from, bytes)
    return #n.packets-from,n.bytes-bytes
end
for _,size in ipairs({2,5,10,25}) do
    local n=network(size,true)
    for i=1,size do n.client(i,nil,{legacy=i>2 and i%5==0}) end
    for _,c in ipairs(n.clients) do
        for j=1,60 do
            c.e.KWCDB.bounties[j]={id="old-"..j,author=n.clients[1].name,text=string.rep("x",125),
                status="ACTIVE",revision=1,created=epoch}
        end
        c.e.KWCDB.deletions={}
        for j=1,25 do c.e.KWCDB.deletions["C:deleted-"..j]={author=n.clients[1].name,at=epoch} end
        c.e.KWCDB.raidSignups={events={},responses={}}
        for j=1,10 do
            c.e.KWCDB.raidSignups.events["raid-"..j]={id="raid-"..j,title="Event "..j,when="Tomorrow",
                author=n.clients[1].name,rev=epoch}
        end
        c.event("PLAYER_ENTERING_WORLD")
        c.event("GUILD_ROSTER_UPDATE")
    end
    n.run(90)
    local login,loginBytes=stats(n,0,0)
    local a,b=#n.packets,n.bytes
    n.run(210)
    local drain,drainBytes=stats(n,a,b)
    a,b=#n.packets,n.bytes
    for _,c in ipairs(n.clients) do c.e.KWC.Sync.RequestAll(true) end
    n.run(300)
    local manual,manualBytes=stats(n,a,b)
    local c=n.clients[1]
    c.e.KWC.Operations.AddBounty("New live bounty")
    local bid=c.e.KWCDB.bounties[1].id
    c.e.KWC.RaidSignup.Create("New live raid","Next week")
    a,b=#n.packets,n.bytes
    for j=1,12 do
        c.world,c.honor=c.world+1,c.honor+1
        c.event("PLAYER_PVP_KILLS_CHANGED")
        c.e.KWC.Operations.AddSighting(bid,"Audit Zone","report "..j)
        n.run(5)
    end
    local active,activeBytes=stats(n,a,b)
    n.run(240)
    local withBoard,withPvP,expectedPvP,withHonor,withRaid,dropped,backlog,errors=0,0,0,0,0,0,0,0
    local raidID
    for id,event in pairs(c.e.KWCDB.raidSignups.events) do
        if event.title=="New live raid" then raidID=id end
    end
    assert(raidID)
    for _,peer in ipairs(n.clients) do
        local q,_,_,d=peer.e.KWC.Net.Status()
        backlog,dropped=backlog+q,dropped+d
        if find(peer.e.KWCDB.bounties,bid) then withBoard=withBoard+1 end
        local stat=peer.e.KWCDB.pvp[c.name]
        if stat and stat.honor and stat.honor.lifetime==c.honor then withHonor=withHonor+1 end
        if peer.e.KWCDB.raidSignups.events[raidID] then withRaid=withRaid+1 end
        if not peer.legacy then
            expectedPvP=expectedPvP+1
            if stat and stat.honorByArea and stat.honorByArea.world.value==c.world then withPvP=withPvP+1 end
        end
        for _,log in ipairs(peer.logs) do if log:find("error:",1,true) then errors=errors+1 end end
    end
    print(("%2d clients | login 90s %d/%d | drain 210s %d/%d | manual 300s %d/%d | active 60s %d/%d | board %d/%d PvP %d/%d lifetime %d/%d raid %d/%d | loss %d dup %d throttle %d queue drop %d pending %d errors %d")
        :format(size,login,loginBytes,drain,drainBytes,manual,manualBytes,active,activeBytes,
            withBoard,size,withPvP,expectedPvP,withHonor,size,withRaid,size,n.loss,n.duplicates,n.throttles,dropped,backlog,errors))
end
