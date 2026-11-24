local F=CreateFrame('Frame')
KWC={version='2.0.2',listeners={}};local K=KWC
-- Stable release build identifier.
K.build='2.0.2'
-- Legacy guild packets remain compatible. EVENT1 and CTARESULT are optional additive messages.
K.protocolFamily='1.8.2-compatible'
function K.Say(s) print('|cffffb54d[Keepers]|r '..tostring(s)) end
function K.Clean(s,n) return tostring(s or ''):gsub('[\r\n|]',' '):sub(1,n or 180) end
function K.Now() return date('%Y-%m-%d %H:%M') end
function K.On(event,fn)
 local ok,err=pcall(F.RegisterEvent,F,event)
 if not ok then K.Say('Event unavailable: '..tostring(event));return false end
 K.listeners[event]=K.listeners[event] or {};table.insert(K.listeners[event],fn)
 return true
end
-- Diagnostic log shown in the Activity view. Entries keep the {time,category,text}
-- shape. Secret values are never stringified, and the category is always a non-empty
-- string so the Activity view can concatenate it safely.
function K.Log(cat,msg)
 if not KWCDB then return end
 if type(KWCDB.history)~='table' then KWCDB.history={} end
 if issecretvalue and issecretvalue(cat) then cat='[secret]' end
 if issecretvalue and issecretvalue(msg) then msg='[secret]' end
 cat=K.Clean(cat,24);if cat:match('^%s*$') then cat='GENERAL' end
 local t=KWCDB.history;table.insert(t,1,{time=K.Now(),category=cat,text=K.Clean(msg,230)});while #t>350 do table.remove(t) end
end
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
-- Full display names come from an exact current-roster identity or the local GUID.
function K.CharacterDisplayName(name,localUnit)
 local id=localUnit and K.LocalGuildMember() or K.CurrentGuildMember(name)
 if id then
  for i=1,rosterCount() do
   local current=GetGuildRosterInfo(i)
   if type(current)=='string' and current:lower()==id then return current:match('^[^-]+') end
  end
 end
 return name
end
function K.IsLocalSender(sender)
 local id=K.CurrentGuildMember(sender)
 return id~=nil and id==K.LocalGuildMember()
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
 'guildService','guildServices','pvp','pendingCommand','pendingCommandEvents','deferredCommandEvents','boardDeleteClaims','guildLFG','guildRecords','warSpoils'}
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
 local fresh=KWCDB==nil
 KWCDB=KWCDB or {};local d=KWCDB
 for _,key in ipairs({'history','roster','ops','bounties','pvp','settings','recruiter','responses','scoutReports','afterAction'}) do d[key]=d[key] or {} end
 if fresh then d.settings.tutorialFresh=true end
 -- Default to enabled only when no explicit preference exists.
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
 -- 2.0: the recruiting pitch and all recruitment state belong to KeepersWarCommand_Command.
 if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix,'KWC3');pcall(C_ChatInfo.RegisterAddonMessagePrefix,'KWC4');pcall(C_ChatInfo.RegisterAddonMessagePrefix,'KWCS1') end
 K.Say('War Command '..K.version..' loaded. /kt opens the War Room. /kt help lists commands.')
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
-- /kt instancestatus: read-only summary of the instance alert policy. Unknown,
-- missing or unreadable values are reported as such, never guessed.
function K.InstanceStatusLine()
 local head='KWC '..tostring(K.version or 'unknown')..' | InstanceAlerts '..tostring(K.build or 'unknown')
 local P=K.InstanceAlerts
 if type(P)~='table' or type(P.Status)~='function' then
  return head..' | module=missing | state=unavailable | automatic alerts=unavailable | loading=unavailable'
 end
 local ok,status=pcall(P.Status)
 if not ok or type(status)~='table' then
  return head..' | module=loaded | state=unavailable | automatic alerts=unavailable | loading=unavailable'
 end
 local known={open=true,instance=true,unknown=true,loading=true}
 local state=known[status.state] and status.state or 'unavailable'
 local alerts='unavailable'
 if type(P.Allowed)=='function' then
  local okAllowed,allowed=pcall(P.Allowed)
  if okAllowed and allowed==true then alerts='allowed' elseif okAllowed and allowed==false then alerts='suppressed' end
 end
 local loading=status.loading==true and 'yes' or status.loading==false and 'no' or 'unavailable'
 return head..' | module=loaded | state='..state..' | automatic alerts='..alerts..' | loading='..loading
end
-- 2.0: slash commands are registered by UI/Commands.lua (single registration point).
