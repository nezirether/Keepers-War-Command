-- Measure the remaining offline recovery gap through the real send/receive path.
local network, _, find = assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
for _, size in ipairs({2,5,10,25,50}) do
    local n = network(size, true)
    for i = 1, size do n.client(i, nil, {legacy=i>2 and i%5==0}) end
    local author = n.clients[1]
    local returning = n.clients[size]
    returning.online = false
    author.e.KWC.Operations.AddBounty("Offline recovery probe")
    author.e.KWC.Operations.CreateCTA("Offline CTA probe")
    local bid, cid = author.e.KWCDB.bounties[1].id, author.e.KWCDB.ops[1].id
    n.run(30)
    local holders = 0
    for i = 2, size-1 do
        local db = n.clients[i].e.KWCDB
        if find(db.bounties,bid) and find(db.ops,cid) then holders = holders+1 end
    end
    author.online = false
    returning.online = true
    local before, bytes = #n.packets, n.bytes
    returning.event("PLAYER_ENTERING_WORLD")
    n.run(120)
    local db = returning.e.KWCDB
    print(("%d clients | verified holders %d | bounty %s | CTA %s | recovery packets %d | bytes %d")
        :format(size, holders, tostring(find(db.bounties,bid) ~= nil),
            tostring(find(db.ops,cid) ~= nil), #n.packets-before, n.bytes-bytes))
end
