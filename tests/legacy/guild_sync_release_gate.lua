-- Current release criteria, through real addon event handlers.
local network, packet, find = assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
local failures = {}
local function check(name, fn)
    local ok, err = pcall(fn)
    print((ok and "PASS: " or "FAIL: ") .. name .. (ok and "" or " (" .. tostring(err) .. ")"))
    if not ok then failures[#failures+1] = name end
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local clone = {}
    for k, v in pairs(value) do clone[k] = copy(v) end
    return clone
end
local scoped = {scoped=true}
check("delete-before-create survives reload and blocks both board protocols", function()
    local n = network(3,false)
    local author, peer, other = n.client(1,nil,scoped), n.client(2,nil,scoped), n.client(3,nil,scoped)
    local stamp = peer.e.time()
    for _, kind in ipairs({"B","C"}) do
        packet(peer,"KWC4",("D|%s|gone|%s|%d"):format(kind,author.name,stamp),other)
        assert(not peer.e.KWC.Sync.IsBoardDeleted(kind,"gone",author.name), "foreign owner tombstone")
        packet(peer,"KWC4",("D|%s|gone|%s|%d"):format(kind,author.name,stamp),author)
    end
    peer.online=false
    local reload=n.client(2,copy(peer.e.KWCDB),scoped)
    for _, kind in ipairs({"B","C"}) do
        assert(reload.e.KWC.Sync.IsBoardDeleted(kind,"gone",author.name))
        packet(reload,"KWC4",("S|%s|gone|%s|ACTIVE|8|%d|stale"):format(kind,author.name,stamp),author)
        packet(reload,"KWC3",("2;%s;gone:stale"):format(kind=="B" and "BOUNTY" or "CTA"),author)
    end
    assert(not find(reload.e.KWCDB.bounties,"gone") and not find(reload.e.KWCDB.ops,"gone"))
end)
check("legacy data is preserved without adoption and guild scopes survive restart", function()
    local n=network(2,false)
    local legacy={roster={},bounties={{id="legacy"}},raidSignups={events={old={id="old"}},responses={}},settings={pitch="keep"}}
    local a=n.client(1,legacy,scoped)
    local db=a.e.KWCDB
    assert(db.unscopedGuildArchive.bounties[1].id=="legacy")
    assert(db.unscopedGuildArchive.raidSignups.events.old and db.settings.pitch=="keep")
    assert(#db.bounties==0 and not db.raidSignups)
    a.e.KWC.Operations.AddBounty("Guild one")
    a.e.KWC.RaidSignup.Create("Guild one raid","Tomorrow")
    local id=db.bounties[1].id
    local peer=n.client(2,nil,scoped)
    packet(a,"KWC3","2;HONOR;92",peer)
    assert(db.pvp[peer.name].honor.lifetime==92)
    a.guildID=2
    a.event("PLAYER_GUILD_UPDATE")
    assert(#db.bounties==0 and not db.raidSignups and not db.pvp[peer.name])
    assert(db.pvp[a.name].honor.lifetime==a.honor, "local native HKs should be collected in the new scope")
    a.e.KWC.Operations.AddBounty("Guild two")
    local other=db.bounties[1].id
    a.online=false
    local restart=n.client(1,copy(db),scoped)
    assert(find(restart.e.KWCDB.bounties,id) and not find(restart.e.KWCDB.bounties,other))
    assert(next(restart.e.KWCDB.raidSignups.events))
    restart.guildID=2
    restart.event("PLAYER_GUILD_UPDATE")
    assert(find(restart.e.KWCDB.bounties,other) and not find(restart.e.KWCDB.bounties,id))
end)
local function raidFixture()
    local n=network(4,false)
    local a,b,r,m=n.client(1,nil,scoped),n.client(2,nil,scoped),n.client(3,nil,scoped),n.client(4,nil,scoped)
    r.online=false
    a.e.KWC.RaidSignup.Create("Audit raid","Tomorrow")
    n.run(10)
    local id=next(a.e.KWCDB.raidSignups.events)
    m.e.KWC.RaidSignup.Respond(id,"Attending")
    n.run(10)
    assert(b.e.KWCDB.raidSignups.events[id] and b.e.KWCDB.raidSignups.responses[id][m.name])
    return n,a,b,r,m,id
end
check("Raid Sign-Ups catch up when creator and RSVP author are online", function()
    local n,_,_,r,m,id=raidFixture()
    r.online=true
    assert(r.e.KWC.RaidSignup.Sync(true))
    n.run(20)
    local raid=r.e.KWCDB.raidSignups
    assert(raid and raid.events[id], "event missing")
    assert(raid.responses[id][m.name] and raid.responses[id][m.name].status=="Attending", "RSVP missing")
end)
check("Raid Sign-Ups catch up after the creator disconnects", function()
    local n,a,_,r,_,id=raidFixture()
    a.online=false
    r.online=true
    assert(r.e.KWC.RaidSignup.Sync(true))
    n.run(20)
    local raid=r.e.KWCDB.raidSignups
    assert(raid and raid.events[id], "officer holding the event cannot restore it")
end)
check("Raid Sign-Ups catch up after the RSVP author disconnects", function()
    local n,_,_,r,m,id=raidFixture()
    m.online=false
    r.online=true
    assert(r.e.KWC.RaidSignup.Sync(true))
    n.run(20)
    local raid=r.e.KWCDB.raidSignups
    assert(raid and raid.events[id], "event missing")
    assert(raid.responses[id][m.name], "cached RSVP cannot be restored")
end)
check("legacy RSVP sender cannot impersonate a guildmate", function()
    local n,a,b,_,m,id=raidFixture()
    packet(b,"KWRS1",("RS|%s|%s|Absent|%d"):format(id,a.name,b.e.time()),m)
    assert(not b.e.KWCDB.raidSignups.responses[id][a.name])
end)
check("both raid authors offline: edits, cancellation, deletion and withdrawal recover", function()
    local n,a,b,r,m,id=raidFixture()
    local A,B,R=a.e,b.e,r.e
    assert(A.KWC.RaidSignup.Edit(id,"Updated raid","Friday"))
    local oldRev=B.KWCDB.raidSignups.responses[id][m.name].rev
    m.e.KWC.RaidSignup.Respond(id,"Withdrawn")
    assert(A.KWC.RaidSignup.Create("Cancelled","Tomorrow"))
    assert(A.KWC.RaidSignup.Create("Deleted","Tomorrow"))
    local cancelled,deleted
    for key,event in pairs(A.KWCDB.raidSignups.events) do
        if event.title=="Cancelled" then cancelled=key end
        if event.title=="Deleted" then deleted=key end
    end
    A.KWC.RaidSignup.Cancel(cancelled)
    assert(A.KWC.RaidSignup.Delete(deleted))
    n.run(15)
    a.online=false;m.online=false;r.online=true
    assert(R.KWC.RaidSignup.Sync(true))
    n.run(25)
    local raid=R.KWCDB.raidSignups
    assert(raid.events[id].title=="Updated raid" and raid.events[id].relayedBy==b.name.."-Realm")
    assert(raid.events[cancelled].cancelled and raid.events[deleted].deleted)
    assert(raid.responses[id][m.name].status=="Withdrawn")
    packet(r,"KWRS1",("RS|%s|%s|Attending|%d"):format(id,m.name,oldRev),m)
    packet(r,"KWRS1",("EV|%s|Old|Tomorrow|%s|%d|0"):format(deleted,a.name,R.time()),a)
    assert(raid.responses[id][m.name].status=="Withdrawn" and raid.events[deleted].deleted)
end)
check("authenticated early RSVP drains only after its matching event", function()
    local n=network(3,false)
    local a,b,m=n.client(1,nil,scoped),n.client(2,nil,scoped),n.client(3,nil,scoped)
    local t=b.e.time()
    packet(b,"KWRS1",("RS|early|%s|Absent|%d"):format(a.name,t),m)
    packet(b,"KWRS1",("RS|early|%s|Attending|%d"):format(m.name,t),m)
    packet(b,"KWRS1",("EV|other|Other|Tomorrow|%s|%d|0"):format(a.name,t),a)
    assert(not b.e.KWCDB.raidSignups.responses.other[m.name])
    packet(b,"KWRS1",("EV|early|Raid|Tomorrow|%s|%d|0"):format(a.name,t),a)
    assert(b.e.KWCDB.raidSignups.responses.early[m.name].status=="Attending")
    assert(not b.e.KWCDB.raidSignups.responses.early[a.name])
end)
check("unavailable guild ID hides previous records and blocks transmission", function()
    local n=network(2,false)
    local a,b=n.client(1,nil,scoped),n.client(2,nil,scoped)
    assert(a.e.KWC.RaidSignup.Create("Private raid","Tomorrow"))
    a.e.KWC.Operations.AddBounty("Private board")
    local db=a.e.KWCDB
    local id=db.bounties[1].id
    a.guildID=false
    a.event("PLAYER_GUILD_UPDATE")
    assert(#db.bounties==0 and not db.raidSignups)
    assert(not a.e.KWC.Net.Send("KWC3","2;HONOR;100","GUILD"))
    packet(a,"KWC3","2;HONOR;99999",b)
    assert(not db.pvp[b.name])
    n.run(10)
    for _,sent in ipairs(n.packets) do assert(sent.from~=a.name,"queued previous-guild records leaked") end
    a.guild=false
    a.event("PLAYER_GUILD_UPDATE")
    a.guild=true;a.guildID=2
    a.event("PLAYER_GUILD_UPDATE")
    assert(#db.bounties==0 and not db.raidSignups)
    a.guildID=1
    a.event("PLAYER_GUILD_UPDATE")
    assert(find(db.bounties,id) and next(db.raidSignups.events))
    a.online=false
    local legacy=n.client(1,copy(db),{scoped=false})
    assert(#legacy.e.KWCDB.bounties==0 and not legacy.e.KWCDB.raidSignups)
    legacy.e.C_Club={GetGuildClubId=function() return 1 end}
    legacy.event("INITIAL_CLUBS_LOADED")
    assert(find(legacy.e.KWCDB.bounties,id))
end)
for _,size in ipairs({2,5,10,25,50}) do
    check(size.." clients: officer recovers raid event and RSVP",function()
        local n=network(math.max(3,size),true)
        local clients={}
        for i=1,math.max(3,size) do
            clients[i]=n.client(i,nil,{scoped=true,legacy=i>2 and i%5==0})
        end
        local a,b,r=clients[1],clients[2],clients[#clients]
        r.online=false
        assert(a.e.KWC.RaidSignup.Create("Scale test","Tomorrow"))
        local id=next(a.e.KWCDB.raidSignups.events)
        a.e.KWC.RaidSignup.Respond(id,"Attending")
        n.run(15)
        assert(b.e.KWCDB.raidSignups.events[id] and b.e.KWCDB.raidSignups.responses[id][a.name])
        a.online=false;r.online=true
        local packets,bytes=#n.packets,n.bytes
        assert(r.e.KWC.RaidSignup.Sync(true))
        local completed
        for elapsed=1,110 do
            n.run(1)
            local d=r.e.KWCDB.raidSignups
            if d and d.events[id] and d.responses[id][a.name] then completed=elapsed;break end
            if elapsed%36==0 then r.e.KWC.RaidSignup.Sync(true) end
        end
        local drops=0
        for _,client in ipairs(clients) do
            local _,_,_,d=client.e.KWC.Net.Status()
            drops=drops+d
        end
        print(("%d clients: %ss, %d packets, %d bytes, %d queue drops")
            :format(size,tostring(completed),#n.packets-packets,n.bytes-bytes,drops))
        assert(completed and drops==0)
    end)
end
assert(#failures==0,"Release gate failed: "..table.concat(failures,", "))
