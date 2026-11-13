local KRT = KeepersRaidTools
local ReadyCheck = {}
KRT.ReadyCheck = ReadyCheck
KRT:RegisterModule("readyCheck", ReadyCheck)

local RAID_BUFFS = {
    {
        key = "arcaneIntellect",
        name = "Arcane Intellect",
        spellId = 1459,
        class = "MAGE",
    },
    {
        key = "battleShout",
        name = "Battle Shout",
        spellId = 6673,
        class = "WARRIOR",
    },
    {
        key = "markOfTheWild",
        name = "Mark of the Wild",
        spellId = 1126,
        class = "DRUID",
    },
    {
        key = "powerWordFortitude",
        name = "Power Word: Fortitude",
        spellId = 21562,
        class = "PRIEST",
    },
}

local SOULSTONE_SPELL_ID = 20707
local SOULSTONE_BUFF_NAME = "Soulstone"

KRT.RAID_BUFFS = RAID_BUFFS
KRT.SOULSTONE_SPELL_ID = SOULSTONE_SPELL_ID
KRT.SOULSTONE_BUFF_NAME = SOULSTONE_BUFF_NAME
local MISSING_ADDON_MESSAGE = "Your raid leader is using KeepersRaidTools for coordination. Please make sure you have it installed."
local VERSION_WHISPER_OPTIONS = {
    { name = "Off", value = "off" },
    { name = "Guild Only", value = "guild" },
    { name = "On", value = "on" },
}

KRT.defaults.readyCheck = {
    enabled = true,
    checkSoulstones = true,
    checkDead = true,
    whisperMissingAddon = "guild",
    whisperOutdatedAddon = "guild",
    arcaneIntellect = true,
    battleShout = true,
    markOfTheWild = true,
    powerWordFortitude = true,
}

local function GetPlayersByClass(className)
    local players = {}
    if not IsInRaid() then return players end
    for _, member in pairs(KRT.GroupInspect.members) do
        if member.class == className then
            table.insert(players, member.name)
        end
    end
    return players
end

local function GetAllRaidMembers()
    local members = {}
    local skipped = {}
    if not IsInRaid() then return members, skipped end
    for unit in KRT:IterateGroup() do
        if UnitIsConnected(unit) then
            local name = GetUnitName(unit, true)
            if name then
                if UnitIsVisible(unit) then
                    table.insert(members, { name = name, unit = unit })
                else
                    table.insert(skipped, name)
                end
            end
        end
    end
    return members, skipped
end

local function GetDeadMembers()
    local dead = {}
    if not IsInRaid() then return dead end
    for unit in KRT:IterateGroup() do
        if UnitIsConnected(unit) and not UnitIsUnit(unit, "player") and UnitIsDeadOrGhost(unit) then
            local name = GetUnitName(unit, true)
            if name then
                table.insert(dead, name)
            end
        end
    end
    return dead
end

local function GetHealers()
    local healers = {}
    if not IsInRaid() then return healers end
    for unit in KRT:IterateGroup() do
        if UnitIsConnected(unit) then
            local role = UnitGroupRolesAssigned(unit)
            if role == "HEALER" then
                local name = GetUnitName(unit, true)
                if name then
                    table.insert(healers, { name = name, unit = unit })
                end
            end
        end
    end
    return healers
end

local function HasBuff(unit, buffName)
    return C_UnitAuras.GetAuraDataBySpellName(unit, buffName, "HELPFUL") ~= nil
end

local function AnyoneHasBuff(members, buffName)
    for _, member in ipairs(members) do
        if HasBuff(member.unit, buffName) then
            return true
        end
    end
    return false
end

local function SendWhisper(playerName, message)
    local success = pcall(function()
        C_ChatInfo.SendChatMessage(message, "WHISPER", nil, playerName)
    end)
    return success
end

function ReadyCheck.DecodeVersion(encodedVersion)
    local major = math.floor(encodedVersion / 1000000)
    local minor = math.floor(encodedVersion % 1000000 / 1000)
    local patch = encodedVersion % 1000
    return string.format("%d.%d.%d", major, minor, patch)
end

local function QualifyName(name)
    if not name or name == "" then
        return nil
    end
    if name:find("-", 1, true) then
        return name
    end

    local realm = GetNormalizedRealmName()
    if not realm or realm == "" then
        return nil
    end
    return name .. "-" .. realm
end

local function BuildGuildMemberSet()
    local guildMembers = {}
    if not IsInGuild() then
        return guildMembers
    end

    for index = 1, GetNumGuildMembers() do
        local name = GetGuildRosterInfo(index)
        local qualifiedName = QualifyName(name)
        if qualifiedName then
            guildMembers[qualifiedName] = true
        end
    end
    return guildMembers
end

local function PreferenceAllowsWhisper(preference, memberName, guildMembers)
    if preference == "on" then
        return true
    end
    if preference ~= "guild" then
        return false
    end

    local qualifiedName = QualifyName(memberName)
    return qualifiedName and guildMembers[qualifiedName] or false
end

local function CheckAddonVersions(settings)
    local missingPreference = settings.whisperMissingAddon
    local outdatedPreference = settings.whisperOutdatedAddon
    if missingPreference == "off" and outdatedPreference == "off" then
        return
    end

    local guildMembers = {}
    if missingPreference == "guild" or outdatedPreference == "guild" then
        guildMembers = BuildGuildMemberSet()
    end

    local playerGUID = UnitGUID("player")
    local player = playerGUID and KRT.GroupInspect.members[playerGUID]
    local raidLeaderVersion = player and player.addonVersion

    for guid, member in pairs(KRT.GroupInspect.members) do
        if guid ~= playerGUID and member.specId ~= nil then
            local memberVersion = member.addonVersion
            if memberVersion == nil then
                if PreferenceAllowsWhisper(missingPreference, member.name, guildMembers) then
                    SendWhisper(member.name, MISSING_ADDON_MESSAGE)
                end
            elseif type(memberVersion) == "number" and type(raidLeaderVersion) == "number"
                and memberVersion < raidLeaderVersion then
                if PreferenceAllowsWhisper(outdatedPreference, member.name, guildMembers) then
                    local message = string.format(
                        "Your version of KeepersRaidTools (%s) is out of date. Please update to %s.",
                        ReadyCheck.DecodeVersion(memberVersion),
                        ReadyCheck.DecodeVersion(raidLeaderVersion)
                    )
                    SendWhisper(member.name, message)
                end
            end
        end
    end
end

local function NotifyPlayers(players, message)
    for _, name in ipairs(players) do
        SendWhisper(name, message)
    end
end

local function NagDeadPlayers()
    for _, name in ipairs(GetDeadMembers()) do
        SendWhisper(name, "Please accept your resurrection before the pull.")
    end
end

local function CheckRaidBuff(buff, allMembers, skippedMembers, totalRaid)
    local providers = GetPlayersByClass(buff.class)
    if #providers == 0 then
        return
    end

    local missing = {}
    for _, member in ipairs(allMembers) do
        if not HasBuff(member.unit, buff.name) then
            table.insert(missing, member.name)
        end
    end
    if #missing == 0 then
        return
    end

    print(string.format(
        "KRT: %s missing â€” checked %d/%d, missing: %s%s",
        buff.name,
        #allMembers,
        totalRaid,
        table.concat(missing, ", "),
        #skippedMembers > 0 and (", skipped (out of range): " .. table.concat(skippedMembers, ", ")) or ""
    ))
    NotifyPlayers(providers, "Missing raid buff: " .. buff.name .. ".")
end

local function CheckSoulstones()
    local warlocks = GetPlayersByClass("WARLOCK")
    if #warlocks == 0 then
        return
    end

    local healers = GetHealers()
    if #healers == 0 or AnyoneHasBuff(healers, SOULSTONE_BUFF_NAME) then
        return
    end

    NotifyPlayers(warlocks, "No healer has a Soulstone. Please apply one before the pull.")
end

function ReadyCheck:OnReadyCheck()
    local settings = KRT:GetSetting("readyCheck")
    if not settings or not settings.enabled then
        return
    end
    if not IsInRaid() then
        return
    end
    if not UnitIsGroupLeader("player") then
        return
    end

    -- Dead nags are independent of buff auras, so they run before the secret-aura guard.
    if settings.checkDead then
        NagDeadPlayers()
    end

    local allMembers, skippedMembers = GetAllRaidMembers()
    if #allMembers > 0 then
        local aurasAreSecret = C_Secrets and C_Secrets.ShouldAurasBeSecret
            and C_Secrets.ShouldAurasBeSecret()
        if not aurasAreSecret then
            local totalRaid = #allMembers + #skippedMembers
            for _, buff in ipairs(RAID_BUFFS) do
                if settings[buff.key] then
                    CheckRaidBuff(buff, allMembers, skippedMembers, totalRaid)
                end
            end

            if settings.checkSoulstones then
                CheckSoulstones()
            end
        end
    end

    CheckAddonVersions(settings)
end

KRT:RegisterTab("Ready Check", function(parent)
    return KRT.Components.GetSubTabGroup(parent, {
        {
            name = "Notifications",
            setup = function(panel)
                local yOffset = 0
                local ROW_HEIGHT = 24

                local function GetSettings()
                    return KRT:GetSetting("readyCheck")
                end

                local enabledCheckbox = KRT.Components.GetCheckbox(panel, "Enabled", function(value)
                    GetSettings().enabled = value
                end)
                enabledCheckbox:SetPoint("TOPLEFT", 0, yOffset)
                enabledCheckbox:SetValue(GetSettings().enabled)

                local raidLeaderNote = enabledCheckbox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                raidLeaderNote:SetPoint("LEFT", enabledCheckbox, "CENTER", 20, 0)
                raidLeaderNote:SetText("(requires Raid Leader)")

                yOffset = yOffset - ROW_HEIGHT

                yOffset = yOffset - 10

                local buffCheckboxes = {}
                for _, buff in ipairs(RAID_BUFFS) do
                    local checkbox = KRT.Components.GetCheckbox(panel, buff.name, function(value)
                        GetSettings()[buff.key] = value
                    end)
                    checkbox:SetPoint("TOPLEFT", 0, yOffset)
                    checkbox:SetValue(GetSettings()[buff.key])
                    buffCheckboxes[buff.key] = checkbox
                    yOffset = yOffset - ROW_HEIGHT
                end

                local soulstoneCheckbox = KRT.Components.GetCheckbox(panel, "Soul Stones", function(value)
                    GetSettings().checkSoulstones = value
                end)
                soulstoneCheckbox:SetPoint("TOPLEFT", 0, yOffset)
                soulstoneCheckbox:SetValue(GetSettings().checkSoulstones)
                yOffset = yOffset - ROW_HEIGHT

                local deadCheckbox = KRT.Components.GetCheckbox(panel, "Dead players", function(value)
                    GetSettings().checkDead = value
                end)
                deadCheckbox:SetPoint("TOPLEFT", 0, yOffset)
                deadCheckbox:SetValue(GetSettings().checkDead)
                yOffset = yOffset - ROW_HEIGHT

                local missingAddonDropdown = KRT.Components.GetBasicDropdown(
                    panel,
                    "Missing Addon",
                    function() return VERSION_WHISPER_OPTIONS end,
                    function(value) return GetSettings().whisperMissingAddon == value end,
                    function(value) GetSettings().whisperMissingAddon = value end
                )
                missingAddonDropdown:SetPoint("TOPLEFT", 0, yOffset)
                yOffset = yOffset - ROW_HEIGHT

                local outdatedAddonDropdown = KRT.Components.GetBasicDropdown(
                    panel,
                    "Outdated Addon",
                    function() return VERSION_WHISPER_OPTIONS end,
                    function(value) return GetSettings().whisperOutdatedAddon == value end,
                    function(value) GetSettings().whisperOutdatedAddon = value end
                )
                outdatedAddonDropdown:SetPoint("TOPLEFT", 0, yOffset)
                yOffset = yOffset - ROW_HEIGHT

                panel:SetScript("OnShow", function()
                    local settings = GetSettings()
                    enabledCheckbox:SetValue(settings.enabled)
                    for _, buff in ipairs(RAID_BUFFS) do
                        buffCheckboxes[buff.key]:SetValue(settings[buff.key])
                    end
                    soulstoneCheckbox:SetValue(settings.checkSoulstones)
                    deadCheckbox:SetValue(settings.checkDead)
                    missingAddonDropdown:SetValue()
                    outdatedAddonDropdown:SetValue()
                end)
            end,
        },
        {
            name = "Ready Screen",
            setup = function(panel)
                local yOffset = 0
                local ROW_HEIGHT = 24

                local function GetSettings()
                    return KRT:GetSetting("readyScreen")
                end

                local enabledCheckbox = KRT.Components.GetCheckbox(panel, "Enabled", function(value)
                    GetSettings().enabled = value
                    KRT:ApplySettings("readyScreen")
                end)
                enabledCheckbox:SetPoint("TOPLEFT", 0, yOffset)
                enabledCheckbox:SetValue(GetSettings().enabled)
                yOffset = yOffset - ROW_HEIGHT

                local autoDismissCheckbox = KRT.Components.GetCheckbox(panel, "Close after ready", function(value)
                    GetSettings().autoDismiss = value
                end)
                autoDismissCheckbox:SetPoint("TOPLEFT", 0, yOffset)
                autoDismissCheckbox:SetValue(GetSettings().autoDismiss)
                yOffset = yOffset - ROW_HEIGHT

                panel:SetScript("OnShow", function()
                    local settings = GetSettings()
                    enabledCheckbox:SetValue(settings.enabled)
                    autoDismissCheckbox:SetValue(settings.autoDismiss)
                end)
            end,
        },
    })
end)

function ReadyCheck:IsActivatable()
    return IsInRaid()
end

function ReadyCheck:OnEnable()
    self.eventFrame:RegisterEvent("READY_CHECK")
    self.eventFrame:SetScript("OnEvent", function(_, event)
        if event == "READY_CHECK" then
            ReadyCheck:OnReadyCheck()
        end
    end)
end

function ReadyCheck:OnDisable()
    self.eventFrame:UnregisterAllEvents()
    self.eventFrame:SetScript("OnEvent", nil)
end

