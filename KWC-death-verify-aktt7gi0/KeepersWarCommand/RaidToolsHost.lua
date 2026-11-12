-- DEV34: Native KWC raid tools view; no separate KRT window.
local K=KWC
local R=K.RaidTools
function R.Mount(parent,tab)
 if InCombatLockdown and InCombatLockdown() then
  K.Say('Raid tools configuration is unavailable during combat.')
  return false
 end
 local impl=KeepersRaidTools
 if not impl or not impl.MountInWarCommand then return false end
 return impl:MountInWarCommand(parent,tab)
end
function R.Close()
 local impl=KeepersRaidTools
 if impl and impl.UnmountFromWarCommand then impl:UnmountFromWarCommand() end
 local f=KeepersRaidToolsConfigFrame
 if f then f:Hide() end
end
function R.Open(tab)
 if K.UI and K.UI.Toggle then K.UI.Toggle('Raid Tools: '..tostring(tab or 'Attendance')) end
end
