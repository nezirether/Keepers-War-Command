-- Run from the repository root with Lua 5.1.
local LFG = assert(loadfile("KeepersWarCommand/GuildLFGModel.lua"))()
local storage, now = {}, 1000
local function clock() return now end
local function open(actor, guild) return LFG.Open(storage, guild or "guild-a", actor, clock) end
local owner, member = open("leader-realm"), open("member-realm")

local fields = {
    activity="Dungeon", name="Scarlet Monastery", minLevel=35, maxLevel=40,
    roles={Tank=true, DPS=true}, needed=2, description="Library run",
}
local id = assert(owner.Create(fields))
local rows = member.Browse({activity="Dungeon", level=40, role="Tank"})
assert(#rows == 1 and rows[1].id == id and rows[1].owner == "leader-realm")
assert(rows[1].expiresAt == now + 3600 and rows[1].createdAt == now)
assert(rows[1].groupSize - rows[1].needed == 3)
assert(#member.Browse({level=41}) == 0 and #member.Browse({role="Healer"}) == 0)
assert(#member.Browse({activity="Raid"}) == 0 and #member.Browse({mine=true}) == 0)
assert(#open("leader-otherrealm").Browse({mine=true}) == 0)
assert(#open("leader-realm", "guild-b").Browse() == 0)

-- Views and caller-owned input tables cannot change the stored record.
rows[1].roles.Healer = true
fields.roles.Healer = true
assert(#member.Browse({role="Healer"}) == 0)
assert(not owner.SetInterest(id, true))
assert(member.SetInterest(id, true))
assert(not member.SetInterest(id, true))
local mine = owner.Browse({mine=true})[1]
assert(mine.mine and mine.interestedMembers[1] == "member-realm")
assert(member.Browse()[1].interested and not member.Browse()[1].interestedMembers)
assert(member.SetInterest(id, false) and not member.SetInterest(id, false))
assert(#owner.Browse({mine=true})[1].interestedMembers == 0)

for _, action in ipairs({"edit", "close", "delete", "renew"}) do
    assert(not member.Update(id, 1, action, fields))
end
fields.roles = {Any=true}
fields.name = "Armory run"
fields.lifetimeMinutes = 15
assert(owner.Update(id, 1, "edit", fields))
assert(not owner.Update(id, 1, "close"))
assert(member.Browse({role="Healer"})[1].name == "Armory run")
assert(member.SetInterest(id, true))
now = now + 15 * 60
assert(#member.Browse() == 0)
assert(owner.Browse({mine=true})[1].status == "expired")
assert(not member.SetInterest(id, false))
assert(owner.Update(id, 2, "renew"))
assert(not member.Browse()[1].interested and member.Browse()[1].revision == 3)
assert(owner.Update(id, 3, "close"))
assert(not owner.Update(id, 4, "renew"))
assert(owner.Update(id, 4, "delete"))
assert(not owner.Update(id, 4, "edit", fields))
assert(not owner.Update(id, 5, "renew"))

-- Model reopening with the caller's persisted table.
local reopened = open("leader-realm")
assert(#reopened.Browse({mine=true}) == 0)
assert(storage["guild-a"].listings[id].status == "deleted")
assert(storage["guild-a"].listings[id].fields == nil)
fields.startAt = now + 30 * 60
fields.lifetimeMinutes = 240
local second = assert(reopened.Create(fields))
assert(second ~= id and reopened.Browse()[1].startAt == fields.startAt)
for _, lifetime in ipairs({14, 241, 15.5, "60"}) do
    fields.lifetimeMinutes = lifetime
    assert(not reopened.Create(fields))
end
fields.lifetimeMinutes = 60
fields.roles = {Any=true, Healer=true}
assert(not reopened.Create(fields))
fields.roles = {Tank=true}
fields.description = "|Hunsafe|h"
assert(not reopened.Create(fields))
print("PASS: local Guild LFG creation, validation, ownership, revisions, filtering, interest, expiry, renewal, deletion, and guild partitioning")
