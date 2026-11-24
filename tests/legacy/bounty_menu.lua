-- Run from the repository root with Lua 5.1.
local events, tags, messages = {}, {}, {}
local picked
local target = "Enemy"
local env = setmetatable({
    CreateFrame = function() return {
        RegisterEvent = function() end,
        SetScript = function(_, _, callback) events.dispatch = callback end,
    } end,
    SlashCmdList = {},
    print = function(msg) table.insert(messages, msg) end,
    UnitExists = function(unit) return unit ~= "missing" end,
    UnitIsPlayer = function(unit) return unit ~= "npc" end,
    UnitFullName = function(unit) if unit == "target" then return target, "Realm" end end,
    UnitName = function() return "Focus-Realm", "Realm" end,
}, {__index = _G})
setfenv(assert(loadfile("KeepersWarCommand/Core.lua")),env)()
setfenv(assert(loadfile("KeepersWarCommand/UITheme.lua")),env)()
setfenv(assert(loadfile("KeepersWarCommand/UI.lua")),env)()
env.KWC.UI.OpenBountyForName = function(name) picked = name end
setfenv(assert(loadfile("KeepersWarCommand/BountyContextMenu.lua")),env)()
events.dispatch(nil,"PLAYER_LOGIN")
assert(next(tags) == nil)
env.SlashCmdList.KEEPERSWARCOMMAND("bounty addtarget")
assert(picked == "Enemy-Realm")
env.Menu = {ModifyMenu = function(tag, cb)
    assert(not tags[tag], "duplicate registration")
    tags[tag] = cb
end}
events.dispatch(nil,"ADDON_LOADED","Blizzard_Menu")
events.dispatch(nil,"PLAYER_ENTERING_WORLD")
events.dispatch(nil,"PLAYER_LOGIN")
assert(tags.MENU_UNIT_PLAYER and tags.MENU_UNIT_RAID and tags.MENU_UNIT_ENEMY_PLAYER)
local options = {}
local root = {CreateButton = function(_, text, cb)
    assert(text == "KWC: Add Bounty")
    table.insert(options, cb)
end}
local cb = tags.MENU_UNIT_ENEMY_PLAYER
cb(nil, root, {unit="npc"})
cb(nil, root, {})
assert(#options == 0)
cb(nil, root, {unit="target"})
cb(nil, root, {unit="target"})
assert(#options == 1)
target = "Different"
options[1]()
assert(picked == "Enemy-Realm")
env.KWC.UI.OpenBountyForUnit("focus")
assert(picked == "Focus-Realm")
env.KWC.UI.OpenBountyForUnit("missing")
assert(messages[1]:find("Target a player first.",1,true))
print("PASS: Forever tagged menus, delayed and duplicate registration, captured full name and target fallback")
