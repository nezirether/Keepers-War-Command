-- Run from the repository root with Lua 5.1.
local root = "KeepersWarCommand/Modules/RaidTools/"
local env = setmetatable({ KeepersRaidTools = {}, UISpecialFrames = {} }, { __index = _G })
local frames = {}
local noop = function() end
local methods = {}
local function widget(parent, template)
    local frame = setmetatable({ parent = parent, template = template, shown = true,
        scripts = {}, regions = {}, children = {}, width = 100, height = 28 },
        { __index = function(_, key) return methods[key] or noop end })
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
function methods:CreateTexture() return widget() end
function methods:CreateFontString(_, _, template)
    assert(template == nil or (type(template) == "string" and not template:match("^KWCRaid")),
        "CreateFontString requires a template name, not a custom FontObject")
    local f = widget()
    table.insert(self.regions, f)
    return f
end
function methods:SetFontObject(font)
    assert(type(font) == "table" and font.isFontObject, "expected a FontObject")
    self.appliedFont = font
end
function methods:GetFontString() self.fontString = rawget(self, "fontString") or widget(); return self.fontString end
function methods:SetText(text) self.text = text; self:GetFontString().text = text end
function methods:GetStringWidth() return #(self.text or "") * 7 end
function methods:SetSize(w,h) self.width,self.height = w,h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
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
function methods:Hide() self.shown = false end
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
env.CreateFrame = function(_, _, parent, template) return widget(parent, template) end
env.CreateFont = function(name) local font = widget(); font.isFontObject = true; env[name] = font; return font end
env.C_AddOns = { GetAddOnMetadata = function() return "test" end }
env.hooksecurefunc = function(object, key, after)
    local prior = object[key]
    object[key] = function(self, ...) prior(self, ...); after(self, ...) end
end
setfenv(assert(loadfile(root .. "ConfigFrame.lua")), env)()
local krt = env.KeepersRaidTools
local ui = krt.Components
local host = widget(env.UIParent)
local first, second
krt:RegisterTab("Attendance", function(parent)
    return ui.GetSubTabGroup(parent, {
        {name = "Records", setup = function(panel) first = panel end},
        {name = "Settings", setup = function(panel) second = panel end},
    })
end)
local roster
krt:RegisterTab("Roster", function(parent) roster = widget(parent); return roster end)
assert(krt:MountInWarCommand(host, "Attendance"))
assert(first:IsShown() and not second:IsShown())
for _, f in ipairs(frames) do
    if f.scripts.OnClick and f.text == "Settings" then f:Click(); break end
end
assert(not first:IsShown() and second:IsShown())
assert(krt:MountInWarCommand(host, "Roster") and roster:IsShown())
local picked, checked
local dropdown = ui.GetBasicDropdown(host, "Records", function()
    return {{name = "Example record", value = "day"}}
end, function(value) return picked == value end, function(value) picked = value end).DropDown
assert(dropdown.Background.alpha == 0 and dropdown.Arrow.alpha == 0)
dropdown.menu(dropdown, {CreateRadio = function(_, name, selected, callback)
    assert(name == "Example record" and not selected())
    callback()
    assert(selected())
end})
local check = ui.GetCheckbox(host, "Guild members only", function(value) checked = value end)
check:SetValue(false)
check.CheckBox:Click()
assert(check:GetValue() and checked and picked == "day")
local panel = ui.CreatePanel("Test", host)
panel:Show()
panel.CloseButton:Click()
assert(not panel:IsShown())
print("PASS: Raid Tools shell, mounting, tabs, panel close, dropdown selection and checkbox callback")
