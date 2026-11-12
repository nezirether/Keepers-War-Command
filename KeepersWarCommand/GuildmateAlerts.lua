-- Local passive guildmate spotting, based only on visible unit tokens.
local K=KWC
local A={};K.GuildmateAlerts=A
local seen={}
local frame=CreateFrame('Frame','KWC_GuildmateAlertBanner',UIParent)
frame:SetSize(370,80);frame:SetPoint('TOP',UIParent,'TOP',0,-235)
frame:SetFrameStrata('DIALOG');frame:Hide()
local bg=frame:CreateTexture(nil,'BACKGROUND');bg:SetAllPoints();bg:SetColorTexture(0.04,0.19,0.12,0.94)
local heading=frame:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');heading:SetPoint('TOP',0,-12);heading:SetText('GUILDMATE NEARBY')
local detail=frame:CreateFontString(nil,'OVERLAY','GameFontHighlight');detail:SetPoint('CENTER',0,-8);detail:SetWidth(340)
local close=CreateFrame('Button',nil,frame,'UIPanelCloseButton');close:SetPoint('TOPRIGHT',0,0)
local elapsed=0
frame:SetScript('OnUpdate',function(self,dt) elapsed=elapsed+dt;if elapsed>=5 then self:Hide() end end)
local function norm(name)
 if type(name)~='string' then return '' end
 return name:lower():match('^%s*([^%-]+)') or ''
end
-- Ignore guildmates who are already in the player's party or raid.
-- Use both direct group APIs and unit-token comparison for client compatibility.
local function isGroupedWith(unit, name)
 if UnitInParty then
  local ok, member=pcall(UnitInParty,unit)
  if ok and member then return true end
 end
 if UnitInRaid then
  local ok, member=pcall(UnitInRaid,unit)
  if ok and member then return true end
 end
 local key=norm(name)
 local function sameGroupUnit(groupUnit)
  if not UnitExists(groupUnit) then return false end
  if UnitIsUnit and UnitIsUnit(groupUnit,unit) then return true end
  local groupName=UnitName(groupUnit)
  return key~='' and norm(groupName)==key
 end
 for i=1,4 do if sameGroupUnit('party'..i) then return true end end
 for i=1,40 do if sameGroupUnit('raid'..i) then return true end end
 return false
end
local function check(unit)
 if not KWCDB or not KWCDB.settings or KWCDB.settings.guildmateAlerts==false then return end
 if not IsInGuild() or not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
 if UnitIsUnit and UnitIsUnit('player',unit) then return end
 if UnitCanAttack and UnitCanAttack('player',unit) then return end
 local name=UnitName(unit);local key=norm(name)
 if isGroupedWith(unit,name) then return end
 if key=='' then return end
 local roster=KWCDB.roster or {}
 local entry=roster[key]
 if not entry then
  -- Realm suffixes are permitted only when they identify a known roster entry.
  for id,r in pairs(roster) do
   if type(id)=='string' and id:match('^[^-]+')==key then entry=r;break end
  end
 end
 if not entry then
  -- Guild roster may not have been delivered yet; request refresh and retry later.
  if K.Roster and K.Roster.Scan then K.Roster.Scan() end
  entry=(KWCDB.roster or {})[key]
  if not entry then return end
 end
 local now=time();if now-(seen[key] or 0)<120 then return end
 seen[key]=now
 heading:SetText('GUILDMATE NEARBY')
 detail:SetText(name..(entry.class and ('  |  '..tostring(entry.class)) or ''))
 elapsed=0;frame:Show()
 K.Say('Guildmate nearby: '..name..' ('..tostring(GetRealZoneText and GetRealZoneText() or 'unknown zone')..').')
 if PlaySound and (not K.QOL or (K.QOL.Enabled('guildmateSound') and K.QOL.Enabled('alertSound'))) then pcall(PlaySound,8959,'Master') end
end
K.On('NAME_PLATE_UNIT_ADDED',function(unit) if type(unit)=='string' then check(unit) end end)
K.On('PLAYER_TARGET_CHANGED',function() check('target') end)
K.On('UPDATE_MOUSEOVER_UNIT',function() check('mouseover') end)
function A.SetEnabled(enabled)
 if not KWCDB then return end
 KWCDB.settings.guildmateAlerts=enabled and true or false
 if enabled then wipe(seen) end
 K.Say('Guildmate nearby alerts '..(enabled and 'ON' or 'OFF')..'.')
end
function A.Status() return not KWCDB or not KWCDB.settings or KWCDB.settings.guildmateAlerts~=false end

function A.Demo() heading:SetText('GUILDMATE ALERT TEST');detail:SetText('Display and sound test (no player detected)');elapsed=0;frame:Show();if PlaySound then pcall(PlaySound,8959,'Master') end end

-- Some client builds do not consistently fire nameplate events for already-visible units.
-- Scan only exposed units, never perform automated targeting or hidden-player discovery.
local poll=CreateFrame('Frame')
local pollElapsed=0
poll:SetScript('OnUpdate',function(_,dt)
 pollElapsed=pollElapsed+dt
 if pollElapsed<1.5 then return end
 pollElapsed=0
 if not KWCDB or not KWCDB.settings then return end
 check('target');check('mouseover')
 if C_NamePlate and C_NamePlate.GetNamePlates then
  local ok,plates=pcall(C_NamePlate.GetNamePlates)
  if ok and type(plates)=='table' then
   for _,plate in ipairs(plates) do
    local unit=plate and (plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
    if type(unit)=='string' then check(unit) end
   end
  end
 end
end)
