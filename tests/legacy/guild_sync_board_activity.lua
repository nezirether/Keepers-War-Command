local network, packet, find = assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
local scoped = {scoped=true}
local function announcements(client)
    local count=0
    for _,line in ipairs(client.logs) do
        if line:find("Bounty sighting:",1,true) then count=count+1 end
    end
    return count
end

for _,size in ipairs({2,5,10,25,50}) do
    -- Two online clients after both authors disconnect needs four characters.
    local n = network(math.max(4,size), false)
    local author = n.client(1,nil,scoped)
    local officer = n.client(2,nil,scoped)
    local receiver = n.client(3,nil,scoped)
    local member = n.client(4,nil,scoped)
    for i=5,size do n.client(i,nil,scoped) end
    receiver.online=false
    local A, B, R, M = author.e, officer.e, receiver.e, member.e
    A.KWC.Operations.QuickBounty("Offline target","A reason","10g")
    A.KWC.Operations.CreateCTA("Offline operation",{zone="Harbor"})
    local bid,cid=A.KWCDB.bounties[1].id,A.KWCDB.ops[1].id
    n.run(15)
    assert(find(M.KWCDB.ops,cid).details.zone=="Harbor")
    assert(A.KWC.Operations.AssignLieutenant(cid,member.name))
    M.KWC.Operations.AddSighting(bid,"Harbor","Latest location")
    M.KWC.Operations.ClaimBounty(bid)
    M.KWC.Operations.Respond(cid,"Coming")
    M.KWC.Operations.Respond(cid,"Maybe")
    member.zone="Harbor"
    member.event("ZONE_CHANGED_NEW_AREA")
    A.KWC.GuildService.Approve(bid,member.name)
    n.run(25)
    local cachedBounty,cachedCTA=find(B.KWCDB.bounties,bid),find(B.KWCDB.ops,cid)
    assert(cachedCTA.commandEvents and next(cachedCTA.commandEvents))
    assert(cachedBounty.details.reward=="10g" and #cachedBounty.sightings==1)
    assert(announcements(member)==1 and announcements(officer)==1)
    packet(officer,"KWC4",("W|B|%s|S|%s|%d|Harbor|Forged"):format(bid,member.name,B.time()),author)
    assert(announcements(officer)==1 and #cachedBounty.sightings==1)
    assert(B.KWCDB.responses[cid][member.name:lower()]=="Maybe")
    local revision=cachedCTA.responseRevisions[member.name:lower()]
    local stale=("W|C|%s|R|%s|%d|Coming"):format(cid,member.name,revision-1)
    packet(officer,"KWC4",stale,member)
    packet(officer,"KWC4",stale:gsub("Coming$","Busy"),author)
    assert(B.KWCDB.responses[cid][member.name:lower()]=="Maybe")
    assert(B.KWC.GuildService.CTARecords(cid)[member.name].zone)
    author.online,member.online=false,false
    receiver.online=true
    n.impaired=size>=10
    local first,bytes=#n.packets,n.bytes
    receiver.event("PLAYER_ENTERING_WORLD")
    local elapsed
    for seconds=1,120 do
        n.run(1)
        local bounty,cta=find(R.KWCDB.bounties,bid),find(R.KWCDB.ops,cid)
        local approvals=(R.KWCDB.guildService or {}).claims or {}
        if bounty and bounty.details and bounty.details.reward=="10g" and bounty.sightings and #bounty.sightings==1
            and bounty.claims and bounty.claims[member.name:lower()]
            and cta and cta.details and cta.details.zone=="Harbor" and cta.relayedLieutenants
            and cta.relayedLieutenants[author.name:lower()]
            and R.KWCDB.responses[cid] and R.KWCDB.responses[cid][member.name:lower()]=="Maybe"
            and R.KWC.GuildService.CTARecords(cid)[member.name]
            and approvals[bid] and approvals[bid][member.name] then
            elapsed=seconds
            assert(cta.relayedLieutenants[author.name:lower()].target==member.name:lower())
            assert(not cta.commandEvents and not R.KWC.Operations.IsCommander(cta,author.name))
            break
        end
    end
    assert(elapsed,"offline board activity failed at "..size.." clients")
    assert(announcements(receiver)==0,"recovery replayed old sighting in chat")
    local drops,boardPackets=0,0
    for _,client in ipairs(n.clients) do
        local _,_,_,d=client.e.KWC.Net.Status()
        drops=drops+d
    end
    for index=first+1,#n.packets do
        if n.packets[index].prefix=="KWC4" then boardPackets=boardPackets+1 end
    end
    assert(drops==0 and boardPackets<=100 and n.bytes-bytes<=15000)
    print(("%d clients | %ds | %d board packets | %d total packets/%d bytes | %d drops")
        :format(size,elapsed,boardPackets,#n.packets-first,n.bytes-bytes,drops))
end

-- An authorized parent's delayed appearance drains its pending response.
-- Changing guild scope must drop the queued response, even for the same ID.
local n=network(4,false)
local owner,receiver,member=n.client(1,nil,scoped),n.client(2,nil,scoped),n.client(3,nil,scoped)
local E=receiver.e
local t=E.time()
local function respond(id)
    packet(receiver,"KWC4",("W|C|%s|R|%s|%d|Coming"):format(id,member.name,t),member)
end
local function create(id)
    packet(receiver,"KWC4",("S|C|%s|%s|ACTIVE|0|%d|Test"):format(id,owner.name,t),owner)
end
respond("early")
assert(not E.KWCDB.responses.early)
create("early")
assert(E.KWCDB.responses.early[member.name:lower()]=="Coming")
local legacyCommand=("E|early|legacy-lieutenant|L|%s|%s|0"):format(owner.name,member.name)
packet(receiver,"KWC4",legacyCommand,owner)
local early=assert(find(E.KWCDB.ops,"early"))
assert(early.commandEvents["legacy-lieutenant"])
packet(receiver,"KWC4",legacyCommand,member)
assert(early.lieutenants[owner.name]==member.name)
respond("switch")
receiver.guildID=2
receiver.event("PLAYER_GUILD_UPDATE")
owner.guildID,member.guildID=2,2
create("switch")
assert(not E.KWCDB.responses.switch)

-- A long escaped description and a maximum-width guild ID must fit in
-- one recovery packet. Structured CTA values should survive that roundtrip.
local large=network(3,false)
local a,b,r=large.client(1,nil,scoped),large.client(2,nil,scoped),large.client(3,nil,scoped)
for _,c in ipairs(large.clients) do
    c.guildID="123456789012345678901234"
    c.event("PLAYER_GUILD_UPDATE")
end
r.online=false
a.e.KWC.Operations.CreateCTA(string.rep("%",155),{zone="Harbor",horde=0,alliance=123,priority="HIGH"})
local id=a.e.KWCDB.ops[1].id
large.run(10)
assert(find(b.e.KWCDB.ops,id).details.alliance==123)
a.online,r.online=false,true
r.event("PLAYER_ENTERING_WORLD")
large.run(35)
local decoded=assert(find(r.e.KWCDB.ops,id))
assert(decoded.details.horde==0 and decoded.details.alliance==123 and decoded.details.priority=="HIGH")

print("PASS: board activity recovery, authority, replay, dependency ordering and guild isolation")
