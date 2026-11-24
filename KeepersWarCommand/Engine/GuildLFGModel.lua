local LFG = {}

local activities = {
    Dungeon=true, Questing=true, ["World PvP"]=true, Battlegrounds=true,
    Raid=true, Farming=true, Other=true,
}
local roles = {Tank=true, Healer=true, DPS=true, Any=true}
local minute = 60

local function integer(value, minimum, maximum)
    return type(value) == "number" and value >= minimum and value <= maximum
        and value % 1 == 0
end

local function text(value, limit, required)
    if type(value) ~= "string" or #value > limit or value:find("[%c|]") then return end
    value = value:match("^%s*(.-)%s*$")
    if value ~= "" or not required then return value end
end

local function listingFields(input, now)
    if type(input) ~= "table" then return end
    local name = text(input.name, 64, true)
    local description = text(input.description or "", 160)
    local lifetime = input.lifetimeMinutes or 60
    local groupSize = input.groupSize or 5
    if not name or not description or not activities[input.activity]
        or not integer(input.minLevel, 1, 255)
        or not integer(input.maxLevel, input.minLevel, 255)
        or not integer(groupSize, 2, 40)
        or not integer(input.needed, 1, groupSize - 1)
        or not integer(lifetime, 15, 240)
        or (input.startAt ~= nil and not integer(input.startAt, now, now + 240 * minute))
        or type(input.roles) ~= "table" then return end

    local desired = {}
    for role, enabled in pairs(input.roles) do
        if not roles[role] or enabled ~= true then return end
        desired[role] = true
    end
    if not next(desired)
        or (desired.Any and (desired.Tank or desired.Healer or desired.DPS)) then return end

    return {
        activity=input.activity, name=name, description=description, roles=desired,
        minLevel=input.minLevel, maxLevel=input.maxLevel, needed=input.needed,
        groupSize=groupSize, startAt=input.startAt, lifetimeMinutes=lifetime,
    }
end

LFG.ValidFields = listingFields

local function active(listing, now)
    return listing.status == "open" and listing.expiresAt > now
end

-- Callers own persistence and must resolve these IDs at operation time. This
-- module neither accepts packets nor interprets guild/player display names.
function LFG.Open(storage, guildID, actorID, clock)
    assert(type(guildID) == "string" and guildID ~= "", "guild ID required")
    assert(type(actorID) == "string" and actorID ~= "", "character ID required")
    storage[guildID] = storage[guildID] or {listings={}, sequence=0}
    local guild = storage[guildID]
    local board = {}

    function board.Create(input)
        local now = clock()
        local fields = listingFields(input, now)
        if not fields then return nil, "invalid listing" end
        guild.sequence = guild.sequence + 1
        local id = actorID .. "/" .. guild.sequence
        guild.listings[id] = {
            id=id, owner=actorID, createdAt=now, updatedAt=now, revision=1,
            status="open", generation=1, expiresAt=now + fields.lifetimeMinutes * minute,
            fields=fields, interest={},
        }
        return id
    end

    function board.Update(id, expectedRevision, action, input)
        local listing = guild.listings[id]
        if not listing or listing.owner ~= actorID then return false, "owner required" end
        if listing.revision ~= expectedRevision then return false, "listing changed" end
        if listing.status == "deleted" then return false, "listing deleted" end
        local now = clock()
        if action == "edit" then
            if not active(listing, now) then return false, "listing inactive" end
            local fields = listingFields(input, now)
            if not fields then return false, "invalid listing" end
            listing.fields = fields
            listing.expiresAt = math.min(listing.expiresAt, now + fields.lifetimeMinutes * minute)
        elseif action == "close" then
            if not active(listing, now) then return false, "listing inactive" end
            listing.status = "closed"
            listing.interest = {}
        elseif action == "delete" then
            listing.status = "deleted"
            listing.fields, listing.interest = nil, nil
        elseif action == "renew" then
            if listing.status ~= "open" then return false, "listing closed" end
            if not active(listing, now) then
                listing.interest = {}
                listing.generation = (listing.generation or 1) + 1
            end
            listing.expiresAt = now + listing.fields.lifetimeMinutes * minute
            if listing.fields.startAt and listing.fields.startAt < now then listing.fields.startAt = nil end
        else
            return false, "unknown action"
        end
        listing.updatedAt = now
        listing.revision = listing.revision + 1
        return true
    end

    function board.SetInterest(id, interested)
        local listing = guild.listings[id]
        if not listing or not active(listing, clock()) or listing.owner == actorID
            or type(interested) ~= "boolean" then return false end
        if (listing.interest[actorID] == true) == interested then return false end
        listing.interest[actorID] = interested or nil
        return true
    end

    function board.Browse(filter)
        filter = filter or {}
        local rows, now = {}, clock()
        for _, listing in pairs(guild.listings) do
            local mine = listing.owner == actorID
            local isActive = active(listing, now)
            local fields = listing.fields
            if fields and ((filter.mine and mine) or (not filter.mine and isActive))
                and (not filter.activity or fields.activity == filter.activity)
                and (not filter.level or (fields.minLevel <= filter.level and fields.maxLevel >= filter.level))
                and (not filter.role or fields.roles.Any or fields.roles[filter.role]) then
                local row = {}
                for key, value in pairs(fields) do
                    if key ~= "roles" then row[key] = value end
                end
                row.roles = {}
                for role in pairs(fields.roles) do row.roles[role] = true end
                row.id, row.owner, row.mine = listing.id, listing.owner, mine
                row.createdAt, row.expiresAt = listing.createdAt, listing.expiresAt
                row.revision = listing.revision
                row.status = isActive and "open" or (listing.status == "open" and "expired" or listing.status)
                row.interested = listing.interest[actorID] == true
                if mine then
                    row.interestedMembers = {}
                    for member in pairs(listing.interest) do
                        table.insert(row.interestedMembers, member)
                    end
                    table.sort(row.interestedMembers)
                end
                table.insert(rows, row)
            end
        end
        table.sort(rows, function(a, b)
            if a.createdAt == b.createdAt then return a.id < b.id end
            return a.createdAt > b.createdAt
        end)
        return rows
    end

    return board
end

if KWC then KWC.GuildLFGModel = LFG end
return LFG
