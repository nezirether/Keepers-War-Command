KeepersRaidTools = KeepersRaidTools or {}
local KRT = KeepersRaidTools

KeepersRaidToolsDB = KeepersRaidToolsDB or {}

KRT.defaults = {}

KRT.applyCallbacks = {}

KRT.modules = {}
KRT.modulesByName = {}

function KRT:RegisterModule(name, moduleTable)
    moduleTable.eventFrame = CreateFrame("Frame")
    moduleTable.active = false
    table.insert(self.modules, { name = name, module = moduleTable })
    self.modulesByName[name] = moduleTable
end

function KRT:RegisterApplyCallback(name, callback)
    self.applyCallbacks[name] = callback
end

function KRT:ApplySettings(settingName)
    if settingName then
        local callback = self.applyCallbacks[settingName]
        if callback then callback() end
    else
        for _, callback in pairs(self.applyCallbacks) do
            callback()
        end
    end
    self:EvaluateAllModules()
end

function KRT:EvaluateModule(entry)
    local name = entry.name
    local module = entry.module

    -- Modules without OnEnable/OnDisable are "always on" after Initialize
    if not module.OnEnable and not module.OnDisable then
        return
    end

    local enabled
    if module.GetEnabledSetting then
        enabled = module:GetEnabledSetting()
    else
        local settings = self:GetSetting(name)
        enabled = settings and (settings.enabled ~= false)
    end

    local activatable = enabled
    if activatable and module.IsActivatable then
        activatable = module:IsActivatable()
    end

    if activatable and not module.active then
        module.active = true
        if module.OnEnable then
            module:OnEnable()
        end
    elseif not activatable and module.active then
        if module.OnDisable then
            module:OnDisable()
        end
        module.active = false
    end
end

function KRT:EvaluateAllModules()
    for _, entry in ipairs(self.modules) do
        self:EvaluateModule(entry)
    end
end

local function DeepCopy(source)
    if type(source) ~= "table" then return source end
    local copy = {}
    for k, v in pairs(source) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

-- Deep merge defaults into target (missing keys are deep-copied; existing values win)
local function DeepMerge(defaults, target)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = DeepCopy(v)
        elseif type(v) == "table" and type(target[k]) == "table" then
            DeepMerge(v, target[k])
        end
    end
end

function KRT:GetSetting(key)
    local settings = KeepersRaidToolsDB.settings
    if settings and settings[key] ~= nil then
        return settings[key]
    end
    return self.defaults[key]
end

function KRT:InitializeDB()
    local db = KeepersRaidToolsDB
    if type(db.settings) ~= "table" then
        local profiles = type(db.profiles) == "table" and db.profiles or {}
        local legacy = profiles[db.currentProfile or "Default"]
        if type(legacy) ~= "table" then legacy = profiles.Default end
        -- Leave legacy profiles intact for rollback and copy only the selected configuration.
        db.settings = type(legacy) == "table" and DeepCopy(legacy) or {}
    end
    DeepMerge(self.defaults, db.settings)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == "KeepersWarCommand" then
        KRT:InitializeDB()
        for _, entry in ipairs(KRT.modules) do
            if entry.module.Initialize then
                entry.module:Initialize()
            end
        end
        eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        KRT:EvaluateAllModules()
        eventFrame:UnregisterEvent("ADDON_LOADED")
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD"
        or event == "ZONE_CHANGED_NEW_AREA" then
        KRT:EvaluateAllModules()
    end
end)

-- Forever 1.6.x uses Classic instance types. Keep legacy SavedVariables paths
-- (dungeon.normal and raid.normal) to avoid losing user preferences.
function KRT.GetCurrentContentType()
    local _, instanceType = GetInstanceInfo()
    if instanceType == "party" then return "dungeon", "normal" end
    if instanceType == "raid" then return "raid", "normal" end
    if instanceType == "none" or not instanceType or instanceType == "pvp" or instanceType == "arena" then
        return "openWorld", nil
    end
    return nil, nil
end

function KRT.IsContentTypeEnabled(contentTypes)
    if not contentTypes then return false end
    local contentType, subType = KRT.GetCurrentContentType()
    if not contentType then return false end
    if contentType == "openWorld" then return contentTypes.openWorld == true end
    local settings = contentTypes[contentType]
    return type(settings) == "table" and settings[subType] == true
end

function KRT:IterateGroup()
    if IsInRaid() then
        local count = GetNumGroupMembers()
        local i = 0
        return function()
            i = i + 1
            if i <= count then
                return "raid" .. i
            end
        end
    elseif IsInGroup() then
        local count = GetNumGroupMembers() - 1
        local i = 0
        local sentPlayer = false
        return function()
            i = i + 1
            if i <= count then
                return "party" .. i
            elseif not sentPlayer then
                sentPlayer = true
                return "player"
            end
        end
    else
        local done = false
        return function()
            if not done then
                done = true
                return "player"
            end
        end
    end
end

-- Slash commands are routed by Keepers War Command (/kt).
