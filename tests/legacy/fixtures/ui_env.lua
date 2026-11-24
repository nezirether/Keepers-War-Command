-- Shared widget mock, taken from the KWC tests/raid_tools_initialization.lua
-- harness. Returns env, frames, methods, widget. Not a suite: CI runs only
-- tests/*.lua, and this file lives in tests/fixtures/.
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
env.CreateFont = function(name) local font = widget(); font.isFontObject = true; env[name] = font; return font end
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
env.InCombatLockdown = function() return false end
env.GetNumGroupMembers = function() return 0 end
env.GetNumSubgroupMembers = env.GetNumGroupMembers
env.GetNumGuildMembers = env.GetNumGroupMembers
env.GetBuildInfo = function() return "1.60.1", "", "", 16001 end
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
    if template=="UIPanelScrollFrameTemplate" then
        frame.ScrollBar=widget(frame)
        frame.ScrollBar.ThumbTexture=widget(frame.ScrollBar)
        frame.ScrollBar.ScrollUpButton=widget(frame.ScrollBar)
        frame.ScrollBar.ScrollDownButton=widget(frame.ScrollBar)
    end
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
return env, frames, methods, widget
