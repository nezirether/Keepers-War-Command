-- Comms: shared broadcast transport built on LibSerialize/LibDeflate. Outgoing messages
-- use the KWC network queue (Network.lua) with AceComm-compatible framing; incoming
-- messages are reassembled by AceComm. The "KRTools" wire format is unchanged.
--
-- Headless-load safety: AceComm-3.0 and ChatThrottleLib call CreateFrame at load
-- and cannot run under the headless test harness. This file therefore looks up
-- AceComm silently (LibStub("AceComm-3.0", true)) and gates the embed/RegisterComm
-- behind its presence, so the module loads cleanly without it.

local KRT = KeepersRaidTools

local PREFIX = "KRTools"
local VERSION = 1

local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")

local Comms = {}
KRT.Comms = Comms

Comms.handlers = {}

-- Injectable transport: defaults to the shared KWC queue (K.Net), falling back to
-- AceComm when K.Net is absent (set below); tests replace this with a capturing function.
Comms.sendFunc = nil

function Comms:Encode(tbl)
    tbl.v = VERSION
    local serialized = LibSerialize:Serialize(tbl)
    local compressed = LibDeflate:CompressDeflate(serialized)
    return LibDeflate:EncodeForWoWAddonChannel(compressed)
end

-- Returns (true, table) on success, or (false, nil) for any non-string, empty,
-- corrupted, truncated, or wrong-version input. Never throws.
function Comms:Decode(str)
    if type(str) ~= "string" or (issecretvalue and issecretvalue(str)) or str == "" then
        return false, nil
    end

    local decoded = LibDeflate:DecodeForWoWAddonChannel(str)
    if not decoded then
        return false, nil
    end

    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        return false, nil
    end

    local ok, result = LibSerialize:Deserialize(decompressed)
    if not ok or type(result) ~= "table" then
        return false, nil
    end

    if result.v ~= VERSION then
        return false, nil
    end

    return true, result
end

function Comms:RegisterHandler(msgType, fn)
    self.handlers[msgType] = fn
end

-- Whispered multi-piece messages: the time each sender's latest one started (its first
-- piece, \001, arrived; see Comms:NotePiece). Kept for at most STREAM_LIMIT senders.
-- Receive-side bookkeeping only; it grants no authority and changes no wire format.
local STREAM_LIMIT = 40
-- A reassembled message this long always arrived in pieces: AceComm splits anything over
-- 255 bytes and Comms.Split anything over 250.
local MULTIPART_MIN = 256
Comms.streamStarts = {}

-- While a handler runs, Comms.dispatchStarted holds the time the message's first piece
-- arrived when it is a whispered multi-piece message, and nil otherwise. Reply windows
-- use it to accept a long reply that started inside the window but completed after it.
function Comms:Dispatch(encodedStr, sender, channel)
    if issecretvalue and (issecretvalue(sender) or issecretvalue(channel)) then return end
    if channel ~= "RAID" and channel ~= "PARTY" and channel ~= "WHISPER"
        and channel ~= "INSTANCE_CHAT" then return end
    if not self:GroupUnit(sender) then return end
    local ok, payload = self:Decode(encodedStr)
    if not ok then
        return
    end

    local handler = self.handlers[payload.type]
    if handler then
        local started
        if channel == "WHISPER" and type(encodedStr) == "string" and #encodedStr >= MULTIPART_MIN
            and type(sender) == "string" then
            started = self.streamStarts[sender:lower()]
        end
        self.dispatchStarted = started
        local ok, err = pcall(handler, payload.data, sender, channel)
        self.dispatchStarted = nil
        if not ok and KWC and KWC.Log then KWC.Log("KRT", "Raid Tools handler failed: " .. tostring(err):sub(1,160)) end
    end
end

-- Queue classes by message type. They affect local queueing only; the wire format and
-- the message types themselves are unchanged.
-- Order-independent requests and replies: one that fits in a single piece may be sent
-- between the pieces of a long message (for example a raid note) on the same channel.
-- Notes, clears and pushes are not listed: they must arrive in the order they were sent.
Comms.UNORDERED_TYPES = {
    versionQuery = true, versionResponse = true,
    readyStatusQuery = true, readyStatusResponse = true,
    attInventoryRequest = true, attInventoryResponse = true,
    attPullRequest = true, attPullMissing = true, attRosterRequest = true,
}
-- Whispered replies to a request use the reserved reply budget in the KWC queue, so a
-- responder whose other group traffic is at its cap can still answer.
Comms.REPLY_TYPES = {
    versionResponse = true, readyStatusResponse = true,
    attInventoryResponse = true, attPullResponse = true, attPullMissing = true,
    attRosterPush = true,
}

function Comms:SendOptions(msgType, channel)
    return {
        unordered = self.UNORDERED_TYPES[msgType] == true,
        reply = channel == "WHISPER" and self.REPLY_TYPES[msgType] == true,
    }
end

-- Returns false when the message was refused (nothing will be sent). The optional
-- onComplete(sent) callback runs once the message leaves the KWC queue: sent is true
-- after its last piece went out and false when it was dropped unsent. Callers use it
-- to start reply deadlines when the request is actually sent, not when it is queued.
function Comms:Send(msgType, data, channel, target, onComplete)
    local encoded = self:Encode({ type = msgType, data = data })
    if self.sendFunc then
        return self.sendFunc(encoded, channel, target, onComplete, self:SendOptions(msgType, channel))
    end
    return false
end

function Comms:GroupUnit(sender)
    if type(sender) ~= "string" or not (IsInRaid() or IsInGroup()) then return end
    local raid = IsInRaid()
    local prefix = raid and "raid" or "party"
    local qualified = sender:find("-", 1, true)
    local expected = sender:lower()
    local found
    for index = raid and 1 or 0, raid and 40 or 4 do
        local unit = index == 0 and "player" or prefix .. index
        local name, realm
        if UnitFullName then name, realm = UnitFullName(unit) end
        if name == nil then name, realm = UnitName(unit) end
        local secret = issecretvalue and (issecretvalue(name) or issecretvalue(realm))
        if not secret and type(name) == "string" and name ~= "" then
            if qualified and not name:find("-", 1, true) then
                if not realm or realm == "" then realm = GetNormalizedRealmName and GetNormalizedRealmName() end
                name = realm and (name .. "-" .. realm) or name
            elseif not qualified then
                name = name:match("^[^-]+") or name
            end
            if name:lower() == expected then
                if found then return end
                found = unit
            end
        end
    end
    return found
end

function Comms:IsSenderPrivileged(sender)
    local unit = self:GroupUnit(sender)
    if not unit then return false end

    if IsInRaid() then
        return UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit)
    elseif IsInGroup() then
        return UnitIsGroupLeader(unit)
    end

    return false
end

-- AceComm-compatible framing, so receivers (including older clients that send and
-- receive through AceComm only) reassemble these messages unchanged. A message that
-- fits is sent as is; a message that starts with a control byte gets AceComm's \004
-- escape; anything longer is split into \001 first, \002 next and \003 last pieces.
-- Pieces are at most 250 bytes to fit the KWC transport cap (AceComm uses 255; its
-- receiver accepts pieces of any size).
local PIECE_LIMIT = 250
local MULTI_FIRST, MULTI_NEXT, MULTI_LAST, ESCAPE = "\001", "\002", "\003", "\004"

function Comms.Split(text)
    local forceMultipart
    if text:match("^[\001-\009]") then
        if #text + 1 > PIECE_LIMIT then
            forceMultipart = true
        else
            text = ESCAPE .. text
        end
    end
    if not forceMultipart and #text <= PIECE_LIMIT then
        return { text }
    end
    local size = PIECE_LIMIT - 1
    local parts = { MULTI_FIRST .. text:sub(1, size) }
    local pos = 1 + size
    while pos + size <= #text do
        parts[#parts + 1] = MULTI_NEXT .. text:sub(pos, pos + size - 1)
        pos = pos + size
    end
    parts[#parts + 1] = MULTI_LAST .. text:sub(pos)
    return parts
end

-- Records when a sender's whispered multi-piece KRTools message started. AceComm's
-- receiver restarts its spool for prefix, channel and sender on every \001 piece, so the
-- latest start recorded here belongs to the message AceComm completes next from that
-- sender. Fed by the raw CHAT_MSG_ADDON listener below (tests call it directly).
function Comms:NotePiece(prefix, message, channel, sender)
    if issecretvalue and (issecretvalue(prefix) or issecretvalue(message)
        or issecretvalue(channel) or issecretvalue(sender)) then return end
    if prefix ~= PREFIX or channel ~= "WHISPER" or type(message) ~= "string"
        or type(sender) ~= "string" or message:sub(1, 1) ~= MULTI_FIRST then return end
    local starts = self.streamStarts
    local key = sender:lower()
    if starts[key] == nil then
        local count, oldestKey, oldest = 0, nil, nil
        for k, t in pairs(starts) do
            count = count + 1
            if not oldest or t < oldest then oldestKey, oldest = k, t end
        end
        if count >= STREAM_LIMIT and oldestKey then starts[oldestKey] = nil end
    end
    starts[key] = time()
end

-- Sends through the shared KWC queue (lockdown hold, offline-whisper handling,
-- duplicate suppression, bounded group traffic). Whispers are validated by current
-- group membership because raid members need not be guild members. Returns nil when
-- the KWC transport is unavailable so the caller can fall back to AceComm.
-- sendOpts (optional) carries the queue classes from Comms:SendOptions.
function Comms.NetSend(encoded, channel, target, onComplete, sendOpts)
    local K = KWC
    local net = K and K.Net
    if not (net and net.Send and net.SendParts) then return nil end
    local parts = Comms.Split(encoded)
    local opts = { groupWhisper = channel == "WHISPER" }
    if type(onComplete) == "function" then opts.onComplete = onComplete end
    if type(sendOpts) == "table" then
        opts.unordered = sendOpts.unordered == true or nil
        opts.reply = sendOpts.reply == true or nil
    end
    if #parts == 1 then
        return net.Send(PREFIX, parts[1], channel, target, nil, opts)
    end
    return net.SendParts(PREFIX, parts, channel, target, nil, opts)
end

local function DefaultSend(encoded, channel, target, onComplete, sendOpts)
    local queued = Comms.NetSend(encoded, channel, target, onComplete, sendOpts)
    if queued ~= nil then return queued end
    if Comms.SendCommMessage then
        Comms:SendCommMessage(PREFIX, encoded, channel, target)
        -- AceComm accepted it; reply deadlines keep their previous start-at-send timing.
        if type(onComplete) == "function" then pcall(onComplete, true) end
        return true
    end
    return false
end

Comms.sendFunc = DefaultSend

-- Raw piece listener for Comms:NotePiece. It only records stream start times; messages
-- are still reassembled and dispatched by AceComm below. Guarded so a missing frame API
-- (headless load) or event cannot break loading.
if type(CreateFrame) == "function" then
    local created, pieceFrame = pcall(CreateFrame, "Frame")
    if created and pieceFrame and pieceFrame.RegisterEvent and pieceFrame.SetScript then
        if pcall(pieceFrame.RegisterEvent, pieceFrame, "CHAT_MSG_ADDON") then
            pieceFrame:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
                Comms:NotePiece(prefix, message, channel, sender)
            end)
        end
    end
end

-- Silent lookup: absent under the headless harness, present in-game.
local AceComm = LibStub("AceComm-3.0", true)
if AceComm then
    AceComm:Embed(Comms)

    -- Receiving stays on AceComm: it reassembles both KWC-queued and AceComm-sent pieces.
    Comms:RegisterComm(PREFIX, function(_, message, channel, sender)
        Comms:Dispatch(message, sender, channel)
    end)
end
