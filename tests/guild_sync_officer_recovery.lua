-- Acceptance budget for the small recovery fixture: <= 24 directed board
-- responses per request, <= 100 board packets and <= 15 KB over 120 seconds,
-- no queue drops, and both records recovered when an eligible holder exists.
local network, packet, find = assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
for _,size in ipairs({2,5,10,25,50}) do
    -- The 2-online-client case needs a third character: the offline creator.
    local count=math.max(3,size)
    local n=network(count,true)
    for i=1,count do n.client(i,nil,{scoped=true,legacy=i>2 and i%5==0}) end
    local author,officer,receiver=n.clients[1],n.clients[2],n.clients[count]
    receiver.online=false
    local A=author.e
    A.KWC.Operations.AddBounty("Recovery bounty")
    A.KWC.Operations.AddBounty("Deleted bounty")
    A.KWC.Operations.CreateCTA("Resolved CTA")
    local deleted, bid, cid=A.KWCDB.bounties[1].id,A.KWCDB.bounties[2].id,A.KWCDB.ops[1].id
    n.run(20)
    A.KWC.Operations.Delete("BOUNTY",deleted)
    A.KWC.Operations.ChangeStatus("CTA",cid,"RESOLVED")
    n.run(20)
    -- Establish the verified holder before simulating loss on recovery.
    -- A missing live deletion is retried as the original sender here.
    if not officer.e.KWCDB.deletions["B:"..deleted] then
        local mark=A.KWCDB.deletions["B:"..deleted]
        packet(officer,"KWC4",("D|B|%s|%s|%d"):format(deleted,mark.author,mark.at),author)
    end
    assert(find(officer.e.KWCDB.bounties,bid) and officer.e.KWCDB.deletions["B:"..deleted])
    assert(find(officer.e.KWCDB.ops,cid).status=="RESOLVED")
    author.online=false
    receiver.online=true
    local R=receiver.e
    local first,firstBytes=#n.packets,n.bytes
    receiver.event("PLAYER_ENTERING_WORLD")
    local completed
    for elapsed=1,120 do
        n.run(1)
        if not completed and find(R.KWCDB.bounties,bid) and find(R.KWCDB.ops,cid) then completed=elapsed end
        if elapsed%31==0 then R.KWC.Sync.Request(true) end
    end
    assert(completed, "officer recovery failed at "..size)
    assert(find(R.KWCDB.ops,cid).status=="RESOLVED")
    assert(find(R.KWCDB.bounties,bid).relayedBy==officer.name.."-Realm")
    assert(not R.KWC.Operations.IsCommander(find(R.KWCDB.ops,cid),author.name))
    packet(receiver,"KWC3","2;BOUNTY;"..deleted..":stale",author)
    assert(not find(R.KWCDB.bounties,deleted), "offline deletion resurrected")
    local request
    local packets,bytes,drops=0,0,0
    for i=first+1,#n.packets do
        local p=n.packets[i]
        if p.prefix=="KWC4" then
            packets=packets+1
            bytes=bytes+#p.message+#p.prefix
            if p.from==receiver.name then request=p.message:match("^RQ|1|(%d+%-%d+)|%d+$") or request end
        end
    end
    for _,client in ipairs(n.clients) do
        local _,_,_,d=client.e.KWC.Net.Status()
        drops=drops+d
    end
    assert(packets<=100 and bytes<=15000 and drops==0)
    local allPackets,allBytes=#n.packets-first,n.bytes-firstBytes
    assert(request)
    local forged="RS|1|"..request.."|S|B|forged|"..author.name.."|ACTIVE|1|"..R.time().."|fake"
    packet(receiver,"KWC4",forged,receiver,"WHISPER")
    assert(not find(R.KWCDB.bounties,"forged"))
    local saved=R.KWCDB
    receiver.guildID=2
    receiver.event("PLAYER_GUILD_UPDATE")
    assert(#saved.bounties==0 and #saved.ops==0)
    packet(receiver,"KWC4",forged,officer,"WHISPER")
    assert(#saved.bounties==0)
    receiver.guildID=1
    receiver.event("PLAYER_GUILD_UPDATE")
    assert(find(saved.bounties,bid))
    receiver.online=false
    local reload=n.client(count,saved,{scoped=true})
    assert(find(reload.e.KWCDB.bounties,bid) and not find(reload.e.KWCDB.bounties,deleted))
    print(("%d clients | %ds | board %d packets/%d bytes | all %d packets/%d bytes | %d drops"):format(size,completed,packets,bytes,allPackets,allBytes,drops))
end
local n=network(2,false)
local a,b=n.client(1,nil,{scoped=true}),n.client(2,{roster={},bounties={{id="legacy"}}},{scoped=true})
assert(#b.e.KWCDB.bounties==0 and b.e.KWCDB.unscopedGuildArchive.bounties[1].id=="legacy")
local stamp=b.e.time()
packet(b,"KWC4",("D|B|unseen|%s|%d"):format(a.name,stamp),a)
packet(b,"KWC4",("S|B|unseen|%s|ACTIVE|1|%d|stale"):format(a.name,stamp),a)
assert(not find(b.e.KWCDB.bounties,"unseen"))
