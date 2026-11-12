local K=KWC;local C={};K.Companions=C
local function loaded(name)
 if C_AddOns and C_AddOns.IsAddOnLoaded then
  local ok,v=pcall(C_AddOns.IsAddOnLoaded,name);if ok then return v==true end
 end
 return IsAddOnLoaded and IsAddOnLoaded(name)==true or false
end
function C.Overlord() return loaded('Overlord') end
function C.WarEffort() return loaded('WarEffortScout') end
local function field(t,k) if type(t)=='table' then return rawget(t,k) end end
-- Read-only snapshot of the Overlord 2.5.0 objective registry. No network
-- messages, protected actions, or modifications to Overlord's own data.
function C.OverlordSnapshot()
 if not C.Overlord() then return nil,'Not installed or disabled' end
 local o=rawget(_G,'Overlord')
 local fronts=field(field(o,'Fronts'),'Registry')
 if type(fronts)~='table' then return nil,'Objective registry unavailable (version mismatch)' end
 local result={fronts=0,objectives=0,contested=0,heldHorde=0,heldAlliance=0,zones={}}
 local safe=0
 for _,front in pairs(fronts) do
  safe=safe+1;if safe>30 then break end
  if type(front)=='table' then
   result.fronts=result.fronts+1
   local zones=field(front,'zones')
   if type(zones)=='table' then
    for _,zone in ipairs(zones) do
     if type(zone)=='table' and result.objectives<200 then
      result.objectives=result.objectives+1
      local status=field(zone,'status');local owner=field(zone,'owner')
      if status=='in_progress' then result.contested=result.contested+1 end
      if owner=='Horde' then result.heldHorde=result.heldHorde+1 end
      if owner=='Alliance' then result.heldAlliance=result.heldAlliance+1 end
      local name=field(zone,'name')
      if type(name)=='string' and name~='' and #result.zones<12 then
       result.zones[#result.zones+1]={name=name,status=type(status)=='string' and status or 'unknown',owner=type(owner)=='string' and owner or 'unclaimed'}
      end
     end
    end
   end
  end
 end
 if result.objectives==0 then return nil,'No readable objectives (version mismatch)' end
 return result
end
-- War Effort 1.6.6 uses a private addon namespace. Its cluster engine and
-- reporting functions are not exposed as a public API; do not scrape its
-- saved variables or impersonate its network packets.
function C.WarEffortStatus()
 if not C.WarEffort() then return 'Not installed or disabled' end
 return 'Loaded - use its native scout/map UI; automatic data import unavailable'
end
function C.Report()
 local snapshot,err=C.OverlordSnapshot()
 K.Say('Overlord: '..(snapshot and (snapshot.objectives..' objectives, '..snapshot.contested..' contested') or err))
 K.Say('War Effort: '..C.WarEffortStatus())
end
function C.OpenOverlord()
 if not C.Overlord() then K.Say('Overlord is not loaded.');return end
 if ChatFrame_OpenChat then ChatFrame_OpenChat('/ov show') end
end
function C.OpenWarEffort()
 if not C.WarEffort() then K.Say('War Effort is not loaded.');return end
 if ChatFrame_OpenChat then ChatFrame_OpenChat('/we') end
end
