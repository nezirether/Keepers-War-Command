local KRT = KeepersRaidTools
local AttendanceDatabaseUI = {}
KRT.AttendanceDatabaseUI = AttendanceDatabaseUI

local statusText

local function SummaryText(summary)
    return summary.days .. " attendance days containing " .. summary.attendanceRecords
        .. " character records, plus " .. summary.rosterEntries .. " roster entries containing "
        .. summary.rosterCharacters .. " characters"
end

local function PrintError(message)
    print("|cFFFF0000KeepersRaidTools:|r " .. message)
end

local function RefreshViews()
    if KRT.AttendanceUI then
        KRT.AttendanceUI:Refresh()
    end
    if KRT.RecordsUI then
        KRT.RecordsUI:Refresh()
    end
    if KRT.RosterUI then
        KRT.RosterUI:Refresh()
    end
end

StaticPopupDialogs["KRT_ATTENDANCE_IMPORT_DATABASE"] = {
    text = "%s",
    button1 = "Replace Database",
    button2 = "Cancel",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    OnAccept = function(_, prepared)
        local ok, result = KRT.AttendanceDatabase:ApplyPrepared(prepared)
        if not ok then
            if statusText then
                statusText:SetText("|cFFFF4D4D" .. result .. "|r")
            end
            PrintError(result)
            return
        end

        if statusText then
            statusText:SetText("|cFF33FF99Imported " .. SummaryText(result) .. ".|r")
        end
        RefreshViews()
        print("|cFF00FF00KeepersRaidTools:|r Imported the complete attendance database.")
    end,
}

function AttendanceDatabaseUI:Build(panel)
    local header = KRT.Components.GetHeader(panel, "Attendance Database Backup")
    header:SetPoint("TOPLEFT", 0, -10)

    local description = KRT.Components.CreateText(panel, KWCRaidControlFont)
    description:SetPoint("TOPLEFT", 20, -42)
    description:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
    description:SetJustifyH("LEFT")
    description:SetText(
        "Export copies every attendance day and roster entry into one text payload. "
        .. "To restore a backup, paste it below and review the import before replacing local data."
    )

    local exportButton = KRT.Components.CreateButton(panel)
    exportButton:SetSize(104, 30)
    exportButton:SetPoint("TOPLEFT", 20, -82)
    exportButton:SetText("Export")

    local importButton = KRT.Components.CreateButton(panel)
    importButton:SetSize(128, 30)
    importButton:SetPoint("LEFT", exportButton, "RIGHT", 8, 0)
    importButton:SetText("Review Import")

    local scrollFrame = KRT.Components.CreateScrollFrame(panel)
    scrollFrame:SetPoint("TOPLEFT", 20, -124)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 54)

    KRT.Components.Surface(scrollFrame, KWC.UITheme.panel)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(KWCRaidControlFont)
    editBox:SetTextInsets(8, 8, 6, 6)
    editBox:SetWidth(math.max(1, panel:GetWidth() - 92))
    editBox:SetMaxLetters(0)
    editBox:SetScript("OnEscapePressed", editBox.ClearFocus)
    scrollFrame:SetScrollChild(editBox)
    scrollFrame:SetScript("OnSizeChanged", function(_, width)
        editBox:SetWidth(math.max(1, width))
    end)

    statusText = KRT.Components.CreateText(panel, KWCRaidSmallFont)
    statusText:SetPoint("BOTTOMLEFT", 20, 24)
    statusText:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
    statusText:SetJustifyH("LEFT")

    exportButton:SetScript("OnClick", function()
        local payload = KRT.AttendanceDatabase:Export()
        editBox:SetText(payload)
        editBox:SetFocus()
        editBox:HighlightText()
        statusText:SetText("|cFF33FF99The complete database is ready to copy.|r")
    end)

    importButton:SetScript("OnClick", function()
        local prepared, err = KRT.AttendanceDatabase:PrepareImport(editBox:GetText())
        if not prepared then
            statusText:SetText("|cFFFF4D4D" .. err .. "|r")
            return
        end

        local question = "Replace your complete local attendance database with "
            .. SummaryText(prepared.summary) .. "?"
        StaticPopup_Show("KRT_ATTENDANCE_IMPORT_DATABASE", question, nil, prepared)
    end)
end
