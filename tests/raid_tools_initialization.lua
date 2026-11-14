-- Run from the repository root with LuaJIT (WoW-style bit library).
local root = "KeepersWarCommand/Modules/RaidTools/"
local env = setmetatable({ UISpecialFrames = {} }, { __index = _G })
local frames = {}
local noop = function() end
local methods = {}
local function widget(parent, template)
    local frame = setmetatable({ parent = parent, template = template, shown = true,
        scripts = {}, regions = {}, children = {}, width = 100, height = 28 },
        { __index = function(_, key) return methods[key] or (key:match("^%u") and noop or nil) end })
    frame.text = false
    if parent then table.insert(parent.children, frame) end
    table.insert(frames, frame)
    if template == "WowStyle1DropdownTemplate" then
        frame.Background, frame.Arrow, frame.Text = widget(), widget(), widget()
    elseif template == "SettingsCheckboxTemplate" then
        frame.fontString = widget()
    end
    return frame
end
function methods:CreateTexture(_, layer, _, sublayer)
    local texture = widget()
    texture.layer, texture.sublayer = layer, sublayer
    table.insert(self.regions, texture)
    return texture
end
function methods:SetColorTexture(...) self.color = {...} end
function methods:CreateLine() return widget() end
function methods:CreateFontString(_, _, template)
    assert(template == nil or (type(template) == "string" and not template:match("^KWCRaid")),
        "CreateFontString requires a template name, not a custom FontObject")
    local f = widget()
    f.parent = self
    f.kind = "FontString"
    table.insert(self.regions, f)
    return f
end
function methods:SetFontObject(font)
    assert(type(font) == "table" and font.isFontObject, "expected a FontObject")
    self.appliedFont = font
end
function methods:GetFontString() self.fontString = rawget(self, "fontString") or widget(); return self.fontString end
function methods:SetText(text) self.text = text; self:GetFontString().text = text end
function methods:GetStringHeight()
    assert(self.kind == "FontString", "GetStringHeight is unavailable on "..tostring(self.kind))
    local size = rawget(self, "fontSize") or 14
    local columns = math.max(1, math.floor(self.width / (size / 2)))
    local rows = 0
    for line in (self:GetText() .. "\n"):gmatch("([^\n]*)\n") do
        rows = rows + math.max(1, math.ceil(#line / columns))
    end
    return rows * size
end
function methods:SetFont(file, size, flags) self.fontFile,self.fontSize,self.fontFlags=file,size,flags end
function methods:GetFont()
    local font = rawget(self, "fontFile") and self or self.appliedFont
    return font.fontFile,font.fontSize,font.fontFlags
end
function methods:IsVisible()
    return self.shown and (not self.parent or self.parent:IsVisible())
end
function methods:GetStringWidth() return #(self.text or "") * 7 end
function methods:SetSize(w,h) self.width,self.height = w,h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:SetVerticalScroll(value) self.verticalScroll=value end
function methods:GetVerticalScroll() return self.verticalScroll or 0 end
function methods:SetAlpha(alpha) self.alpha = alpha end
function methods:SetChecked(value) self.checked = value end
function methods:GetChecked() return self.checked end
function methods:GetParent() return self.parent end
function methods:SetParent(parent) self.parent = parent end
function methods:SetScript(event, cb) self.scripts[event] = cb end
function methods:HookScript(event, cb)
    local prior = self.scripts[event]
    self.scripts[event] = function(...) if prior then prior(...) end; cb(...) end
end
function methods:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:Hide()
    local wasShown=self.shown
    self.shown=false
    if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:IsShown() return self.shown end
function methods:SetShown(show) if show then self:Show() else self:Hide() end end
function methods:SetupMenu(callback) self.menu = callback end
function methods:Click()
    if self.template == "SettingsCheckboxTemplate" then self.checked = not self.checked end
    self.scripts.OnClick(self)
end
function methods:GetFrameLevel() return 1 end
function methods:GetLeft() return 0 end
function methods:GetTop() return 900 end
env.UIParent = widget()
env.UIParent:SetSize(1600,900)
env.UIParent.scale=1
env.CreateFrame = function(_, _, parent, template) return widget(parent, template) end
env.CreateFont = function(name) local font = widget(); font.isFontObject = true; env[name] = font; return font end
env.C_AddOns = { GetAddOnMetadata = function() return "test" end }
env.hooksecurefunc = function(object, key, after)
    if type(object) == "string" then object,key,after=env,object,key end
    local prior = object[key] or noop
    object[key] = function(self, ...) prior(self, ...); after(self, ...) end
end
local bitOps = require("bit")
env.CreateColor = function(r,g,b,a)
    return {r=r,g=g,b=b,a=a,GetRGBA=function() return r,g,b,a end}
end
env.CopyTable = function(source)
    local copy={}
    for key,value in pairs(source) do copy[key]=type(value)=="table" and env.CopyTable(value) or value end
    return copy
end
env._G = env
env.bit = bitOps
env.strmatch, env.strfind, env.strsub, env.strlen, env.gsub = string.match, string.find, string.sub, string.len, string.gsub
env.strlower, env.strupper, env.format = string.lower, string.upper, string.format
env.tinsert, env.tremove, env.sort = table.insert, table.remove, table.sort
env.floor, env.ceil, env.min, env.max = math.floor, math.ceil, math.min, math.max
env.SlashCmdList = {}
env.StaticPopupDialogs = {}
env.Enum = { ItemClass = {}, ItemArmorSubclass = {}, ItemWeaponSubclass = {} }
env.C_ChatInfo = {RegisterAddonMessagePrefix = noop, SendAddonMessage = noop, SendChatMessage = noop, SendAddonMessageLogged = noop}
env.C_Timer = {After = noop, NewTicker = function() return {Cancel=noop} end}
env.C_Spell = {GetSpellTexture = function() return 123 end, GetSpellCharges = function() end}
env.C_DateAndTime = {
    GetCurrentCalendarTime=function() return {year=2026,month=11,monthDay=13,hour=12} end,
    AdjustTimeByDays=function(date,offset)
        local d=os.date("!*t",os.time({year=date.year,month=date.month,day=date.monthDay,hour=12})+offset*86400)
        return {year=d.year,month=d.month,monthDay=d.day,hour=d.hour}
    end,
}
env.C_GuildInfo = {GuildRoster=noop}
env.C_PlayerInfo = {}
env.C_PartyInfo = {}
env.C_Item = {}
env.C_SpecializationInfo = {GetSpecialization=function() return nil end}
env.GetInventoryItemLink = function() return nil end
env.GetInventoryItemID = env.GetInventoryItemLink
env.C_UnitAuras = {}
env.GameTooltip = widget()
env.DEFAULT_CHAT_FRAME = widget()
env.print = noop
env.GetTime = function() return 1000 end
env.GetTimePreciseSec = env.GetTime
env.time = os.time
env.date = os.date
env.GetLocale = function() return "enUS" end
env.GetRealmName = function() return "Realm" end
env.GetNormalizedRealmName = env.GetRealmName
env.GetInstanceInfo = function() return "World", "none", 0 end
env.UnitName = function() return "Tester", "Realm" end
env.UnitFullName = env.UnitName
env.UnitGUID = function(unit) if unit == "player" then return "Player-1-0001" end end
env.UnitClass = function() return "Druid", "DRUID", 11 end
env.UnitLevel = function() return 60 end
env.UnitExists = function(unit) return unit == "player" end
env.UnitIsPlayer = env.UnitExists
env.UnitIsUnit = function(a,b) return a==b end
env.IsInGuild = function() return false end
env.IsInGroup = env.IsInGuild
env.IsInRaid = env.IsInGuild
env.InCombatLockdown = env.IsInGuild
env.GetNumGroupMembers = function() return 0 end
env.GetNumSubgroupMembers = env.GetNumGroupMembers
env.GetNumGuildMembers = env.GetNumGroupMembers
env.GetBuildInfo = function() return "1.60.1", "", "", 16001 end
env.GetAddOnMetadata = env.C_AddOns.GetAddOnMetadata
env.GetCVar = function() return "0" end
env.wipe = function(t) for key in pairs(t) do t[key]=nil end; return t end
env.strsplit = function(delimiter, text)
    local values = {}
    for value in text:gmatch("[^" .. delimiter .. "]+") do values[#values+1] = value end
    return unpack(values)
end
env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

function methods:RegisterEvent(event) self.events[event] = true end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:UnregisterAllEvents() self.events = {} end
function methods:GetRegions() return unpack(self.regions) end
function methods:GetChildren() return unpack(self.children) end
function methods:GetEffectiveScale() return self.scale end
function methods:SetScale(scale) self.scale = scale end
function methods:SetPoint(point, relative, relativePoint, x, y)
    if point=="TOPLEFT" and type(relative)=="number" then self.anchorX,self.anchorY=relative,relativePoint end
    if point=="CENTER" and relativePoint=="BOTTOMLEFT" then self.x,self.y=x,y end
end
function methods:GetCenter() return self.x,self.y end
function methods:GetPoint() return "TOP",env.UIParent,"TOP",20,-75 end
for _,state in ipairs({"Normal","Pushed","Disabled","Highlight"}) do
    methods["Get"..state.."Texture"]=function() return widget() end
end
function methods:GetHorizontalScroll() return 0 end
function methods:GetMinMaxValues() return 0, 0 end
function methods:GetTexture() return self.texture end
function methods:SetTexture(value) self.texture=value end
function methods:GetText() return self.text or "" end
function methods:GetValue() return self.value end
function methods:SetValue(value) self.value=value end
function methods:SetEnabled(enabled) self.enabled=enabled end
function methods:IsEnabled() return rawget(self,'enabled')~=false end
function methods:SetScrollChild(child) self.scrollChild=child end
function methods:GenerateMenu()
    if self.menu then
        self.menu(self, {CreateRadio=noop, CreateButton=noop})
    end
end

local function makeFrame(kind, name, parent, template)
    local frame=widget(parent,template)
    frame.kind=kind
    frame.events={}
    frame.scale=1
    frame.value=0
    frame.texture=false
    frame.x,frame.y=0,0
    if name then env[name]=frame end
    if template=="UIPanelScrollFrameTemplate" then frame.ScrollBar=widget(frame) end
    if template=="UIPanelScrollBarTemplate" then
        frame.ThumbTexture=widget(frame)
        frame.ScrollUpButton,frame.ScrollDownButton=widget(frame),widget(frame)
    end
    if template=="MinimalSliderWithSteppersTemplate" then frame.Slider=widget(frame) end
    if template=="ColorSwatchTemplate" then frame.Color=widget(frame) end
    return frame
end
env.CreateFrame=makeFrame
env.MinimalSliderWithSteppersMixin={Event={OnValueChanged="OnValueChanged"}}
for _,name in ipairs({"GameFontHighlight","GameFontHighlightSmall","GameFontHighlightLarge","GameFontNormal","GameFontNormalSmall","GameFontNormalLarge","GameFontDisable","GameFontDisableSmall","ChatFontNormal"}) do
    env.CreateFont(name)
end

local migrated = {widgetScale=150, widgetPosition={nx=0.5,ny=0.5}}
local legacy = {currentProfile="Raid",profiles={Raid={battleResCounter=migrated}}}
local attendance = {}
local roster = {}
env.KWCDB = {raidTools={main=legacy,attendance=attendance,roster=roster}}
local addon = "KeepersWarCommand/"
local function loadTOC()
local count=0
local private = {}
for line in io.lines(addon.."KeepersWarCommand.toc") do
    local path = line:match("^%s*(.-)%s*$")
    if path~="" and path:sub(1,1)~="#" then
        path=path:gsub("\\","/")
        local chunk=assert(loadfile(addon..path))
        local ok, err=xpcall(function() setfenv(chunk,env)("KeepersWarCommand",private) end,debug.traceback)
        assert(ok,path..": "..tostring(err))
        if path==root.."ConfigFrame.lua" then
            assert(type(env.KeepersRaidTools.RegisterTab)=="function")
            assert(type(env.KeepersRaidTools.Components.CreateText)=="function")
        end
        count=count+1
    end
end
return count
end
local count=loadTOC()
assert(count>0)
local krt=env.KeepersRaidTools
assert(#krt.modules==9)
for _,name in ipairs({"groupInspect","dontRelease","readyScreen","readyCheck","autoInvite","battleResCounter","cooldownRoster","combatTimer","attendance"}) do
    assert(krt.modulesByName[name], name.." failed to register")
end
local initialized={}
for _,entry in ipairs(krt.modules) do
    if entry.module.Initialize then
        local initialize=entry.module.Initialize
        entry.module.Initialize=function(self)
            local ok,err=xpcall(function() initialize(self) end,debug.traceback)
            assert(ok,entry.name..": "..tostring(err))
            initialized[entry.name]=true
        end
    end
end
local frameCount=#frames
for index=1,frameCount do
    local frame=frames[index]
    if rawget(frame,"events") and frame.events.ADDON_LOADED and frame.scripts.OnEvent then
        frame.scripts.OnEvent(frame,"ADDON_LOADED","KeepersWarCommand")
    end
end
for _,entry in ipairs(krt.modules) do
    assert(not entry.module.Initialize or initialized[entry.name], entry.name.." never initialized")
end
local host=widget(env.UIParent)
for _, tab in ipairs({"Don't Release","Ready Check","Auto-Invite","Combat Tools","Notes","Attendance","Roster"}) do
    assert(krt:SelectUnifiedTab(tab),tab.." failed to register")
    assert(krt:MountInWarCommand(host,tab))
    krt:UnmountFromWarCommand()
end
assert(krt.Profiles==nil)
assert(krt:GetSetting("battleResCounter").widgetScale==150)
assert(krt:GetSetting("battleResCounter")~=migrated and legacy.profiles.Raid.battleResCounter==migrated)
assert(env.KWCDB.raidTools.attendance==attendance and env.KWCDB.raidTools.roster==roster)
assert(env.KWCRaidControlFont.isFontObject)
assert(legacy.settings.battleResCounter == krt:GetSetting("battleResCounter"))
local cooldown=env.KRT_CooldownRoster_defensive
local timer=env.KRT_CombatTimerWidget
cooldown.scripts.OnDragStop(cooldown)
timer.scripts.OnDragStop(timer)
assert(legacy.settings.cooldownRoster.positions.defensive.point=="TOPLEFT")
assert(legacy.settings.combatTimer.widgetPosition.y==-75)
assert(legacy.profiles.Raid.cooldownRoster==nil and legacy.profiles.Raid.combatTimer==nil)
for _, frame in ipairs(frames) do
    if rawget(frame,"events") and frame.events.PLAYER_ENTERING_WORLD and frame.scripts.OnEvent then
        frame.scripts.OnEvent(frame,"PLAYER_ENTERING_WORLD")
    end
end
print(("PASS: %d TOC files, seven Raid Tools tabs, %d Raid Tools modules, strict font arguments and legacy settings"):format(count,#krt.modules))

local function visible(frame)
    while frame do
        if not frame:IsShown() then return false end
        frame=frame:GetParent()
    end
    return true
end
local function control(kind,caption)
    for i=#frames,1,-1 do
        local frame=frames[i]
        if rawget(frame,"kind")==kind and visible(frame) then
            if frame.text==caption then
                return frame
            end
            for _, region in ipairs(frame.regions) do
                if region.text==caption then return frame end
            end
        end
    end
end
local function click(caption)
    local button=assert(control("Button",caption),caption)
    button.scripts.OnClick(button)
end

local ui=env.KWC.UI
env.KWC.IsOfficer=function() return true end
ui.Toggle()
assert(control("Button","Home").kwcPage=="Home")
assert(control("Button","Find a Group") and control("Button","Guild Overview"))
local sidebar=control("Button","Home"):GetParent():GetParent()
sidebar.scripts.OnMouseWheel(sidebar,-10)
assert(sidebar:GetVerticalScroll()>0)
sidebar.scripts.OnMouseWheel(sidebar,10)
assert(sidebar:GetVerticalScroll()==0)
click("Find a Group")
assert(not control("Button","Find a Group"))
click("Home")
click("PvP Operations")
assert(control("Button","War Room").kwcPage=="War Room")
click("Home")
click("Settings")
assert(control("Button","View Guild Roster"))
assert(control("Button","Sharing unavailable").enabled==false)
click("View Guild Roster")
assert(control("Button","Check addon versions"))
click("Home")
click("Guild Services")
assert(not control("Button","Find a Group"))
ui.Toggle()
ui.Toggle()
assert(control("Button","Find a Group"))
click("Raid Operations")
assert(control("Button","Raid Sign-Ups"))
ui.Toggle("Raid Tools: Battle Resurrection")
assert(control("Button","Show Preview").enabled==false)
local lock=assert(control("Button","Unlock Position"))
assert(lock.enabled==false)
print("PASS: Home, shortcut and sidebar navigation, Preferences access and unavailable controls")

ui.Toggle("Raid Tools")
assert(control("Button","Raid Operations").kwcPage=="Raid Tools")
assert(not control("Button","War Intelligence"))
assert(rawget(control("Button","Raid Command"),"kwcPage")==nil)
click("Raid Sign-Ups")
local title=assert(control("EditBox","Molten Core"))
title:SetText("Raid draft")
title.scripts.OnTextChanged(title)
click("Raid Command")
assert(control("Button","Raid Sign-Ups"))
click("Raid Sign-Ups")
assert(control("EditBox","Raid draft"))
env.IsInGuild=function() return true end
env.C_Club={GetGuildClubId=function() return 1 end}
click("Create Raid Sign-Up")
local id,event=next(env.KWCDB.raidSignups.events)
assert(id and event.title=="Raid draft")
env.IsInGuild=function() return true end
click("Attending")
assert(env.KWCDB.raidSignups.responses[id].Tester.status=="Attending")
ui.Toggle("KT Raid")
assert(control("Button","Raid Sign-Ups"))
print("PASS: Raid Operations tabs, legacy route, draft, raid creation and RSVP")

ui.Toggle("Raid Tools: Notes")
assert(not env.KRTForeverNoteDisplay)
click("Show Note")
assert(not env.KRTForeverNoteDisplay, "blank note opened a window")
local editor=assert(control("EditBox",""))
editor:SetText("Pull left")
editor.scripts.OnTextChanged(editor)
click("Save")
click("Show Note")
local display=assert(env.KRTForeverNoteDisplay)
assert(display:IsShown() and env.KRTForeverNotesDB.notes["Raid Plan"]=="Pull left")
local steel, graphite
for _, texture in ipairs(display.regions) do
    if texture.sublayer==-8 then steel=texture.color end
    if texture.sublayer==-7 then graphite=texture.color end
end
assert(steel and steel[1]==env.KWC.UITheme.steel[1] and steel[4]==1)
assert(graphite and graphite[1]<0.1 and graphite[4]==1)
click("New")
assert(not display:IsShown())
editor:SetText("Second plan")
editor.scripts.OnTextChanged(editor)
click("Show Note")
assert(display:IsShown())
click("Delete")
assert(env.KRTForeverNotesDB.notes["Note 1"]==nil)
assert(env.KRTForeverNotesDB.notes["Raid Plan"]=="Pull left" and editor:GetText()=="Pull left")
assert(display:IsShown())
click("Hide Note")
assert(not display:IsShown())
local longNote = "First line\nSecond line\n" .. string.rep("longword ", 400)
editor:SetText(longNote)
editor.scripts.OnTextChanged(editor)
assert(editor:GetHeight()>editor:GetParent():GetHeight())
local oldHeight = editor:GetHeight()
editor:SetFont("Fonts\\FRIZQT__.TTF", 20, "")
editor:GetParent().scripts.OnSizeChanged(editor:GetParent())
assert(editor:GetHeight()>oldHeight, "measurement did not follow the editor font")
click("Show Note")
assert(display:IsShown() and display.CloseButton:IsShown())
for _, child in ipairs(display.children) do
    if child.kind=="ScrollFrame" then
        assert(child.scrollChild:GetHeight()>208, "long display note should scroll")
        local noteText=child.scrollChild.regions[1]
        assert(noteText.appliedFont==env.KWCRaidControlFont and noteText:GetText()==longNote)
    end
end
display.CloseButton:Click()
assert(not display:IsShown())
print("PASS: Raid Notepad Show, Hide, Save, New and Delete preserve the intended notes")

env.GetNumGroupMembers=function() return 2 end
env.UnitIsGroupLeader=function(unit) return unit=="player" end
env.UnitIsConnected=function() return true end
env.KWC.Net.Send=function() return true end
ui.Toggle("Raid Tools: Command")
click("G1 Tester")
local duty
for _,widget in ipairs(frames) do
    if rawget(widget,"kind")=="EditBox" and visible(widget) then duty=widget;break end
end
assert(duty)
duty:SetText("Assign interrupts")
duty.scripts.OnTextChanged(duty)
click("Set Assignment")
assert(env.KWCDB.raidCommand.assignments.Tester=="Assign interrupts")
local template=assert(control("EditBox",""))
template:SetText("Progression")
template.scripts.OnTextChanged(template)
click("Raid Sign-Ups")
assert(control("Button","> Raid draft"))
click("Raid Command")
assert(control("EditBox","Progression"))
click("Save Template")
assert(env.KWCDB.raidCommand.templates.Progression.Tester=="Assign interrupts")

local whispers={}
env.C_ChatInfo.SendChatMessage=function(message,channel,_,player)
    assert(channel=="WHISPER")
    whispers[player]=message
end
env.IsInRaid=function() return true end
env.GetUnitName=function(unit) return unit end
env.UnitIsVisible=function() return true end
env.UnitIsDeadOrGhost=function(unit) return unit=="Fallen" end
env.UnitGroupRolesAssigned=function(unit) return unit=="Healer" and "HEALER" or "NONE" end
env.C_UnitAuras.GetAuraDataBySpellName=function() return nil end
function krt:IterateGroup() return string.gmatch("Fallen Healer","%S+") end
krt.GroupInspect.members={
    priest={class="PRIEST",name="Priest"},
    lock={class="WARLOCK",name="Warlock"},
}
local ready=krt:GetSetting("readyCheck")
ready.snarkyMessages=true -- Existing SavedVariables must have no effect on wording.
ready.whisperMissingAddon="off"
ready.whisperOutdatedAddon="off"
krt.ReadyCheck:OnReadyCheck()
assert(whispers.Fallen=="Please accept your resurrection before the pull.")
assert(whispers.Priest=="Missing raid buff: Power Word: Fortitude.")
assert(whispers.Warlock=="No healer has a Soulstone. Please apply one before the pull.")
ui.Toggle("Raid Tools: Ready Check")
assert(not control("Button","Playful messages"))
print("PASS: Raid Command assignment and template drafts, professional readiness messages with legacy settings")

-- Exercise the real leaderboard controls and each view's displayed totals.
local player = env.KWC.PvP.PlayerName()
if not player then
    env.UnitFullName=function() return "Tester Example" end
    player=env.KWC.PvP.PlayerName()
end
env.KWCDB.pvp[player]={
    honor={available=true,lifetime=473},
    honorByArea={world={value=37,at=1},battleground={value=129,at=1}}
}
local function hasLabel(value)
    for _, frame in ipairs(frames) do
        if visible(frame) then
            for _, region in ipairs(frame.regions) do
                if region.text==value and region:IsShown() then return true end
            end
        end
    end
end
ui.Toggle("Settings")
local beforeSettings=env.CopyTable(env.KWCDB.settings)
local originalSend=env.C_ChatInfo.SendAddonMessage
local searchSends=0
env.C_ChatInfo.SendAddonMessage=function() searchSends=searchSends+1 end
click("Search Settings")
local search=assert(control("EditBox",""))
local function findSetting(term,caption)
    search:SetText(term)
    search.scripts.OnTextChanged(search)
    assert(control("Button",caption),caption)
end
findSetting("battle rez","Battle Resurrection")
assert(not control("Button","Guild Services Sharing"))
findSetting("minimap","Minimap Launcher")
findSetting("sharing","Guild Services Sharing")
findSetting("bounty","Bounty Alerts")
findSetting("guild death","Guild Death Alerts")
findSetting("autoscout","Auto Scout")
findSetting("sync","Sync Health")
findSetting("sound","Alert Sound")
findSetting("scale","Window Scale")
search:SetText("impossible term")
search.scripts.OnTextChanged(search)
assert(hasLabel("No settings match this search."))
findSetting("battle rez","Battle Resurrection")
click("Battle Resurrection")
assert(control("Button","Show Preview").enabled==false)
assert(hasLabel("Show the Battle Resurrection button while in a raid."))
for key,value in pairs(beforeSettings) do
    if type(value)~="table" then assert(env.KWCDB.settings[key]==value,key) end
end
assert(searchSends==0)
env.C_ChatInfo.SendAddonMessage=originalSend
ui.Toggle("CTA Board")
assert(control("Button","New Call to Arms") and not control("Button","+ New CTA"))
print("PASS: settings terms, search empty state and routing, no outgoing traffic, and full Call to Arms label")

ui.Toggle("PvP Leaderboard")
assert(control("Button","All-Time HKs") and hasLabel("473") and hasLabel("Warlord"))
click("World PvP")
assert(hasLabel("WORLD HKs") and hasLabel("37") and not hasLabel("473"))
click("Battlegrounds")
assert(hasLabel("BATTLEGROUND HKs") and hasLabel("129") and not hasLabel("37"))
click("All-Time HKs")
assert(hasLabel("473") and hasLabel("BOUNTIES") and hasLabel("CALLS TO ARMS"))
print("PASS: all three leaderboard views and lifetime tiers, bounty and CTA columns")

-- Drive the actual Recruitment buttons and the Core WHO_LIST_UPDATE handler.
local whoTime=1000
local queries, timers, whoRows, drafts = {}, {}, {}, {}
env.GetTime=function() return whoTime end
env.GetNormalizedRealmName=function() return "Home" end
env.C_Timer.After=function(delay,fn) timers[#timers+1]={at=whoTime+delay,fn=fn} end
env.C_FriendList={
    SetWhoToUi=function() end,
    SendWho=function(query) queries[#queries+1]=query end,
    GetNumWhoResults=function() return #whoRows,#whoRows>0 and 95 or 0 end,
    GetWhoInfo=function(index) return whoRows[index] end,
}
env.ChatFrame_OpenChat=function(text) drafts[#drafts+1]=text end
local function deliverWho()
    for _,frame in ipairs(frames) do
        if rawget(frame,"events") and frame.events.WHO_LIST_UPDATE then
            frame.scripts.OnEvent(frame,"WHO_LIST_UPDATE")
            return
        end
    end
    error("WHO_LIST_UPDATE listener missing")
end
local function advanceWho(seconds)
    whoTime=whoTime+seconds
    local previous=timers
    timers={}
    for _,timer in ipairs(previous) do
        if timer.at<=whoTime then timer.fn() else timers[#timers+1]=timer end
    end
end
for i=1,50 do
    whoRows[i]={fullName=("Candidate%02d-Home"):format(i),fullGuildName=i<=16 and "" or "Already Guilded",
        level=15,classStr="Warrior",area="Durotar"}
end
ui.Toggle("Recruitment")
assert(not control("Button","Prepare invite"):IsEnabled())
local search=assert(control("Button","Search /who"))
local query=assert(control("EditBox","10-20"))
click("Search /who")
assert(#queries==1 and queries[1]=="10-20")
assert(not search:IsEnabled())
env.KWC.Recruiter.Search("10-20")
assert(#queries==1)
deliverWho()
assert(#env.KWC.Recruiter.results==16)
for i=1,16 do assert(control("Button",("Candidate%02d-Home"):format(i))) end
assert(hasLabel("Level 15  |  Warrior  |  Durotar"))
local last=control("Button","Candidate16-Home")
assert(last:GetParent():GetHeight()>=16*46 and last:GetParent():GetParent().kind=="ScrollFrame")
click("Candidate16-Home")
assert(hasLabel("Selected: Candidate16-Home") and control("Button","Prepare invite"):IsEnabled())
click("Prepare whisper")
click("Prepare invite")
assert(drafts[1]:find("/w Candidate16-Home ",1,true)==1 and drafts[2]=="/ginvite Candidate16-Home")
assert(hasLabel("invite prepared"))
assert(not search:IsEnabled())
advanceWho(8)
assert(search:IsEnabled())
click("Search /who")
assert(#queries==2 and control("Button","Candidate01-Home"))
local first=whoRows[1]
whoRows={{fullName="Unrelated",fullGuildName="",level=40,classStr="Priest"}}
deliverWho()
assert(env.KWC.Recruiter.pending and #env.KWC.Recruiter.results==16)
whoRows={first,{fullName="CANDIDATE01",fullGuildName="",level=15,classStr="Warrior"}}
deliverWho()
assert(#env.KWC.Recruiter.results==1 and not control("Button","Candidate16-Home"))
assert(control("EditBox","10-20")==query, "result refresh recreated the active query field")
advanceWho(8)
click("Search /who")
whoRows={}
deliverWho()
assert(hasLabel("No eligible candidates in the latest results."))
advanceWho(8)
click("Search /who")
whoRows={first}
deliverWho()
assert(control("Button","Candidate01-Home"))
local savedRecruitment=env.CopyTable(env.KWCDB.recruiter)
env.KWCDB.recruiter=savedRecruitment
local recruiterChunk=assert(loadfile(addon.."Recruiter.lua"))
setfenv(recruiterChunk,env)()
env.KWC.Recruiter.Restore()
assert(#env.KWC.Recruiter.results==1 and savedRecruitment.candidates.candidate16.status=="invite prepared")
assert(not env.KWC.Recruiter.SearchReady(),"reload reset WHO cooldown")
print("PASS: WHO event renders 16 selectable candidates, drafts actions, deduplicates results, throttles and restores state")

-- Drive the runtime Guild LFG sidebar through late club and roster readiness.
local guildMember,clubID,rosterCount=true,nil,0
local rosterRequests=0
env.IsInGuild=function() return guildMember end
env.C_Club={GetGuildClubId=function() return clubID end}
env.C_GuildInfo={GuildRoster=function() rosterRequests=rosterRequests+1 end}
env.GetNormalizedRealmName=function() return "Home" end
env.UnitFullName=function() return "Tester","Home" end
env.GetNumGuildMembers=function() return rosterCount end
env.GetGuildRosterInfo=function(i)
    return i==1 and "Tester" or "Guildmate","Member",i==1 and 1 or 3,40,"Warrior","","","",true
end
local function lfgEvent(event)
    for _,f in ipairs(frames) do
        if rawget(f,"events") and f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f,event) end
    end
end
ui.Toggle("Overview")
click("Looking for Group")
assert(hasLabel("Guild identity unavailable") and control("Button","Retry"))
assert(not control("Button","Create Listing"))
clubID=1
lfgEvent("INITIAL_CLUBS_LOADED")
advanceWho(1)
assert(hasLabel("Waiting for guild roster") and rosterRequests>0)
rosterCount=2
lfgEvent("GUILD_ROSTER_UPDATE")
advanceWho(1)
assert(control("Button","> Browse Groups") and control("Button","Create Listing"))
click("Preferences")
assert(env.KWC.GuildServices.IsSharing() and control("Button","Sharing On"))
click("Sharing On")
assert(not env.KWC.GuildServices.IsSharing() and control("Button","Sharing Off"))
click("Hide Minimap Icon")
assert(not env.KWC.MinimapLauncher.IsVisible() and control("Button","Show Minimap Icon"))
click("Show Minimap Icon")
assert(env.KWC.MinimapLauncher.IsVisible())
click("Looking for Group")
-- A populated roster can coexist with an unresolved local character.
local oldRoster=env.GetGuildRosterInfo
local oldName,oldFull,oldGet=env.UnitName,env.UnitFullName,env.GetUnitName
env.UnitName=function() return "Nez","Home" end
env.UnitFullName=env.UnitName
env.GetUnitName=env.UnitName
rosterCount=84
local showGuid=false
env.GetGuildRosterInfo=function(i)
    local name=i==1 and "Nez Dankdabs-Home" or i==2 and "Righteous Bonez-Home" or ("Green Burninator "..i.."-Home")
    local guid=i==1 and showGuid and "Player-1-0001" or nil
    return name,"Member",i==1 and 1 or 3,40,"Warrior","","","",true,nil,nil,nil,nil,nil,nil,nil,guid
end
lfgEvent("GUILD_ROSTER_UPDATE")
assert(env.KWCDB.roster["nez dankdabs-home"] and env.KWC.GuildReadiness()=="Local character not verified")
assert(hasLabel("Local character not verified") and not control("Button","Create Listing"))
click("Guild Services")
assert(hasLabel("Local character not verified") and not control("Button","Professions"))
env.C_Club.GetMemberInfoForSelf=function(id) assert(id==1);return {isSelf=true,name="Nez Dankdabs-Home"} end
lfgEvent("GUILD_ROSTER_UPDATE")
assert(control("Button","Professions") and control("Button","Recipes"))
assert(env.KWC.AddonChecker.ForRoster("Nez Dankdabs-Home").localClient)
env.C_Club.GetMemberInfoForSelf=nil
showGuid=true
lfgEvent("GUILD_ROSTER_UPDATE")
assert(not env.KWC.AddonChecker.ForRoster("Righteous Bonez-Home"))
local function checkerPacket(body,sender)
    for _,handler in ipairs(env.KWC.listeners.CHAT_MSG_ADDON) do handler("KWCCHK",body,"GUILD",sender) end
end
checkerPacket("R|1.6.0-dev.55","Righteous Bonez-Home")
assert(env.KWC.AddonChecker.ForRoster("Righteous Bonez-Home").version=="1.6.0-dev.55")
checkerPacket("V2|R|2.0","Righteous Bonez-Home")
assert(env.KWC.AddonChecker.ForRoster("Righteous Bonez-Home").unsupported)
local messages={}
local say=env.KWC.Say
env.KWC.Say=function(msg) messages[#messages+1]=msg end
for i,alias in ipairs({"/kwc","/kt","/keepers"}) do
    assert(env["SLASH_KEEPERSWARCOMMAND"..i]==alias)
    env.SlashCmdList.KEEPERSWARCOMMAND("help")
    assert(#messages==i,"help must print once per invocation")
end
env.SlashCmdList.KEEPERSWARCOMMAND("guilddebug")
assert(messages[4]:find("84 readable",1,true) and messages[5]:find("roster GUID",1,true))
env.KWC.Say=say
click("Looking for Group")
assert(control("Button","> Browse Groups") and control("Button","Create Listing"))
-- An ambiguous given name is not accepted for remote authorization.
assert(not env.KWC.CurrentGuildMember("Nez-Home"))
env.UnitName,env.UnitFullName,env.GetUnitName=oldName,oldFull,oldGet
env.GetGuildRosterInfo=oldRoster
rosterCount=2
lfgEvent("GUILD_ROSTER_UPDATE")
print("PASS: 84-row readiness reproduction, GUID match, shared page refresh, checker identity and one help line")
click("Create Listing")
local function typeIn(box,value)
    box:SetText(value)
    box.scripts.OnTextChanged(box)
end
-- The name and description are initially empty. Locate the name by its width.
local activityBox
for _,f in ipairs(frames) do
    if f.kind=="EditBox" and visible(f) and f:GetWidth()==340 then activityBox=f end
end
typeIn(assert(activityBox),"Library LFG")
click("Create")
assert(control("Button","> My Listings") and control("Button","[Mine] Library LFG"))
click("Edit")
typeIn(assert(control("EditBox","Library LFG")),"Armory LFG")
click("Save Listing")
assert(control("Button","[Mine] Armory LFG"))
local listing=env.KWC.GuildLFG.Browse({mine=true})[1]
local invited
env.C_PartyInfo={InviteUnit=function(name) invited=name end}
for _,handler in ipairs(env.KWC.listeners.CHAT_MSG_ADDON) do
    handler("KWL1","1|I|"..listing.id.."|guildmate|1|"..env.time().."|1","GUILD","Guildmate-Home")
end
ui.Toggle("Looking for Group")
click("Invite")
assert(invited=="guildmate")
click("Close")
click("Delete")
assert(#env.KWC.GuildLFG.Browse({mine=true})==0)
local row="1|L|guildmate/1|1|1|open|"..env.time().."|"..env.time().."|"..(env.time()+3600)..
    "|1|8|1|60|2|5|60|0|Guildmate Dungeon|"
for _,handler in ipairs(env.KWC.listeners.CHAT_MSG_ADDON) do handler("KWL1",row,"GUILD","Guildmate-Home") end
click("Browse Groups")
click("Guildmate Dungeon")
click("Interested")
assert(control("Button","Withdraw Interest"))
click("Whisper Leader")
assert(drafts[#drafts]=="/w guildmate ")
local whisperTarget
env.ChatFrameUtil={SendTell=function(name) whisperTarget=name end}
click("Whisper Leader")
assert(whisperTarget=="guildmate")
click("Withdraw Interest")
assert(control("Button","Interested"))
clubID=nil
lfgEvent("PLAYER_GUILD_UPDATE")
advanceWho(1)
assert(hasLabel("Guild identity unavailable") and not control("Button","Guildmate Dungeon"))
clubID=2
lfgEvent("CLUB_UPDATED")
advanceWho(1)
assert(control("Button","> Browse Groups") and not control("Button","Guildmate Dungeon"))
guildMember=false
lfgEvent("PLAYER_GUILD_UPDATE")
advanceWho(1)
assert(hasLabel("Not currently in a guild"))
guildMember=true;clubID=1
click("Looking for Group")
advanceWho(1)
assert(control("Button","Guildmate Dungeon"))
-- Silent availability without an event is picked up by the bounded retry.
clubID=nil
lfgEvent("CLUB_UPDATED")
advanceWho(1)
assert(hasLabel("Guild identity unavailable"))
clubID=1
advanceWho(8)
assert(control("Button","Guildmate Dungeon"))
print("PASS: Guild LFG sidebar, form, selection, edit, interest, withdrawal, invite and whisper callbacks")

-- Exercise the real Bounty Board toolbar at supported scale and viewport sizes.
local bounty=env.CopyTable(env.KWCDB.bounties)
env.KWCDB.bounties={{id="toolbar-active",author="Tester",text="Toolbar Rival",status="ACTIVE",details={target="Toolbar Rival"}}}
local targetAvailable=false
env.UnitExists=function(unit) return unit=="player" or (unit=="target" and targetAvailable) end
env.UnitIsPlayer=env.UnitExists
env.UnitFullName=function(unit) return unit=="target" and "Rival" or "Tester","Home" end
local titles={"New Bounty","Report Sighting","Capture Target","Report to Guild"}
for _,config in ipairs({{1024,768,0.65},{1600,900,1},{2560,1440,1.35}}) do
    env.UIParent:SetSize(config[1],config[2])
    env.KWC.UI.SetScale(config[3])
    env.KWC.UI.Toggle("Bounty Board")
    local items={}
    for _,title in ipairs(titles) do
        local b=assert(control("Button",title),title)
        assert(b.anchorX and b.anchorY and b:GetWidth()>0)
        for _,region in ipairs(b.regions) do
            if region.text==title then assert(region:GetWidth()>=region:GetStringWidth(),title.." clipped") end
        end
        for _,other in ipairs(items) do
            assert(b.anchorX+b:GetWidth()<=other.anchorX or other.anchorX+other:GetWidth()<=b.anchorX
                or b.anchorY-b:GetHeight()>=other.anchorY or other.anchorY-other:GetHeight()>=b.anchorY,
                title.." overlaps another action")
        end
        items[#items+1]=b
    end
end
assert(not control("Button","Report Sighting"):IsEnabled())
assert(not control("Button","Capture Target"):IsEnabled())
click("Report Sighting")
assert(control("Button","New Bounty"))
click("Toolbar Rival")
assert(control("Button","Report Sighting"):IsEnabled())
click("Report Sighting")
assert(control("Button","SUBMIT SIGHTING"))
click("Back to Bounty Board")
env.KWCDB.bounties[1].status="COMPLETED"
click("Report Sighting")
assert(control("Button","New Bounty"),"stale selection opened a sighting form")
click("COMPLETED")
assert(not control("Button","Report Sighting"):IsEnabled())
targetAvailable=true
lfgEvent("PLAYER_TARGET_CHANGED")
assert(control("Button","Capture Target"):IsEnabled())
click("Capture Target")
assert(control("EditBox","Rival-Home") and control("Button","POST BOUNTY"))
env.KWC.UI.Toggle("Bounty Board")
local reports=0
local listActive=env.KWC.Operations.ListActive
env.KWC.Operations.ListActive=function(kind,draft)
    assert(kind=="BOUNTY" and draft==true)
    reports=reports+1
end
click("Report to Guild")
assert(reports==1)
env.KWC.Operations.ListActive=listActive
click("New Bounty")
assert(control("Button","POST BOUNTY"))
env.KWCDB.bounties=bounty
print("PASS: Bounty toolbar spacing, label widths, scales, selection, target and action callbacks")

-- Simulate a new Lua session loading the same saved notes in the actual TOC.
local savedNotes = env.CopyTable(env.KRTForeverNotesDB)
env.KRTForeverNoteDisplay = nil
env.KRTForeverNotesDB = savedNotes
env.KWC.UI.Toggle()
assert(loadTOC()==count)
-- On reload, saved listings remain hidden until both sources return.
clubID=nil;rosterCount=0
for _,f in ipairs(frames) do
    if rawget(f,"events") and f.events.ADDON_LOADED and f.scripts.OnEvent then
        f.scripts.OnEvent(f,"ADDON_LOADED","KeepersWarCommand")
    end
end
env.KWC.UI.Toggle("Looking for Group")
assert(hasLabel("Guild identity unavailable") and not control("Button","Guildmate Dungeon"))
clubID=1
lfgEvent("INITIAL_CLUBS_LOADED")
assert(hasLabel("Waiting for guild roster"))
rosterCount=2
lfgEvent("GUILD_ROSTER_UPDATE")
assert(control("Button","> Browse Groups") and control("Button","Guildmate Dungeon"))
assert(env.KeepersRaidTools:MountInWarCommand(widget(env.UIParent),"Notes"))
local restored
for i=#frames,1,-1 do
    if frames[i].kind=="EditBox" and frames[i]:GetText()==longNote then
        restored=frames[i]
        break
    end
end
assert(restored and env.KRTForeverNotesDB.notes["Raid Plan"]==longNote)
assert(not env.KRTForeverNoteDisplay)
print("PASS: existing multiline raid notes survive TOC reload and remain closed on startup")
