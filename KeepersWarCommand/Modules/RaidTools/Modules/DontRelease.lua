local KRT = KeepersRaidTools
local DontRelease = {}
KRT.DontRelease = DontRelease
KRT:RegisterModule("dontRelease", DontRelease)

KRT.defaults.dontRelease = {
    enabled = true,
    delay = 2,
    requireModifier = false,
    randomizeModifier = false,
    contentTypes = {
        openWorld = false,
        dungeon = { normal = false, heroic = false, mythic = false, mythicPlus = false },
        raid = { lfr = false, normal = true, heroic = true, mythic = true },
        scenario = { normal = false, heroic = false },
    },
}

local delayAccumulated = 0
local requiredModifier = nil
local overlayButton = nil
local blockingActive = false

local MODIFIERS = {
    { name = "Ctrl", check = IsControlKeyDown },
    { name = "Alt", check = IsAltKeyDown },
    { name = "Shift", check = IsShiftKeyDown },
}

function DontRelease:IsBlockingEnabled()
    local settings = KRT:GetSetting("dontRelease")
    if not settings or not settings.enabled then
        return false
    end
    return KRT.IsContentTypeEnabled(settings.contentTypes)
end

function DontRelease:GetDelayRemaining()
    local settings = KRT:GetSetting("dontRelease")
    return math.max(0, settings.delay - delayAccumulated)
end

function DontRelease:IsModifierSatisfied()
    local settings = KRT:GetSetting("dontRelease")
    if not settings.requireModifier then
        return true
    end
    if not requiredModifier then
        return true
    end

    local heldCount = 0
    local correctHeld = false

    for _, mod in ipairs(MODIFIERS) do
        if mod.check() then
            heldCount = heldCount + 1
            if mod.name == requiredModifier then
                correctHeld = true
            end
        end
    end

    return heldCount == 1 and correctHeld
end

function DontRelease:ShouldBlockRelease()
    if not self:IsBlockingEnabled() then
        return false
    end
    if self:GetDelayRemaining() > 0 then
        return true
    end
    if not self:IsModifierSatisfied() then
        return true
    end
    return false
end

local function CreateOverlayButton()
    local button = KRT.Components.CreateButton(UIParent, "KRT_DontReleaseOverlay")
    button:SetSelected(true)
    button:SetSize(120, 22)
    button:SetFrameStrata("TOOLTIP")
    button:SetFrameLevel(1000)
    button:Hide()

    button:SetScript("OnClick", function()
        -- Absorb click - do nothing
    end)

    button:SetScript("OnUpdate", function(self, elapsed)
        if not blockingActive then return end

        local settings = KRT:GetSetting("dontRelease")
        local modifierRequired = settings.requireModifier
        local modifierHeld = not modifierRequired or DontRelease:IsModifierSatisfied()

        if modifierRequired then
            if modifierHeld then
                delayAccumulated = delayAccumulated + elapsed
            else
                delayAccumulated = 0
            end
        else
            delayAccumulated = delayAccumulated + elapsed
        end

        local delayRemaining = settings.delay - delayAccumulated

        if delayRemaining > 0 then
            if modifierRequired and not modifierHeld then
                self:SetText(string.format("Hold [%s]", requiredModifier))
            else
                self:SetText(string.format("%.1f", delayRemaining))
            end
            self:EnableMouse(true)
            self:SetAlpha(1)
        elseif modifierRequired and not modifierHeld then
            delayAccumulated = 0
            self:SetText(string.format("Hold [%s]", requiredModifier))
            self:EnableMouse(true)
            self:SetAlpha(1)
        else
            self:EnableMouse(false)
            self:SetAlpha(0)
        end
    end)

    return button
end

local function PositionOverlay(dialog)
    if not overlayButton then
        overlayButton = CreateOverlayButton()
    end

    local button1 = dialog:GetButton1()
    if not button1 then return end

    overlayButton:ClearAllPoints()
    overlayButton:SetPoint("CENTER", button1, "CENTER", 0, 0)
    overlayButton:SetSize(button1:GetSize())
end

function DontRelease:OnDeathPopupShow(dialog)
    if not self:IsBlockingEnabled() then
        blockingActive = false
        if overlayButton then
            overlayButton:Hide()
        end
        return
    end

    delayAccumulated = 0
    blockingActive = true

    local settings = KRT:GetSetting("dontRelease")
    if settings.requireModifier then
        if settings.randomizeModifier then
            requiredModifier = MODIFIERS[math.random(#MODIFIERS)].name
        else
            requiredModifier = "Ctrl"
        end
    else
        requiredModifier = nil
    end

    PositionOverlay(dialog)

    if settings.requireModifier then
        overlayButton:SetText(string.format("Hold [%s]", requiredModifier))
    else
        overlayButton:SetText(string.format("%.1f", settings.delay))
    end
    overlayButton:EnableMouse(true)
    overlayButton:SetAlpha(1)
    overlayButton:Show()
end

function DontRelease:OnDeathPopupHide()
    blockingActive = false
    delayAccumulated = 0
    if overlayButton then
        overlayButton:Hide()
        overlayButton:EnableMouse(true)
        overlayButton:SetAlpha(1)
    end
end

function DontRelease:Initialize()
    local deathDialog = StaticPopupDialogs["DEATH"]
    if not deathDialog then
        return
    end

    local originalOnShow = deathDialog.OnShow
    local originalOnHide = deathDialog.OnHide

    deathDialog.OnShow = function(dialog, data)
        if originalOnShow then
            originalOnShow(dialog, data)
        end
        DontRelease:OnDeathPopupShow(dialog)
    end

    deathDialog.OnHide = function(dialog, data)
        DontRelease:OnDeathPopupHide()
        if originalOnHide then
            originalOnHide(dialog, data)
        end
    end
end

KRT:RegisterTab("Don't Release", function(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()
    container:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(container:GetWidth() - 40)
    scrollChild:SetHeight(600)
    scrollFrame:SetScrollChild(scrollChild)

    local yOffset = 0
    local ROW_HEIGHT = 24

    local function GetSettings()
        return KRT:GetSetting("dontRelease")
    end

    local function GetContentValue(settings, path)
        local value = settings
        for _, key in ipairs(path) do
            value = value[key]
        end
        return value
    end

    local function SetContentValue(settings, path, value)
        local node = settings
        for i = 1, #path - 1 do
            node = node[path[i]]
        end
        node[path[#path]] = value
    end

    local generalHeader = KRT.Components.GetHeader(scrollChild, "General")
    generalHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local enabledCheckbox = KRT.Components.GetCheckbox(scrollChild, "Enabled", function(value)
        GetSettings().enabled = value
    end)
    enabledCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    enabledCheckbox:SetValue(GetSettings().enabled)
    yOffset = yOffset - ROW_HEIGHT

    local delaySlider = KRT.Components.GetSliderWithInput(scrollChild, "Delay (seconds)", 1, 10, 1, false, function(value)
        GetSettings().delay = value
    end)
    delaySlider:SetPoint("TOPLEFT", 0, yOffset)
    delaySlider:SetValue(GetSettings().delay)
    yOffset = yOffset - ROW_HEIGHT

    yOffset = yOffset - 10
    local contentHeader = KRT.Components.GetHeader(scrollChild, "Block Release In")
    contentHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local contentCheckboxes = {
        { label = "Open World", path = {"contentTypes", "openWorld"} },
        { label = "Dungeon", path = {"contentTypes", "dungeon", "normal"} },
        { label = "Raid", path = {"contentTypes", "raid", "normal"} },
    }

    for i, info in ipairs(contentCheckboxes) do
        local checkbox = KRT.Components.GetCheckbox(scrollChild, info.label, function(value)
            SetContentValue(GetSettings(), info.path, value)
        end)
        checkbox:SetPoint("TOPLEFT", 0, yOffset)
        contentCheckboxes[i].widget = checkbox
        checkbox:SetValue(GetContentValue(GetSettings(), info.path))

        yOffset = yOffset - ROW_HEIGHT
    end

    yOffset = yOffset - 10
    local modifierHeader = KRT.Components.GetHeader(scrollChild, "Modifier Key")
    modifierHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local randomizeCheckbox

    local function UpdateRandomizeState(enabled)
        if not randomizeCheckbox then
            return
        end
        if enabled then
            randomizeCheckbox:SetAlpha(1)
            randomizeCheckbox:EnableMouse(true)
        else
            randomizeCheckbox:SetAlpha(0.5)
            randomizeCheckbox:EnableMouse(false)
        end
    end

    local requireModifierCheckbox = KRT.Components.GetCheckbox(scrollChild, "Required", function(value)
        GetSettings().requireModifier = value
        UpdateRandomizeState(value)
    end)
    requireModifierCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    requireModifierCheckbox:SetValue(GetSettings().requireModifier)
    yOffset = yOffset - ROW_HEIGHT

    randomizeCheckbox = KRT.Components.GetCheckbox(scrollChild, "Randomized", function(value)
        GetSettings().randomizeModifier = value
    end)
    randomizeCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    randomizeCheckbox:SetValue(GetSettings().randomizeModifier)
    UpdateRandomizeState(GetSettings().requireModifier)
    yOffset = yOffset - ROW_HEIGHT

    container:SetScript("OnShow", function()
        local settings = GetSettings()
        enabledCheckbox:SetValue(settings.enabled)
        delaySlider:SetValue(settings.delay)
        for _, info in ipairs(contentCheckboxes) do
            info.widget:SetValue(GetContentValue(settings, info.path))
        end
        requireModifierCheckbox:SetValue(settings.requireModifier)
        randomizeCheckbox:SetValue(settings.randomizeModifier)
        UpdateRandomizeState(settings.requireModifier)
    end)

    return container
end)

