-- World PvP death broadcasts. Victim's addon reports their own death only.
local K=KWC
local A={};K.WorldPvPDeaths=A
local lastAttacker=nil
local lastHitAt=0
local lastKillingBlow=nil
local lastKillingAt=0
local lastReportAt=0
local seen={}
local function outdoors()
 if not IsInGuild() then return false end
 if IsInInstance then
  local inside,kind=IsInInstance()
  if kind=='pvp' or kind=='arena' then return false end
  -- Instances are excluded: the feature is for open-world PvP.
  if inside then return false end
 end
 return true
end
local function cleanName(name)
 if type(name)~='string' then return nil end
 name=name:gsub('[\r\n;|]',' '):sub(1,48)
 if name=='' then return nil end
 return name
end
local banner=CreateFrame('Frame','KWC_WorldPvPDeathBanner',UIParent)
banner:SetSize(470,125);banner:SetPoint('TOP',UIParent,'TOP',0,-335)
banner:SetFrameStrata('DIALOG');banner:Hide()
local bg=banner:CreateTexture(nil,'BACKGROUND');bg:SetAllPoints();bg:SetColorTexture(0.24,0.055,0.055,0.95)
local heading=banner:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');heading:SetPoint('TOP',0,-12);heading:SetText('GUILDMATE SLAIN IN WORLD PVP')
local detail=banner:CreateFontString(nil,'OVERLAY','GameFontHighlight');detail:SetPoint('TOP',heading,'BOTTOM',0,-8);detail:SetWidth(440)
local close=CreateFrame('Button',nil,banner,'UIPanelCloseButton');close:SetPoint('TOPRIGHT',0,0)
local bountyButton=CreateFrame('Button',nil,banner,'UIPanelButtonTemplate')
bountyButton:SetSize(150,23);bountyButton:SetPoint('BOTTOM',banner,'BOTTOM',0,5)
bountyButton:SetText('Add to Bounty Board')
local shownKiller=nil
bountyButton:SetScript('OnClick',function()
 if shownKiller and K.UI and K.UI.OpenBountyForName then K.UI.OpenBountyForName(shownKiller) end
end)

local shown=0
banner:SetScript('OnUpdate',function(self,dt) shown=shown+dt;if shown>=7 then self:Hide() end end)
local function remember(victim,killer,zone,method)
 if not KWCDB then return end
 KWCDB.worldPvPDeaths=KWCDB.worldPvPDeaths or {}
 local records=KWCDB.worldPvPDeaths
 table.insert(records,1,{victim=victim,killer=killer,zone=zone,at=K.Now(),method=method or 'Recent player damage'})
 while #records>75 do table.remove(records) end
end
local function display(victim,killer,zone,method)
 if not KWCDB or KWCDB.settings.worldPvPDeathAlerts==false then return end
 heading:SetText('GUILDMATE SLAIN IN WORLD PVP')
 detail:SetText(victim..' was slain!  Attacker: '..killer..'  |  '..zone)
 shownKiller=(killer~='Unknown Alliance attacker' and killer) or nil
 bountyButton:SetShown(shownKiller~=nil)
 shown=0;banner:Show()
 remember(victim,killer,zone,method)
 K.Say('WORLD PVP: '..victim..' was killed by '..killer..' in '..zone..'.')
 if PlaySound and KWCDB.settings.worldPvPDeathSound~=false and (not K.QOL or K.QOL.Enabled('alertSound')) then pcall(PlaySound,8959,'Master') end
end
-- Automatic open-world death reporting uses ordinary unit/death events, never combat-log events.
-- A hostile player targeting us is a *candidate*, not a verified killing blow.
local hostileName=nil
local hostileAt=0
local scanElapsed=0
local function observe(unit)
 if not UnitExists or not UnitExists(unit) then return end
 if not UnitIsPlayer or not UnitIsPlayer(unit) then return end
 if not UnitCanAttack or not UnitCanAttack('player',unit) then return end
 if UnitIsUnit and not UnitIsUnit(unit..'target','player') then return end
 local name=cleanName(UnitName(unit))
 if name then hostileName=name;hostileAt=time() end
end
local scanner=CreateFrame('Frame')
scanner:SetScript('OnUpdate',function(_,dt)
 scanElapsed=scanElapsed+dt
 if scanElapsed<0.5 then return end
 scanElapsed=0
 if not outdoors() or (UnitIsDeadOrGhost and UnitIsDeadOrGhost('player')) then return end
 observe('target');observe('mouseover')
 for i=1,20 do observe('nameplate'..i) end
end)
K.On('PLAYER_DEAD',function()
 if not outdoors() or not KWCDB or not KWCDB.settings or KWCDB.settings.worldPvPDeathBroadcast==false then return end
 local now=time()
 if now-lastReportAt<12 then return end
 -- Only send when there is recent evidence of hostile-player contact.
 -- This cannot establish the actual cause of death.
 if not hostileName or now-hostileAt>15 then return end
 local victim=cleanName(UnitName('player'));if not victim then return end
 local zone=K.Clean((GetRealZoneText and GetRealZoneText()) or 'Unknown zone',65):gsub(';',' ')
 lastReportAt=now
 local candidate=hostileName
 K.Send('WORLDDEATH','Unknown Alliance attacker;'..zone)
 display(victim,'Unknown Alliance attacker',zone,'Automatic: hostile player recently targeted victim; killer unconfirmed')
 K.Say('Possible nearby hostile player: '..candidate..' (NOT confirmed as killer).')
end)
-- WoW Forever Interface 16001 forbids COMBAT_LOG_EVENT_UNFILTERED.
-- Do not register it: registration taints Blizzard's protected UI.
-- Automatic alerts use PLAYER_DEAD with recent hostile targeting evidence.
-- Exact killer identification remains unavailable; manual reports remain optional.
function A.Report(killer)
 if not outdoors() then K.Say('Death reports are for open-world PvP only.');return end
 killer=cleanName(killer)
 if not killer then K.Say('Usage: /kt deathreport AlliancePlayerName');return end
 if not UnitIsDeadOrGhost('player') then K.Say('Death report available only while dead or a ghost.');return end
 if not KWCDB or not KWCDB.settings or KWCDB.settings.worldPvPDeathBroadcast==false then return end
 local now=time()
 if now-lastReportAt<12 then K.Say('Please wait before reporting another death.');return end
 local name=cleanName(UnitName('player'))
 if not name then return end
 local zone=K.Clean((GetRealZoneText and GetRealZoneText()) or 'Unknown zone',65):gsub(';',' ')
 lastReportAt=now
 K.Send('WORLDDEATH',killer..';'..zone)
 display(name,killer,zone,'Manually reported by victim')
end
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~='KWC3' or channel~='GUILD' or not K.IsMember(sender) or type(msg)~='string' then return end
 local killer,zone=msg:match('^2;WORLDDEATH;([^;]+);([^;]+)$')
 if not killer or not zone or #killer>48 or #zone>65 then return end
 local victim=cleanName(sender:match('^[^-]+'))
 if not victim then return end
 local now=time();local key=victim:lower()
 if now-(seen[key] or 0)<12 then return end
 seen[key]=now
 if victim:lower()==tostring(UnitName('player')):lower() then return end
 display(victim,killer,zone,'Reported by victim')
end)
function A.SetEnabled(enabled)
 if KWCDB then KWCDB.settings.worldPvPDeathAlerts=not not enabled end
 K.Say('World PvP death popups '..(enabled and 'ON' or 'OFF'))
end
function A.Demo() display('Guildmate','Alliance Rogue','Hillsbrad Foothills','Test alert') end
