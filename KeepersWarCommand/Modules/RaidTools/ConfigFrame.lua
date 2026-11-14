local KRT = KeepersRaidTools

local FRAME_WIDTH = 880
local FRAME_HEIGHT = 725
local ROW_HEIGHT = 32
local SECTION_SPACING = 20
local SIDEBAR_WIDTH = 125
local LABEL_WIDTH = 200
local CONTROL_MAX_WIDTH = 350

local Components = {}

local theme = KWC.UITheme
local FONT = theme.font
local PRIMARY, MUTED = theme.cream, theme.muted
local STEEL, GRAPHITE, PANEL = theme.steel, theme.graphite, theme.panel

local function ControlFont(name, size, color, face)
    local font = CreateFont(name)
    if not font:SetFont(face or FONT, size, "") then font:SetFont(theme.fallbackFont, size, "") end
    font:SetTextColor(unpack(color))
    return font
end
local normal = ControlFont("KWCRaidControlFont", 14, PRIMARY)
local disabled = ControlFont("KWCRaidDisabledFont", 14, MUTED)
ControlFont("KWCRaidSmallFont", 13, PRIMARY)
ControlFont("KWCRaidHeadingFont", 18, theme.gold, theme.headingFont)

-- The template argument is a template name; custom fonts are applied as objects.
function Components.CreateText(parent, font)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFontObject(font)
    return text
end

local function Surface(frame, color)
    local border = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    border:SetAllPoints()
    border:SetColorTexture(unpack(STEEL))
    local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(unpack(color))
    return fill
end

function Components.CreateButton(parent, name)
    local button = CreateFrame("Button", name, parent)
    local fill = Surface(button, GRAPHITE)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(fill)
    hover:SetColorTexture(0.47, 0.26, 0.31, 0.26)
    button:SetSize(100, 28)
    button:SetNormalFontObject(normal)
    button:SetHighlightFontObject(normal)
    button:SetDisabledFontObject(disabled)
    button:SetPushedTextOffset(0, -1)
    function button:SetSelected(selected)
        fill:SetTexture(theme.warRoomArt .. (selected and "Crimson.tga" or "Grain.tga"))
    end
    button:SetSelected(false)
    return button
end

function Components.CreateInput(parent)
    local field = CreateFrame("EditBox", nil, parent)
    Surface(field, PANEL)
    field:SetFontObject(normal)
    field:SetTextInsets(6, 6, 0, 0)
    field:SetAutoFocus(false)
    field:SetScript("OnEscapePressed", field.ClearFocus)
    return field
end

function Components.CreateDropdown(parent)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    -- Preserve Blizzard's selection, menu, and mouse behavior.
    dropdown.Background:SetAlpha(0)
    dropdown.Arrow:SetAlpha(0)
    Surface(dropdown, GRAPHITE)
    local indicator = Components.CreateText(dropdown, normal)
    indicator:SetPoint("RIGHT", -6, 0)
    indicator:SetText("v")
    dropdown.Text:ClearAllPoints()
    dropdown.Text:SetPoint("LEFT", 7, 0)
    dropdown.Text:SetPoint("RIGHT", indicator, "LEFT", -5, 0)
    dropdown.Text:SetJustifyH("LEFT")
    dropdown.baseFontObject = normal
    dropdown.disableFontObject = disabled
    dropdown.Text:SetFontObject(normal)
    return dropdown
end

function Components.CreatePanel(name, parent)
    local panel = CreateFrame("Frame", name, parent)
    Surface(panel, PANEL)
    local title = Components.CreateText(panel, normal)
    title:SetFont(FONT, 16, "")
    title:SetPoint("TOPLEFT", 12, -8)
    local close = Components.CreateButton(panel)
    close:SetPoint("TOPRIGHT", -5, -4)
    close:SetSize(23, 22)
    close:SetText("X")
    close:SetScript("OnClick", function() panel:Hide() end)
    panel.CloseButton = close
    function panel:SetTitle(text) title:SetText(text) end
    return panel
end

function Components.CreateCheck(parent, template)
    local check = CreateFrame("CheckButton", nil, parent, template)
    Surface(check, GRAPHITE)
    for _, kind in ipairs({"Normal", "Pushed", "Highlight", "Disabled", "Checked", "DisabledChecked"}) do
        local texture = check["Get" .. kind .. "Texture"](check)
        if texture then texture:SetAlpha(0) end
    end
    local mark = check:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", 5, -5)
    mark:SetPoint("BOTTOMRIGHT", -5, 5)
    mark:SetColorTexture(0.70, 0.31, 0.37, 1)
    local function update() mark:SetShown(not not check:GetChecked()) end
    hooksecurefunc(check, "SetChecked", update)
    check:HookScript("OnClick", update)
    update()
    return check
end

function Components.GetCheckbox(parent, label, callback)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(ROW_HEIGHT)
    holder:SetPoint("LEFT", 20, 0)
    holder:SetPoint("RIGHT", -20, 0)

    local checkBox = Components.CreateCheck(holder, "SettingsCheckboxTemplate")
    checkBox:SetSize(22, 22)
    checkBox:SetPoint("LEFT", holder, "LEFT", LABEL_WIDTH - 15, 0)
    checkBox:SetText(label)
    checkBox:SetNormalFontObject(normal)
    checkBox:GetFontString():SetPoint("RIGHT", holder, "LEFT", LABEL_WIDTH - 30, 0)
    checkBox:GetFontString():SetPoint("LEFT", holder, 20, 0)
    checkBox:GetFontString():SetJustifyH("RIGHT")

    function holder:SetValue(value)
        checkBox:SetChecked(value)
    end

    function holder:GetValue()
        return checkBox:GetChecked()
    end

    function holder:SetEnabled(enabled)
        checkBox:SetEnabled(enabled)
        holder:EnableMouse(enabled)
    end

    holder:SetScript("OnEnter", function()
        if checkBox.OnEnter then checkBox:OnEnter() end
    end)

    holder:SetScript("OnLeave", function()
        if checkBox.OnLeave then checkBox:OnLeave() end
    end)

    holder:SetScript("OnMouseUp", function()
        checkBox:Click()
    end)

    checkBox:SetScript("OnClick", function()
        if callback then callback(checkBox:GetChecked()) end
    end)

    holder.CheckBox = checkBox

    return holder
end

function Components.GetBasicDropdown(parent, labelText, getItems, isSelectedCallback, onSelectionCallback)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(ROW_HEIGHT)
    frame:SetPoint("LEFT", 20, 0)
    frame:SetPoint("RIGHT", -20, 0)

    local dropdown = Components.CreateDropdown(frame)
    dropdown:SetWidth(200)
    dropdown:SetPoint("LEFT", frame, "LEFT", LABEL_WIDTH - 20, 0)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 0, 0)
    label:SetPoint("RIGHT", frame, "LEFT", LABEL_WIDTH - 40, 0)
    label:SetJustifyH("RIGHT")
    label:SetText(labelText)

    dropdown:SetupMenu(function(_, rootDescription)
        local items = getItems()
        for _, item in ipairs(items) do
            rootDescription:CreateRadio(
                item.name,
                function() return isSelectedCallback(item.value) end,
                function() onSelectionCallback(item.value) end
            )
        end
    end)

    function frame:SetValue()
        dropdown:GenerateMenu()
    end

    frame.Label = label
    frame.DropDown = dropdown

    return frame
end

function Components.GetTextureDropdown(parent, labelText, getTextures, isSelectedCallback, onSelectionCallback)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(ROW_HEIGHT)
    frame:SetPoint("LEFT", 20, 0)
    frame:SetPoint("RIGHT", -20, 0)

    local dropdown = Components.CreateDropdown(frame)
    dropdown:SetWidth(200)
    dropdown:SetPoint("LEFT", frame, "LEFT", LABEL_WIDTH - 20, 0)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 0, 0)
    label:SetPoint("RIGHT", frame, "LEFT", LABEL_WIDTH - 40, 0)
    label:SetJustifyH("RIGHT")
    label:SetText(labelText)

    dropdown:SetupMenu(function(_, rootDescription)
        for _, texture in ipairs(getTextures()) do
            local preview = texture.name
            if texture.path then
                preview = "|T" .. texture.path .. ":16:80|t " .. texture.name
            end
            rootDescription:CreateRadio(
                preview,
                function() return isSelectedCallback(texture.value) end,
                function() onSelectionCallback(texture.value) end
            )
        end
        rootDescription:SetScrollMode(20 * 10)
    end)

    function frame:SetValue()
        dropdown:GenerateMenu()
    end

    frame.Label = label
    frame.DropDown = dropdown

    return frame
end

function Components.GetSliderWithInput(parent, labelText, min, max, step, isDecimal, callback)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(ROW_HEIGHT)
    holder:SetPoint("LEFT", 20, 0)
    holder:SetPoint("RIGHT", -20, 0)

    holder.Label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    holder.Label:SetJustifyH("RIGHT")
    holder.Label:SetPoint("LEFT", 0, 0)
    holder.Label:SetPoint("RIGHT", holder, "LEFT", LABEL_WIDTH - 40, 0)
    holder.Label:SetText(labelText)

    local editBox = Components.CreateInput(holder)
    editBox:SetSize(50, 20)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(not isDecimal)
    editBox:SetMaxLetters(6)

    holder.Slider = CreateFrame("Slider", nil, holder, "MinimalSliderWithSteppersTemplate")
    holder.Slider:SetPoint("LEFT", holder, "LEFT", LABEL_WIDTH - 20, 0)
    holder.Slider:SetPoint("RIGHT", editBox, "LEFT", -10, 0)
    holder.Slider:SetHeight(20)

    do
        local START, RIGHT_INSET = LABEL_WIDTH - 20, 5
        local function UpdateSliderWidth(_, w)
            w = w or holder:GetWidth()
            local rightX = math.min(START + CONTROL_MAX_WIDTH, math.max(START + 50, w - RIGHT_INSET))
            editBox:SetPoint("RIGHT", holder, "LEFT", rightX, 0)
        end
        holder:SetScript("OnSizeChanged", UpdateSliderWidth)
        UpdateSliderWidth(holder, holder:GetWidth())
    end

    local numSteps = math.floor((max - min) / step)
    holder.Slider:Init(min, min, max, numSteps, {})

    local updatingFromSlider = false
    local updatingFromInput = false

    holder.Slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        if updatingFromInput then return end
        updatingFromSlider = true
        if isDecimal then
            editBox:SetText(string.format("%.2f", value))
        else
            editBox:SetText(tostring(math.floor(value)))
        end
        updatingFromSlider = false
        if callback then callback(value) end
    end)

    local function ApplyInputValue()
        if updatingFromSlider then return end
        local text = editBox:GetText()
        local value = tonumber(text)
        if value then
            value = math.max(min, math.min(max, value))
            updatingFromInput = true
            holder.Slider:SetValue(value)
            updatingFromInput = false
            if callback then callback(value) end
        end
    end

    editBox:SetScript("OnEnterPressed", function(self)
        ApplyInputValue()
        self:ClearFocus()
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    editBox:SetScript("OnEditFocusLost", function()
        ApplyInputValue()
    end)

    function holder:GetValue()
        return holder.Slider.Slider:GetValue()
    end

    function holder:SetValue(value)
        updatingFromSlider = true
        holder.Slider:SetValue(value)
        if isDecimal then
            editBox:SetText(string.format("%.2f", value))
        else
            editBox:SetText(tostring(math.floor(value)))
        end
        updatingFromSlider = false
    end

    holder.EditBox = editBox

    return holder
end

function Components.GetIntegerInput(parent, labelText, min, max, callback)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(ROW_HEIGHT)
    holder:SetPoint("LEFT", 20, 0)
    holder:SetPoint("RIGHT", -20, 0)

    holder.Label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    holder.Label:SetJustifyH("RIGHT")
    holder.Label:SetPoint("LEFT", 0, 0)
    holder.Label:SetPoint("RIGHT", holder, "LEFT", LABEL_WIDTH - 40, 0)
    holder.Label:SetText(labelText)

    local editBox = Components.CreateInput(holder)
    editBox:SetSize(50, 20)
    editBox:SetPoint("LEFT", holder, "LEFT", LABEL_WIDTH - 20, 0)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(true)
    editBox:SetMaxLetters(6)

    local currentValue = min

    local function ApplyInputValue()
        local value = tonumber(editBox:GetText())
        if not value then
            editBox:SetText(tostring(currentValue))
            return
        end
        currentValue = math.max(min, math.min(max, math.floor(value)))
        editBox:SetText(tostring(currentValue))
        if callback then callback(currentValue) end
    end

    editBox:SetScript("OnEnterPressed", function(self)
        ApplyInputValue()
        self:ClearFocus()
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(currentValue))
        self:ClearFocus()
    end)

    editBox:SetScript("OnEditFocusLost", ApplyInputValue)

    function holder:GetValue()
        return currentValue
    end

    function holder:SetValue(value)
        currentValue = math.max(min, math.min(max, math.floor(tonumber(value) or min)))
        editBox:SetText(tostring(currentValue))
    end

    holder.EditBox = editBox

    return holder
end

function Components.GetColorPicker(parent, labelText, hasAlpha, callback)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(ROW_HEIGHT)
    holder:SetPoint("LEFT", 20, 0)
    holder:SetPoint("RIGHT", -20, 0)

    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 0, 0)
    label:SetPoint("RIGHT", holder, "LEFT", LABEL_WIDTH - 40, 0)
    label:SetJustifyH("RIGHT")
    label:SetText(labelText)

    local swatch = CreateFrame("Button", nil, holder, "ColorSwatchTemplate")
    swatch:SetPoint("LEFT", holder, "LEFT", LABEL_WIDTH - 15, 0)

    function holder:SetValue(color)
        swatch.currentColor = CopyTable(color)
        swatch:SetColor(CreateColor(color.r, color.g, color.b))
    end

    swatch:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    swatch:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then
            local info = {}
            info.r = swatch.currentColor.r
            info.g = swatch.currentColor.g
            info.b = swatch.currentColor.b
            info.opacity = swatch.currentColor.a
            info.hasOpacity = hasAlpha

            info.swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = hasAlpha and ColorPickerFrame:GetColorAlpha() or nil
                swatch.currentColor = { r = r, g = g, b = b, a = a }
                swatch:SetColor(CreateColor(r, g, b))
                if callback then callback(swatch.currentColor) end
            end

            info.cancelFunc = function(previousValues)
                swatch.currentColor = previousValues
                swatch:SetColor(CreateColor(previousValues.r, previousValues.g, previousValues.b))
                if callback then callback(previousValues) end
            end

            info.previousValues = CopyTable(swatch.currentColor)

            ColorPickerFrame:SetupColorPickerAndShow(info)
        else
            swatch.currentColor = { r = 1, g = 1, b = 1, a = hasAlpha and 1 or nil }
            swatch:SetColor(CreateColor(1, 1, 1))
            if callback then callback(swatch.currentColor) end
        end
    end)

    holder:SetScript("OnEnter", function()
        if swatch:GetScript("OnEnter") then swatch:GetScript("OnEnter")(swatch) end
    end)

    holder:SetScript("OnLeave", function()
        if swatch:GetScript("OnLeave") then swatch:GetScript("OnLeave")(swatch) end
    end)

    holder:SetScript("OnMouseUp", function(_, mouseButton)
        swatch:Click(mouseButton)
    end)

    return holder
end

function Components.GetHeader(parent, text)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("LEFT", 10, 0)
    holder:SetPoint("RIGHT", -10, 0)
    holder:SetHeight(28)

    holder.text = Components.CreateText(holder, KWCRaidHeadingFont)
    holder.text:SetText(text)
    holder.text:SetPoint("LEFT", 10, 0)

    return holder
end

function Components.GetTab(parent, text)
    local tab = Components.CreateButton(parent)
    tab:SetText(text)
    tab:SetSize(math.max(70, tab:GetFontString():GetStringWidth() + 18), 28)
    return tab
end

function Components.GetSidebarTab(parent, text)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(SIDEBAR_WIDTH - 8, 28)

    btn.selectedBg = btn:CreateTexture(nil, "BACKGROUND")
    btn.selectedBg:SetAllPoints()
    btn.selectedBg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    btn.selectedBg:Hide()

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetColorTexture(0.3, 0.3, 0.3, 0.5)

    btn.text = Components.CreateText(btn, KWCRaidControlFont)
    btn.text:SetPoint("LEFT", 8, 0)
    btn.text:SetText(text)

    function btn:SetSelected(selected)
        if selected then
            btn.selectedBg:Show()
            btn.text:SetTextColor(unpack(PRIMARY))
        else
            btn.selectedBg:Hide()
            btn.text:SetTextColor(unpack(MUTED))
        end
    end

    return btn
end

-- defs: array of { name = "Tab Name", setup = function(panel) ... end }
-- Each setup function builds its content inside the panel it is given.
-- Returns the outer container (suitable as a RegisterTab container).
local SUBTAB_HEIGHT = 28

function Components.GetSubTabGroup(parent, defs)
    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()
    container:Hide()

    local subTabs = {}
    local currentIndex = 1

    local function SelectSubTab(index)
        for i, st in ipairs(subTabs) do
            if i == index then
                st.tab:SetSelected(true)
                st.panel:Show()
            else
                st.tab:SetSelected(false)
                st.panel:Hide()
            end
        end
        currentIndex = index
    end

    for i, def in ipairs(defs) do
        local panel = CreateFrame("Frame", nil, container)
        panel:SetPoint("TOPLEFT", 0, -(SUBTAB_HEIGHT + 10))
        panel:SetPoint("BOTTOMRIGHT", 0, 0)
        panel:Hide()

        local tab = Components.GetTab(container, def.name)
        if i == 1 then
            tab:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        else
            tab:SetPoint("LEFT", subTabs[i - 1].tab, "RIGHT", 4, 0)
        end
        tab:SetScript("OnClick", function() SelectSubTab(i) end)

        table.insert(subTabs, { tab = tab, panel = panel })
        def.setup(panel)
    end

    container:SetScript("OnShow", function()
        SelectSubTab(currentIndex)
    end)

    return container
end

KRT.Components = Components

local ConfigFrame = Components.CreatePanel("KeepersRaidToolsConfigFrame", UIParent)
ConfigFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
ConfigFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
ConfigFrame:SetToplevel(true)
ConfigFrame:Hide()

ConfigFrame:SetTitle(string.format(
    "Keepers War Command v%s",
    (C_AddOns.GetAddOnMetadata("KeepersWarCommand", "Version") or "1.6.0")
))

ConfigFrame:SetMovable(true)
ConfigFrame:SetResizable(true)
ConfigFrame:SetClampedToScreen(true)

local function UpdateWindowBounds()
    local viewportWidth, viewportHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local minWidth = math.min(FRAME_WIDTH, viewportWidth)
    local minHeight = math.min(FRAME_HEIGHT, viewportHeight)
    local width = math.max(minWidth, math.min(ConfigFrame:GetWidth(), viewportWidth))
    local height = math.max(minHeight, math.min(ConfigFrame:GetHeight(), viewportHeight))
    local left = math.max(0, math.min(ConfigFrame:GetLeft() or 0, viewportWidth - width))
    local top = math.max(height, math.min(ConfigFrame:GetTop() or viewportHeight, viewportHeight))

    ConfigFrame:SetResizeBounds(minWidth, minHeight, viewportWidth - left, top)
    ConfigFrame:SetSize(width, height)
    ConfigFrame:ClearAllPoints()
    ConfigFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

ConfigFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
ConfigFrame:RegisterEvent("UI_SCALE_CHANGED")
ConfigFrame:SetScript("OnEvent", function()
    ConfigFrame:StopMovingOrSizing()
    UpdateWindowBounds()
end)
UpdateWindowBounds()

ConfigFrame:EnableMouse(true)
ConfigFrame:RegisterForDrag("LeftButton")
ConfigFrame:SetScript("OnDragStart", ConfigFrame.StartMoving)
ConfigFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SetUserPlaced(false)
    UpdateWindowBounds()
end)

local resizeHandle = CreateFrame("Button", nil, ConfigFrame)
resizeHandle:SetSize(18, 18)
resizeHandle:SetPoint("BOTTOMRIGHT", -2, 2)
resizeHandle:SetFrameLevel(ConfigFrame:GetFrameLevel() + 30)
resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeHandle:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" then return end
    UpdateWindowBounds()
    ConfigFrame:StartSizing("BOTTOMRIGHT")
end)

local function StopResizing()
    ConfigFrame:StopMovingOrSizing()
    if ConfigFrame:IsMovable() or ConfigFrame:IsResizable() then
        ConfigFrame:SetUserPlaced(false)
    end
end

resizeHandle:SetScript("OnMouseUp", function(_, button)
    if button ~= "LeftButton" then return end
    StopResizing()
end)
ConfigFrame:HookScript("OnHide", StopResizing)

-- UISpecialFrames membership makes Escape close the frame.
table.insert(UISpecialFrames, "KeepersRaidToolsConfigFrame")

local Sidebar = CreateFrame("Frame", nil, ConfigFrame)
Sidebar:SetWidth(SIDEBAR_WIDTH)
Sidebar:SetPoint("TOPLEFT", 8, -28)
Sidebar:SetPoint("BOTTOMLEFT", 8, 8)

local sidebarBg = Sidebar:CreateTexture(nil, "BACKGROUND")
sidebarBg:SetAllPoints()
sidebarBg:SetColorTexture(0.05, 0.05, 0.05, 0.8)

local ContentArea = CreateFrame("Frame", nil, ConfigFrame)
ContentArea:SetPoint("TOPLEFT", Sidebar, "TOPRIGHT", 4, 0)
ContentArea:SetPoint("BOTTOMRIGHT", -8, 8)

local tabEntries = {}
local bottomEntries = {}
local currentEntry = nil

local bottomSeparator = Sidebar:CreateTexture(nil, "ARTWORK")
bottomSeparator:SetColorTexture(0.3, 0.3, 0.3, 0.8)
bottomSeparator:SetHeight(1)
bottomSeparator:Hide()

local function ApplySelection(entry, list)
    for _, e in ipairs(list) do
        if e == entry then
            e.button:SetSelected(true)
            e.container:Show()
        else
            e.button:SetSelected(false)
            e.container:Hide()
        end
    end
end

-- KWC host can select the original KRT tab without duplicating its logic.
function KRT:SelectUnifiedTab(name)
    for _, entry in ipairs(tabEntries) do
        if entry.name == name then
            if not ConfigFrame:IsShown() then ConfigFrame:Show() end
            ApplySelection(entry, tabEntries)
            ApplySelection(entry, bottomEntries)
            currentEntry=entry
            return true
        end
    end
    for _, entry in ipairs(bottomEntries) do
        if entry.name == name then
            if not ConfigFrame:IsShown() then ConfigFrame:Show() end
            ApplySelection(entry, tabEntries)
            ApplySelection(entry, bottomEntries)
            currentEntry=entry
            return true
        end
    end
    return false
end

-- DEV34: Native KWC content mounting. The original frame is only an
-- initialization shell; its sidebar, portrait, and window never appear.
function KRT:MountInWarCommand(parent, name)
    if not parent then return false end
    ConfigFrame:Hide()
    ContentArea:SetParent(parent)
    ContentArea:ClearAllPoints()
    ContentArea:SetPoint('TOPLEFT', parent, 'TOPLEFT', 0, 0)
    ContentArea:SetSize(700, 760)
    ContentArea:SetScale(0.79)
    ContentArea:Show()
    for _, entry in ipairs(tabEntries) do
        entry.container:SetShown(entry.name == name)
    end
    for _, entry in ipairs(bottomEntries) do
        entry.container:SetShown(entry.name == name)
    end
    return true
end
function KRT:UnmountFromWarCommand()
    if ContentArea:GetParent() ~= ConfigFrame then
        ContentArea:Hide()
        ContentArea:SetParent(ConfigFrame)
        ContentArea:SetScale(1)
        ContentArea:ClearAllPoints()
        ContentArea:SetPoint('TOPLEFT', Sidebar, 'TOPRIGHT', 4, 0)
        ContentArea:SetPoint('BOTTOMRIGHT', ConfigFrame, 'BOTTOMRIGHT', -8, 8)
    end
end

local function SelectTab(entry)
    ApplySelection(entry, tabEntries)
    ApplySelection(entry, bottomEntries)
    currentEntry = entry
end

local function LayoutSidebarTabs()
    for i, e in ipairs(tabEntries) do
        e.button:ClearAllPoints()
        if i == 1 then
            e.button:SetPoint("TOPLEFT", Sidebar, "TOPLEFT", 4, -8)
        else
            e.button:SetPoint("TOPLEFT", tabEntries[i - 1].button, "BOTTOMLEFT", 0, -2)
        end
    end

    for i, e in ipairs(bottomEntries) do
        e.button:ClearAllPoints()
        if i == 1 then
            e.button:SetPoint("BOTTOMLEFT", Sidebar, "BOTTOMLEFT", 4, 8)
        else
            e.button:SetPoint("BOTTOMLEFT", bottomEntries[i - 1].button, "TOPLEFT", 0, 2)
        end
    end

    if #bottomEntries > 0 then
        local topButton = bottomEntries[#bottomEntries].button
        bottomSeparator:ClearAllPoints()
        bottomSeparator:SetPoint("BOTTOMLEFT", topButton, "TOPLEFT", 0, 5)
        bottomSeparator:SetPoint("BOTTOMRIGHT", topButton, "TOPRIGHT", 0, 5)
        bottomSeparator:Show()
    else
        bottomSeparator:Hide()
    end
end

-- Tabs are kept in alphabetical order. Pass opts.bottom = true to pin a tab
-- to the bottom of the sidebar, separated from the main group.
KRT.RegisterTab = function(self, name, setupFunc, opts)
    local entry = {
        name = name,
        container = setupFunc(ContentArea),
        button = Components.GetSidebarTab(Sidebar, name),
    }
    entry.button:SetScript("OnClick", function() SelectTab(entry) end)

    if opts and opts.bottom then
        table.insert(bottomEntries, entry)
    else
        local insertAt = #tabEntries + 1
        for i, e in ipairs(tabEntries) do
            if name < e.name then
                insertAt = i
                break
            end
        end
        table.insert(tabEntries, insertAt, entry)
    end
    LayoutSidebarTabs()
end

ConfigFrame:SetScript("OnShow", function()
    if not (KWC and KWC.RaidTools and ConfigFrame:GetParent() == (KWC.UI and KWC.UI.GetHost and KWC.UI.GetHost())) then UpdateWindowBounds() end
    if #tabEntries > 0 or #bottomEntries > 0 then
        SelectTab(currentEntry or tabEntries[1] or bottomEntries[1])
    end
end)

local placeholder = CreateFrame("Frame", nil, ContentArea)
placeholder:SetAllPoints()

local placeholderText = Components.CreateText(placeholder, KWCRaidControlFont)
placeholderText:SetPoint("CENTER")
placeholderText:SetText("No modules loaded.\n\nModules will appear here as tabs.")

placeholder:SetScript("OnShow", function()
    if #tabEntries > 0 or #bottomEntries > 0 then
        placeholder:Hide()
    end
end)

ConfigFrame:HookScript("OnShow", function()
    if #tabEntries > 0 or #bottomEntries > 0 then
        placeholder:Hide()
    else
        placeholder:Show()
    end
end)
