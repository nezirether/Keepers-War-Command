-- K.UI adapter: the only surface the 1.8.2-derived engine uses to reach the
-- interface. Engine modules call K.UI.Refresh()/Toggle()/... exactly as before;
-- this file routes those calls into the 2.0 War Room. No legacy UI code exists.
local K=KWC
local W=K.WarRoom2
local U={};K.UI=U

-- Legacy page names used by engine modules and old slash habits -> 2.0 pages.
local ALIAS={
 ['War Room']='dashboard',['Home']='dashboard',['Overview']='dashboard',
 ['CTA Board']='cta',['CTA Entry']='cta',['After Action']='cta',['Calls to Arms']='cta',
 ['Bounty Board']='bounties',['Bounty Entry']='bounties',['Report Sighting']='bounties',['Bounties']='bounties',
 ['World PvP Deaths']='records',['Death Leaderboard']='records',['Guild Records']='records',['Deaths & Records']='records',
 ['Scout Network']='pvp',['World PvP']='pvp',
 ['Leaderboards']='leaderboards',['PvP Leaderboard']='leaderboards',
 ['Looking for Group']='lfg',['Guild LFG']='lfg',
 ['Guild Services']='services',['Guild Roster']='services',['Services']='services',
 ['Raids']='raids',['Raid Tools: Command']='raids',['Raid Tools: Sign-Ups']='raids',
 ['Alerts']='alerts',['Settings']='settings',['Addon Checker']='settings',
}
local function resolve(page)
 if page==nil then return nil end
 if W.pages[page] then return page end
 if ALIAS[page] then return ALIAS[page] end
 local tool=type(page)=='string' and page:match('^Raid Tools: (.+)$')
 if tool then return 'raids',tool end
 return 'dashboard'
end

function U.Toggle(page)
 if page=='Recruitment' then
  -- Recruitment lives only in the officer add-on. KWC exposes no recruitment UI.
  if K.Officer and K.Officer.Open then K.Officer.Open('recruit') else K.Say('Recruitment is part of the officer add-on (KeepersWarCommand_Command).') end
  return
 end
 local id,arg=resolve(page)
 W.Toggle(id,arg)
end
function U.Open(page,arg) local id,a=resolve(page);W.Show(id,arg or a) end
function U.Refresh() W.Refresh() end
-- Specialized refreshers from 1.8.2 collapse into the coalesced refresh.
U.RaidRefresh=U.Refresh
U.LFGRefresh=U.Refresh
U.GuildRecordsRefresh=U.Refresh
U.CheckerRefresh=U.Refresh
function U.RecruitmentRefresh() if K.Officer and K.Officer.Refresh then K.Officer.Refresh() end end
function U.ApplyAppearance() if K.WarRoomSkin then K.WarRoomSkin.Apply(K.WarRoomSkin.Current()) end end
function U.GetScale() return KWCDB and KWCDB.settings.ui2Scale or 1 end
function U.SetScale(v)
 v=K.Kit.Clamp(v,0.75,1.35)
 if KWCDB then KWCDB.settings.ui2Scale=v end
 W.FitWindow()
 K.Say('War Room scale: '..math.floor(v*100+0.5)..'%')
end
-- Raid Tools mounts its content into the War Room host (see Pages/Raids.lua).
function U.GetHost() return W.raidHost end

-- Player-name helper kept for the bounty context menu (1.8.2 contract).
function U.GetBountyPlayerName(unit)
 if type(unit)~='string' or (issecretvalue and issecretvalue(unit)) then return end
 if not UnitExists or not UnitIsPlayer or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
 local name,realm
 if UnitFullName then name,realm=UnitFullName(unit) end
 if issecretvalue and issecretvalue(name) then return end
 if not name or name=='' then name,realm=UnitName(unit) end
 if issecretvalue and (issecretvalue(name) or issecretvalue(realm)) then return end
 if not name or name=='' then return end
 if realm and realm~='' and not name:find('-',1,true) then return name..'-'..realm end
 return name
end
-- Prefill only; posting always requires the player's explicit confirmation.
function U.OpenBountyForName(name)
 name=K.Clean(name,45)
 if name=='' then return end
 W.Show('bounties',{compose=true,target=name})
end
function U.OpenBountyForUnit(unit)
 if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then K.Say('Target a player first.');return end
 local name=U.GetBountyPlayerName(unit)
 if not name then K.Say('Player name unavailable.');return end
 U.OpenBountyForName(name)
end
function U.OpenBountySighting(id,zone)
 if not K.GuildScope() then K.Say('Guild is not ready.');return false end
 local found
 for _,b in ipairs(KWCDB.bounties or {}) do if b.id==id and (b.status or 'ACTIVE')=='ACTIVE' then found=b end end
 if not found then K.Say('Active bounty not found.');return false end
 W.Show('bounties',{select=id,sighting=zone or ''})
 return true
end

-- New Call to Arms notices. Seeded at login so recovered/old CTAs never alert;
-- only CTAs that first appear during this session, are active, recent and not
-- authored by this character produce a toast. Instance policy applies.
local seen,seeded,seenScope={},false,nil
local function scanCTAs()
 if not KWCDB or not KWCDB.ops then return end
 local scope=K.GuildScope()
 if scope~=seenScope then seenScope=scope;seen={};seeded=false end
 if not seeded then
  for _,e in ipairs(KWCDB.ops) do seen[e.id]=e.revision or e.updated or e.created end
  seeded=true;return
 end
 local current={}
 local me=UnitName and UnitName('player')
 for _,e in ipairs(KWCDB.ops) do
  local revision=e.revision or e.updated or e.created
  current[e.id]=revision
  if seen[e.id]~=revision then
   local fresh=type(e.created)=='number' and time()-e.created<600
   local mine=me and K.SameGuildMember and K.SameGuildMember(e.author,me)
   if fresh and not mine and (e.status or 'ACTIVE')=='ACTIVE' and KWCDB.settings.alerts~=false
    and K.InstanceAlerts and K.InstanceAlerts.Allowed() and K.Toast then
    local id=e.id
    K.Toast.Notice('cta',K.Clean(e.text,90),'Posted by '..tostring(e.author),{label='Open',fn=function() W.Show('cta',{select=id}) end},tostring(id)..':'..tostring(revision))
   end
  end
 end
 seen=current
end
U.ScanCTAs=scanCTAs
local baseRefresh=U.Refresh
function U.Refresh() pcall(scanCTAs);baseRefresh() end
K.On('PLAYER_ENTERING_WORLD',function() pcall(scanCTAs) end)
