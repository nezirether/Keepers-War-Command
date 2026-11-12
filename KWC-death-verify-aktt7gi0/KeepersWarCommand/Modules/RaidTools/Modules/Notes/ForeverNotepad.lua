-- KRT Forever: persistent, encounter-independent raid notepad.
local KRT = KeepersRaidTools
local selected = "Raid Plan"
local editor, displayFrame, displayText, displayScroll
local loadingNote = false
local NOTE_INSET = 8
local DISPLAY_WIDTH, DISPLAY_HEIGHT = 346, 208
local function Store()
    if type(KRTForeverNotesDB) ~= "table" then KRTForeverNotesDB = {} end
    if type(KRTForeverNotesDB.notes) ~= "table" then KRTForeverNotesDB.notes = {} end
    return KRTForeverNotesDB.notes
end
local function Save()
    if editor then Store()[selected] = editor:GetText() or "" end
end
local function MakeButton(parent, title, x, y, width, action)
    local b = KRT.Components.CreateButton(parent)
    b:SetSize(width, 23); b:SetPoint("TOPLEFT", x, y); b:SetText(title)
    b:SetScript("OnClick", action); return b
end
local function ShowDisplay()
    local text = Store()[selected] or ""
    if not text:find("%S") then
        if displayFrame then displayFrame:Hide() end
        KWC.Say("Write a note before showing it.")
        return
    end
    if not displayFrame then
        displayFrame = KRT.Components.CreatePanel("KRTForeverNoteDisplay", UIParent)
        displayFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        displayFrame:SetFrameLevel(200)
        displayFrame:SetClampedToScreen(true)
        displayFrame:Hide()
        displayFrame:SetSize(390, 260); displayFrame:SetPoint("CENTER", UIParent, "CENTER", 300, 80)
        displayFrame:SetMovable(true); displayFrame:EnableMouse(true); displayFrame:RegisterForDrag("LeftButton")
        displayFrame:SetScript("OnDragStart", displayFrame.StartMoving)
        displayFrame:SetScript("OnDragStop", displayFrame.StopMovingOrSizing)
        displayScroll = CreateFrame("ScrollFrame", nil, displayFrame, "UIPanelScrollFrameTemplate")
        displayScroll:SetPoint("TOPLEFT", 14, -38)
        displayScroll:SetPoint("BOTTOMRIGHT", -30, 14)
        local content = CreateFrame("Frame", nil, displayScroll)
        content:SetSize(DISPLAY_WIDTH, DISPLAY_HEIGHT)
        displayScroll:SetScrollChild(content)
        displayText = KRT.Components.CreateText(content, KWCRaidControlFont)
        displayText:SetPoint("TOPLEFT")
        displayText:SetWidth(DISPLAY_WIDTH)
        displayText:SetWordWrap(true)
        displayText:SetNonSpaceWrap(true)
        displayText:SetJustifyH("LEFT")
        displayText:SetJustifyV("TOP")
    end
    displayFrame:SetTitle(selected)
    displayText:SetText(text)
    displayFrame:Show()
    displayText:GetParent():SetHeight(math.max(DISPLAY_HEIGHT, displayText:GetStringHeight() + NOTE_INSET))
    displayScroll:UpdateScrollChildRect()
    displayScroll:SetVerticalScroll(0)
end
KRT:RegisterTab("Notes", function(parent)
    local page=CreateFrame("Frame",nil,parent);page:SetAllPoints(parent)
    local title=KRT.Components.CreateText(page, KWCRaidHeadingFont)
    title:SetPoint("TOPLEFT",14,-12);title:SetText("Raid Notepad")
    local name=KRT.Components.CreateText(page, KWCRaidControlFont)
    name:SetPoint("TOPLEFT",16,-43)
    local listScroll=CreateFrame("ScrollFrame",nil,page,"UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT",12,-68)
    listScroll:SetPoint("BOTTOMRIGHT",page,"TOPLEFT",139,-285)
    local listPanel=CreateFrame("Frame",nil,listScroll)
    listPanel:SetSize(108,217)
    listScroll:SetScrollChild(listPanel)
    local scroll=CreateFrame("ScrollFrame",nil,page,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",154,-68);scroll:SetPoint("BOTTOMRIGHT",-32,42)
    editor=CreateFrame("EditBox",nil,scroll)
    editor:SetMultiLine(true)
    editor:SetFontObject(KWCRaidControlFont)
    editor:SetAutoFocus(false)
    editor:SetWidth(math.max(220, parent:GetWidth()-190))
    editor:SetHeight(1)
    editor:SetTextInsets(NOTE_INSET, NOTE_INSET, NOTE_INSET, NOTE_INSET)
    editor:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(editor)

    local measure = KRT.Components.CreateText(page, KWCRaidControlFont)
    measure:SetPoint("TOPLEFT")
    measure:SetAlpha(0)
    measure:SetWordWrap(true)
    measure:SetNonSpaceWrap(true)
    local function ResizeEditor()
        if not scroll:IsVisible() then return end
        local width, height = scroll:GetWidth(), scroll:GetHeight()
        if width <= NOTE_INSET * 2 or height <= 0 then return end
        editor:SetWidth(width)
        local font, size, flags = editor:GetFont()
        if font then measure:SetFont(font, size, flags) end
        measure:SetWidth(width - NOTE_INSET * 2)
        measure:SetText(editor:GetText() .. "\n ")
        editor:SetHeight(math.max(height, measure:GetStringHeight() + NOTE_INSET * 2))
        scroll:UpdateScrollChildRect()
    end
    scroll:SetScript("OnSizeChanged", ResizeEditor)
    scroll:SetScript("OnShow", ResizeEditor)
    editor:SetScript("OnTextChanged", function(self)
        if loadingNote then return end
        Store()[selected] = self:GetText()
        ResizeEditor()
    end)
    local bg = page:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0.05, 0.06, 0.08, 1)
    bg:SetPoint("TOPLEFT", scroll, -4, 4)
    bg:SetPoint("BOTTOMRIGHT", scroll, 4, -4)
    local list={}
    local function Select(n)
        selected=n
        name:SetText("Editing: "..n)
        loadingNote=true
        editor:SetText(Store()[n] or "")
        loadingNote=false
        ResizeEditor()
        scroll:SetVerticalScroll(0)
        if displayFrame and displayFrame:IsShown() then ShowDisplay() end
    end
    local function Refresh()
        for _,b in ipairs(list) do b:Hide() end
        local keys={};for n in pairs(Store()) do keys[#keys+1]=n end;table.sort(keys)
        listPanel:SetHeight(math.max(217,#keys*26))
        for i,n in ipairs(keys) do
            local b=list[i] or MakeButton(listPanel,n,0,-(i-1)*26,108,function(self) Save();Select(self.noteName) end)
            list[i]=b;b.noteName=n;b:SetText(n);b:Show()
        end
    end
    if not Store()[selected] then Store()[selected]="" end
    MakeButton(page,"New",12,-295,62,function()
        Save();local i=1;while Store()["Note "..i] do i=i+1 end
        local n="Note "..i;Store()[n]="";Refresh();Select(n)
    end)
    MakeButton(page,"Delete",80,-295,62,function()
        Store()[selected]=nil;local nextName=next(Store()) or "Raid Plan"
        if not Store()[nextName] then Store()[nextName]="" end
        Refresh();Select(nextName)
    end)
    MakeButton(page,"Show Note",155,-20,100,function() Save();ShowDisplay() end)
    MakeButton(page,"Hide Note",263,-20,100,function() if displayFrame then displayFrame:Hide() end end)
    MakeButton(page,"Save",371,-20,72,function()
        Save()
        if displayFrame and displayFrame:IsShown() then ShowDisplay() end
    end)
    Refresh();Select(selected)
    return page
end)
