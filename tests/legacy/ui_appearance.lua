-- Run from the repository root with LuaJIT: luajit tests/ui_appearance.lua
-- UI Appearance (Classic / Trogdor) regression suite.
-- Part 1 drives Appearance.lua directly: defaults, invalid values, switching,
-- preservation of unrelated settings, combat deferral and /reload persistence.
-- Part 2 loads the full TOC with mocked widgets: the Settings selector and
-- search entry, live re-tinting without reload, combat-safe switching, no
-- addon or chat traffic, CTA and bounty actions in both appearances, identical
-- page layouts and navigation, and texture/TOC references.

local function deepCopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return "<cycle>" end
    seen[v] = true
    local out = {}
    for k, x in pairs(v) do out[k] = deepCopy(x, seen) end
    seen[v] = nil
    return out
end
local function same(a, b, path)
    path = path or "value"
    if type(a) ~= type(b) then return false, path end
    if type(a) ~= "table" then return a == b, path end
    for k, v in pairs(a) do local ok, p = same(v, b[k], path .. "." .. tostring(k)); if not ok then return false, p end end
    for k in pairs(b) do if a[k] == nil then return false, path .. "." .. tostring(k) end end
    return true
end
local function assertSame(a, b, what)
    local ok, where = same(a, b, what)
    assert(ok, what .. " differs at " .. tostring(where))
end

-- ------------------------------------------------------------------ Part 1
local TOKENS = {"gold","cream","muted","bronze","steel","graphite","charcoal","panel","hover",
    "crimson","accent","sidebar","molten","card","buttonEdge","headingFont"}
local function themeTokens(T)
    local out = {}
    for _, key in ipairs(TOKENS) do out[key] = deepCopy(T[key]) end
    return out
end

local function session(db)
    local e = setmetatable({}, {__index = _G})
    local listeners = {}
    local combat = false
    e.KWCDB = db
    e.InCombatLockdown = function() return combat end
    e.KWC = {On = function(event, fn)
        listeners[event] = listeners[event] or {}
        table.insert(listeners[event], fn)
        return true
    end}
    setfenv(assert(loadfile("KeepersWarCommand/UITheme.lua")), e)()
    local pristine = themeTokens(e.KWC.UITheme)
    setfenv(assert(loadfile("KeepersWarCommand/Appearance.lua")), e)()
    local s = {env = e, K = e.KWC, A = e.KWC.Appearance, T = e.KWC.UITheme, pristine = pristine, redraws = 0}
    e.KWC.UI = {ApplyAppearance = function() s.redraws = s.redraws + 1 end}
    function s.fire(event) for _, fn in ipairs(listeners[event] or {}) do fn() end end
    function s.combat(value) combat = value end
    return s
end

-- Defaults and invalid values fall back to Trogdor without writing anything.
do
    local s = session(nil)
    assert(s.A.Get() == "Trogdor" and s.A.DEFAULT == "Trogdor")
    local ok = s.A.Set("Classic")
    assert(ok == false, "Set must refuse before SavedVariables load")
    assert(s.redraws == 0)

    local db = {settings = {windowScale = 0.9, alerts = true}}
    s = session(db)
    local before = deepCopy(db)
    s.fire("PLAYER_LOGIN")
    assert(s.A.Get() == "Trogdor" and s.A.IsTrogdor() and not s.A.IsClassic())
    assertSame(before, db, "KWCDB after default login")
    assertSame(s.pristine, themeTokens(s.T), "default Trogdor theme")

    for _, bad in ipairs({"classic", "TROGDOR", "Dark", 42, true, {}, ""}) do
        db = {settings = {uiAppearance = bad, windowScale = 0.9, autoScout = false}}
        s = session(db)
        local snapshot = deepCopy(db)
        s.fire("PLAYER_LOGIN")
        assert(s.A.Get() == "Trogdor", "invalid value " .. tostring(bad) .. " must fall back to Trogdor")
        assertSame(snapshot, db, "KWCDB with invalid appearance " .. tostring(bad))
        assertSame(s.pristine, themeTokens(s.T), "fallback theme")
    end
    for _, broken in ipairs({{}, {settings = "oops"}}) do
        s = session(broken)
        assert(s.A.Get() == "Trogdor")
    end
    assert(not s.A.Illustrated() or s.A.mediaBundled == true)
    print("PASS: missing, invalid and unloaded settings fall back to Trogdor without altering SavedVariables")
end

-- Switching both directions saves only uiAppearance and swaps theme tokens in place.
do
    local db = {settings = {windowScale = 0.9, alerts = false, autoScout = true, pitch = "Join us", nested = {a = 1}},
        ops = {{id = "c1"}}, bounties = {{id = "b1"}}}
    local s = session(db)
    s.fire("PLAYER_LOGIN")
    local goldRef, steelRef = s.T.gold, s.T.steel
    local before = deepCopy(db)

    assert(s.A.Set("Classic") == true)
    assert(db.settings.uiAppearance == "Classic" and s.A.Get() == "Classic" and s.A.IsClassic())
    assert(s.redraws == 1, "Classic switch did not redraw")
    assert(s.T.gold == goldRef and s.T.steel == steelRef, "theme tables must be updated in place")
    assertSame(deepCopy(s.A.palettes.Classic), themeTokens(s.T), "Classic theme")
    local after = deepCopy(db); after.settings.uiAppearance = nil
    assertSame(before, after, "KWCDB after Classic switch")

    assert(s.A.Set("Trogdor") == true)
    assert(db.settings.uiAppearance == "Trogdor" and s.redraws == 2)
    assertSame(s.pristine, themeTokens(s.T), "Trogdor theme after switching back")
    after = deepCopy(db); after.settings.uiAppearance = nil
    assertSame(before, after, "KWCDB after Trogdor switch")

    local ok, err = s.A.Set("Purple")
    assert(ok == false and type(err) == "string")
    assert(db.settings.uiAppearance == "Trogdor" and s.redraws == 2)

    local fresh = {}
    s = session(fresh)
    assert(s.A.Set("Classic") == true)
    assertSame({settings = {uiAppearance = "Classic"}}, fresh, "KWCDB created settings")
    print("PASS: Classic and Trogdor switch both ways, save only uiAppearance and keep unrelated settings")
end

-- Combat: the choice saves immediately and the redraw waits for PLAYER_REGEN_ENABLED.
do
    local db = {settings = {windowScale = 1.1}}
    local s = session(db)
    s.fire("PLAYER_LOGIN")
    s.combat(true)
    local ok, message = s.A.Set("Classic")
    assert(ok == true and type(message) == "string")
    assert(db.settings.uiAppearance == "Classic" and s.A.pending == true)
    assert(s.redraws == 0, "no redraw during combat")
    assertSame(s.pristine, themeTokens(s.T), "theme unchanged during combat")
    s.fire("PLAYER_REGEN_ENABLED")
    assert(s.redraws == 0 and s.A.pending == true, "still in combat")
    s.combat(false)
    s.fire("PLAYER_REGEN_ENABLED")
    assert(s.redraws == 1 and not s.A.pending)
    assertSame(deepCopy(s.A.palettes.Classic), themeTokens(s.T), "Classic theme after combat")
    s.fire("PLAYER_REGEN_ENABLED")
    assert(s.redraws == 1, "a later combat end must not redraw again")
    assert(db.settings.windowScale == 1.1)
    print("PASS: combat-time selection saves immediately and applies once combat ends")
end

-- Illustrated media is detected from the packaged manifest, never assumed.
do
    local s = session({settings = {}})
    s.fire("PLAYER_LOGIN")
    assert(s.A.mediaBundled == false and not s.A.Illustrated(), "media must be off without the manifest")
    assert(s.A.RegisterMedia(nil) == false and #s.A.missingMedia == #s.A.MEDIA_FILES)
    assert(s.A.RegisterMedia({"Wood", "Frame"}) == false, "a partial set must not enable illustrated media")
    assert(not s.A.Illustrated() and #s.A.missingMedia == #s.A.MEDIA_FILES - 2)
    setfenv(assert(loadfile("KeepersWarCommand/Media/MediaManifest.lua")), s.env)()
    assert(s.A.mediaBundled == true and #s.A.missingMedia == 0, "manifest did not enable illustrated media")
    assert(s.A.Get() == "Trogdor" and s.A.Illustrated(), "default Trogdor must draw the illustrated set")
    assert(s.A.Set("Classic") and not s.A.Illustrated(), "Classic must never draw illustrated media")
    assert(s.A.Set("Trogdor") and s.A.Illustrated())
    -- The manifest is harmless if Appearance.lua is absent.
    local bare = setmetatable({KWC = {}}, {__index = _G})
    setfenv(assert(loadfile("KeepersWarCommand/Media/MediaManifest.lua")), bare)()
    print("PASS: illustrated media turns on only from a complete packaged manifest; Classic stays distinct")
end

-- Every required Media file exists and is an uncompressed 32-bit TGA with
-- power-of-two dimensions (the client's TGA loader requirement).
do
    local function pow2(n)
        local p = 1
        while p < n and p < 1024 do p = p * 2 end
        return p == n
    end
    local s = session({})
    setfenv(assert(loadfile("KeepersWarCommand/Media/MediaManifest.lua")), s.env)()
    for _, name in ipairs(s.A.MEDIA_FILES) do
        local path = "KeepersWarCommand/Media/" .. name .. ".tga"
        local file = assert(io.open(path, "rb"), path .. " is missing")
        local h = file:read(18); file:close()
        assert(h and #h == 18, path .. ": truncated header")
        local idLen, mapType, imgType = h:byte(1), h:byte(2), h:byte(3)
        local w = h:byte(13) + h:byte(14) * 256
        local ht = h:byte(15) + h:byte(16) * 256
        local bpp = h:byte(17)
        assert(mapType == 0 and imgType == 2, path .. ": not an uncompressed true-colour TGA (type " .. imgType .. ")")
        assert(bpp == 32, path .. ": expected 32 bpp, got " .. bpp)
        assert(pow2(w) and pow2(ht), ("%s: %dx%d is not power-of-two"):format(path, w, ht))
        assert(idLen >= 0)
    end
    print(("PASS: %d illustrated Media files are uncompressed 32-bit power-of-two TGAs"):format(#s.A.MEDIA_FILES))
end

-- /reload: SavedVariables round trip restores the selection at login.
do
    for _, choice in ipairs({"Classic", "Trogdor"}) do
        local db = {settings = {windowScale = 0.75}}
        local s = session(db)
        s.fire("PLAYER_LOGIN")
        assert(s.A.Set(choice))
        local saved = deepCopy(db)
        local reloaded = session(saved)
        assertSame(reloaded.pristine, themeTokens(reloaded.T), "theme before login")
        reloaded.fire("PLAYER_LOGIN")
        assert(reloaded.A.Get() == choice)
        assertSame(deepCopy(reloaded.A.palettes[choice]), themeTokens(reloaded.T), choice .. " theme after reload")
        assert(saved.settings.windowScale == 0.75)
    end
    print("PASS: the selected appearance persists across /reload")
end

-- ------------------------------------------------------------------ Part 2
local env, frames, methods = assert(loadfile("tests/fixtures/ui_env.lua"))()
local roster = {
    {"Tester-Realm", "Officer", 1, "Player-1-0001"},
    {"Ally-Realm", "Member", 3, "Player-1-0002"},
}
env.IsInGuild = function() return true end
env.C_Club = {GetGuildClubId = function() return 4242 end}
env.GetNumGuildMembers = function() return #roster end
env.GetGuildRosterInfo = function(i)
    local r = roster[i]
    if not r then return end
    return r[1], r[2], r[3], 60, "Warrior", "Zone", "", "", true, 0, "WARRIOR", 0, 0, false, false, 0, r[4]
end
env.GetGuildInfo = function() return "Keepers of Trogdor", "Officer", 1 end
env.GetZoneText = function() return "Hillsbrad Foothills" end
local combat = false
env.InCombatLockdown = function() return combat end
local addonSends, chatSends = 0, 0
env.C_ChatInfo.SendAddonMessage = function() addonSends = addonSends + 1; return 0 end
env.C_ChatInfo.SendAddonMessageLogged = env.C_ChatInfo.SendAddonMessage
env.C_ChatInfo.SendChatMessage = function() chatSends = chatSends + 1 end
env.SendAddonMessage = env.C_ChatInfo.SendAddonMessage
env.SendChatMessage = env.C_ChatInfo.SendChatMessage
env.ChatFrame_OpenChat = function() end
env.KWCDB = {settings = {uiAppearance = "Classic", windowScale = 0.9, alerts = true, customPreference = "keep me"}}

local textures = {}
local phaseMedia = 0
local rawSetTexture = methods.SetTexture
function methods:SetTexture(value)
    if type(value) == "string" then
        textures[value] = true
        if value:match("^Interface\\AddOns\\KeepersWarCommand\\Media\\") then phaseMedia = phaseMedia + 1 end
    end
    return rawSetTexture(self, value)
end

-- TOC order: Appearance.lua loads directly after UITheme.lua.
local tocFiles = {}
for line in io.lines("KeepersWarCommand/KeepersWarCommand.toc") do
    local path = line:match("^%s*(.-)%s*$")
    if path ~= "" and path:sub(1, 1) ~= "#" then tocFiles[#tocFiles + 1] = path:gsub("\\", "/") end
end
local uiThemeAt, appearanceAt, uiAt
for i, path in ipairs(tocFiles) do
    if path == "UITheme.lua" then uiThemeAt = i end
    if path == "Appearance.lua" then appearanceAt = i end
    if path == "UI.lua" then uiAt = i end
end
assert(uiThemeAt and appearanceAt == uiThemeAt + 1, "Appearance.lua must load right after UITheme.lua")
assert(uiAt and uiAt > appearanceAt)
local private = {}
for _, path in ipairs(tocFiles) do
    local chunk = assert(loadfile("KeepersWarCommand/" .. path))
    local ok, err = xpcall(function() setfenv(chunk, env)("KeepersWarCommand", private) end, debug.traceback)
    assert(ok, path .. ": " .. tostring(err))
end
-- Core's dispatcher already isolates KWC listeners with pcall; library frames
-- (AceComm, Raid Tools) may need APIs the mock lacks, so their errors are
-- collected rather than aborting the appearance checks.
local handlerErrors = {}
local function fire(event, ...)
    for index = 1, #frames do
        local f = frames[index]
        if rawget(f, "events") and f.events[event] and f.scripts.OnEvent then
            local ok, err = pcall(f.scripts.OnEvent, f, event, ...)
            if not ok then handlerErrors[#handlerErrors + 1] = event .. ": " .. tostring(err) end
        end
    end
end
fire("ADDON_LOADED", "KeepersWarCommand")
fire("PLAYER_LOGIN")
fire("GUILD_ROSTER_UPDATE")
local K = env.KWC
local A = K.Appearance
local db = env.KWCDB
assert(A and A.Get() == "Classic", "saved Classic choice not restored at login")
assert(A.mediaBundled == true, "packaged Media/MediaManifest.lua did not enable illustrated media: "
    .. table.concat(A.missingMedia or {}, ", "))
assertSame(deepCopy(A.palettes.Classic), themeTokens(K.UITheme), "Classic theme at login")
print(("PASS: %d TOC files load with Appearance.lua after UITheme.lua"):format(#tocFiles))

-- Traffic counters: queued sends, direct sends, and chat.
local netSends = 0
if K.Net and K.Net.Send then
    local raw = K.Net.Send
    K.Net.Send = function(...) netSends = netSends + 1; return raw(...) end
end
if K.Send then
    local raw = K.Send
    K.Send = function(...) netSends = netSends + 1; return raw(...) end
end
local function traffic() return netSends + addonSends + chatSends end

-- Record the existing action handlers instead of running them.
local calls = {}
for _, name in ipairs({"DetailedCTA", "Respond", "ChangeStatus", "QuickBounty", "ClaimBounty"}) do
    K.Operations[name] = function(...) calls[#calls + 1] = {name, ...} end
end
local function lastCall() return calls[#calls] or {} end

-- Seed one Call to Arms and one bounty in the bound guild partition.
table.insert(db.ops, 1, {id = "cta1", author = "Tester-Realm", text = "[NORMAL] Hillsbrad Foothills - Hold the mill H:6 A:11",
    time = "2026-11-16 12:00", created = 1, status = "ACTIVE",
    details = {zone = "Hillsbrad Foothills", objective = "Hold the mill", horde = 6, alliance = 11, priority = "NORMAL"}})
table.insert(db.bounties, 1, {id = "b1", author = "Tester-Realm", text = "Duskwalker", time = "2026-11-16 12:00",
    created = 1, status = "ACTIVE", details = {target = "Duskwalker", reward = "2g"}})

local function visible(f)
    while f do
        if not f:IsShown() then return false end
        f = f:GetParent()
    end
    return true
end
local function control(kind, caption)
    for i = #frames, 1, -1 do
        local f = frames[i]
        if rawget(f, "kind") == kind and visible(f) then
            if f.text == caption then return f end
            for _, region in ipairs(f.regions) do
                if region.text == caption then return f end
            end
        end
    end
end
local function click(caption)
    local b = assert(control("Button", caption), "button missing: " .. caption)
    b.scripts.OnClick(b)
end
local function hasLabel(value)
    for _, f in ipairs(frames) do
        if visible(f) then
            for _, region in ipairs(f.regions) do
                if region.text == value and region:IsShown() then return true end
            end
        end
    end
end
local function edits()
    local out = {}
    for _, f in ipairs(frames) do
        if rawget(f, "kind") == "EditBox" and visible(f) then out[#out + 1] = f end
    end
    return out
end
local ui = K.UI
local function open(page) ui.Toggle(page) end
local function windowTrim()
    local window = assert(env.KeepersWarCommandFrame, "main window missing")
    for _, region in ipairs(window.regions) do
        if region.layer == "BACKGROUND" and region.sublayer == -4 then return region end
    end
    error("window trim texture missing")
end

-- Settings Center selector: switch both ways without reload, save only the preference.
open("Settings")
assert(hasLabel("UI Appearance"), "Settings Center has no UI Appearance panel")
assert(control("Button", "Classic") and control("Button", "Trogdor"))
assert(hasLabel("Feature settings") and control("Button", "Alert Settings"))
local classicSteel = K.UITheme.steel[1]
assert(windowTrim().color[1] == classicSteel, "window chrome not drawn with the Classic palette")
-- Account settings plus the guild record tables an appearance must never touch.
local function guarded()
    return deepCopy({settings = db.settings, ops = db.ops, bounties = db.bounties, responses = db.responses,
        deletions = db.deletions, boardDeleteClaims = db.boardDeleteClaims, guildRecords = db.guildRecords})
end
local beforeSwitch, sentBefore = guarded(), traffic()
click("Trogdor")
assert(A.Get() == "Trogdor" and db.settings.uiAppearance == "Trogdor")
assertSame(A.palettes.Trogdor, themeTokens(K.UITheme), "Trogdor theme after Settings switch")
assert(windowTrim().color[1] == K.UITheme.steel[1] and K.UITheme.steel[1] ~= classicSteel,
    "window chrome was not re-tinted without a reload")
assert(hasLabel("Settings Center") and control("Button", "Classic"), "Settings did not redraw")
local afterSwitch = guarded()
afterSwitch.settings.uiAppearance = "Classic"
assertSame(beforeSwitch, afterSwitch, "settings and records after switching to Trogdor")
click("Classic")
assert(A.Get() == "Classic" and windowTrim().color[1] == classicSteel)
assertSame(beforeSwitch, guarded(), "settings and records after switching back to Classic")
assert(db.settings.customPreference == "keep me" and db.settings.windowScale == 0.9)
assert(traffic() == sentBefore, "appearance switching sent addon or chat traffic")
print("PASS: Settings selector switches both ways live, saves only uiAppearance and sends nothing")

-- Settings search finds the selector and routes to it.
open("Settings")
click("Search Settings")
local search = assert(edits()[1], "settings search field missing")
for _, term in ipairs({"appearance", "theme", "trogdor", "classic"}) do
    search:SetText(term)
    search.scripts.OnTextChanged(search)
    assert(control("Button", "UI Appearance"), "search term '" .. term .. "' did not find UI Appearance")
end
click("UI Appearance")
assert(control("Button", "Classic") and control("Button", "Trogdor") and hasLabel("Settings Center"))
assert(traffic() == sentBefore)
print("PASS: Settings search lists UI Appearance and opens the selector")

-- Combat-safe switching from the Settings Center.
open("Settings")
local framesBefore = #frames
combat = true
click("Trogdor")
assert(db.settings.uiAppearance == "Trogdor" and A.pending, "combat choice not saved")
assertSame(deepCopy(A.palettes.Classic), themeTokens(K.UITheme), "theme changed during combat")
assert(windowTrim().color[1] == classicSteel, "window re-tinted during combat")
assert(#frames == framesBefore, "window redrew during combat")
combat = false
fire("PLAYER_REGEN_ENABLED")
assert(not A.pending and A.Get() == "Trogdor")
assert(windowTrim().color[1] == K.UITheme.steel[1] and #frames > framesBefore, "deferred appearance not applied after combat")
assert(traffic() == sentBefore)
print("PASS: switching in combat saves now and redraws after combat")

-- Existing CTA and bounty actions reach the same handlers in both appearances.
for _, choice in ipairs({"Classic", "Trogdor"}) do
    assert(A.Set(choice))
    open("CTA Entry")
    local e = edits()
    assert(#e >= 5, choice .. ": CTA form fields missing")
    e[5]:SetText(choice .. " objective")
    click("POST CALL TO ARMS")
    assert(lastCall()[1] == "DetailedCTA" and lastCall()[2] == "Hillsbrad Foothills" and lastCall()[3] == choice .. " objective",
        choice .. ": post did not reach DetailedCTA")
    open("CTA Board")
    click("View Details")
    click("Coming")
    assert(lastCall()[1] == "Respond" and lastCall()[2] == "cta1" and lastCall()[3] == "Coming", choice .. ": Respond")
    click("Resolve")
    assert(lastCall()[1] == "ChangeStatus" and lastCall()[2] == "CTA" and lastCall()[3] == "cta1" and lastCall()[4] == "RESOLVED",
        choice .. ": Resolve")
    open("Bounty Entry")
    e = edits()
    assert(#e >= 3, choice .. ": bounty form fields missing")
    e[1]:SetText("Duskwalker"); e[2]:SetText("Camps the flight master"); e[3]:SetText("2g")
    click("POST BOUNTY")
    assert(lastCall()[1] == "QuickBounty" and lastCall()[2] == "Duskwalker" and lastCall()[4] == "2g", choice .. ": QuickBounty")
    open("Bounty Board")
    click("View Details")
    click("Claim Kill")
    assert(lastCall()[1] == "ClaimBounty" and lastCall()[2] == "b1", choice .. ": ClaimBounty")
    click("Complete")
    assert(lastCall()[1] == "ChangeStatus" and lastCall()[2] == "BOUNTY" and lastCall()[3] == "b1" and lastCall()[4] == "COMPLETED",
        choice .. ": Complete")
end
print("PASS: Call to Arms and bounty actions reach the existing handlers with the same record IDs in both appearances")

-- Navigation and page layouts: identical controls and positions in both appearances,
-- and the appearance adds no traffic to any page.
local pages = {"Home", "War Room", "CTA Board", "CTA Entry", "CTA Attendance", "Bounty Board", "Bounty Entry",
    "PvP Leaderboard", "Death Leaderboard", "Raid Tools", "Raid Tools: Command", "Raid Tools: Sign-Ups",
    "Recruitment", "Looking for Group", "Guild Services", "Guild Records", "Guild Roster", "Addon Checker",
    "Settings", "Settings Search", "Alerts", "Sync Health", "Chronicle", "Scout Network", "World PvP Deaths"}
local function layout()
    local rows = {}
    for _, f in ipairs(frames) do
        if (rawget(f, "kind") == "Button" or rawget(f, "kind") == "EditBox") and visible(f) then
            local caption = f.text
            if not caption then
                for _, region in ipairs(f.regions) do if region.kind == "FontString" and region.text then caption = region.text; break end end
            end
            rows[#rows + 1] = table.concat({f.kind, tostring(caption), tostring(rawget(f, "anchorX")), tostring(rawget(f, "anchorY"))}, "|")
        end
    end
    table.sort(rows)
    return rows
end
-- Visible illustrated Media textures (and which files) in the open window.
local function shownMedia()
    local count, names = 0, {}
    for _, f in ipairs(frames) do
        if visible(f) then
            for _, region in ipairs(f.regions) do
                local name = type(region.texture) == "string" and region.texture:match("\\Media\\([%w]+)%.tga$")
                if name and region:IsShown() then count = count + 1; names[name] = true end
            end
        end
    end
    return count, names
end
local results, media = {}, {}
for _, choice in ipairs({"Trogdor", "Classic"}) do
    assert(A.Set(choice))
    results[choice] = {}
    media[choice] = {pages = {}}
    for _, page in ipairs(pages) do
        local sent = traffic()
        local ok, err = pcall(open, page)
        results[choice][page] = {ok = ok, err = err, traffic = traffic() - sent, layout = ok and layout() or nil}
        if ok then media[choice].pages[page] = shownMedia() end
    end
    open("CTA Board")
    media[choice].count, media[choice].names = shownMedia()
end
-- Trogdor draws the illustrated chrome, nav banners, button plates and cards;
-- Classic shows none of it.
assert(A.Illustrated() == false and A.Get() == "Classic")
for _, name in ipairs({"Wood", "HeaderArtVeil", "Slate", "TitleBanner", "WarRoomScene", "Spikes", "Frame", "Banner", "BannerSelected", "Card"}) do
    assert(media.Trogdor.names[name], "illustrated Trogdor did not show Media/" .. name .. ".tga")
end
assert(media.Classic.count == 0, "Classic shows illustrated Media textures")
for _, page in ipairs({"Home", "CTA Board", "Bounty Board", "Settings", "PvP Leaderboard"}) do
    assert((media.Trogdor.pages[page] or 0) > 0, "Trogdor " .. page .. " is not illustrated")
    assert((media.Classic.pages[page] or 0) == 0, "Classic " .. page .. " shows illustrated media")
end
print(("PASS: illustrated Trogdor shows %d Media textures on the CTA Board; Classic shows none"):format(media.Trogdor.count))
local core = {Home = true, ["CTA Board"] = true, ["Bounty Board"] = true, Settings = true, ["War Room"] = true, ["PvP Leaderboard"] = true}
for _, page in ipairs(pages) do
    local t, c = results.Trogdor[page], results.Classic[page]
    if core[page] then assert(t.ok, "Trogdor " .. page .. ": " .. tostring(t.err)) end
    assert(t.ok == c.ok, page .. " opens in one appearance only: " .. tostring(t.err or c.err))
    assert(t.traffic == c.traffic, page .. ": the appearance changed addon or chat traffic")
    if t.ok then assertSame(t.layout, c.layout, page .. " layout") end
end
for _, caption in ipairs({"Command Center", "War Room", "Calls to Arms", "Bounty Board", "PvP Leaderboard",
    "Death Leaderboard", "Raid Operations", "Recruitment", "Looking for Group", "Guild Services", "Guild Records",
    "Guild Roster", "Addon Checker", "Settings Center", "Alert Command Center"}) do
    assert(control("Button", caption), "sidebar entry missing: " .. caption)
end
print(("PASS: %d pages keep the same controls, positions and traffic in Classic and Trogdor; sidebar navigation intact"):format(#pages))

-- Texture references: every KWC path requested exists; Media only when bundled.
local missing, mediaUsed = {}, 0
for path in pairs(textures) do
    local rel = path:match("^Interface\\AddOns\\KeepersWarCommand\\(.+)$")
    if rel and (rel:match("^Textures\\") or rel:match("^Media\\")) then
        if rel:match("^Media\\") then mediaUsed = mediaUsed + 1 end
        local file = io.open("KeepersWarCommand/" .. rel:gsub("\\", "/"), "rb")
        if file then file:close() else missing[#missing + 1] = path end
    end
end
table.sort(missing)
assert(#missing == 0, "missing textures:\n" .. table.concat(missing, "\n"))
if A.mediaBundled then
    for _, name in ipairs(A.MEDIA_FILES) do
        local file = io.open("KeepersWarCommand/Media/" .. name .. ".tga", "rb")
        assert(file, "mediaBundled is true but Media/" .. name .. ".tga is missing")
        file:close()
    end
else
    assert(mediaUsed == 0, "illustrated Media textures requested while mediaBundled is false")
end
local n = 0; for _ in pairs(textures) do n = n + 1 end
print(("PASS: %d texture paths requested across both appearances exist (illustrated media bundled: %s)"):format(n, tostring(A.mediaBundled)))

-- V4.2 UI: Death Leaderboard tabs and default, the honest personal ledger line,
-- clean table rows in the illustrated look, and text shadows in every look.
do
    local shadows = 0
    methods.SetShadowColor = function(self, ...) self.shadow = {...}; shadows = shadows + 1 end
    local realRankings = K.GuildRecords.DeathRankings
    K.GuildRecords.DeathRankings = function(view)
        return {{name = "Alpha", value = 9}, {name = "Bravo", value = 5}, {name = "Charlie", value = 2}}
    end
    local function textStartingWith(prefix)
        for _, f in ipairs(frames) do
            if visible(f) then
                for _, region in ipairs(f.regions) do
                    if type(region.text) == "string" and region.text:sub(1, #prefix) == prefix and region:IsShown() then return region.text end
                end
            end
        end
    end
    local function colorCount(r, g, b, a)
        local n = 0
        for _, f in ipairs(frames) do
            if visible(f) then
                for _, region in ipairs(f.regions) do
                    local c = rawget(region, "color")
                    if c and math.abs(c[1] - r) < 1e-6 and math.abs(c[2] - g) < 1e-6 and math.abs(c[3] - b) < 1e-6
                        and math.abs((c[4] or 1) - a) < 1e-6 and region:IsShown() then n = n + 1 end
                end
            end
        end
        return n
    end
    for _, choice in ipairs({"Trogdor", "Classic"}) do
        assert(A.Set(choice) == true or A.Get() == choice)
        shadows = 0
        open("Death Leaderboard")
        local tabs = {"Open World Deaths", "Lifetime (no BGs)", "Battlegrounds", "Total Deaths", "Deaths to Players", "World PvP Estimate"}
        local lastX
        for _, caption in ipairs(tabs) do
            local b = assert(control("Button", caption), choice .. ": Death Leaderboard tab missing: " .. caption)
            local x = rawget(b, "anchorX")
            if lastX and x then assert(x > lastX, choice .. ": tab order changed at " .. caption) end
            lastX = x or lastX
        end
        -- Default: Open World Deaths from the Death Ledger, never lifetime statistics.
        assert(textStartingWith("Deaths outside battlegrounds, dungeons and raids"), choice .. ": Open World Deaths is the default view")
        assert(not hasLabel("Lifetime deaths from WoW Statistics."), choice .. ": Total Deaths is not the default")
        assert(not hasLabel("Alpha") and not hasLabel("9"), choice .. ": lifetime statistics never appear on the Open World board")
        assert(hasLabel("Tester") and hasLabel("Ally") and hasLabel("Untracked"), choice .. ": guild members without verified data show as Untracked")
        assert(not hasLabel("0"), choice .. ": untracked members are not shown as zero")
        -- The existing statistics tabs still work, then return to the default board.
        click("Total Deaths")
        assert(hasLabel("Lifetime deaths from WoW Statistics.") and hasLabel("Alpha") and hasLabel("9"), choice .. ": Total Deaths tab preserved")
        if A.Illustrated() then
            assert(colorCount(0.125, 0.092, 0.07, 0.88) == 2, "illustrated odd table rows use the flat row fill")
            assert(colorCount(0.11, 0.075, 0.055, 0.95) >= 1, "illustrated table header uses the flat header fill")
        end
        click("Open World Deaths")
        assert(hasLabel("Untracked"), choice .. ": Open World Deaths tab reselects")
        local mine = textStartingWith("Your open-world deaths")
        assert(mine and not mine:lower():find("guild", 1, true), choice .. ": personal ledger line must not claim a guild ranking")
        local wantLine, wantNote = K.DeathLedger.Display()
        assert(mine == wantLine, choice .. ": personal ledger line comes from the Death Ledger")
        assert(hasLabel(wantNote), choice .. ": personal ledger scope note must be visible")
        assert(control("Button", "Guild Records"), choice .. ": existing Guild Records button preserved")
        assert(shadows > 0, choice .. ": labels are drawn with a text shadow")
    end
    -- Once the character is confirmed alive, the line shows the saved count and start date.
    local realDead, realGUID = env.UnitIsDeadOrGhost, env.UnitGUID
    env.UnitIsDeadOrGhost = function() return false end
    env.UnitGUID = function() return "Player-1-0001" end
    fire("PLAYER_ENTERING_WORLD")
    open("Death Leaderboard")
    local saved = textStartingWith("Your open-world deaths since ")
    assert(saved and saved:match(": 0$"), "confirmed-alive character shows its saved count and start date")
    local _, savedNote = K.DeathLedger.Display()
    assert(savedNote:find("Saved for this character", 1, true) and hasLabel(savedNote), "saved ledger scope note is visible")
    assert(savedNote:find(K.OpenWorldDeathSync.Sharing() and "Shared with your guild" or "Not shared", 1, true),
        "the note matches the Share My Records setting")
    assert(K.GuildRecords.SetSharing ~= nil and K.OpenWorldDeathSync.PREFIX == "KWCOW1" and K.DeathLedgerSync.PREFIX == "KWCOW2", "V4.9: open-world (KWCOW1) and lifetime (KWCOW2) sync both loaded")
    assert(type(db.deathLedger) == "table" and db.deathLedger.characters["Player-1-0001"].openWorld == 0,
        "the record is created in KWCDB.deathLedger with no seeded deaths")
    local ranked = K.DeathLedger.GuildRankings()
    assert(ranked[1].name == "Tester-Realm" and ranked[1].tracked and ranked[1].value == 0, "this character ranks first with a tracked 0")
    assert(ranked[2].name == "Ally-Realm" and not ranked[2].tracked, "guildmate without shared data stays Untracked")
    assert(hasLabel("0") and hasLabel("Untracked"), "board shows the tracked 0 and the Untracked guildmate")
    env.UnitIsDeadOrGhost, env.UnitGUID = realDead, realGUID
    -- Plain Trogdor (no illustrated media): previously drew text with no shadow.
    assert(A.Set("Trogdor") == true or A.Get() == "Trogdor")
    local bundled = A.mediaBundled
    A.mediaBundled = false
    shadows = 0
    open("Death Leaderboard")
    assert(not A.Illustrated() and shadows > 0, "plain Trogdor labels are drawn with a text shadow")
    A.mediaBundled = bundled
    K.GuildRecords.DeathRankings = realRankings
    methods.SetShadowColor = nil
    assert(A.Set("Trogdor") == true or A.Get() == "Trogdor")
    for _, caption in ipairs({"Command Center", "War Room", "Calls to Arms", "Bounty Board", "PvP Leaderboard",
        "Death Leaderboard", "Raid Operations", "Recruitment", "Guild Records", "Settings Center"}) do
        assert(control("Button", caption), "sidebar entry missing after V4.2 checks: " .. caption)
    end
    print("PASS: Death Leaderboard opens on Open World Deaths from the ledger; Untracked guildmates; statistics tabs preserved; flat rows; shadowed text")
end

-- V4.8: Alert Command Center configures Guild PvP Kill with the death controls.
for _, look in ipairs({"Classic", "Trogdor"}) do
    assert(K.Appearance.Set(look))
    open("Alerts")
    click("Configure Kill")
    assert(hasLabel("Guild PvP Kill settings"), look .. ": kill settings panel")
    local s = env.KWCDB.settings
    s.pvpKillAlerts, s.pvpKillBroadcast, s.pvpKillSmart = nil, nil, nil
    click("Show popup: ON");assert(s.pvpKillAlerts == false, "popup toggle")
    click("Show popup: OFF");assert(s.pvpKillAlerts == true)
    click("Guild broadcast: ON");assert(s.pvpKillBroadcast == false, "broadcast toggle")
    click("Guild broadcast: OFF");assert(s.pvpKillBroadcast == true)
    click("Smart Mode: ON");assert(s.pvpKillSmart == false, "smart toggle")
    click("Time +");assert(s.pvpKillDuration == 9, "duration stepper")
    click("Size +");assert(math.abs((s.pvpKillScale or 1) - 1.1) < 1e-6, "size stepper")
    assert(s.worldPvPDeathAlerts == nil and s.worldPvPDeathBroadcast == nil, "death settings untouched")
    s.pvpKillDuration, s.pvpKillScale = nil, nil
    open("Alerts")
end
print("PASS: Alert Command Center configures Guild PvP Kill in both appearances without touching death settings")
