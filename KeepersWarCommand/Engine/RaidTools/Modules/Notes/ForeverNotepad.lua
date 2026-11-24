-- KRT Forever: persistent, encounter-independent raid notepad.
local KRT = KeepersRaidTools
local selected = "Raid Plan"
local editor, displayFrame, displayText, displayScroll
local loadingNote = false
local NOTE_INSET = 8
local DISPLAY_WIDTH, DISPLAY_HEIGHT = 346, 208
local Components = KRT.Components
local theme = KWC.UITheme
local LIST_WIDTH, LIST_HEIGHT, LIST_ROW = 168, 290, 34
local function Store()
    if type(KRTForeverNotesDB) ~= "table" then KRTForeverNotesDB = {} end
    if type(KRTForeverNotesDB.notes) ~= "table" then KRTForeverNotesDB.notes = {} end
    return KRTForeverNotesDB.notes
end
local function Save()
    if editor then Store()[selected] = editor:GetText() or "" end
end
local function MakeButton(parent, title, x, y, width, action)
    local b = Components.CreateButton(parent)
    b:SetSize(width, 30); b:SetPoint("TOPLEFT", x, y); b:SetText(title)
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
        displayScroll = Components.CreateScrollFrame(displayFrame)
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
    local library=CreateFrame("Frame",nil,page)
    library:SetPoint("TOPLEFT",0,0)
    library:SetSize(210,400)
    Components.Surface(library,theme.panel)
    local title=Components.CreateText(library, KWCRaidHeadingFont)
    title:SetPoint("TOPLEFT",14,-12);title:SetText("Your Notes")
    local name=Components.CreateText(page, KWCRaidHeadingFont)
    name:SetPoint("TOPLEFT",232,-56)
    local listScroll=Components.CreateScrollFrame(library)
    listScroll:SetPoint("TOPLEFT",12,-44)
    listScroll:SetSize(LIST_WIDTH+4,LIST_HEIGHT)
    local listPanel=CreateFrame("Frame",nil,listScroll)
    listPanel:SetSize(LIST_WIDTH,LIST_HEIGHT)
    listScroll:SetScrollChild(listPanel)
    local scroll=Components.CreateScrollFrame(page)
    scroll:SetPoint("TOPLEFT",232,-84);scroll:SetPoint("BOTTOMRIGHT",-27,22)
    editor=CreateFrame("EditBox",nil,scroll)
    editor:SetMultiLine(true)
    editor:SetFontObject(KWCRaidControlFont)
    editor:SetAutoFocus(false)
    editor:SetWidth(math.max(220, parent:GetWidth()-259))
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
    Components.Surface(scroll,theme.panel)
    local list={}
    local function Select(n)
        selected=n
        name:SetText("Editing: "..n)
        for _,button in ipairs(list) do button:SetSelected(button.noteName==n) end
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
        listPanel:SetHeight(math.max(LIST_HEIGHT,#keys*LIST_ROW))
        for i,n in ipairs(keys) do
            local b=list[i] or MakeButton(listPanel,n,0,-(i-1)*LIST_ROW,LIST_WIDTH,function(self) Save();Select(self.noteName) end)
            list[i]=b;b.noteName=n;b:SetText(n);b:Show()
        end
    end
    if not Store()[selected] then Store()[selected]="" end
    MakeButton(library,"New",12,-352,83,function()
        Save();local i=1;while Store()["Note "..i] do i=i+1 end
        local n="Note "..i;Store()[n]="";Refresh();Select(n)
    end)
    MakeButton(library,"Delete",107,-352,83,function()
        Store()[selected]=nil;local nextName=next(Store()) or "Raid Plan"
        if not Store()[nextName] then Store()[nextName]="" end
        Refresh();Select(nextName)
    end)
    MakeButton(page,"Show Note",232,-8,116,function() Save();ShowDisplay() end)
    MakeButton(page,"Hide Note",358,-8,116,function() if displayFrame then displayFrame:Hide() end end)
    MakeButton(page,"Save",484,-8,92,function()
        Save()
        if displayFrame and displayFrame:IsShown() then ShowDisplay() end
    end):SetSelected(true)
    Refresh();Select(selected)
    return page
end)
