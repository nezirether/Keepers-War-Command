-- DEV31 unified integration bridge. KRT v0.1.7 modules are native files inside KWC.
-- Retain KRT internal API and database globals as compatibility aliases.
-- Legacy saved variable globals, when present, are copied once to KWCDB.raidTools.
local K=KWC
K.RaidTools=K.RaidTools or {}
local function copy(t)
 if type(t)~='table' then return {} end
 local result={}
 for k,v in pairs(t) do result[k]=(type(v)=='table') and copy(v) or v end
 return result
end
local function attach()
 if type(KWCDB)~='table' then return end
 KWCDB.raidTools=KWCDB.raidTools or {}
 local db=KWCDB.raidTools
 local legacy={
  main='KeepersRaidToolsDB',attendance='KeepersRaidToolsAttendanceDB',
  roster='KeepersRaidToolsRosterDB',notes='KRTForeverNotesDB'
 }
 for field,global in pairs(legacy) do
  if type(db[field])~='table' then
   local old=_G[global]
   db[field]=type(old)=='table' and copy(old) or {}
  end
  _G[global]=db[field]
 end
end
-- KWC.Init runs on ADDON_LOADED, but KRT module code needs tables at file-load time.
KWCDB=KWCDB or {}
attach()
K.RaidTools.Attach=attach
-- Expose a single KWC-owned module handle for integration and later refactoring.
K.RaidTools.Get=function()return KeepersRaidTools end
