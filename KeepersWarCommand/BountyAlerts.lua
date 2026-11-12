-- Local, passive target/mouseover bounty notifications. No automated targeting or chat.
local K=KWC
local A={};K.BountyAlerts=A
local seen={}
local banner=CreateFrame('Frame','KWC_BountyAlertBanner',UIParent)
banner:SetSize(370,90);banner:SetPoint('TOP',UIParent,'TOP',0,-135)
banner:SetFrameStrata('DIALOG');banner:Hide()
local bg=banner:CreateTexture(nil,'BACKGROUND');bg:SetAllPoints();bg:SetColorTexture(0.16,0.04,0.04,0.94)
local title=banner:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');title:SetPoint('TOP',0,-12);title:SetText('BOUNTY TARGET SPOTTED')
local detail=banner:CreateFontString(nil,'OVERLAY','GameFontHighlight');detail:SetPoint('CENTER',0,-5);detail:SetWidth(340)
local close=CreateFrame('Button',nil,banner,'UIPanelCloseButton');close:SetPoint('TOPRIGHT',0,0)
local elapsed=0
banner:SetScript('OnUpdate',function(self,dt) elapsed=elapsed+dt;if elapsed>=7 then self:Hide() end end)
local function normalized(name)
 if type(name)~='string' then return '' end
 return (name:lower():match('^%s*(.-)%s*$') or ''):match('^([^%-]+)') or ''
end
-- Match the actual character name against either a bare target name or
-- a display name containing a surname/title (e.g. "Cliveanna Vine").
-- Do not use substring matching: "Ann" must not match "Anna".
local function bountyMatches(target, playerName)
 local player=normalized(playerName)
 local stored=normalized(target)
 if player=='' or stored=='' then return false end
 if stored==player then return true end
 -- Only treat a space-separated suffix as a display surname/title.
 -- A hyphen remains reserved for the optional realm suffix above.
 return stored:match('^([^%s]+)%s+')==player
end
local function check(unit)
 if not KWCDB or not KWCDB.settings or KWCDB.settings.bountyAlerts==false then return end
 if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
 local enemy=UnitCanAttack and UnitCanAttack('player',unit)
 local friendlyTest=KWCDB.settings.bountyAlertTest==true
 if not enemy and not friendlyTest then return end
 local name=UnitName(unit);local key=normalized(name);if key=='' then return end
 for _,b in ipairs(KWCDB.bounties or {}) do
  if (b.status or 'ACTIVE')=='ACTIVE' then
   local target=b.details and b.details.target
   -- Legacy bounties only have free-form text; do not guess a target from that text.
   if bountyMatches(target,name) then
    local now=time();if now-(seen[key] or 0)<90 then return end;seen[key]=now
    local reward=b.details and b.details.reward or ''
    title:SetText(enemy and 'BOUNTY TARGET SPOTTED' or 'TEST MODE - FRIENDLY BOUNTY')
    detail:SetText(name..(reward~='' and ('  |  Reward: '..tostring(reward)) or ''))
    elapsed=0;banner:Show()
    K.Say((enemy and 'BOUNTY SPOTTED: ' or 'TEST FRIENDLY BOUNTY: ')..name..' in '..tostring(GetRealZoneText and GetRealZoneText() or 'unknown zone')..'. Open Bounty Board to record a sighting.')
    if PlaySound and (not K.QOL or (K.QOL.Enabled('bountySound') and K.QOL.Enabled('alertSound'))) then pcall(PlaySound,8959,'Master') end
    return
   end
  end
 end
end
K.On('PLAYER_TARGET_CHANGED',function() check('target') end)
K.On('UPDATE_MOUSEOVER_UNIT',function() check('mouseover') end)
-- Detect enemy player nameplates as they become visible to the client.
-- Only the event-provided unit token is inspected; no automated targeting.
K.On('NAME_PLATE_UNIT_ADDED',function(unitToken)
 if type(unitToken)=='string' then check(unitToken) end
end)
function A.SetEnabled(enabled)
 if not KWCDB then return end
 KWCDB.settings.bountyAlerts=enabled and true or false
 K.Say('Bounty spotting alerts '..(enabled and 'enabled' or 'disabled')..'.')
 if enabled then wipe(seen);check('target') end
end
function A.Status() return not KWCDB or not KWCDB.settings or KWCDB.settings.bountyAlerts~=false end

function A.SetTestMode(enabled)
 if not KWCDB then return end
 KWCDB.settings.bountyAlertTest=enabled and true or false
 wipe(seen)
 K.Say('Friendly bounty detection TEST MODE '..(enabled and 'ON (Horde + Alliance)' or 'OFF (enemy only)')..'.')
 if enabled then check('target') end
end
function A.TestMode() return KWCDB and KWCDB.settings and KWCDB.settings.bountyAlertTest==true end

function A.Diagnose()
 if not KWCDB then K.Say('Diagnostics: database not initialized');return end
 local unit='target'
 local exists=UnitExists(unit) and true or false
 local player=exists and UnitIsPlayer(unit) and true or false
 local name=exists and UnitName(unit) or nil
 local enemy=exists and UnitCanAttack and UnitCanAttack('player',unit) and true or false
 local matches=0
 for _,b in ipairs(KWCDB.bounties or {}) do
  if (b.status or 'ACTIVE')=='ACTIVE' and bountyMatches(b.details and b.details.target,name) then matches=matches+1 end
 end
 K.Say('Bounty diagnostic: target='..tostring(name)..', exists='..tostring(exists)..', player='..tostring(player)..', enemy='..tostring(enemy)..', enabled='..tostring(A.Status())..', friendlyTest='..tostring(A.TestMode())..', activeMatches='..matches)
 if exists then check(unit) end
end
function A.Demo() title:SetText('BOUNTY ALERT TEST');detail:SetText('Display and sound test (no player detected)');elapsed=0;banner:Show();if PlaySound then pcall(PlaySound,8959,'Master') end end

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
