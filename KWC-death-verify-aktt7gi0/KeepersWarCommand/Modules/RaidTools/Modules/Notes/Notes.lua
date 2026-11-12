-- Notes: timed boss note reminders. Owns storage/selection, module registration,
-- defaults, and lifecycle.
local KRT = KeepersRaidTools
local Notes = {}
KRT.Notes = Notes
KRT:RegisterModule("notes", Notes)

-- ============================================================================
-- FROZEN DATA CONTRACT (rev 2, spec 21a81ca) — do not change without Niv
--
-- A note is ONE encounter's plan. NotesParser:Parse(text) returns:
--   note, nil  on success:
--     { encounterID(number or nil),  -- nil = inert note (no metadata line)
--       name, difficulty,            -- "Normal"|"Heroic"|"Mythic"|nil (nil = any)
--       reminders = { [phaseKey(string)] = array sorted by time },
--       lines = ordered { type = "reminder"|"freeform", ... } }  -- note-frame order
--   nil, errMessage  on invalid input (more than one EncounterID: line):
--     errMessage = "A note may only contain one encounter. Use a separate note per encounter."
--   Content before the metadata line (or in an inert note) is kept as freeform.
--   Timed lines before the metadata line are freeform, not reminders.
--   Reminder = { time, tag, text, spellID, phase(number), phaseKey(string),
--                duration, displayType, tts, ttsTimer, countdown, sound,
--                bossSpell, colors, relevant(bool, set by tag matcher),
--                bossDuration, bossTicks (derived from canonical BossData) }
--   phaseKey is tostring(phase) ("2.5") to avoid float table-key identity.
--   duration and ttsTimer are clamped to time at parse (spec 9.2.1).
--
-- NotesTags:MarkRelevance(note, ctx) — takes the single note, not a dict.
--
-- Note applies to a live encounter iff note.encounterID == liveEncounterID
-- (numeric) AND (note.difficulty == nil OR note.difficulty == liveDifficultyString).
--
-- Timer callbacks (NotesTimer, unchanged):
--   onPopupShow(reminder, remaining)
--   onAudio(reminder)
--   onCountdown(reminder, number)
--   onPopupExpire(reminder)
--   onCancelPhase(reminders)
-- ============================================================================

KRT.defaults.notes = {
    enabled = true,
    -- activeNote is intentionally omitted: nil keys do not exist, and a nil
    -- default would be recreated when defaults are merged. "No active note" is simply the absence of this key.
    savedNotes = {},  -- Keep sample notes out of persistent settings.
    annotations = {},
    display = {
        locked = true,
        showOnlyMine = true,
        hideExpired = true,
        hideMode = "Immediately",  -- "Immediately" | "Fade" | "Never"
        countdownColor = { r = 0, g = 1, b = 0, a = 1 },
        fontFace = "Friz Quadrata TT",
        fontSize = 12,
        fontOutline = "NONE",
        backgroundColor = { r = 0, g = 0, b = 0, a = 1 },
        backgroundOpacity = 0.7,
    },
    popups = {
        locked = true,
        enabledTypes = {
            Icon = true,
            Bar = true,
            Text = true,
            Circle = true,
        },
        barWidth = 220,
        barHeight = 24,
        barTexture = "Blizzard",
        scale = 1,
        growDirection = "Down",
        ttsEnabled = true,
        soundsEnabled = true,
        soundChannel = "Master",
    },
    contentTypes = {
        openWorld = false,
        dungeon = { normal = false, heroic = false, mythic = false, mythicPlus = false },
        raid = { lfr = true, normal = true, heroic = true, mythic = true },
        scenario = { normal = false, heroic = false },
    },
    positions = {},
}

function Notes:MigrateLockSettings(settings)
    settings = settings or KRT:GetSetting("notes")
    if type(settings) ~= "table" then
        return
    end
    if type(settings.display) ~= "table" then
        settings.display = {}
    end
    if type(settings.popups) ~= "table" then
        settings.popups = {}
    end

    if settings.locked ~= nil then
        settings.display.locked = settings.locked
        settings.popups.locked = settings.locked
        settings.locked = nil
    end
    if settings.display.locked == nil then
        settings.display.locked = true
    end
    if settings.popups.locked == nil then
        settings.popups.locked = true
    end
end

local function GetNotesStore()
    local settings = KRT:GetSetting("notes")
    if not settings.savedNotes then
        settings.savedNotes = {}
    end
    if not settings.annotations then
        settings.annotations = {}
    end
    return settings
end

-- Single-encounter validation is delegated to NotesParser:Parse. When the parser
-- is absent (headless harness only; TOC order guarantees it in-game) the note is
-- saved without validation rather than erroring.
function Notes:SaveNote(name, text)
    if not name then return false end
    if KRT.NotesParser then
        local _, err = KRT.NotesParser:Parse(text or "")
        if err then
            return false, err
        end
    end
    local store = GetNotesStore()
    store.savedNotes[name] = text
    return true
end

function Notes:SaveAnnotation(name, text)
    if not name then return false end
    if KRT.NotesParser then
        local _, err = KRT.NotesParser:Parse(text or "")
        if err then
            return false, err
        end
    end
    local store = GetNotesStore()
    store.annotations[name] = text
    return true
end

function Notes:GetAnnotation(name)
    local store = GetNotesStore()
    return store.annotations[name]
end

function Notes:DeleteAnnotation(name)
    local store = GetNotesStore()
    if not store.annotations[name] then return false end
    store.annotations[name] = nil
    return true
end

function Notes:DeleteNote(name)
    local store = GetNotesStore()
    if not store.savedNotes[name] then return false end
    store.savedNotes[name] = nil
    store.annotations[name] = nil
    if store.activeNote == name then
        store.activeNote = nil
    end
    return true
end

function Notes:DuplicateNote(name)
    local store = GetNotesStore()
    if not name or not store.savedNotes[name] then
        return false
    end

    local duplicateName = name .. " Copy"
    local copyNumber = 2
    while store.savedNotes[duplicateName] do
        duplicateName = name .. " Copy " .. copyNumber
        copyNumber = copyNumber + 1
    end

    store.savedNotes[duplicateName] = store.savedNotes[name]
    store.annotations[duplicateName] = store.annotations[name]
    return true, duplicateName
end

function Notes:RenameNote(oldName, newName)
    if not oldName or not newName then return false end
    local store = GetNotesStore()
    if not store.savedNotes[oldName] then return false end
    if store.savedNotes[newName] then return false end
    store.savedNotes[newName] = store.savedNotes[oldName]
    store.savedNotes[oldName] = nil
    if store.annotations[oldName] then
        store.annotations[newName] = store.annotations[oldName]
        store.annotations[oldName] = nil
    end
    if store.activeNote == oldName then
        store.activeNote = newName
    end
    return true
end

function Notes:ActivateNote(name, source)
    local store = GetNotesStore()
    if name ~= nil and not store.savedNotes[name] then
        return false
    end
    store.activeNote = name
    store.activeNoteSource = name and (source or "self") or nil
    self:OnActiveNoteChanged()
    return true
end

function Notes:GetActiveNoteSource()
    local store = GetNotesStore()
    return store.activeNoteSource
end

function Notes:GetActiveNote()
    local store = GetNotesStore()
    local name = store.activeNote
    if not name then return nil end
    return name, store.savedNotes[name]
end

local activeNote = nil
local ticker = nil
local encounterPhase = 1
local phaseStart = nil
local bossModHooked = false
local warnedNoBossMod = false
local testRunning = false
local encounterPhaseAttempt = nil
local useCanonicalPhases = false
local registeredObservationEvents = {}
local registeredUnitObservationEvents = {}

-- difficultyID -> capitalized note-vocabulary difficulty string. The lowercase
-- content-type strings from GetCurrentContentType must NEVER be used here.
local DIFFICULTY_ID_TO_NOTE_STRING = {
    [14] = "Normal",
    [15] = "Heroic",
    [16] = "Mythic",
    [17] = "LFR",
}

-- Reject any WoW event/callback argument that is a protected "secret" value
-- (post-Midnight combat data restrictions).
local function isSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

-- Tanks count as melee here; DPS/healer classification defers to IsMeleeSpec.
local function BuildPlayerCtx()
    local name = UnitName("player")
    local _, _, classID = UnitClass("player")
    local role = UnitGroupRolesAssigned("player")

    local specID
    local specIndex = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
        and C_SpecializationInfo.GetSpecialization()
    if specIndex then
        specID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    end

    if (not role or role == "NONE") and specIndex then
        local specRole = GetSpecializationRole(specIndex)
        if specRole and specRole ~= "NONE" then
            role = specRole
        end
    end

    local subgroup
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unitName, _, subGroup = GetRaidRosterInfo(i)
            if unitName and name and unitName == name then
                subgroup = subGroup
                break
            end
        end
    else
        subgroup = 1
    end

    local isMelee = role == "TANK" or KRT.NotesTags.IsMeleeSpec(specID)

    return {
        name = name,
        role = role,
        classID = classID,
        specID = specID,
        subgroup = subgroup,
        isMelee = isMelee,
    }
end

function Notes:MarkRelevance(note)
    if not (note and KRT.NotesTags) then
        return
    end
    KRT.NotesTags.MarkRelevance(note, BuildPlayerCtx())
end

-- Content-only: never changes frame visibility. Safe with no active note.
local function RefreshRelevance()
    if activeNote then
        KRT.NotesTags.MarkRelevance(activeNote, BuildPlayerCtx())
    end
    KRT.NotesFrame:RebuildRoster()
    KRT.NotesFrame:SetNote(activeNote)
end

local function NoteApplies(note, encounterID, difficultyString)
    if not note then
        return false
    end
    if note.encounterID ~= nil and note.encounterID ~= encounterID then
        return false
    end
    return note.difficulty == nil or note.difficulty == difficultyString
end

local timerCallbacks = {
    onPopupShow = function(reminder, remaining)
        KRT.NotesPopups:Show(reminder, remaining)
    end,
    onAudio = function(reminder)
        KRT.NotesPopups:PlayAudio(reminder)
    end,
    onCountdown = function(reminder, number)
        KRT.NotesPopups:AnnounceCountdown(number)
    end,
    onPopupExpire = function(reminder)
        KRT.NotesPopups:Expire(reminder)
    end,
    onCancelPhase = function(reminders)
        for _, reminder in ipairs(reminders) do
            KRT.NotesPopups:Dismiss(reminder)
        end
    end,
}

local function ApplyPhase(stage, activationTime)
    if isSecret(stage) then
        return
    end
    stage = tonumber(stage)
    if not stage then
        return
    end
    encounterPhase = stage
    phaseStart = activationTime or GetTime()
    KRT.NotesTimer:SetPhase(stage, phaseStart)
end

-- Registers exactly once. Callback arg order: BigWigs (event, addon, stage);
-- DBM (event, addon, modId, stage, ...). Every arg is guarded against secret
-- values.
local function HookBossMods()
    if bossModHooked then
        return
    end

    local hooked = false

    if type(BigWigsLoader) == "table" and BigWigsLoader.RegisterMessage then
        BigWigsLoader.RegisterMessage(Notes, "BigWigs_SetStage", function(_, addon, stage)
            if isSecret(addon) or isSecret(stage) then
                return
            end
            if useCanonicalPhases then
                return
            end
            ApplyPhase(stage)
        end)
        hooked = true
    end

    if type(DBM) == "table" and DBM.RegisterCallback then
        DBM:RegisterCallback("DBM_SetStage", function(_, addon, modId, stage)
            if isSecret(addon) or isSecret(modId) or isSecret(stage) then
                return
            end
            if useCanonicalPhases then
                return
            end
            ApplyPhase(stage)
        end)
        hooked = true
    end

    bossModHooked = hooked
end

local function StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local BASE_EVENTS = {
    ADDON_LOADED = true,
    ENCOUNTER_END = true,
    ENCOUNTER_START = true,
    GROUP_ROSTER_UPDATE = true,
    PLAYER_SPECIALIZATION_CHANGED = true,
}
local BOSS1_OBSERVATION_EVENTS = {
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_SUCCEEDED = true,
}

local function StopEncounterPhaseAttempt()
    if encounterPhaseAttempt and KRT.EncounterPhases then
        KRT.EncounterPhases:EndAttempt(encounterPhaseAttempt)
    end
    encounterPhaseAttempt = nil
    useCanonicalPhases = false

    if Notes.eventFrame and Notes.eventFrame.UnregisterEvent then
        for event in pairs(registeredObservationEvents) do
            Notes.eventFrame:UnregisterEvent(event)
        end
    end
    registeredObservationEvents = {}
    registeredUnitObservationEvents = {}
end

local function StartEncounterPhaseAttempt(encounterID, difficultyID)
    if not KRT.EncounterPhases then
        return
    end
    if not KRT.EncounterPhases:GetDefinition(encounterID) then
        return
    end

    useCanonicalPhases = true
    encounterPhaseAttempt = KRT.EncounterPhases:BeginAttempt(encounterID, difficultyID, {
        activate = function(phase, now)
            ApplyPhase(phase, now)
        end,
        isSecret = isSecret,
        now = GetTime,
        schedule = function(delay, callback)
            if not C_Timer or not C_Timer.NewTimer then
                return nil
            end
            return C_Timer.NewTimer(delay, callback)
        end,
    })
    if not encounterPhaseAttempt then
        return
    end

    for _, declaration in ipairs(KRT.EncounterPhases:GetAttemptEvents(encounterPhaseAttempt)) do
        local event = declaration
        local unit
        if type(declaration) == "table" then
            event = declaration.event
            unit = declaration.unit
        end
        if not BASE_EVENTS[event] then
            if unit then
                Notes.eventFrame:RegisterUnitEvent(event, unit)
                registeredUnitObservationEvents[event] = true
            elseif BOSS1_OBSERVATION_EVENTS[event] then
                Notes.eventFrame:RegisterUnitEvent(event, "boss1")
            else
                Notes.eventFrame:RegisterEvent(event)
            end
            registeredObservationEvents[event] = true
        end
    end
end

local function OnEncounterStart(encounterID, difficultyID)
    StopEncounterPhaseAttempt()
    if isSecret(encounterID) or isSecret(difficultyID) then
        return
    end

    local settings = KRT:GetSetting("notes")
    if not settings or not KRT.IsContentTypeEnabled(settings.contentTypes) then
        return
    end

    encounterID = tonumber(encounterID)
    if not encounterID then
        return
    end

    local difficultyString = DIFFICULTY_ID_TO_NOTE_STRING[tonumber(difficultyID)]
    if not NoteApplies(activeNote, encounterID, difficultyString) then
        return
    end

    if testRunning then
        Notes:TestStop()
    end

    local planningModel = KRT.EncounterPhases
        and KRT.EncounterPhases.GetPlanningModel
        and KRT.EncounterPhases:GetPlanningModel(encounterID, tonumber(difficultyID))
    if KRT.NotesBossTimeline then
        KRT.NotesBossTimeline:Apply(activeNote, planningModel)
    end

    StartEncounterPhaseAttempt(encounterID, tonumber(difficultyID))

    if not useCanonicalPhases
        and not (type(BigWigsLoader) == "table" or type(DBM) == "table")
    then
        if not warnedNoBossMod then
            warnedNoBossMod = true
            print("KRT: No boss mod (BigWigs or DBM) detected. Only phase 1 reminders will fire.")
        end
    end

    encounterPhase = 1
    phaseStart = GetTime()

    KRT.NotesTags.MarkRelevance(activeNote, BuildPlayerCtx())
    KRT.NotesFrame:SetNote(activeNote)
    KRT.NotesFrame:Show()
    KRT.NotesTimer:Start(activeNote, timerCallbacks, phaseStart)

    StopTicker()
    ticker = C_Timer.NewTicker(1, function()
        local now = GetTime()
        KRT.NotesTimer:Tick(now)
        KRT.NotesFrame:TickUpdate(now, phaseStart, encounterPhase)
    end)
end

local function OnEncounterEnd(success)
    StopEncounterPhaseAttempt()
    StopTicker()
    KRT.NotesTimer:Stop()
    KRT.NotesPopups:DismissAll()

    local settings = KRT:GetSetting("notes")
    local hideMode = settings and settings.display and settings.display.hideMode
    KRT.NotesFrame:OnEncounterEnd(hideMode)

    if success == 1 then
        Notes:ActivateNote(nil)
    end
end

-- Test mode starts the active note's timer without an encounter event,
-- bypassing encounterID matching and content-type gates. The note frame shows,
-- popups fire, and the ticker runs exactly as in a real encounter. TestStop
-- tears everything down.
function Notes:TestStart()
    if testRunning then
        return false
    end
    if not activeNote then
        return false
    end

    testRunning = true
    encounterPhase = 1
    phaseStart = GetTime()

    local difficultyID = KRT.NotesPlanner
        and KRT.NotesPlanner:GetDifficultyID(activeNote.difficulty)
    local planningModel = difficultyID
        and activeNote.encounterID
        and KRT.EncounterPhases
        and KRT.EncounterPhases.GetPlanningModel
        and KRT.EncounterPhases:GetPlanningModel(activeNote.encounterID, difficultyID)
    if KRT.NotesBossTimeline then
        KRT.NotesBossTimeline:Apply(activeNote, planningModel)
    end

    KRT.NotesTags.MarkRelevance(activeNote, BuildPlayerCtx())
    KRT.NotesFrame:SetNote(activeNote)
    KRT.NotesFrame:Show()
    KRT.NotesTimer:Start(activeNote, timerCallbacks, phaseStart)

    local maxTime = 0
    for _, bucket in pairs(activeNote.reminders) do
        for _, reminder in ipairs(bucket) do
            local timeline = KRT.NotesBossTimeline
                and KRT.NotesBossTimeline:GetBarTimeline(reminder)
            local endTime = reminder.time + (timeline and timeline.postDuration or 0)
            if endTime > maxTime then
                maxTime = endTime
            end
        end
    end

    StopTicker()
    ticker = C_Timer.NewTicker(1, function()
        local now = GetTime()
        KRT.NotesTimer:Tick(now)
        KRT.NotesFrame:TickUpdate(now, phaseStart, encounterPhase)

        if now - phaseStart >= maxTime then
            self:TestStop()
        end
    end)

    return true
end

function Notes:TestStop()
    if not testRunning then
        return
    end
    testRunning = false

    StopTicker()
    KRT.NotesTimer:Stop()
    KRT.NotesPopups:DismissAll()
    KRT.NotesFrame:OnEncounterEnd("Immediately")

    if self.onTestStopped then
        self.onTestStopped()
    end
end

function Notes:IsTestRunning()
    return testRunning
end

-- Broadcast send seam. Both entry points re-check the group/privilege gates at
-- call time and HARD-ban sending while in combat, so no code path can broadcast
-- mid-pull. Each returns ok(boolean), reason(string when refused) for the
-- config UI's tooltip. InCombatLockdown is guarded for headless safety,
-- mirroring isSecret.
local SEND_MSG_TYPE = "note"
local CLEAR_MSG_TYPE = "clear"
local REASON_NO_PRIVILEGE = "Requires raid leader or assistant."
local REASON_COMBAT = "Cannot send during combat."
local REASON_NO_NOTE = "No note selected."

local function InCombat()
    return InCombatLockdown ~= nil and InCombatLockdown()
end

-- Solo sending is legal: it is a send-to-self (activate + show locally, no
-- wire). In a group the sender's own client activates via the RAID channel's
-- self-echo through the receive path. Combat is a hard ban either way.
local function BroadcastGate()
    if IsInGroup() and not KRT.Comms:IsSenderPrivileged(UnitName("player")) then
        return false, REASON_NO_PRIVILEGE
    end
    if InCombat() then
        return false, REASON_COMBAT
    end
    return true
end

function Notes:BroadcastNote(name)
    local ok, reason = BroadcastGate()
    if not ok then
        return false, reason
    end
    local note = name and GetNotesStore().savedNotes[name]
    if not note then
        return false, REASON_NO_NOTE
    end
    if not IsInGroup() then
        self:ActivateNote(name, "broadcast")
        KRT.NotesFrame:Show()
        return true
    end
    KRT.Comms:Send(SEND_MSG_TYPE, { name = name, text = note }, "RAID")
    return true
end

function Notes:BroadcastClear()
    local ok, reason = BroadcastGate()
    if not ok then
        return false, reason
    end
    if not IsInGroup() then
        self:ActivateNote(nil)
        KRT.NotesFrame:Hide()
        return true
    end
    KRT.Comms:Send(CLEAR_MSG_TYPE, {}, "RAID")
    return true
end

local function OnNoteReceived(data, sender)
    -- Notes are never sent or received in combat: distribution is pre-pull
    -- setup, and 12.1 makes the privilege APIs return secrets while identity
    -- is secret (branching on one is a Lua error). Drop anything that arrives
    -- mid-combat — only in-flight or non-compliant sends can — BEFORE the
    -- privilege check ever runs.
    if InCombat() then
        return
    end
    if type(data) ~= "table" or not data.name then
        return
    end
    if not KRT.Comms:IsSenderPrivileged(sender) then
        return
    end
    -- A note that fails SaveNote's validation is rejected silently. A compliant
    -- KRT sender can never produce one.
    if not Notes:SaveNote(data.name, data.text) then
        return
    end
    Notes:ActivateNote(data.name, "broadcast")
    print("KRT: Received note: " .. data.name .. " from " .. sender)
    KRT.NotesFrame:Show()
end

local function OnClearReceived(_, sender)
    -- Same combat drop as OnNoteReceived, same reason.
    if InCombat() then
        return
    end
    if not KRT.Comms:IsSenderPrivileged(sender) then
        return
    end
    Notes:ActivateNote(nil)
    KRT.NotesFrame:Hide()
end

local function OnEvent(_, event, ...)
    if event == "ENCOUNTER_START" then
        HookBossMods()
        local encounterID, _, difficultyID = ...
        OnEncounterStart(encounterID, difficultyID)
    elseif event == "ENCOUNTER_END" then
        OnEncounterEnd(select(5, ...))
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        RefreshRelevance()
    elseif event == "ADDON_LOADED" then
        HookBossMods()
    elseif encounterPhaseAttempt and KRT.EncounterPhases then
        if BOSS1_OBSERVATION_EVENTS[event] or registeredUnitObservationEvents[event] then
            KRT.EncounterPhases:ObserveAttempt(encounterPhaseAttempt, event, (...))
        else
            KRT.EncounterPhases:ObserveAttempt(encounterPhaseAttempt, event, ...)
        end
    end
end

-- Reparse and remark relevance. The sibling modules are absent under the
-- headless harness, so parsing is skipped there.
function Notes:OnActiveNoteChanged()
    if not (KRT.NotesParser and KRT.NotesTags) then
        return
    end
    local name, stored = self:GetActiveNote()
    if not stored then
        activeNote = nil
        KRT.NotesFrame:SetNote(nil)
        return
    end
    local parsed, err = KRT.NotesParser:Parse(stored or "")
    if err then
        activeNote = nil
        KRT.NotesFrame:SetNote(nil)
        return
    end

    if KRT.NotesMerge and name then
        local annotationText = self:GetAnnotation(name)
        if annotationText then
            local parsedAnnotation = KRT.NotesParser:Parse(annotationText)
            if parsedAnnotation then
                parsed = KRT.NotesMerge:Merge(parsed, parsedAnnotation)
            end
        end
    end

    activeNote = parsed
    KRT.NotesTags.MarkRelevance(activeNote, BuildPlayerCtx())
    KRT.NotesFrame:SetNote(activeNote)
end

function Notes:Initialize()
    self:MigrateLockSettings()
    KRT.NotesFrame:Init()
    KRT.NotesPopups:Init()
end

function Notes:OnEnable()
    self.eventFrame:RegisterEvent("ENCOUNTER_START")
    self.eventFrame:RegisterEvent("ENCOUNTER_END")
    self.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    self.eventFrame:RegisterEvent("ADDON_LOADED")
    self.eventFrame:SetScript("OnEvent", OnEvent)

    KRT.Comms:RegisterHandler(SEND_MSG_TYPE, OnNoteReceived)
    KRT.Comms:RegisterHandler(CLEAR_MSG_TYPE, OnClearReceived)

    HookBossMods()
    self:OnActiveNoteChanged()
    KRT.NotesFrame:RebuildRoster()
end

function Notes:OnDisable()
    StopEncounterPhaseAttempt()
    self.eventFrame:UnregisterAllEvents()
    self.eventFrame:SetScript("OnEvent", nil)

    testRunning = false
    StopTicker()
    KRT.NotesTimer:Stop()
    KRT.NotesPopups:DismissAll()
    KRT.NotesFrame:Hide()
end
