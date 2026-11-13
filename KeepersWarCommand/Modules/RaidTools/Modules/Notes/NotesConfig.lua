local KRT = KeepersRaidTools
local NotesConfig = {}
KRT.NotesConfig = NotesConfig

local TOOLTIP_NO_PRIVILEGE = "Requires raid leader or assistant."
local TOOLTIP_COMBAT = "Cannot send during combat."
local TOOLTIP_NO_SELECTION = "No note selected."
local ERROR_NAME_REQUIRED = "Name is required."
local ERROR_NAME_TAKEN = "A note with that name already exists."

local LIST_HEIGHT = 180
local LIST_ROW_HEIGHT = 20
local ACTIVE_COLOR = { r = 0.4, g = 0.8, b = 1 }
local SELECTED_COLOR = { r = 0.3, g = 0.3, b = 0.5 }

local OUTLINE_OPTIONS = {
    { name = "None",          value = "NONE" },
    { name = "Outline",       value = "OUTLINE" },
    { name = "Thick Outline", value = "THICKOUTLINE" },
    { name = "Monochrome",    value = "MONOCHROME" },
}

local HIDE_MODE_OPTIONS = {
    { name = "Immediately", value = "Immediately" },
    { name = "Fade",        value = "Fade" },
    { name = "Never",       value = "Never" },
}

local GROW_OPTIONS = {
    { name = "Up",   value = "Up" },
    { name = "Down", value = "Down" },
}

local SOUND_CHANNEL_OPTIONS = {
    { name = "Master",              value = "Master" },
    { name = "Sound Effects (SFX)", value = "SFX" },
    { name = "Music",               value = "Music" },
    { name = "Ambience",            value = "Ambience" },
    { name = "Dialog",              value = "Dialog" },
}

local POPUP_TYPES = { "Icon", "Bar", "Text", "Circle" }

local CONTENT_CHECKBOXES = {
    { label = "Open World",        path = { "contentTypes", "openWorld" } },
    { label = "Dungeon",  path = { "contentTypes", "dungeon", "normal" } },
    { label = "Raid",     path = { "contentTypes", "raid", "normal" } },
}

local function GetSettings()
    return KRT:GetSetting("notes")
end

local function ReadPath(settings, path)
    local value = settings
    for _, key in ipairs(path) do
        value = value[key]
    end
    return value
end

local function WritePath(settings, path, value)
    local node = settings
    for i = 1, #path - 1 do
        node = node[path[i]]
    end
    node[path[#path]] = value
end

local function ListFonts()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then
        return {}
    end
    local names = LSM:List("font")
    local items = {}
    for _, name in ipairs(names) do
        items[#items + 1] = { name = name, value = name }
    end
    return items
end

local function ListStatusBars()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then
        return {
            {
                name = "Blizzard",
                value = "Blizzard",
                path = "Interface\\TargetingFrame\\UI-StatusBar",
            },
        }
    end
    local items = {}
    for _, name in ipairs(LSM:List("statusbar")) do
        items[#items + 1] = {
            name = name,
            value = name,
            path = LSM:Fetch("statusbar", name),
        }
    end
    return items
end

local function SortedNoteNames()
    local settings = GetSettings()
    local names = {}
    for name in pairs(settings.savedNotes or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

StaticPopupDialogs["KRT_NOTES_DELETE"] = {
    text = "Delete note \"%s\"?",
    button1 = YES,
    button2 = NO,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    OnAccept = function()
        if NotesConfig.OnDeleteNote then
            NotesConfig.OnDeleteNote()
        end
    end,
}

local function OnEditorSaved(savedName)
    if NotesConfig._refreshAfterSave then
        NotesConfig._refreshAfterSave(savedName)
    end
end

KRT:RegisterTab("Notes", function(parent)
    local ROW_HEIGHT = 28

    local function SetupNotes(panel)
        local childWidth = panel:GetWidth()
        local yOffset = -10

        local selectedNote

        local refreshGates
        local refreshList
        local RefreshTestNoteButton

        local function CurrentActiveName()
            return (KRT.Notes:GetActiveNote())
        end

        local function IsNotesFrameShown()
            local frame = _G.KRT_NotesFrame
            return frame ~= nil and frame:IsShown()
        end

        local function PushIfActive(name)
            if name ~= CurrentActiveName() then
                return
            end
            KRT.Notes:OnActiveNoteChanged()
        end

        local listFrame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        listFrame:SetPoint("TOPLEFT", 20, yOffset)
        listFrame:SetSize(childWidth - 48, LIST_HEIGHT)
        listFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        listFrame:SetBackdropColor(0, 0, 0, 0.5)

        local listScroll = CreateFrame("ScrollFrame", nil, listFrame, "UIPanelScrollFrameTemplate")
        listScroll:SetPoint("TOPLEFT", 6, -6)
        listScroll:SetPoint("BOTTOMRIGHT", -26, 6)

        local listChild = CreateFrame("Frame", nil, listScroll)
        listChild:SetSize(childWidth - 80, LIST_HEIGHT)
        listScroll:SetScrollChild(listChild)

        local listRows = {}

        local function SelectNote(name)
            selectedNote = name
            refreshList()
            refreshGates()
        end

        refreshList = function()
            local names = SortedNoteNames()
            local activeName = CurrentActiveName()

            if selectedNote and not GetSettings().savedNotes[selectedNote] then
                selectedNote = nil
            end

            for i, name in ipairs(names) do
                local row = listRows[i]
                if not row then
                    row = CreateFrame("Button", nil, listChild)
                    row:SetHeight(LIST_ROW_HEIGHT)
                    row:SetPoint("TOPLEFT", 0, -(i - 1) * LIST_ROW_HEIGHT)
                    row:SetPoint("RIGHT", listChild, "RIGHT", 0, 0)

                    row.highlight = row:CreateTexture(nil, "BACKGROUND")
                    row.highlight:SetAllPoints()
                    row.highlight:SetColorTexture(SELECTED_COLOR.r, SELECTED_COLOR.g, SELECTED_COLOR.b, 0.6)
                    row.highlight:Hide()

                    row.label = KRT.Components.CreateText(row, KWCRaidControlFont)
                    row.label:SetPoint("LEFT", 6, 0)
                    row.label:SetPoint("RIGHT", -6, 0)
                    row.label:SetJustifyH("LEFT")

                    row:SetScript("OnClick", function(self)
                        SelectNote(self.noteName)
                    end)

                    listRows[i] = row
                end

                row.noteName = name
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -(i - 1) * LIST_ROW_HEIGHT)
                row:SetPoint("RIGHT", listChild, "RIGHT", 0, 0)

                local isActive = (name == activeName)
                local labelText = name
                if isActive then
                    labelText = name .. " (active)"
                    row.label:SetTextColor(ACTIVE_COLOR.r, ACTIVE_COLOR.g, ACTIVE_COLOR.b)
                else
                    row.label:SetTextColor(1, 1, 1)
                end
                row.label:SetText(labelText)

                if name == selectedNote then
                    row.highlight:Show()
                else
                    row.highlight:Hide()
                end

                row:Show()
            end

            for i = #names + 1, #listRows do
                listRows[i]:Hide()
            end

            listChild:SetHeight(math.max(LIST_HEIGHT, #names * LIST_ROW_HEIGHT))
        end

        yOffset = yOffset - LIST_HEIGHT - 8

        NotesConfig._refreshAfterSave = function(savedName)
            selectedNote = savedName
            refreshList()
            refreshGates()
            PushIfActive(savedName)
        end

        local buttonRow = CreateFrame("Frame", nil, panel)
        buttonRow:SetPoint("TOPLEFT", 20, yOffset)
        buttonRow:SetSize(childWidth - 48, 24)

        local function MakeButton(label, width, anchor, fromRight)
            local button = KRT.Components.CreateButton(buttonRow)
            button:SetSize(width, 22)
            if fromRight then
                if anchor then
                    button:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
                else
                    button:SetPoint("RIGHT", 0, 0)
                end
            else
                if anchor then
                    button:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
                else
                    button:SetPoint("LEFT", 0, 0)
                end
            end
            button:SetText(label)
            return button
        end

        local newButton = MakeButton("New", 60)
        local editButton = MakeButton("Edit", 60, newButton)
        local annotateButton = MakeButton("Annotate", 70, editButton)
        local duplicateButton = MakeButton("Duplicate", 75, annotateButton)
        local deleteButton = MakeButton("Delete", 60, duplicateButton)

        local testButton = MakeButton("Test", 60, nil, true)
        local showHideButton = MakeButton("Show", 60, testButton, true)
        local clearButton = MakeButton("Clear", 60, showHideButton, true)
        local sendButton = MakeButton("Send", 70, clearButton, true)
        local activateButton = MakeButton("Activate", 70, clearButton, true)

        yOffset = yOffset - 30

        local buttonError = KRT.Components.CreateText(panel, KWCRaidSmallFont)
        buttonError:SetPoint("TOPLEFT", 20, yOffset)
        buttonError:SetWidth(childWidth - 48)
        buttonError:SetJustifyH("LEFT")
        buttonError:SetTextColor(1, 0.3, 0.3, 1)
        buttonError:SetText("")

        yOffset = yOffset - 22

        newButton:SetScript("OnClick", function()
            buttonError:SetText("")
            KRT.NotesEditor:Open(nil, "")
        end)

        editButton:SetScript("OnClick", function()
            if not selectedNote then
                return
            end
            local text = GetSettings().savedNotes[selectedNote]
            buttonError:SetText("")
            KRT.NotesEditor:Open(selectedNote, text or "", "edit")
        end)

        annotateButton:SetScript("OnClick", function()
            if not selectedNote then
                return
            end
            local text = GetSettings().savedNotes[selectedNote]
            buttonError:SetText("")
            KRT.NotesEditor:Open(selectedNote, text or "", "annotate")
        end)

        duplicateButton:SetScript("OnClick", function()
            if not selectedNote then
                return
            end
            buttonError:SetText("")
            local ok, duplicateName = KRT.Notes:DuplicateNote(selectedNote)
            if not ok then
                return
            end
            SelectNote(duplicateName)
        end)

        activateButton:SetScript("OnClick", function()
            if not selectedNote then
                return
            end
            buttonError:SetText("")
            KRT.Notes:ActivateNote(selectedNote, "self")
            KRT.NotesFrame:Show()
            refreshList()
            refreshGates()
        end)

        deleteButton:SetScript("OnClick", function()
            if not selectedNote then
                return
            end
            buttonError:SetText("")
            StaticPopup_Show("KRT_NOTES_DELETE", selectedNote)
        end)

        sendButton:SetScript("OnClick", function()
            local ok, reason = KRT.Notes:BroadcastNote(selectedNote)
            buttonError:SetText(not ok and reason or "")
            refreshList()
            refreshGates()
        end)

        clearButton:SetScript("OnClick", function()
            local ok, reason = KRT.Notes:BroadcastClear()
            buttonError:SetText(not ok and reason or "")
            refreshList()
            refreshGates()
        end)

        showHideButton:SetScript("OnClick", function()
            buttonError:SetText("")
            if not selectedNote then
                KRT.NotesFrame:Toggle()
                refreshGates()
                return
            end
            if IsNotesFrameShown() then
                KRT.NotesFrame:Hide()
                refreshGates()
                return
            end
            KRT.Notes:ActivateNote(selectedNote, "self")
            KRT.NotesFrame:Show()
            refreshGates()
        end)

        local function PrivilegeCombatReason()
            if IsInGroup() and not KRT.Comms:IsSenderPrivileged(UnitName("player")) then
                return TOOLTIP_NO_PRIVILEGE
            end
            if InCombatLockdown() then
                return TOOLTIP_COMBAT
            end
            return nil
        end

        local function ApplyGate(button, reason)
            if reason then
                button:Disable()
                button.disabledReason = reason
            else
                button:Enable()
                button.disabledReason = nil
            end
        end

        local function HookTooltip(button)
            button:SetScript("OnEnter", function(self)
                if not self.disabledReason then
                    return
                end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.disabledReason, 1, 0.3, 0.3, true)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end

        HookTooltip(sendButton)
        HookTooltip(clearButton)
        HookTooltip(editButton)
        HookTooltip(annotateButton)
        HookTooltip(duplicateButton)
        HookTooltip(deleteButton)
        HookTooltip(activateButton)

        refreshGates = function()
            local isPrivileged = not IsInGroup() or KRT.Comms:IsSenderPrivileged(UnitName("player"))
            local inCombat = InCombatLockdown and InCombatLockdown()

            if isPrivileged then
                sendButton:Show()
                activateButton:Hide()
                local sendReason
                if inCombat then
                    sendReason = TOOLTIP_COMBAT
                elseif not selectedNote then
                    sendReason = TOOLTIP_NO_SELECTION
                end
                ApplyGate(sendButton, sendReason)
            else
                sendButton:Hide()
                activateButton:Show()
                local activateReason
                if not selectedNote then
                    activateReason = TOOLTIP_NO_SELECTION
                elseif KRT.Notes:GetActiveNoteSource() == "broadcast" then
                    activateReason = "The raid leader has set an active note."
                end
                ApplyGate(activateButton, activateReason)
            end

            local clearReason
            if isPrivileged then
                if inCombat then clearReason = TOOLTIP_COMBAT end
            else
                clearReason = TOOLTIP_NO_PRIVILEGE
            end
            ApplyGate(clearButton, clearReason)
            ApplyGate(editButton, not selectedNote and TOOLTIP_NO_SELECTION or nil)
            ApplyGate(annotateButton, not selectedNote and TOOLTIP_NO_SELECTION or nil)
            ApplyGate(duplicateButton, not selectedNote and TOOLTIP_NO_SELECTION or nil)
            ApplyGate(deleteButton, not selectedNote and TOOLTIP_NO_SELECTION or nil)

            if IsNotesFrameShown() then
                showHideButton:SetText("Hide")
            else
                showHideButton:SetText("Show")
            end

            if RefreshTestNoteButton then
                RefreshTestNoteButton()
            end
        end

        testButton:SetScript("OnClick", function()
            if KRT.Notes:IsTestRunning() then
                KRT.Notes:TestStop()
            else
                KRT.Notes:TestStart()
            end
            refreshGates()
        end)
        HookTooltip(testButton)

        KRT.Notes.onTestStopped = function()
            refreshGates()
        end

        RefreshTestNoteButton = function()
            if KRT.Notes:IsTestRunning() then
                testButton:SetText("Stop")
                testButton:Enable()
                testButton.disabledReason = nil
            else
                testButton:SetText("Test")
                local activeName = CurrentActiveName()
                if activeName then
                    testButton:Enable()
                    testButton.disabledReason = nil
                else
                    testButton:Disable()
                    testButton.disabledReason = "No active note."
                end
            end
        end

        NotesConfig.OnDeleteNote = function()
            if not selectedNote then
                return
            end
            KRT.Notes:DeleteNote(selectedNote)
            selectedNote = nil
            refreshList()
            refreshGates()
        end

        local gateFrame = CreateFrame("Frame")
        gateFrame:SetScript("OnEvent", function()
            if panel:IsShown() then
                refreshList()
                refreshGates()
            end
        end)

        panel:SetScript("OnShow", function()
            gateFrame:RegisterEvent("PARTY_LEADER_CHANGED")
            gateFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
            gateFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            gateFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            refreshList()
            RefreshTestNoteButton()
            refreshGates()
        end)

        panel:SetScript("OnHide", function()
            gateFrame:UnregisterAllEvents()
        end)
    end

    local function SetupDisplay(panel)
        local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 0, 0)
        scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetWidth(panel:GetWidth() - 40)
        scrollChild:SetHeight(700)
        scrollFrame:SetScrollChild(scrollChild)

        local yOffset = -10

        local showMineCheckbox = KRT.Components.GetCheckbox(scrollChild, "Show only my assignments", function(value)
            GetSettings().display.showOnlyMine = value
            KRT:ApplySettings("notes")
        end)
        showMineCheckbox:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local hideExpiredCheckbox = KRT.Components.GetCheckbox(scrollChild, "Hide expired reminders", function(value)
            GetSettings().display.hideExpired = value
            KRT:ApplySettings("notes")
        end)
        hideExpiredCheckbox:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local lockedCheckbox = KRT.Components.GetCheckbox(scrollChild, "Locked", function(value)
            GetSettings().display.locked = value
            KRT:ApplySettings("notes")
        end)
        lockedCheckbox:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local hideModeDropdown = KRT.Components.GetBasicDropdown(scrollChild, "Hide",
            function() return HIDE_MODE_OPTIONS end,
            function(value) return GetSettings().display.hideMode == value end,
            function(value)
                GetSettings().display.hideMode = value
                KRT:ApplySettings("notes")
            end)
        hideModeDropdown:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local fontDropdown = KRT.Components.GetBasicDropdown(scrollChild, "Font Face",
            ListFonts,
            function(value) return GetSettings().display.fontFace == value end,
            function(value)
                GetSettings().display.fontFace = value
                KRT:ApplySettings("notes")
            end)
        fontDropdown:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local fontSizeSlider = KRT.Components.GetSliderWithInput(scrollChild, "Font Size", 6, 32, 1, false, function(value)
            GetSettings().display.fontSize = value
            KRT:ApplySettings("notes")
        end)
        fontSizeSlider:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local outlineDropdown = KRT.Components.GetBasicDropdown(scrollChild, "Font Outline",
            function() return OUTLINE_OPTIONS end,
            function(value) return GetSettings().display.fontOutline == value end,
            function(value)
                GetSettings().display.fontOutline = value
                KRT:ApplySettings("notes")
            end)
        outlineDropdown:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local textColorPicker = KRT.Components.GetColorPicker(scrollChild, "Countdown Color", false, function(color)
            local c = GetSettings().display.countdownColor
            c.r, c.g, c.b = color.r, color.g, color.b
            KRT:ApplySettings("notes")
        end)
        textColorPicker:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local bgColorPicker = KRT.Components.GetColorPicker(scrollChild, "Background Color", false, function(color)
            local c = GetSettings().display.backgroundColor
            c.r, c.g, c.b = color.r, color.g, color.b
            KRT:ApplySettings("notes")
        end)
        bgColorPicker:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local bgOpacitySlider = KRT.Components.GetSliderWithInput(scrollChild, "Background Opacity", 0, 1, 0.05, true, function(value)
            GetSettings().display.backgroundOpacity = value
            KRT:ApplySettings("notes")
        end)
        bgOpacitySlider:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        yOffset = yOffset - 6
        local contentHeader = KRT.Components.GetHeader(scrollChild, "Show In")
        contentHeader:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - 30

        for _, info in ipairs(CONTENT_CHECKBOXES) do
            local checkbox = KRT.Components.GetCheckbox(scrollChild, info.label, function(value)
                WritePath(GetSettings(), info.path, value)
                KRT:ApplySettings("notes")
            end)
            checkbox:SetPoint("TOPLEFT", 0, yOffset)
            info.widget = checkbox
            yOffset = yOffset - ROW_HEIGHT
        end

        scrollChild:SetHeight(math.abs(yOffset) + 20)

        panel:SetScript("OnShow", function()
            local settings = GetSettings()
            showMineCheckbox:SetValue(settings.display.showOnlyMine)
            hideExpiredCheckbox:SetValue(settings.display.hideExpired)
            lockedCheckbox:SetValue(settings.display.locked)
            hideModeDropdown:SetValue()
            fontDropdown:SetValue()
            fontSizeSlider:SetValue(settings.display.fontSize)
            outlineDropdown:SetValue()
            textColorPicker:SetValue(settings.display.countdownColor)
            bgColorPicker:SetValue(settings.display.backgroundColor)
            bgOpacitySlider:SetValue(settings.display.backgroundOpacity)

            for _, info in ipairs(CONTENT_CHECKBOXES) do
                info.widget:SetValue(ReadPath(settings, info.path))
            end
        end)
    end

    local function SetupPopups(panel)
        local yOffset = -10
        KRT.NotesPopups:MigrateSettings()

        local testPopupsButton
        local function HasEnabledPopupType()
            for _, displayType in ipairs(POPUP_TYPES) do
                if KRT.NotesPopups:IsTypeEnabled(displayType) then
                    return true
                end
            end
            return false
        end

        local function RefreshTestButton()
            if not testPopupsButton then
                return
            end
            if HasEnabledPopupType() then
                testPopupsButton:Enable()
            else
                testPopupsButton:Disable()
            end
        end

        local typeCheckboxes = {}
        for _, displayType in ipairs(POPUP_TYPES) do
            local popupType = displayType
            local checkbox = KRT.Components.GetCheckbox(
                panel,
                "Enable " .. popupType .. " popups",
                function(value)
                    GetSettings().popups.enabledTypes[popupType] = value
                    KRT:ApplySettings("notes")
                    RefreshTestButton()
                end
            )
            checkbox:SetPoint("TOPLEFT", 0, yOffset)
            yOffset = yOffset - ROW_HEIGHT
            typeCheckboxes[popupType] = checkbox
        end

        local popupLockedCheckbox = KRT.Components.GetCheckbox(panel, "Locked", function(value)
            GetSettings().popups.locked = value
            KRT:ApplySettings("notes")
        end)
        popupLockedCheckbox:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local barWidthInput = KRT.Components.GetIntegerInput(
            panel,
            "Bar Width",
            100,
            1000,
            function(value)
                GetSettings().popups.barWidth = value
                KRT:ApplySettings("notes")
            end
        )
        barWidthInput:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local barHeightInput = KRT.Components.GetIntegerInput(
            panel,
            "Bar Height",
            10,
            100,
            function(value)
                GetSettings().popups.barHeight = value
                KRT:ApplySettings("notes")
            end
        )
        barHeightInput:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local barTextureDropdown = KRT.Components.GetTextureDropdown(panel, "Bar Texture",
            ListStatusBars,
            function(value) return GetSettings().popups.barTexture == value end,
            function(value)
                GetSettings().popups.barTexture = value
                KRT:ApplySettings("notes")
            end
        )
        barTextureDropdown:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local popupScaleSlider = KRT.Components.GetSliderWithInput(
            panel,
            "Popup Scale",
            0.5,
            2,
            0.05,
            true,
            function(value)
                GetSettings().popups.scale = value
                KRT:ApplySettings("notes")
            end
        )
        popupScaleSlider:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local growDropdown = KRT.Components.GetBasicDropdown(panel, "Grow Direction",
            function() return GROW_OPTIONS end,
            function(value) return GetSettings().popups.growDirection == value end,
            function(value)
                GetSettings().popups.growDirection = value
                KRT:ApplySettings("notes")
            end)
        growDropdown:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local ttsCheckbox = KRT.Components.GetCheckbox(panel, "Enable TTS", function(value)
            GetSettings().popups.ttsEnabled = value
            KRT:ApplySettings("notes")
        end)
        ttsCheckbox:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local soundsCheckbox = KRT.Components.GetCheckbox(panel, "Enable sounds", function(value)
            GetSettings().popups.soundsEnabled = value
            KRT:ApplySettings("notes")
        end)
        soundsCheckbox:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local soundChannelDropdown = KRT.Components.GetBasicDropdown(panel, "Sound Channel",
            function() return SOUND_CHANNEL_OPTIONS end,
            function(value) return KRT.NotesPopups:GetSoundChannel() == value end,
            function(value)
                GetSettings().popups.soundChannel = value
                KRT:ApplySettings("notes")
            end)
        soundChannelDropdown:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT - 8

        testPopupsButton = KRT.Components.CreateButton(panel)
        testPopupsButton:SetSize(120, 22)
        testPopupsButton:SetPoint("TOPLEFT", 0, yOffset)
        testPopupsButton:SetText("Test Popups")
        testPopupsButton:SetScript("OnClick", function()
            KRT.NotesPopups:Test()
        end)

        panel:SetScript("OnShow", function()
            local settings = GetSettings()
            KRT.NotesPopups:MigrateSettings(settings.popups)
            for _, displayType in ipairs(POPUP_TYPES) do
                typeCheckboxes[displayType]:SetValue(
                    KRT.NotesPopups:IsTypeEnabled(displayType, settings.popups)
                )
            end
            popupLockedCheckbox:SetValue(settings.popups.locked)
            barWidthInput:SetValue(settings.popups.barWidth)
            barHeightInput:SetValue(settings.popups.barHeight)
            barTextureDropdown:SetValue()
            popupScaleSlider:SetValue(settings.popups.scale)
            growDropdown:SetValue()
            ttsCheckbox:SetValue(settings.popups.ttsEnabled)
            soundsCheckbox:SetValue(settings.popups.soundsEnabled)
            soundChannelDropdown:SetValue()
            RefreshTestButton()
        end)
    end

    return KRT.Components.GetSubTabGroup(parent, {
        { name = "Notes", setup = SetupNotes },
        { name = "Display", setup = SetupDisplay },
        { name = "Popups", setup = SetupPopups },
    })
end)

KRT:RegisterApplyCallback("notes", function()
    KRT.Notes:MigrateLockSettings()
    KRT.NotesFrame:ApplySettings()
    KRT.NotesPopups:ApplySettings()
end)
