-- Run from the repository root with Lua 5.1.
local function loadSettings(db)
    local env = setmetatable({
        KeepersRaidToolsDB = db,
        CreateFrame = function() return {RegisterEvent = function() end, SetScript = function() end} end,
    }, {__index = _G})
    setfenv(assert(loadfile("KeepersWarCommand/Modules/RaidTools/KeepersRaidTools.lua")), env)()
    local krt = env.KeepersRaidTools
    krt.defaults.autoInvite = {enabled = true, inviteRanks = {officer = false}, keywords = "inv"}
    krt.defaults.attendance = {enabled = true}
    krt:InitializeDB()
    return krt
end

local selected = {autoInvite = {enabled = false, inviteRanks = {officer = true}}}
local default = {autoInvite = {keywords = "default"}}
local legacy = {currentProfile = "Progression", profiles = {Progression = selected, Default = default}}
local krt = loadSettings(legacy)
local settings = krt:GetSetting("autoInvite")
assert(settings.enabled == false and settings.inviteRanks.officer and settings.keywords == "inv")
assert(krt:GetSetting("attendance").enabled and krt.Profiles == nil)
assert(settings ~= selected.autoInvite and settings.inviteRanks ~= selected.autoInvite.inviteRanks)
settings.inviteRanks.officer = false
settings.keywords = "saved"
assert(legacy.currentProfile == "Progression" and legacy.profiles.Progression == selected)
assert(selected.autoInvite.inviteRanks.officer and selected.autoInvite.keywords == nil)
legacy.currentProfile = "Default"
assert(loadSettings(legacy):GetSetting("autoInvite").keywords == "saved")
local fallback = {currentProfile = "Missing", profiles = {Default = default}}
assert(loadSettings(fallback):GetSetting("autoInvite").keywords == "default")
assert(loadSettings({}):GetSetting("autoInvite").keywords == "inv")
print("PASS: Raid settings migrate once, preserve selected values and historical profiles, and survive reload")
