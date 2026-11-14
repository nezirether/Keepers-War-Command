local KRT = KeepersRaidTools
local BattleResCounter = {}
KRT.BattleResCounter = BattleResCounter
KRT:RegisterModule("battleResCounter", BattleResCounter)

local defaults = {
    widgetEnabled = false,
    widgetScale = 100,
    widgetPosition = nil,
    zeroChargeOverlay = true,
    rosterRowEnabled = true,
    lockFrames = true,
}

KRT.defaults.battleResCounter = defaults

local REBIRTH_SPELL_ID = 20484

local charges = 0
local maxCharges = 0
local started = 0
local duration = 0
local inEncounter = false
local pollTicker = nil
local widgetFrame, placement
local preview = false
local pendingLayout = false
local function Settings()
    return KRT:GetSetting("battleResCounter")
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function Scale(value)
    return math.max(50, math.min(200, tonumber(value) or defaults.widgetScale))
end

local function FormatTimer()
    if charges >= maxCharges or duration == 0 then return "" end
    local remaining = math.max(0, duration - (GetTime() - started))
    return string.format("%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60))
end

local function ReadCharges()
    local info = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(REBIRTH_SPELL_ID)
    if not info or not info.maxCharges or info.maxCharges == 0 then
        return nil
    end
    return info.currentCharges, info.maxCharges, info.cooldownStartTime, info.cooldownDuration
end

function BattleResCounter:GetChargeState()
    return charges, inEncounter
end

function BattleResCounter:GetTimerText()
    return FormatTimer()
end

local function CreateWidget()
    -- This indicator does not cast a spell and has no secure action template.
    local frame = CreateFrame("Frame", "KRT_BattleResWidget", UIParent)
    frame:SetSize(88, 94)
    local border = frame:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.25, 0.29, 0.35, 1)
    local panel = frame:CreateTexture(nil, "BORDER")
    panel:SetPoint("TOPLEFT", 2, -2)
    panel:SetPoint("BOTTOMRIGHT", -2, 2)
    panel:SetColorTexture(0.08, 0.09, 0.12, 1)
    local outline = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    outline:SetAllPoints()
    outline:SetColorTexture(0.65, 0.24, 0.31, 1)
    outline:Hide()
    frame.outline = outline
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:Hide()

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOP", 0, -22)
    icon:SetSize(60, 60)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:SetTexture(C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(REBIRTH_SPELL_ID) or "Interface\\\\Icons\\\\Spell_Nature_Reincarnation")
    frame.icon = icon

    local desatOverlay = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    desatOverlay:SetAllPoints(icon)
    desatOverlay:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    desatOverlay:SetTexture(icon:GetTexture())
    desatOverlay:SetDesaturated(true)
    desatOverlay:SetVertexColor(0.4, 0.4, 0.4)
    desatOverlay:Hide()
    frame.desatOverlay = desatOverlay

    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(true)
    local regions = { cooldown:GetRegions() }
    for _, region in ipairs(regions) do
        if region:IsObjectType("Texture") and region:GetDrawLayer() == "OVERLAY" then
            region:SetTexture(nil)
            region:Hide()
        end
    end
    frame.cooldown = cooldown

    local textOverlay = CreateFrame("Frame", nil, frame)
    textOverlay:SetAllPoints()
    textOverlay:SetFrameLevel(cooldown:GetFrameLevel() + 1)

    local countText = KRT.Components.CreateText(textOverlay, KWCRaidHeadingFont)
    countText:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -3, 3)
    countText:SetTextColor(1, 1, 1)
    countText:Hide()
    frame.countText = countText

    local timerText = KRT.Components.CreateText(textOverlay, KWCRaidControlFont)
    timerText:SetPoint("CENTER", icon, "CENTER", 0, 0)
    timerText:SetTextColor(1, 1, 1)
    timerText:Hide()
    frame.timerText = timerText

    local title = KRT.Components.CreateText(textOverlay, KWCRaidSmallFont)
    title:SetPoint("TOP", 0, -5)
    title:SetText("BATTLE RES")
    local hint = KRT.Components.CreateText(textOverlay, KWCRaidControlFont)
    hint:SetPoint("BOTTOM", frame, "TOP", 0, 5)
    hint:SetText("DRAG TO MOVE")
    hint:SetTextColor(1, 0.75, 0.78)
    hint:Hide()
    frame.hint = hint

    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(REBIRTH_SPELL_ID)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return frame
end

local function ShowEncounterState()
    widgetFrame.countText:SetText(charges)
    widgetFrame.countText:Show()

    local timerStr = FormatTimer()
    if timerStr ~= "" then
        widgetFrame.timerText:SetText(timerStr)
        widgetFrame.timerText:Show()
    else
        widgetFrame.timerText:Hide()
    end

    if charges < maxCharges and duration > 0 then
        widgetFrame.cooldown:SetCooldown(started, duration)
    else
        widgetFrame.cooldown:Clear()
    end

    local settings = KRT:GetSetting("battleResCounter")
    if charges == 0 and settings and settings.zeroChargeOverlay then
        widgetFrame.icon:Hide()
        widgetFrame.desatOverlay:Show()
    else
        widgetFrame.icon:Show()
        widgetFrame.desatOverlay:Hide()
    end
end

local function ShowIdleState()
    widgetFrame.icon:Show()
    widgetFrame.desatOverlay:Hide()
    widgetFrame.countText:Hide()
    widgetFrame.timerText:Hide()
    widgetFrame.cooldown:Clear()
end

local function UpdateWidget()
    if not widgetFrame then return end
    local settings = Settings()
    if not (IsInRaid and IsInRaid()) or not settings.widgetEnabled then
        preview = false
        widgetFrame:Hide()
        return
    end
    local unlocked = not settings.lockFrames and not InCombat()
    local configuring = not InCombat() and (preview or unlocked)
    widgetFrame.outline:SetShown(unlocked)
    widgetFrame.hint:SetShown(unlocked)
    if not InCombat() and widgetFrame.configuring ~= configuring then
        widgetFrame.configuring = configuring
        widgetFrame:SetFrameStrata(configuring and "FULLSCREEN_DIALOG" or "MEDIUM")
        widgetFrame:SetFrameLevel(configuring and 200 or 1)
    end
    if inEncounter then
        ShowEncounterState()
    else
        ShowIdleState()
    end
    widgetFrame:Show()
end

-- Older builds saved an anchor tuple in frame-scale units. Convert it once
-- without changing the setting key or the old on-screen center.
local function RestoreLegacyPosition(frame, settings)
    local pos = settings.widgetPosition
    if type(pos) ~= "table" or not pos.point or not pos.relativePoint then return end
    frame:SetScale(Scale(settings.widgetScale) / 100)
    local ok = pcall(frame.SetPoint, frame, pos.point, UIParent, pos.relativePoint, pos.x or 0, pos.y or 0)
    local x, y
    if ok then x, y = frame:GetCenter() end
    if x and y then
        local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        settings.widgetPosition = {
            nx = x * ratio / UIParent:GetWidth(),
            ny = y * ratio / UIParent:GetHeight(),
        }
    end
end

-- Adapt the existing percentage scale and inverse lock flag to the shared
-- placement API while keeping all writes in the current raid settings.
local function CreatePlacementSettings()
    return setmetatable({}, {
        __index = function(_, key)
            local settings = Settings()
            if key == "widgetScale" then return Scale(settings.widgetScale) / 100 end
            if key == "widgetUnlocked" then return not settings.lockFrames and not InCombat() end
            return settings[key]
        end,
        __newindex = function(_, key, value)
            local settings = Settings()
            if key == "widgetScale" then settings.widgetScale = value * 100
            elseif key == "widgetUnlocked" then settings.lockFrames = not value
            else settings[key] = value end
        end,
    })
end

local function FitWidget()
    local x, y = widgetFrame:GetCenter()
    if not x or not y then return end
    local ratio = widgetFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local width, height = UIParent:GetWidth() / ratio, UIParent:GetHeight() / ratio
    local halfWidth = math.min(widgetFrame:GetWidth() / 2, width / 2)
    local halfHeight = math.min(widgetFrame:GetHeight() / 2, height / 2)
    local boundedX = math.max(halfWidth, math.min(width - halfWidth, x))
    local boundedY = math.max(halfHeight, math.min(height - halfHeight, y))
    if boundedX ~= x or boundedY ~= y then
        widgetFrame:ClearAllPoints()
        widgetFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", boundedX, boundedY)
    end
end

local function ApplyLayout()
    if InCombat() then
        pendingLayout = pendingLayout or true
        return
    end
    if not placement then return end
    pendingLayout = false
    local settings = Settings()
    -- Finish a drag before applying configuration geometry.
    local locked = settings.lockFrames
    placement.SetUnlocked(false)
    settings.lockFrames = locked
    placement.SetScale(Scale(settings.widgetScale) / 100)
    FitWidget()
    UpdateWidget()
end

function BattleResCounter:SetWidgetEnabled(value)
    Settings().widgetEnabled = not not value
    if not value then preview = false end
    UpdateWidget()
end

function BattleResCounter:SetPreview(value)
    preview = not not value
    UpdateWidget()
end

function BattleResCounter:IsPreviewShown()
    return preview
end

function BattleResCounter:CanConfigurePosition()
    return IsInRaid and IsInRaid() and Settings().widgetEnabled and not InCombat()
end

function BattleResCounter:SetWidgetUnlocked(value)
    Settings().lockFrames = not value
    ApplyLayout()
end

function BattleResCounter:SetWidgetScale(value)
    Settings().widgetScale = Scale(value)
    ApplyLayout()
end

function BattleResCounter:GetWidgetScale()
    return Scale(Settings().widgetScale)
end

function BattleResCounter:ResetPosition()
    if InCombat() then
        pendingLayout = "reset"
        return
    end
    if placement then
        placement.Reset()
        FitWidget()
    end
    UpdateWidget()
end

function BattleResCounter:ResetWidgetDefaults()
    local settings = Settings()
    for key, value in pairs(defaults) do settings[key] = value end
    preview = false
    self:ResetPosition()
    ApplyLayout()
end

local function PollCharges()
    local c, mc, s, d = ReadCharges()
    if c then
        charges, maxCharges, started, duration = c, mc, s, d
        inEncounter = true
    else
        charges, maxCharges, started, duration = 0, 0, 0, 0
        inEncounter = false
    end
    UpdateWidget()
end

local function OnEvent(_, event)
    if event == "ENCOUNTER_START" then
        inEncounter = true
        PollCharges()
        return
    end

    if event == "ENCOUNTER_END" then
        inEncounter = false
        charges, maxCharges, started, duration = 0, 0, 0, 0
        UpdateWidget()
    end
end

local function NotifyCooldownRoster()
    if not KRT.CooldownRoster or not KRT.CooldownRoster.active then return end
    KRT.CooldownRoster:RebuildRoster()
    KRT.CooldownRoster:UpdateDisplay()
end

function BattleResCounter:GetEnabledSetting()
    return Settings() ~= nil
end

function BattleResCounter:IsActivatable()
    return IsInGroup() or IsInRaid()
end

function BattleResCounter:Initialize()
    widgetFrame = CreateWidget()
    local settings = Settings()
    RestoreLegacyPosition(widgetFrame, settings)
    local placementSettings = CreatePlacementSettings()
    placement = KWC.AlertFrameControls.Attach(widgetFrame, function() return placementSettings end, "widget", UIParent:GetHeight() / 2 - 147)
    placement.Initialize()
    FitWidget()
    UpdateWidget()
end

function BattleResCounter:OnEnable()
    self.eventFrame:RegisterEvent("ENCOUNTER_START")
    self.eventFrame:RegisterEvent("ENCOUNTER_END")
    self.eventFrame:SetScript("OnEvent", OnEvent)

    PollCharges()
    pollTicker = C_Timer.NewTicker(1, PollCharges)

    UpdateWidget()
    NotifyCooldownRoster()
end

function BattleResCounter:OnDisable()
    if pollTicker then
        pollTicker:Cancel()
        pollTicker = nil
    end

    self.eventFrame:UnregisterAllEvents()
    self.eventFrame:SetScript("OnEvent", nil)

    inEncounter = false
    charges, maxCharges, started, duration = 0, 0, 0, 0

    UpdateWidget()
    NotifyCooldownRoster()
end

KWC.On("PLAYER_REGEN_DISABLED", function()
    if placement then
        local locked = Settings().lockFrames
        placement.SetUnlocked(false)
        Settings().lockFrames = locked
    end
    UpdateWidget()
end)
KWC.On("DISPLAY_SIZE_CHANGED", ApplyLayout)
KWC.On("UI_SCALE_CHANGED", ApplyLayout)
KWC.On("GROUP_ROSTER_UPDATE", UpdateWidget)
KWC.On("PLAYER_ENTERING_WORLD", UpdateWidget)
KWC.On("PLAYER_REGEN_ENABLED", function()
    if pendingLayout == "reset" then BattleResCounter:ResetPosition() end
    if pendingLayout then ApplyLayout() else UpdateWidget() end
end)
KRT:RegisterApplyCallback("battleResCounter", function()
    ApplyLayout()
    NotifyCooldownRoster()
end)
