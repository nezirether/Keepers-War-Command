-- AttendanceSync: sharing attendance days and the roster over KRT.Comms.
--
-- Replacement is wholesale rather than merged: an accepted day or roster
-- overwrites the local one entirely. A cell-by-cell merge taking the higher
-- status can never lower a value, which makes corrections impossible to
-- propagate, so the spec rules it out.
--
-- This module validates incoming attendance days itself. Incoming rosters pass
-- through the roster's shared validation and replacement boundary, so local
-- edits, imports, and synchronization enforce the same invariants.
--
-- Headless-load safety: no frame, timer or event API is touched at load, and
-- registration is an explicit RegisterHandlers call rather than a load side
-- effect. The two sync settings arrive as the injected confirmBeforeSyncing
-- field and an OnReadyCheck parameter, so nothing here reads KRT:GetSetting.

local KRT = KeepersRaidTools
local AttendanceSync = {}
KRT.AttendanceSync = AttendanceSync
local RosterValidation = KRT.RosterValidation

local INVENTORY_REQUEST = "attInventoryRequest"
local INVENTORY_RESPONSE = "attInventoryResponse"
local PULL_REQUEST = "attPullRequest"
local PULL_RESPONSE = "attPullResponse"
local PULL_MISSING = "attPullMissing"
local DAY_PUSH = "attDayPush"
local ROSTER_PUSH = "attRosterPush"
local ROSTER_REQUEST = "attRosterRequest"

local ISO_DAY_PATTERN = "^%d%d%d%d%-%d%d%-%d%d$"
-- Reply deadlines. Requests go through the shared KWC queue (one send per 0.85 s,
-- shared with guild sync), so the request itself may wait behind a backlog. The
-- REPLY_WINDOW therefore starts when the request's last piece is actually sent
-- (the Comms onComplete callback). On the responder, replies are sent on every other
-- queue turn ahead of other traffic (Network.lua replyTurn), so a reply waits only for
-- replies queued before it. The reply budget holds at most 64 ordinary pieces plus one
-- oversized reply. REPLY_WINDOW covers a whole reply of up to WINDOW_REPLY_PIECES (128)
-- behind a full reply budget: (64 + 128) pieces at two turns (1.7 s) per piece, about
-- 327 s, plus margin. Replies are never refused for their size (AceComm sent any size):
-- a longer whispered reply is still accepted after the window when its first piece
-- arrived inside the window (Comms.dispatchStarted, see ReplyOpen); its first piece waits
-- for at most the 64 reply pieces ahead of it. Lockdown pauses and throttle retries are
-- not bounded and can still outlast the window; the requester then asks again. An
-- inventory request accepts no responses until its send completes (responses carry no
-- token, so earlier ones would be stale or unsolicited). A pull request, whose replies
-- must echo its random token, stays open for at most SEND_GRACE + REPLY_WINDOW seconds
-- until the send completes. Either closes at once if the queue drops it. The roster
-- request accepts nothing until its request is sent (see OnReadyCheck).
local WINDOW_REPLY_PIECES = 128
local REPLY_BUDGET_PIECES = 64 -- Network.lua GROUP_PIECE_CAP (reply budget)
local SECONDS_PER_REPLY_PIECE = 1.7 -- two 0.85 s queue turns per reply piece
local REPLY_WINDOW = math.ceil((REPLY_BUDGET_PIECES + WINDOW_REPLY_PIECES) * SECONDS_PER_REPLY_PIECE) + 33 -- 360 s
local SEND_GRACE = 300
AttendanceSync.REPLY_WINDOW = REPLY_WINDOW
AttendanceSync.WINDOW_REPLY_PIECES = WINDOW_REPLY_PIECES

--- True while a reply window [opened, expires) accepts the message being dispatched:
--- before it expires, or after it when the message is a whispered multi-piece reply
--- whose first piece arrived inside the window (Comms.dispatchStarted). The callers
--- still apply their sender, token and credit checks.
local function ReplyOpen(opened, expires)
    if time() < expires then return true end
    local started = KRT.Comms.dispatchStarted
    return type(started) == "number" and type(opened) == "number"
        and started >= opened and started < expires
end
-- Sent ready-check roster requests still awaiting a reply, per leader (bounded).
local MAX_ROSTER_REPLIES = 4
local requestSequence = 0
local inventorySequence = 0
local dayRequest
local inventoryUntil = 0
local inventoryFrom = 0
local rosterRequest

local MISSING, ABSENT, LATE, PRESENT, STANDBY = 0, 1, 2, 3, 4
local VALID_STATUSES = {
    [MISSING] = true,
    [ABSENT] = true,
    [LATE] = true,
    [PRESENT] = true,
    [STANDBY] = true,
}

AttendanceSync.inventory = {}

local listeners = {}

--- Register a callback to be notified when the sync state changes: a pending
--- replacement appearing or being resolved, a roster replaced outright, or the
--- inventory moving. Callbacks fire synchronously in registration order with no
--- payload.
function AttendanceSync:Listen(callback)
    table.insert(listeners, callback)
end

local function NotifyListeners()
    for i = 1, #listeners do
        listeners[i]()
    end
end

--- A RAID broadcast is delivered back to its sender, so without this an officer
--- pushing a day is offered their own records. The bare-name compare cannot
--- tell a same-named character on a connected realm from the local player; that
--- fails safe, since the cost is ignoring one push.
local function IsOwnBroadcast(sender)
    return Ambiguate(sender, "short") == UnitName("player")
end

local function EnsureAttendanceDB()
    KeepersRaidToolsAttendanceDB = KeepersRaidToolsAttendanceDB or {}
    return KeepersRaidToolsAttendanceDB
end

local function EnsureRosterDB()
    KeepersRaidToolsRosterDB = KeepersRaidToolsRosterDB or {}
    return KeepersRaidToolsRosterDB
end

local function LocalRosterEntries()
    return KeepersRaidToolsRosterDB or {}
end

local function CountRecords(dayRecord)
    local count = 0
    for _ in pairs(dayRecord) do
        count = count + 1
    end
    return count
end

local function LocalRecordCount(day)
    local db = KeepersRaidToolsAttendanceDB
    local dayRecord = db and db[day]
    if not dayRecord then
        return 0
    end
    return CountRecords(dayRecord)
end

local function LocalInventory()
    local days = {}
    local db = KeepersRaidToolsAttendanceDB
    if not db then
        return days
    end

    for day, dayRecord in pairs(db) do
        days[day] = CountRecords(dayRecord)
    end
    return days
end

local function IsSoundInventory(days)
    if type(days) ~= "table" then
        return false
    end

    for day, count in pairs(days) do
        if type(day) ~= "string" or not day:match(ISO_DAY_PATTERN) then
            return false
        end
        if type(count) ~= "number" or count < 0 or count % 1 ~= 0 then
            return false
        end
    end

    return true
end

local function PrepareRecord(record)
    if VALID_STATUSES[record] then
        return { status = record }
    end
    return KRT.AttendanceStore.PrepareRecord(record)
end

local function PrepareDayRecord(data)
    if type(data) ~= "table" then
        return nil
    end
    if type(data.day) ~= "string" or not data.day:match(ISO_DAY_PATTERN) then
        return nil
    end
    if type(data.records) ~= "table" then
        return nil
    end

    local prepared = {}
    for character, record in pairs(data.records) do
        if type(character) ~= "string" or character == "" then
            return nil
        end
        local preparedRecord = PrepareRecord(record)
        if not preparedRecord then
            return nil
        end
        prepared[character] = preparedRecord
    end

    if next(prepared) == nil then
        return nil
    end
    return prepared
end

--- Refilled in place rather than reassigned: Roster:GetEntries hands out the
--- live table, so swapping it strands every reference already taken.
local function ReplaceRoster(entries)
    local db = EnsureRosterDB()
    wipe(db)
    for index, entry in ipairs(entries) do
        db[index] = entry
    end
end

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local function PrepareRoster(entries)
    if KRT.Roster then
        return KRT.Roster:PrepareReplacement(entries)
    end
    return RosterValidation:PrepareEntries(entries)
end

local function ApplyRoster(entries)
    if KRT.Roster then
        return KRT.Roster:ReplaceEntries(entries)
    end
    if InCombat() then
        return false
    end
    ReplaceRoster(entries)
    return true
end

local function IsGroupBroadcast(channel)
    return channel == "RAID" or channel == "PARTY"
end

-- Whispered replies use the reserved reply budget of the KWC queue (Comms.REPLY_TYPES).
-- If even that budget is full, the reply is retried a bounded number of times, well
-- inside the requester's REPLY_WINDOW, instead of being dropped silently. At most
-- MAX_REPLY_RETRIES retries are scheduled at once; a reply refused beyond that is dropped.
local REPLY_RETRY_DELAY = 5
local REPLY_RETRY_ATTEMPTS = 3
local MAX_REPLY_RETRIES = 8
local scheduledRetries = 0

-- Pieces a reply needs on the wire (AceComm-compatible framing, Comms.Split). Diagnostic
-- only: replies are never refused for their size. An injected encoder that does not
-- produce a string (headless test transports) counts as one piece.
local function ReplyPieces(msgType, data)
    local comms = KRT.Comms
    if type(comms.Split) ~= "function" then return 1 end
    local encoded = comms:Encode({ type = msgType, data = data })
    if type(encoded) ~= "string" then return 1 end
    return #comms.Split(encoded)
end
AttendanceSync.ReplyPieces = ReplyPieces

local function SendReply(msgType, data, target, attempt)
    attempt = attempt or 0
    if KRT.Comms:Send(msgType, data, "WHISPER", target) ~= false then
        return true
    end
    if attempt >= REPLY_RETRY_ATTEMPTS or scheduledRetries >= MAX_REPLY_RETRIES
        or not (C_Timer and C_Timer.After) then
        return false
    end
    scheduledRetries = scheduledRetries + 1
    C_Timer.After(REPLY_RETRY_DELAY, function()
        scheduledRetries = scheduledRetries - 1
        -- The requester must still be in the group; whispers outside it are refused anyway.
        if KRT.Comms:GroupUnit(target) then
            SendReply(msgType, data, target, attempt + 1)
        end
    end)
    return false
end
AttendanceSync.SendReply = SendReply

local function OnInventoryRequest(_, sender, channel)
    if not IsGroupBroadcast(channel) or not KRT.Comms:GroupUnit(sender) or IsOwnBroadcast(sender) then return end
    SendReply(INVENTORY_RESPONSE, { days = LocalInventory() }, sender)
end

local function OnInventoryResponse(data, sender, channel)
    if channel ~= "WHISPER" or not ReplyOpen(inventoryFrom, inventoryUntil) or not KRT.Comms:GroupUnit(sender)
        or type(data) ~= "table" or not IsSoundInventory(data.days) then
        return
    end
    AttendanceSync.inventory[sender] = data.days
    NotifyListeners()
end

local function OnPullRequest(data, sender, channel)
    if channel ~= "WHISPER" or not KRT.Comms:IsSenderPrivileged(sender)
        or type(data) ~= "table" or type(data.day) ~= "string" or not data.day:match(ISO_DAY_PATTERN)
        or type(data.request) ~= "string" or not data.request:match("^%d+%-%d+%-%d+$") or #data.request > 32 then
        return
    end

    local db = KeepersRaidToolsAttendanceDB
    local dayRecord = db and db[data.day]
    if not dayRecord then
        SendReply(PULL_MISSING, { day = data.day, request = data.request }, sender)
        return
    end

    SendReply(PULL_RESPONSE, { day = data.day, request = data.request, records = dayRecord }, sender)
end

local function MatchesDayRequest(data, sender, channel)
    local request = dayRequest
    if channel ~= "WHISPER" or not request or not ReplyOpen(request.opened, request.expires) or type(data) ~= "table"
        or data.day ~= request.day or data.request ~= request.token then return false end
    local unit = KRT.Comms:GroupUnit(sender)
    return unit ~= nil and unit == KRT.Comms:GroupUnit(request.target)
        and (not request.target:find("-", 1, true) or sender:lower() == request.target)
        and KRT.Comms:IsSenderPrivileged(UnitName("player"))
end

local function OnPullMissing(data, sender, channel)
    if not MatchesDayRequest(data, sender, channel) then
        return
    end
    dayRequest = nil

    local held = AttendanceSync.inventory[sender]
    if held and held[data.day] ~= nil then
        held[data.day] = nil
        NotifyListeners()
    end

    -- The inventory update above always applies; only the receipt message
    -- follows KWC's instance alert policy.
    local policy = KWC and KWC.InstanceAlerts
    if policy and policy.Allowed() then
        print("|cFF00FF00KeepersRaidTools:|r " .. sender
            .. " no longer has an attendance record for " .. data.day .. ".")
    end
end

local function PendDayReplacement(data, sender)
    local records = PrepareDayRecord(data)
    if not records then
        return
    end

    AttendanceSync.pendingDay = {
        sender = sender,
        day = data.day,
        localCount = LocalRecordCount(data.day),
        incomingCount = CountRecords(records),
        records = records,
    }
    NotifyListeners()
    return true
end

local function OnPullResponse(data, sender, channel)
    if MatchesDayRequest(data, sender, channel) and PendDayReplacement(data, sender) then
        dayRequest = nil
    end
end

local function OnDayPush(data, sender, channel)
    if not IsGroupBroadcast(channel) or IsOwnBroadcast(sender) then
        return
    end
    if not KRT.Comms:IsSenderPrivileged(sender) then
        return
    end
    PendDayReplacement(data, sender)
end

local function OnRosterPush(data, sender, channel)
    if IsOwnBroadcast(sender) then
        return
    end
    if not KRT.Comms:IsSenderPrivileged(sender) then
        return
    end
    if channel == "WHISPER" then
        -- A whispered roster is only a reply to a request that was actually sent and
        -- has not been answered yet; each sent request accepts one reply.
        local unit = KRT.Comms:GroupUnit(sender)
        if not rosterRequest or rosterRequest.outstanding < 1
            or not ReplyOpen(rosterRequest.opened, rosterRequest.expires)
            or not unit or unit ~= KRT.Comms:GroupUnit(rosterRequest.target) then return end
    elseif not IsGroupBroadcast(channel) then
        return
    end
    if InCombat() or type(data) ~= "table" then
        return
    end

    local prepared = PrepareRoster(data.entries)
    if not prepared then
        return
    end
    if channel == "WHISPER" then rosterRequest.outstanding = rosterRequest.outstanding - 1 end

    if AttendanceSync.confirmBeforeSyncing == false then
        if ApplyRoster(prepared) then
            NotifyListeners()
        end
        return
    end

    AttendanceSync.pendingRoster = {
        sender = sender,
        localCount = #LocalRosterEntries(),
        incomingCount = #prepared,
        entries = prepared,
    }
    NotifyListeners()
end

local function OnRosterRequest(_, sender, channel)
    if channel ~= "WHISPER" or not KRT.Comms:GroupUnit(sender)
        or not KRT.Comms:IsSenderPrivileged(UnitName("player")) then return end
    SendReply(ROSTER_PUSH, { entries = LocalRosterEntries() }, sender)
end

function AttendanceSync:RegisterHandlers()
    KRT.Comms:RegisterHandler(INVENTORY_REQUEST, OnInventoryRequest)
    KRT.Comms:RegisterHandler(INVENTORY_RESPONSE, OnInventoryResponse)
    KRT.Comms:RegisterHandler(PULL_REQUEST, OnPullRequest)
    KRT.Comms:RegisterHandler(PULL_RESPONSE, OnPullResponse)
    KRT.Comms:RegisterHandler(PULL_MISSING, OnPullMissing)
    KRT.Comms:RegisterHandler(DAY_PUSH, OnDayPush)
    KRT.Comms:RegisterHandler(ROSTER_PUSH, OnRosterPush)
    KRT.Comms:RegisterHandler(ROSTER_REQUEST, OnRosterRequest)
end

function AttendanceSync:RequestInventory()
    wipe(self.inventory)
    inventorySequence = inventorySequence + 1
    local sequence = inventorySequence
    -- Inventory responses carry no request token, so nothing is accepted until this
    -- request has actually been sent: a response arriving while it is still queued is
    -- stale or unsolicited. Closed before Send because a fallback transport may run the
    -- completion callback synchronously.
    inventoryUntil = 0
    local queued = KRT.Comms:Send(INVENTORY_REQUEST, {}, IsInRaid() and "RAID" or "PARTY", nil, function(sent)
        -- Only the latest request moves the window; a pending duplicate shares one send.
        if sequence ~= inventorySequence then return end
        inventoryFrom = time()
        inventoryUntil = sent and (inventoryFrom + REPLY_WINDOW) or 0
    end)
    if queued == false and sequence == inventorySequence then inventoryUntil = 0 end
    NotifyListeners()
    return queued ~= false
end

function AttendanceSync:GetInventory()
    return self.inventory
end

function AttendanceSync:RequestDay(target, day)
    if type(day) ~= "string" or not day:match(ISO_DAY_PATTERN) or not KRT.Comms:GroupUnit(target)
        or not KRT.Comms:IsSenderPrivileged(UnitName("player")) then return false end
    requestSequence = requestSequence + 1
    local token = ("%d-%d-%d"):format(time(), requestSequence, math.random(100000, 999999))
    local request = { target = target:lower(), day = day, token = token, opened = time(),
        expires = time() + SEND_GRACE + REPLY_WINDOW }
    dayRequest = request
    local queued = KRT.Comms:Send(PULL_REQUEST, { day = day, request = token }, "WHISPER", target, function(sent)
        request.expires = sent and (time() + REPLY_WINDOW) or 0
    end)
    if queued == false then
        if dayRequest == request then dayRequest = nil end
        return false
    end
    return true
end

--- Returns true when the push was queued. Returns false, "missing" when there is no
--- local record for the day, and false, "refused" when the bounded queue refused the
--- send (nothing will be transmitted).
function AttendanceSync:PushDay(day)
    local db = KeepersRaidToolsAttendanceDB
    local dayRecord = db and db[day]
    if not dayRecord then
        return false, "missing"
    end

    if KRT.Comms:Send(DAY_PUSH, { day = day, records = dayRecord }, "RAID") == false then
        return false, "refused"
    end
    return true
end

--- Returns true when the push was queued and false when the queue refused it.
function AttendanceSync:PushRoster()
    return KRT.Comms:Send(ROSTER_PUSH, { entries = LocalRosterEntries() }, "RAID") ~= false
end

--- Ready-check roster requests to one leader share a request record. A whispered roster
--- reply is accepted only against a request that was actually sent: each completed send
--- credits one reply (at most MAX_ROSTER_REPLIES) and moves the window to REPLY_WINDOW
--- from that send. A queued request accepts nothing yet, so the reply to an earlier
--- request cannot use up a later one before that one is even sent. While a request is
--- still queued, a further ready check is served by it rather than queued again (the
--- queue would merge the duplicate, and one send must credit only one reply).
function AttendanceSync:OnReadyCheck(leaderName, autoSyncEnabled)
    if not autoSyncEnabled or not leaderName then
        return
    end
    if not KRT.Comms:IsSenderPrivileged(leaderName) then return end
    local request = rosterRequest
    if not request or request.target ~= leaderName then
        request = { target = leaderName, outstanding = 0, expires = 0 }
        rosterRequest = request
    end
    if request.inFlight then return end
    request.inFlight = true
    local queued = KRT.Comms:Send(ROSTER_REQUEST, {}, "WHISPER", leaderName, function(sent)
        request.inFlight = nil
        if not sent or rosterRequest ~= request then return end
        local now = time()
        -- A new credit cycle opens when the previous window has closed.
        if now >= request.expires then request.outstanding = 0;request.opened = now end
        request.outstanding = math.min(request.outstanding + 1, MAX_ROSTER_REPLIES)
        request.expires = now + REPLY_WINDOW
    end)
    if queued == false then request.inFlight = nil end
end

function AttendanceSync:GetPendingDay()
    return self.pendingDay
end

function AttendanceSync:AcceptPendingDay()
    local pending = self.pendingDay
    if not pending then
        return false
    end

    EnsureAttendanceDB()[pending.day] = pending.records
    self.pendingDay = nil
    NotifyListeners()
    return true
end

function AttendanceSync:DeclinePendingDay()
    if not self.pendingDay then
        return
    end
    self.pendingDay = nil
    NotifyListeners()
end

function AttendanceSync:GetPendingRoster()
    return self.pendingRoster
end

function AttendanceSync:AcceptPendingRoster()
    local pending = self.pendingRoster
    if not pending then
        return false
    end

    if not ApplyRoster(pending.entries) then
        return false
    end
    self.pendingRoster = nil
    NotifyListeners()
    return true
end

function AttendanceSync:DeclinePendingRoster()
    if not self.pendingRoster then
        return
    end
    self.pendingRoster = nil
    NotifyListeners()
end
