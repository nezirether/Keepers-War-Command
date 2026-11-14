local F=CreateFrame('Frame')
KWC={version='1.7.0',listeners={}};local K=KWC
function K.Say(s) print('|cffffb54d[Keepers]|r '..tostring(s)) end
function K.Clean(s,n) return tostring(s or ''):gsub('[\r\n|]',' '):sub(1,n or 180) end
function K.Now() return date('%Y-%m-%d %H:%M') end
function K.On(event,fn)
 local ok,err=pcall(F.RegisterEvent,F,event)
 if not ok then K.Say('Event unavailable: '..tostring(event));return false end
 K.listeners[event]=K.listeners[event] or {};table.insert(K.listeners[event],fn)
 return true
end
function K.Log(cat,msg) if not KWCDB then return end;local t=KWCDB.history;table.insert(t,1,{time=K.Now(),category=cat,text=K.Clean(msg,230)});while #t>350 do table.remove(t) end end
function K.IsOfficer() if not IsInGuild() then return false end;local _,_,rank=GetGuildInfo('player');return type(rank)=='number' and rank<=1 end
-- Preserve the entire character name. Normalize realm spelling separately.
local function accessibleString(value)
 if issecretvalue and issecretvalue(value) then return end
 if type(value)=='string' and value~='' then return value end
end
local function nameParts(value)
 value=accessibleString(value)
 if not value then return end
 local name,realm=value:lower():match('^([^%-]+)%-(.+)$')
 name=(name or value:lower()):match('^%s*(.-)%s*$'):gsub('%s+',' ')
 return name,realm and realm:gsub('[%s\']','')
end
local function rosterCount()
 return GetNumGuildMembers and GetGuildRosterInfo and (GetNumGuildMembers() or 0) or 0
end
local function resolve(name)
 local bare,realm=nameParts(name)
 if not bare or not IsInGuild() then return end
 local _,localRealm=nameParts('x-'..((GetNormalizedRealmName and GetNormalizedRealmName()) or ''))
 local match
 for index=1,rosterCount() do
  local current,_,rank,_,_,_,_,_,online=GetGuildRosterInfo(index)
  local candidate,home=nameParts(current)
  if candidate==bare and (not realm or realm==(home or localRealm)) then
   if match then return nil,'ambiguous' end
   match={current:lower(),rank,online}
  end
 end
 if match then return match end
 return nil,'not matched'
end
function K.CurrentGuildMember(name)
 local match=resolve(name)
 if match then return unpack(match,1,3) end
end
-- GUID comparison identifies only the local unit. Remote senders must still
-- match their delivered names against the current roster.
function K.LocalGuildMember()
 if not IsInGuild() then return end
 local guid=UnitGUID and accessibleString(UnitGUID('player'))
 local matches,found,guids=0,nil,{}
 if guid then
  for i=1,rosterCount() do
   local name,_,rank,_,_,_,_,_,online,_,_,_,_,_,_,_,memberGUID=GetGuildRosterInfo(i)
   name,memberGUID=accessibleString(name),accessibleString(memberGUID)
   if name and memberGUID then
    guids[name:lower()]=memberGUID
    if memberGUID==guid then matches=matches+1;found={name:lower(),rank,online} end
   end
  end
 end
 if matches>1 then return nil,nil,nil,'ambiguous roster GUID' end
 if found then return found[1],found[2],found[3],'roster GUID' end
 local aliases={}
 local function add(name,realm)
  name,realm=accessibleString(name),accessibleString(realm)
  if name then aliases[#aliases+1]=realm and not name:find('-',1,true) and (name..'-'..realm) or name end
 end
 if UnitFullName then add(UnitFullName('player')) end
 if GetUnitName then add(GetUnitName('player',true)) end
 if UnitName then add(UnitName('player')) end
 -- Forever also exposes the logged-in member for the selected guild club.
 -- Use its name only when the API explicitly identifies the member as self.
 if C_Club and C_Club.GetGuildClubId and C_Club.GetMemberInfoForSelf then
  local ok,club=pcall(C_Club.GetGuildClubId)
  if ok and not (issecretvalue and issecretvalue(club)) and club and K.GuildScope() then
   local success,info=pcall(C_Club.GetMemberInfoForSelf,club)
   if success and not (issecretvalue and issecretvalue(info)) and type(info)=='table' and info.isSelf==true then
    add(info.name)
   end
  end
 end
 local reason='local character does not match the live roster'
 for _,name in ipairs(aliases) do
  local candidate,problem=resolve(name)
  if problem=='ambiguous' then reason='ambiguous local name' end
  if candidate and not (guid and guids[candidate[1]] and guids[candidate[1]]~=guid) then
   if found and found[1]~=candidate[1] then return nil,nil,nil,'conflicting local names' end
   found=candidate
  end
 end
 if found then return found[1],found[2],found[3],'exact roster name' end
 return nil,nil,nil,reason
end
function K.IsMember(sender) return K.CurrentGuildMember(sender)~=nil end
function K.SameGuildMember(a,b)
 local id=K.CurrentGuildMember(a)
 return id~=nil and id==K.CurrentGuildMember(b)
end
function K.IsSenderOfficer(sender)
 local _,rank=K.CurrentGuildMember(sender)
 return type(rank)=='number' and rank>=0 and rank<=1
end
function K.RosterRecord(name)
 local short=tostring(name or ''):lower():match('^[^-]+')
 if not short or not KWCDB or not KWCDB.roster then return nil end
 return KWCDB.roster[tostring(name):lower()] or KWCDB.roster[short]
end
function K.IsGuildWarchief(name)
 local r=K.RosterRecord(name)
 if r then return r.rankIndex==0 end
 local me=UnitName and UnitName('player')
 if me and tostring(me):lower()==tostring(name):lower() then
  local _,_,rank=GetGuildInfo('player');return rank==0
 end
 return false
end
function K.CommandIsOffline(name)
 local r=K.RosterRecord(name)
 -- Unknown roster state must NEVER trigger succession.
 local identity,_,online=K.CurrentGuildMember(name)
 return identity~=nil and online==false and r and r.online==false and
  type(r.scannedAt)=='number' and time()-r.scannedAt<=180 and (r.offlineScans or 0)>=2
end
function K.Send(kind,payload)
 if not IsInGuild() or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
 local msg='2;'..K.Clean(kind,18)..';'..K.Clean(payload,210)
 return K.Net.Send('KWC3',msg,'GUILD')
end
local guildFields={'ops','bounties','responses','deletions','raidSignups',
 'guildService','guildServices','pvp','pendingCommand','pendingCommandEvents','boardDeleteClaims','guildLFG'}
local activeGuild,guildBound
function K.GuildScope()
 if not IsInGuild() or not C_Club or not C_Club.GetGuildClubId then return end
 local ok,id=pcall(C_Club.GetGuildClubId)
 if not ok or (issecretvalue and issecretvalue(id)) then return end
 if type(id)=='number' and id>0 then return string.format('%.0f',id) end
 if type(id)=='string' and id:match('^%d+$') and #id<=24 then return id end
end
local function bindGuild()
 if not KWCDB then return end
 local scope=K.GuildScope()
 local d=KWCDB
 if guildBound and activeGuild==scope then return end
 d.guildPartitions=d.guildPartitions or {}
 if activeGuild then
  local previous=d.guildPartitions[activeGuild]
  for _,field in ipairs(guildFields) do previous[field]=d[field] end
 elseif not d.guildPartitionInitialized then
  -- Legacy records have no trustworthy guild identifier. Preserve them
  -- separately instead of adopting them into whichever guild logs in first.
  d.unscopedGuildArchive=d.unscopedGuildArchive or {}
  for _,field in ipairs(guildFields) do d.unscopedGuildArchive[field]=d[field] end
  d.guildPartitionInitialized=true
 elseif d.guildPartitionBound and d.guildPartitions[d.guildPartitionBound] then
  -- Top-level aliases may have been replaced by modules before logout.
  for _,field in ipairs(guildFields) do d.guildPartitions[d.guildPartitionBound][field]=d[field] end
 end
 local current={}
 if scope then
  current=d.guildPartitions[scope] or current
  d.guildPartitions[scope]=current
 end
 for _,field in ipairs(guildFields) do d[field]=current[field] end
 d.ops=d.ops or {};d.bounties=d.bounties or {};d.responses=d.responses or {};d.pvp=d.pvp or {}
 activeGuild=scope;d.guildPartitionBound=scope;guildBound=true
end
-- Readiness retries use the same binder as login and guild events.
K.RefreshGuildScope=bindGuild
local rosterAt,rosterGuild
function K.GuildReadiness()
 if not KWCDB or not IsInGuild or IsInGuild()==nil then return 'Checking guild membership' end
 if not IsInGuild() then return 'Not currently in a guild' end
 local guild=K.GuildScope()
 if not guild then return 'Guild identity unavailable' end
 if KWCDB.guildPartitionBound~=guild then return 'Guild identity not bound' end
 if rosterCount()==0 then return 'Waiting for guild roster' end
 local actor,rank,_,reason=K.LocalGuildMember()
 if not actor then return 'Local character not verified',nil,nil,reason end
 if type(rank)~='number' or rank<0 then return 'Waiting for roster authority' end
 return 'Ready',guild,actor,reason
end
function K.GuildDebug()
 bindGuild()
 local state,guild,actor,reason=K.GuildReadiness()
 local count,readable,valid=rosterCount(),0,0
 for i=1,count do
  local name,_,rank=GetGuildRosterInfo(i)
  if accessibleString(name) then
   readable=readable+1
   if type(rank)=='number' and rank>=0 and K.CurrentGuildMember(name) then valid=valid+1 end
  end
 end
 local checker=K.AddonChecker
 K.Say(('Guild: %s | club ID: %s | bound: %s | roster: %d readable / %d entries / %d validated | last roster event: %s'):format(
  IsInGuild() and 'member' or 'not detected',K.GuildScope() and 'available' or 'unavailable',
  K.GuildScope() and KWCDB and KWCDB.guildPartitionBound==K.GuildScope() and 'yes' or 'no',readable,count,valid,
  rosterAt and rosterGuild==K.GuildScope() and (math.max(0,time()-rosterAt)..'s ago') or 'not observed'))
 K.Say(('LFG / Guild Services: %s | local match: %s | version: %s | checker protocol: %s | requests/replies: %d/%d'):format(
  state,reason or (actor and 'verified' or 'not verified'),K.version,checker and checker.protocol or 'unavailable',
  checker and checker.requests or 0,checker and checker.responses or 0))
end
function K.Init()
 KWCDB=KWCDB or {};local d=KWCDB
 for _,key in ipairs({'history','roster','ops','bounties','pvp','settings','recruiter','responses','scoutReports','afterAction'}) do d[key]=d[key] or {} end
 -- DEV6 migration: start all automatic guild data and scouting features ON,
 -- including clients that disabled them in earlier development builds.
 -- Apply only once; subsequent user OFF choices remain respected.
 if not d.settings.dev6AutoDefaultsApplied then
  d.settings.autoScout=true
  d.settings.autoGuildSync=true
  d.settings.dev6AutoDefaultsApplied=true
 end
 if d.settings.autoScout==nil then d.settings.autoScout=true end
 if d.settings.autoGuildSync==nil then d.settings.autoGuildSync=true end
 if not d.raidCommandTemplates then
  local previous=d.guildPartitions and d.guildPartitions[d.guildPartitionBound]
  local archive=d.unscopedGuildArchive
  local saved=d.raidCommand or (previous and previous.raidCommand) or (archive and archive.raidCommand)
  if saved and saved.templates then d.raidCommandTemplates=saved.templates end
 end
 bindGuild()
 d.settings.alerts=(d.settings.alerts~=false)
 d.settings.pitch=d.settings.pitch or 'Keepers of Trogdor is recruiting! World PvP, dungeons, and a relaxed crew. Interested?'
 if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix,'KWC3');pcall(C_ChatInfo.RegisterAddonMessagePrefix,'KWC4');pcall(C_ChatInfo.RegisterAddonMessagePrefix,'KWCS1') end
 K.Say('War Command '..K.version..' loaded. /kwc to open (/kt also works).')
 if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
 if K.PvP and K.PvP.RefreshHonor then K.PvP.RefreshHonor() end
end
F:RegisterEvent('ADDON_LOADED')
pcall(F.RegisterEvent,F,'INITIAL_CLUBS_LOADED')
F:SetScript('OnEvent',function(_,event,...)
 if event=='ADDON_LOADED' and ...=='KeepersWarCommand' then K.Init() end
 if event=='PLAYER_GUILD_UPDATE' or event=='GUILD_ROSTER_UPDATE' or event=='INITIAL_CLUBS_LOADED' or event=='PLAYER_ENTERING_WORLD' or event=='CLUB_ADDED' or event=='CLUB_REMOVED' or event=='CLUB_UPDATED' or event=='CHAT_MSG_ADDON' then bindGuild() end
 if event=='CHAT_MSG_ADDON' and KWCDB and not activeGuild then
  local prefix,_,channel=...
  if channel=='GUILD' or channel=='WHISPER' then
   if K.Sync and (prefix=='KWC3' or prefix=='KWC4') then K.Sync.RecordOutcome(prefix,'Guild identity unavailable') end
   return
  end
 end
 if event=='GUILD_ROSTER_UPDATE' then rosterAt,rosterGuild=time(),activeGuild end
 for _,fn in ipairs(K.listeners[event] or {}) do local ok,err=pcall(fn,...);if not ok then K.Say(event..' error: '..tostring(err)) end end
end)
SLASH_KEEPERSWARCOMMAND1='/kwc';SLASH_KEEPERSWARCOMMAND2='/kt';SLASH_KEEPERSWARCOMMAND3='/keepers'
SlashCmdList.KEEPERSWARCOMMAND=function(s)
 bindGuild()
 local cmd,arg=tostring(s or ''):match('^(%S*)%s*(.-)%s*$');cmd=(cmd or ''):lower()
 if cmd=='net' then local q,ok,fail,drop=K.Net.Status();K.Say('Network queued: '..q..' | sent: '..ok..' | send errors: '..fail..' | dropped: '..drop)
 elseif cmd=='autoscout' then
  if arg:lower()=='on' then K.AutoScout.SetEnabled(true) elseif arg:lower()=='off' then K.AutoScout.SetEnabled(false) else K.Say('Auto Scout: '..(K.AutoScout.Status() and 'ON' or 'OFF')..'. /kt autoscout on/off. '..K.AutoScout.Info()) end
 elseif cmd=='chatcheck' then K.Operations.GuildChatDiagnostics()
 elseif cmd=='scale' then
  if arg=='' then K.Say('Window scale: '..math.floor(K.UI.GetScale()*100+0.5)..'%. Use /kt scale 75-135')
  else local n=tonumber(arg);if not n then K.Say('Use /kt scale 75-135 (example: /kt scale 90)') else K.UI.SetScale(n/100) end end
 elseif cmd=='bountyalert' then
  local option=arg:lower()
  if option=='test on' then K.BountyAlerts.SetTestMode(true)
  elseif option=='test off' then K.BountyAlerts.SetTestMode(false)
  elseif option=='on' then K.BountyAlerts.SetEnabled(true)
  elseif option=='off' then K.BountyAlerts.SetEnabled(false)
  elseif option=='unlock' then K.BountyAlerts.SetUnlocked(true)
  elseif option=='lock' then K.BountyAlerts.SetUnlocked(false)
  elseif option=='test' then K.BountyAlerts.Demo()
  elseif option=='reset' then K.BountyAlerts.ResetPosition()
  elseif option:match('^scale%s+[%d%.]+$') then K.BountyAlerts.SetScale((tonumber(option:match('[%d%.]+')) or 100)/100)
  else K.Say('/kt bountyalert on/off | test | unlock/lock | reset | scale 50-200 | test on/off') end
 elseif cmd=='bountydiag' then
  if K.BountyAlerts and K.BountyAlerts.Diagnose then K.BountyAlerts.Diagnose() end
 elseif cmd=='alerttest' then
  if K.BountyAlerts and K.BountyAlerts.Demo then K.BountyAlerts.Demo() end
  K.Say('Showing the bounty test. Use /kt deathalert test to preview the death alert.')
 elseif cmd=='deathalert' then
  if arg:lower()=='on' then K.WorldPvPDeaths.SetEnabled(true) elseif arg:lower()=='off' then K.WorldPvPDeaths.SetEnabled(false) elseif arg:lower()=='test' then K.WorldPvPDeaths.Demo() elseif arg:lower()=='status' then K.WorldPvPDeaths.Status() elseif arg:lower()=='debug on' then K.WorldPvPDeaths.SetDebug(true);K.Say('Death alert diagnostics ON') elseif arg:lower()=='debug off' then K.WorldPvPDeaths.SetDebug(false);K.Say('Death alert diagnostics OFF') elseif arg:lower()=='unlock' then K.WorldPvPDeaths.SetUnlocked(true) elseif arg:lower()=='lock' then K.WorldPvPDeaths.SetUnlocked(false) elseif arg:lower()=='reset' then K.WorldPvPDeaths.ResetPosition() elseif arg:lower():match('^scale %d+') then K.WorldPvPDeaths.SetScale((tonumber(arg:match('%d+')) or 100)/100) elseif arg:lower()=='sound on' then KWCDB.settings.worldPvPDeathSound=true;K.Say('World PvP death sound ON') elseif arg:lower()=='sound off' then KWCDB.settings.worldPvPDeathSound=false;K.Say('World PvP death sound OFF') elseif arg:lower()=='broadcast on' then KWCDB.settings.worldPvPDeathBroadcast=true;K.Say('Death broadcasting ON') elseif arg:lower()=='broadcast off' then KWCDB.settings.worldPvPDeathBroadcast=false;K.Say('Death broadcasting OFF') else K.Say('/kt deathalert on/off | test | status | debug on/off | unlock/lock | reset | scale 50-200 | sound on/off | broadcast on/off') end
 elseif cmd=='deathreport' then K.WorldPvPDeaths.Report(arg)
 elseif cmd=='deathhistory' then K.UI.Toggle('World PvP Deaths')
 elseif cmd=='guilddebug' then K.GuildDebug()
 elseif cmd=='lfgdebug' then K.GuildLFG.Debug(arg)
 elseif cmd=='alerts' then K.UI.Toggle('Alerts')
 elseif cmd=='raid' then if K.RaidCommand then K.RaidCommand.Toggle() end
 elseif cmd=='warroom' then K.UI.Toggle('War Room')
 elseif cmd=='scout' then K.UI.Toggle('Scout Network')
 elseif cmd=='aar' then K.UI.Toggle('After Action')
 elseif cmd=='ctahere' then K.UI.Toggle('CTA Entry')
 elseif cmd=='addons' then K.UI.Toggle('Addon Checker');if K.AddonChecker then K.AddonChecker.Request() end
 elseif cmd=='recruit' then K.UI.Toggle('Recruitment')
 elseif cmd=='who' then K.Recruiter.Search(arg)
 elseif cmd=='active' then
  local kind=arg:lower():match('^%s*(%S+)')
  K.Operations.ListActive((kind=='bounty' or kind=='bounties') and 'BOUNTY' or 'CTA',false)
 elseif cmd=='guildreport' then
  local kind=arg:lower():match('^%s*(%S+)')
  K.Operations.ListActive((kind=='bounty' or kind=='bounties') and 'BOUNTY' or 'CTA',true)
 elseif cmd=='cta' then K.Operations.CreateCTA(arg)
 elseif cmd=='bounty' then
  if arg:lower()=='addtarget' then K.UI.OpenBountyForUnit('target') else K.Operations.AddBounty(arg) end
 elseif cmd=='report' then K.Recruiter.Report()
 elseif cmd=='sync' then if K.Sync and K.Sync.RequestAll then K.Sync.RequestAll(false) end
 elseif cmd=='autosync' then
  if arg:lower()=='on' then K.Sync.SetAutoSync(true) elseif arg:lower()=='off' then K.Sync.SetAutoSync(false) else K.Say('Auto Guild Sync: '..(K.Sync.AutoSyncEnabled() and 'ON' or 'OFF')..'. Use /kt autosync on/off.') end
 elseif cmd=='syncdiag' then
  if K.Sync and K.Sync.BoardDiagnostics then
   local d=K.Sync.BoardDiagnostics()
   for _,kind in ipairs({'CTA','Bounty'}) do
    local x=d[kind];K.Say(kind..' sync: sent='..x.sent..' received='..x.received..' applied='..x.applied..' rejected='..x.rejected)
   end
  end
  if K.RaidSignup and K.RaidSignup.Diagnostics then
   local x=K.RaidSignup.Diagnostics()
   K.Say('Raid sign-up sync: sent='..x.sent..' received='..x.received..' applied='..x.applied..' rejected='..x.rejected..' requests='..x.requests)
  end
  K.Say('Counters are since /reload. Received is not the same as applied. Use /kt pvpdiag for honor.')
 elseif cmd=='pvpdiag' then
  local x=K.PvP.Diagnostics()
  K.Say('PvP sync: sent='..x.sent..' received='..x.received..' rejected='..x.rejected..' pending='..x.pending..' last='..tostring(x.lastPeer or 'none')..' ('..tostring(x.lastReason)..')')
 elseif cmd=='honor' then K.PvP.RefreshHonor();K.Say('Honor statistics refreshed (if available).')
 elseif cmd=='scan' then K.Roster.Scan()
 elseif cmd=='integrations' then K.Companions.Report()
 elseif cmd=='' then K.UI.Toggle()
 else
  K.Say('/kwc opens War Command (/kt, /keepers). Subcommands: sync, autoscout, deathalert, guilddebug, lfgdebug, alerts, raid, recruit, addons, help.')
 end
end
