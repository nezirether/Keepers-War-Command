-- Security checks through the actual production event handlers.
local network, packet, find = assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
local n = network(4, false)
local owner, peer, member, other = n.client(1), n.client(2), n.client(3), n.client(4)
local A, B, C = owner.e, peer.e, member.e

A.KWC.RaidSignup.Create("Raid", "Tomorrow")
A.KWC.Operations.CreateCTA("Defense")
local raid = next(A.KWCDB.raidSignups.events)
local cta = A.KWCDB.ops[1].id
n.run(20)
local t = B.time()
local rs = B.KWCDB.raidSignups.responses[raid]
packet(peer, "KWRS1", ("RS|%s|%s|Absent|%d"):format(raid, owner.name, t), member)
assert(not rs[owner.name], "another member changed the owner's RSVP")
packet(peer, "KWRS1", ("RS|%s|%s|Attending|%d"):format(raid, member.name, t), member)
assert(rs[member.name].status == "Attending")
packet(peer, "KWRS1", ("RS|%s|%s|Absent|%d"):format(raid, member.name, t-1), member)
assert(rs[member.name].status == "Attending", "stale RSVP replaced current status")

local entry = assert(find(B.KWCDB.ops, cta))
packet(peer, "KWC4", ("E|%s|assign|L|%s|%s"):format(cta, owner.name, member.name), owner)
assert(entry.commandEvents and entry.commandEvents.assign)
packet(peer, "KWC4", ("E|%s|early|P|%s|%s"):format(cta, member.name, owner.name), member)
assert(not entry.commandEvents.early and B.KWC.Operations.IsCommander(entry, owner.name))
n.roster[owner.name:lower()].rankIndex = 3
assert(not B.KWC.IsSenderOfficer(owner.name.."-Realm"), "saved rank survived demotion")
n.roster[owner.name:lower()].rankIndex = 1

local resolved = ("S|C|%s|%s|RESOLVED|3|%d|closed"):format(cta, owner.name, t)
local competing = ("S|C|%s|%s|ACTIVE|3|%d|competing"):format(cta, owner.name, t)
packet(peer, "KWC4", resolved, owner)
packet(peer, "KWC4", competing, owner)
packet(member, "KWC4", competing, owner)
packet(member, "KWC4", resolved, owner)
assert(entry.status == "RESOLVED" and find(C.KWCDB.ops,cta).status == entry.status)
packet(peer, "KWC3", "2;STATUS;CTA,"..cta..",ACTIVE", owner)
packet(peer, "KWC3", "2;EDIT;CTA,"..cta..":changed", owner)
assert(entry.status == "RESOLVED" and entry.text == "closed")
B.KWC.Operations.Respond(cta, "Coming")
packet(peer, "KWC3", "2;RESPONSE;"..cta..":Coming", member)
packet(peer, "KWC3", "2;RESPONSE;unknown:Coming", member)
assert(not B.KWCDB.responses[cta] and not B.KWCDB.responses.unknown)

local sight = {id="sight", author=owner.name, status="ACTIVE"}
B.KWCDB.bounties[1] = sight
for _ = 1, 30 do packet(peer, "KWC3", "2;SIGHT;sight:Audit Zone,note", member) end
assert(#sight.sightings == 1, "duplicate sightings consumed history")

packet(peer, "KWC3", "2;HONOR;9000", member)
packet(peer, "KWC3", "2;HONOR;10", member)
packet(peer, "KWC3", "2;ACHPTS;45", member)
packet(peer, "KWC3", "2;ACHPTS;5", member)
local p = B.KWCDB.pvp[member.name]
assert(p.honor.lifetime == 9000 and p.achievementPoints == 45)
print("PASS: guild RSVP and command authorization, revision convergence, replay guards, and stale statistics")
