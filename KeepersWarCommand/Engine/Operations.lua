local K=KWC;local O={};K.Operations=O
-- Automatic alerts follow the central instance policy (InstanceAlerts.lua).
-- A missing policy suppresses rather than allows.
local function alertsAllowed(token) local P=K.InstanceAlerts;return P~=nil and P.Allowed(token) end
local function add(t,author,body,id)
 for _,e in ipairs(t) do if e.id==id then return e end end
 local kind=t==KWCDB.ops and 'C' or 'B'
 if K.Sync and K.Sync.IsBoardDeleted and K.Sync.IsBoardDeleted(kind,id,author) then return nil end
 if KWCDB.deletions and KWCDB.deletions[kind..':'..id] then return nil end
 local e={id=id,author=author,text=K.Clean(body,165),time=K.Now(),created=time(),status="ACTIVE"};table.insert(t,1,e)
 while #t>100 do table.remove(t) end;return e
end
local function activeEntries(kind)
 local t=(kind=='CTA') and KWCDB.ops or KWCDB.bounties
 local result={}
 for _,e in ipairs(t or {}) do
  if (e.status or 'ACTIVE')=='ACTIVE' then result[#result+1]=e end
 end
 return result
end
-- ForeverAPI marks chat sending as restricted for addons. Never send chat
-- programmatically. Prepare a chat draft that the player submits manually.
local function chatLine(line)
 if not IsInGuild() then K.Say('Guild chat unavailable.');return false end
 if type(ChatFrame_OpenChat)~='function' then K.Say('Chat draft unavailable.');return false end
 ChatFrame_OpenChat('/g '..K.Clean(line,220))
 K.Say('Guild report prepared. Press Enter to send it yourself.')
 return true
end

-- Snapshot exchange: clients can ask peers for active operations created before login.
-- Only addon messages are automatic; public guild chat remains player-confirmed.
local lastSyncRequest=0
local lastSyncReply=0
function O.RequestSync()
 if K.Sync then return K.Sync.Request() end
 if not IsInGuild() then K.Say('Guild sync requires guild membership.');return end
 local now=time()
 if now-lastSyncRequest<30 then K.Say('Wait before requesting another board refresh.');return end
 lastSyncRequest=now
 K.Send('SYNC','REQ')
 K.Say('Requested active CTA and bounty reports from online War Command users.')
end
local function replySnapshot()
 local now=time()
 if now-lastSyncReply<30 then return end
 lastSyncReply=now
 for _,kind in ipairs({'CTA','BOUNTY'}) do
  local list=activeEntries(kind)
  for i=1,math.min(12,#list) do
   local e=list[i]
   if K.SameGuildMember(e.author,UnitName('player')) then K.Send(kind,e.id..':'..K.Clean(e.text,155)) end
  end
 end
end

function O.Report(kind,id)
 local entry
 for _,v in ipairs(kind=='CTA' and KWCDB.ops or KWCDB.bounties) do if v.id==id then entry=v;break end end
 if not entry then entry=activeEntries(kind)[1] end
 if not entry then K.Say('No active '..kind..' entries.');return end
 local prefix=(kind=='CTA') and '[Keepers CTA] ' or '[Keepers Bounty] '
 chatLine(prefix..entry.text..' ('..(entry.status or 'ACTIVE')..')')
end
function O.ListActive(kind,sendToGuild)
 local list=activeEntries(kind)
 local title=(kind=='CTA') and 'CTAs' or 'bounties'
 local header='[Keepers] '..#list..' active '..title..'. Use /kt to view full board.'
 if sendToGuild then
  local lines={header}
  for i,e in ipairs(list) do if i>3 then break end;lines[#lines+1]=i..'. '..K.Clean(e.text,65) end
  chatLine(table.concat(lines,' / '))
  return
 else K.Say(header) end
 for i,e in ipairs(list) do
  if i>4 then break end
  local line=i..'. '..K.Clean(e.text,150)
  if sendToGuild then chatLine(line) else K.Say(line) end
 end
end
function O.DraftExternal(kind,id,network)
 local e
 for _,v in ipairs(kind=='CTA' and KWCDB.ops or KWCDB.bounties) do if v.id==id then e=v;break end end
 if not e then K.Say('Report not found.');return end
 local label=(kind=='CTA') and 'CTA' or 'Bounty'
 local msg='[Keepers '..label..'] '..e.text
 if network=='OV' and not K.Companions.Overlord() then K.Say('Overlord is not loaded.');return end
 if network=='WE' and not K.Companions.WarEffort() then K.Say('War Effort is not loaded.');return end
 if ChatFrame_OpenChat then
  ChatFrame_OpenChat(K.Clean(msg,225))
  K.Say('Draft prepared. Copy it into the '..(network=='OV' and 'Overlord' or 'War Effort')..' reporting interface; no direct submission was made.')
 else K.Say('Chat draft unavailable.') end
end
-- ForeverAPI: CHAT_MSG_GUILD is supported. Send the reply on the next tick
-- instead of synchronously from the incoming chat event.
-- Guild text commands cannot trigger protected chat sends. They mark a
-- report as pending and notify local addon users; no automated chat reply.
local queryCooldown={}
local function processGuildQuery(message,sender)
 if type(message)~='string' then return end
 local normalized=message:lower():match('^%s*(.-)%s*$')
 local kind
 if normalized=='!cta' or normalized=='!kt cta' or normalized=='!kt ctas' then kind='CTA'
 elseif normalized=='!bounties' or normalized=='!bounty' or normalized=='!kt bounties' or normalized=='!kt bounty' then kind='BOUNTY'
 else return end
 if not KWCDB then return end
 local now=time()
 if now-(queryCooldown[kind] or 0)<15 then return end
 queryCooldown[kind]=now
 KWCDB.pendingGuildReport=kind
 if alertsAllowed() then K.Say(tostring(sender)..' requested active '..(kind=='CTA' and 'CTAs' or 'bounties')..'. Open the '..(kind=='CTA' and 'CTA' or 'Bounty')..' Board and use Report Active to Guild, then press Enter.') end
end
local guildEventRegistered=K.On('CHAT_MSG_GUILD',processGuildQuery)
O.GuildChatDiagnostics=function()
 K.Say('CHAT_MSG_GUILD listener: '..(guildEventRegistered and 'registered' or 'unavailable'))
 K.Say('Guild status: '..tostring(IsInGuild()))
 K.Say('Chat auto-replies disabled: Forever restricts addon chat sending.')
 K.Say('Use /kt guildreport cta to prepare a manual guild-chat draft.')
end
-- Structured operation intelligence, preserved separately from readable summary.
local function get(kind,id)
 local t=kind=='CTA' and KWCDB.ops or KWCDB.bounties
 for _,e in ipairs(t or {}) do if e.id==id then return e end end
end
local function ownerOrOfficer(e)
 if not e then return false end
 local me=UnitName('player') or ''
 return tostring(e.author or ''):lower()==me:lower() or K.IsOfficer()
end
local function syncUpdate(kind,e)
 -- Versioned update: the original entry ID remains unchanged.
 local serial=table.concat({kind,e.id,tostring(e.revision or 1),K.Clean(e.text,110)},',')
 K.Send('UPDATE',serial)
 if K.Sync then K.Sync.Broadcast(kind,e) end
end
function O.NormalizePriority(value)
 if value==true then return 'URGENT' end
 if value==false or value==nil then return 'NORMAL' end
 local v=tostring(value):upper()
 if v=='LOW' or v=='NORMAL' or v=='HIGH' or v=='URGENT' then return v end
 return 'NORMAL'
end
function O.UpdateCTA(id,zone,horde,alliance,objective,priority,notes)
 if K.GuildScope and not K.GuildScope() then return end
 local e=get('CTA',id)
 if not ownerOrOfficer(e) then K.Say('Only the poster or an officer may edit.');return end
 if O.IsSOS(e) then return O.UpdateSOS(e,zone,horde,alliance,objective,notes) end
 local h,a=tonumber(horde),tonumber(alliance)
 if not h or not a or h<0 or a<0 or h>999 or a>999 or h~=math.floor(h) or a~=math.floor(a) then K.Say('Enter Horde and Alliance counts from 0 to 999.');return end
 zone=K.Clean(zone,34);objective=K.Clean(objective,54);notes=K.Clean(notes,28)
 if zone=='' or objective=='' then K.Say('Zone and objective are required.');return end
 local level=O.NormalizePriority(priority)
 e.details={zone=zone,horde=h,alliance=a,objective=objective,priority=level,urgent=level=='URGENT',notes=notes}
 e.text='['..level..'] '..zone..' | H:A '..h..':'..a..' | '..objective..(notes~='' and ' | '..notes or '')
 e.revision=(e.revision or 0)+1;e.updated=K.Now();e.updatedBy=UnitName('player')
 e.modifiedAt=time();syncUpdate('CTA',e);K.Log('CTA','Updated '..e.id);K.UI.Refresh()
end
-- DEV8: independent command seats. Concurrent officer claims are additive.
local function key(name) return tostring(name or ''):lower():match('^[^-]+') end
function O.Commanders(e)
 if not e or e.recoveredOnly then return {} end
 local seats=e.commandSeats
 if type(seats)~='table' then return {e.commander or e.author} end
 local names={};for name,active in pairs(seats) do if active then names[#names+1]=name end end
 table.sort(names);return names
end
-- CTA leadership is derived, never transferred. The creator remains Commander.
-- Responding guild officers are Co-Commanders; rank zero is War Chief.
local function normalizeCTAName(n)
 if type(n)~='string' then return '' end
 return (n:match('^[^-]+') or n):lower()
end
-- Display-only identity resolution: never modify the saved CTA author.
-- A short name is expanded only when exactly one guild roster member matches.
local function fullCTAName(name)
 if type(name)~='string' or name=='' then return '?' end
 local raw=name:match('^[^-]+') or name
 local own=UnitName and UnitName('player')
 if own and own:lower()==raw:lower() and K.PvP and K.PvP.PlayerName then
  local full=K.PvP.PlayerName()
  if type(full)=='string' and full:find(' ') then return full end
 end
 local found=nil
 for _,r in pairs((KWCDB and KWCDB.roster) or {}) do
  local n=type(r)=='table' and r.name
  if type(n)=='string' then
   local matches=n:lower()==raw:lower() or (not raw:find(' ',1,true) and n:lower():sub(1,#raw+1)==raw:lower()..' ')
   if matches then
    if found and found:lower()~=n:lower() then return raw end
    found=n
   end
  end
 end
 return found or raw
end
O.CTAFullName=fullCTAName
function O.CTALeadership(e)
 local result={creator=e and (e.author or e.commander) or '?',officers={},warchief=nil}
 if not e then return result end
 result.creator=fullCTAName(result.creator)
 local responses=(KWCDB.responses or {})[e.id] or {}
 local found={}
 for name,status in pairs(responses) do
  if status=='Coming' then
   local record=K.RosterRecord(name)
   local rank=record and record.rankIndex
   local full=fullCTAName(record and record.name or name)
   local id=normalizeCTAName(full)
   if not found[id] then
    found[id]=true
    if rank==0 or K.IsGuildWarchief(name) then
     result.warchief=full
    elseif rank==1 and normalizeCTAName(full)~=normalizeCTAName(result.creator) then
     result.officers[#result.officers+1]=full
    end
   end
  end
 end
 table.sort(result.officers)
 return result
end
function O.Commander(e) return e and (e.author or e.commander) or '?' end
function O.IsCommander(e,name)
 if e and e.recoveredOnly then return false end
 for _,v in ipairs(O.Commanders(e)) do if K.SameGuildMember(v,name) then return true end end
 return false
end
function O.CanAssumeCommand(e)
 return e and not e.recoveredOnly and (e.status or 'ACTIVE')=='ACTIVE' and K.IsOfficer() and not O.IsCommander(e,UnitName('player'))
end
function O.ApplyCommandEvent(e,event)
 if e and e.recoveredOnly then return false end
 if not e or not event or not event.id or not event.actor then return false end
 e.commandEvents=e.commandEvents or {}
 if e.commandEvents[event.id] then return false end
 local typ=event.type;local actor=event.actor;local target=event.target
 if not K.IsMember(actor) then return false end
 if typ=='A' then
  if not (K.IsSenderOfficer and K.IsSenderOfficer(actor)) then return false end
 elseif typ=='L' then
  if not O.IsCommander(e,actor) or not K.IsMember(target) then return false end
 elseif typ=='P' then
  if not target or not O.IsCommander(e,target) then return false end
  if not K.SameGuildMember(actor,(e.lieutenants or {})[target]) or not K.CommandIsOffline(target) then return false end
 elseif typ=='R' then
  if not O.IsCommander(e,actor) or not K.IsMember(target) then return false end
 else return false end
 e.commandSeats=e.commandSeats or {[e.commander or e.author]=true}
 e.lieutenants=e.lieutenants or {}
 if typ=='A' then e.commandSeats[actor]=true
 elseif typ=='L' then e.lieutenants[actor]=target
 elseif typ=='P' then
  e.commandSeats[target]=nil;e.commandSeats[actor]=true
  e.lieutenants[actor]=target;e.lieutenants[target]=nil
 elseif typ=='R' then
  -- Voluntary restoration: commander hands their own seat to former LT.
  e.commandSeats[actor]=nil;e.commandSeats[target]=true
  e.lieutenants[target]=actor;e.lieutenants[actor]=nil
 end
 e.commandEvents[event.id]=event
 e.commander=O.Commanders(e)[1] or e.author
 e.lieutenant=e.lieutenants[e.commander]
 return true
end
local seq=0
local function act(e,typ,target)
 seq=seq+1
 local actor=UnitName('player') or ''
 local event={id=actor..':'..time()..':'..seq,type=typ,actor=actor,target=target or ''}
 if not O.ApplyCommandEvent(e,event) then K.Say('Command action not permitted.');return false end
 if K.Sync and K.Sync.BroadcastCommandEvent then K.Sync.BroadcastCommandEvent(e,event) end
 if K.UI then K.UI.Refresh() end
 return true
end
function O.AssumeCommand(id)
 local e=get('CTA',id)
 if not O.CanAssumeCommand(e) then K.Say('Only an eligible officer can assume a new command seat.');return false end
 return act(e,'A')
end
function O.AssignLieutenant(id,name)
 local e=get('CTA',id);name=K.Clean(name,90)
 if not e or not O.IsCommander(e,UnitName('player')) or name=='' then return false end
 return act(e,'L',name)
end
function O.RestoreCommander(id,name)
 local e=get('CTA',id);name=K.Clean(name,90)
 if not e or not O.IsCommander(e,UnitName('player')) or name=='' then return false end
 return act(e,'R',name)
end
function O.TrySuccession()
 for _,e in ipairs(KWCDB and KWCDB.ops or {}) do
  if (e.status or 'ACTIVE')=='ACTIVE' then
   local me=UnitName('player')
   for commander,lt in pairs(e.lieutenants or {}) do
    if key(lt)==key(me) and O.IsCommander(e,commander) and K.CommandIsOffline and K.CommandIsOffline(commander) then
     act(e,'P',commander)
    end
   end
  end
 end
end
-- Warlord is a derived group role, never an addon-message appointment.
function O.Warlord()
 if not IsInGroup or not IsInGroup() then return nil end
 local function check(unit)
  if UnitExists and UnitExists(unit) and UnitIsPlayer and UnitIsPlayer(unit) then
   local name=UnitName(unit)
   if name and K.IsGuildWarchief and K.IsGuildWarchief(name) then return name end
  end
 end
 local name=check('player');if name then return name end
 local n=(GetNumGroupMembers and GetNumGroupMembers()) or 0
 for i=1,n do
  name=check('raid'..i) or check('party'..i)
  if name then return name end
 end
 return nil
end
function O.UpdateBounty(id,target,location,reason,reward)
 if K.GuildScope and not K.GuildScope() then return end
 local e=get('BOUNTY',id)
 if not ownerOrOfficer(e) then K.Say('Only the poster or an officer may edit.');return end
 target=K.Clean(target,36);location=K.Clean(location,35);reason=K.Clean(reason,48);reward=K.Clean(reward,25)
 if target=='' then K.Say('Target name is required.');return end
 e.details={target=target,location=location,reason=reason,reward=reward}
 e.text=target..(location~='' and ' @ '..location or '')..(reason~='' and ' - '..reason or '')..(reward~='' and ' | Reward: '..reward or '')
 e.revision=(e.revision or 0)+1;e.updated=K.Now();e.updatedBy=UnitName('player')
 e.modifiedAt=time();syncUpdate('BOUNTY',e);K.Log('BOUNTY','Updated '..e.id);K.UI.Refresh()
end
function O.RememberSighting(entry,who,zone,note,stamp)
 stamp=stamp or time()
 entry.sightings=entry.sightings or {}
 for _,sighting in ipairs(entry.sightings) do
  if sighting.zone==zone and sighting.note==note and sighting.receivedAt
   and math.abs(stamp-sighting.receivedAt)<300 and K.SameGuildMember(sighting.who,who) then return false end
 end
 entry.sightings[#entry.sightings+1]={who=who,zone=zone,note=note,at=date('%Y-%m-%d %H:%M',stamp),receivedAt=stamp}
 table.sort(entry.sightings,function(a,b)
  if (a.receivedAt or 0)~=(b.receivedAt or 0) then return (a.receivedAt or 0)>(b.receivedAt or 0) end
  return table.concat({a.who or '',a.zone or '',a.note or ''},'|')
       < table.concat({b.who or '',b.zone or '',b.note or ''},'|')
 end)
 while #entry.sightings>15 do table.remove(entry.sightings) end
 return true
end
-- automatic: true for sightings received from the guild (instance policy applies).
-- token: policy token from receipt time, for sightings replayed later.
function O.AnnounceSighting(entry,who,zone,note,automatic,token)
 if automatic and not alertsAllowed(token) then return end
 local target=entry.details and entry.details.target or entry.text
 K.Say('Bounty sighting: '..K.Clean(target,70)..' in '..K.Clean(zone,38)..' (reported by '..K.Clean(who,90)..').'
  ..(note~='' and ' '..K.Clean(note,50) or ''))
end
function O.AddSighting(id,zone,note)
 if K.GuildScope and not K.GuildScope() then return end
 local e=get('BOUNTY',id)
 if not e or (e.status or 'ACTIVE')~='ACTIVE' then K.Say('Active bounty not found.');return end
 zone=K.Clean(zone,38):gsub('%c',' '):match('^%s*(.-)%s*$')
 note=K.Clean(note,50):gsub('%c',' ')
 if zone=='' then K.Say('Location required.');return end
 local who=K.LocalGuildMember()
 if not who then K.Say('Guild roster verification is required to report a sighting.');return end
 local stamp=time()
 local name=UnitName('player') or who
 if not O.RememberSighting(e,name,zone,note,stamp) then K.Say('That sighting was already reported.');return end
 if K.Sync then K.Sync.BroadcastBountyActivity(e,'S',who,stamp,zone..'|'..note) end
 if not zone:find(',',1,true) then K.Send('SIGHT',id..':'..zone..','..note) end
 O.AnnounceSighting(e,name,zone,note)
 K.Log('SIGHTING',name..' saw '..(e.details and e.details.target or e.text)..' at '..zone)
 K.UI.Refresh()
 return true
end
function O.Stats()
 local result={activeCTA=0,urgent=0,activeBounty=0,closedCTA=0,closedBounty=0,claims=0,sightings=0,coming=0}
 for _,e in ipairs(KWCDB.ops or {}) do
  if (e.status or 'ACTIVE')=='ACTIVE' then
   result.activeCTA=result.activeCTA+1
   if (e.text or ''):find('URGENT',1,true) then result.urgent=result.urgent+1 end
   -- Reinforcements are active only while their CTA remains active.
   -- Keep saved responses for historical records; exclude them from the live dashboard.
   for _,r in pairs((KWCDB.responses or {})[e.id] or {}) do
    if r=='Coming' then result.coming=result.coming+1 end
   end
  else
   result.closedCTA=result.closedCTA+1
  end
 end
 for _,e in ipairs(KWCDB.bounties or {}) do
  if (e.status or 'ACTIVE')=='ACTIVE' then result.activeBounty=result.activeBounty+1 else result.closedBounty=result.closedBounty+1 end
  for _ in pairs(e.claims or {}) do result.claims=result.claims+1 end
  result.sightings=result.sightings+#(e.sightings or {})
 end
 return result
end
function O.CreateCTA(text,details)
 if K.GuildScope and not K.GuildScope() then return end
 if not IsInGuild() then K.Say('You must be in a guild.');return end
 text=K.Clean(text,155);if text=='' then K.Say('Usage: /kt cta Hillsbrad - Defend Tarren Mill');return end
 local id=tostring(time())..'-'..tostring(math.random(1000,9999));add(KWCDB.ops,UnitName('player'),text,id)
 KWCDB.ops[1].commander=UnitName('player');KWCDB.ops[1].lieutenant=nil
 if details then KWCDB.ops[1].details=details end
 if K.Sync then K.Sync.Broadcast('CTA',KWCDB.ops[1]) end
 K.Send('CTA',id..':'..text);if KWCDB.settings.autoGuildReports then K.Say('CTA ready: use CTA Board > Guild report to prepare a chat draft.') end;K.Log('CTA',text);K.Say('CTA published locally and broadcast attempted.');K.UI.Refresh()
end
-- Guild SOS: an ordinary URGENT call to arms, so responses, command, sync,
-- deletion and alerts all behave as for any other call. The text marker survives
-- clients and recovery paths that carry no details.
local SOS_MARK='SOS: backup needed'
local SOS_COOLDOWN=60
local lastSOS=0
-- e.sos remembers the identity if an older client rewrites the text.
function O.IsSOS(e) return e~=nil and (e.sos==true or tostring(e.text or ''):find(SOS_MARK,1,true)~=nil) end
-- A request lives 10 minutes from its creation. The call ID carries the creator's
-- creation time, which edits and sync never change.
local SOS_LIFETIME=600
local function started(e) return tonumber(tostring(e.id):match('^(%d+)%-%d+$')) or tonumber(e.created) end
-- When it ends on this computer's clock. The creator's clock stamped the start, so
-- a known difference between the two clocks is added back.
local function deadline(e,at)
 return at+SOS_LIFETIME+(K.Sync and K.Sync.ClockOffset and K.Sync.ClockOffset(e.author) or 0)
end
function O.SOSRemaining(e)
 local at=O.IsSOS(e) and started(e)
 if not at then return nil end
 return math.max(0,math.min(SOS_LIFETIME,deadline(e,at)-time()))
end
function O.SOSExpired(e)
 if not O.IsSOS(e) or (e.status or 'ACTIVE')=='ACTIVE' then return false end
 local at=started(e)
 return e.sosExpired==true or (at~=nil and e.modifiedAt==at+SOS_LIFETIME)
end
function O.SOSTimeText(e)
 local left=O.SOSRemaining(e)
 if not left then return nil end
 if left<=0 then return 'expired' end
 return left<60 and (left..'s left') or (math.ceil(left/60)..'m left')
end
local function mySOS(e,me) return O.IsSOS(e) and K.SameGuildMember(e.author,me) end
-- This character's active request, if any.
function O.ActiveSOS()
 O.ExpireSOS()
 local me=K.LocalGuildMember and K.LocalGuildMember()
 if not me then return nil end
 for _,e in ipairs(KWCDB and KWCDB.ops or {}) do
  if (e.status or 'ACTIVE')=='ACTIVE' and mySOS(e,me) then return e end
 end
end
local function readableText(value,limit)
 if (issecretvalue and issecretvalue(value)) or type(value)~='string' then return nil end
 value=K.Clean(value,limit):gsub('%c',' '):match('^%s*(.-)%s*$')
 return value~='' and value or nil
end
-- This session's local send state per SOS. Never saved, never a delivery receipt.
local outbound={}
local function refreshPages() if K.WarRoom2 and K.WarRoom2.Refresh then K.WarRoom2.Refresh() end end
-- Moves what was queued since mark ahead of the backlog and follows it out.
local function dispatch(id,mark,announce)
 local state={total=0,pending=0,failed=0}
 outbound[id]=state
 local function done(ok)
  state.pending=state.pending-1
  if not ok then state.failed=state.failed+1 end
  if state.pending==0 then
   if announce and K.InstanceAlerts and K.InstanceAlerts.Allowed() then
    K.Say(state.failed==0 and 'Backup request sent by your client. Delivery is not confirmed.'
     or 'Part of your backup request could not be sent. Guildmates may not have it.')
   end
   refreshPages()
  end
 end
 state.total=K.Net.Expedite(mark,done)
 state.pending=state.total
end
-- Sends whatever fn queues ahead of the backlog when it concerns an SOS.
local function sendFirst(entry,fn)
 if not O.IsSOS(entry) then return fn() end
 local mark=K.Net.Mark()
 fn()
 dispatch(entry.id,mark)
end
O.SendFirst=sendFirst
-- Plain wording for what this client actually knows. Responses from others are the
-- only evidence anyone received it.
function O.SOSStatusText(e)
 if not O.IsSOS(e) then return nil end
 local lines={}
 local state=outbound[e.id]
 if state then
  if state.total==0 then lines[#lines+1]='Saved on this client only; nothing was queued to send.'
  elseif state.pending>0 then lines[#lines+1]='Queued to send ('..state.pending..' of '..state.total..' messages waiting).'
  elseif state.failed>0 then lines[#lines+1]='Some messages could not be sent.'
  else lines[#lines+1]='Sent by your client. Delivery is not confirmed.' end
 end
 local replies=0
 for who in pairs((KWCDB.responses or {})[e.id] or {}) do
  if not K.SameGuildMember(who,e.author) then replies=replies+1 end
 end
 if replies>0 then lines[#lines+1]=replies..' guildmate response'..(replies>1 and 's' or '')..' received.' end
 return #lines>0 and table.concat(lines,' ') or nil
end
-- Every client closes an old request itself, so it cannot return after a reload or
-- late sync. Only the requester also publishes the change, which is how older
-- versions learn of it.
-- Older versions cannot expire a request, and only learn of it from an update. If
-- the requester is offline, an officer publishes the same update through normal
-- call sync, after a grace period that absorbs clock error. Officers wait
-- different lengths so that usually only one of them sends it.
local OFFICER_GRACE=120
local function standInDue(e,at)
 if not (e.sosExpired and not e.sosExpirySent and e.sosBaseRevision) then return false end
 -- A higher revision means someone has already published a change.
 if (e.revision or 0)~=e.sosBaseRevision or not (K.IsOfficer and K.IsOfficer()) then return false end
 local guid=UnitGUID and UnitGUID('player') or ''
 local jitter=0
 for i=1,#guid do jitter=(jitter*31+guid:byte(i))%90 end
 local overdue=time()-deadline(e,at)
 if overdue<OFFICER_GRACE+jitter or overdue>86400 then return false end
 local member,_,online=K.CurrentGuildMember(e.author)
 return member~=nil and online==false
end
local expiring=false
function O.ExpireSOS()
 if expiring or not KWCDB or not KWCDB.ops or (K.GuildScope and not K.GuildScope()) then return end
 expiring=true
 local me=K.LocalGuildMember and K.LocalGuildMember()
 local changed=false
 for _,e in ipairs(KWCDB.ops) do
  if O.IsSOS(e) then
   e.sos=true
   local at=started(e)
   if (e.status or 'ACTIVE')=='ACTIVE' and at and time()>=deadline(e,at) then
    e.status='RESOLVED';e.sosExpired=true;e.sosExpirySent=nil;e.sosBaseRevision=e.revision or 0;changed=true
   end
   local mine=me and K.SameGuildMember(e.author,me)
   if e.sosExpired and not e.sosExpirySent and me and (mine or standInDue(e,at)) then
    e.sosExpirySent=true;changed=true
    e.status='RESOLVED';e.revision=(e.revision or 0)+1;e.modifiedAt=at+SOS_LIFETIME
    e.updated=K.Now();e.updatedBy=UnitName('player')
    sendFirst(e,function()
     K.Send('STATUS','CTA,'..e.id..',RESOLVED')
     if K.Sync then K.Sync.Broadcast('CTA',e) end
    end)
    if mine and K.InstanceAlerts and K.InstanceAlerts.Allowed() then K.Say('Your backup request expired after 10 minutes.') end
   end
  end
 end
 expiring=false
 if changed then
  if K.UI and K.UI.Refresh then K.UI.Refresh() end
  refreshPages()
 end
end
function O.UpdateSOS(e,zone,horde,alliance,objective,notes)
 local function blank(v) return v==nil or v=='' end
 local h,a=tonumber(horde),tonumber(alliance)
 if not (blank(horde) and blank(alliance)) then
  if not h or not a or h<0 or a<0 or h>999 or a>999 or h~=math.floor(h) or a~=math.floor(a) then
   K.Say('Leave both enemy counts blank, or enter both from 0 to 999.');return end
 end
 zone=K.Clean(zone,34);notes=K.Clean(notes,28)
 if zone=='' then K.Say('Zone is required.');return end
 local extra=tostring(objective or '')
 local from,to=extra:find(SOS_MARK,1,true)
 if from then extra=extra:sub(1,from-1)..extra:sub(to+1) end
 extra=extra:match('^[%s:%-]*(.-)%s*$')
 local goal=K.Clean(SOS_MARK..(extra~='' and (': '..extra) or ''),55)
 local coords=e.details and e.details.coords or tostring(e.text):match('(%d+%.%d, %d+%.%d)') or ''
 e.sos=true
 e.details={zone=zone,objective=goal,priority='URGENT',urgent=true,notes=notes,coords=coords,horde=h,alliance=a}
 e.text=K.Clean('[URGENT] '..zone..' - '..goal..(coords~='' and (' - '..coords) or '')..(h and (' - H:A '..h..':'..a) or '')..(notes~='' and (' - '..notes) or ''),165)
 e.revision=(e.revision or 0)+1;e.updated=K.Now();e.updatedBy=UnitName('player')
 e.modifiedAt=time()
 sendFirst(e,function() syncUpdate('CTA',e) end)
 K.Log('CTA','Updated '..e.id);K.UI.Refresh()
end
local ticker,sinceTick,sinceShown=CreateFrame('Frame'),0,0
ticker:SetScript('OnUpdate',function(_,elapsed)
 sinceTick=sinceTick+(elapsed or 0);sinceShown=sinceShown+(elapsed or 0)
 if sinceTick<1 then return end
 sinceTick=0
 O.ExpireSOS()
 -- Keeps the remaining time on screen current while a request is running.
 if sinceShown>=15 then
  sinceShown=0
  for _,e in ipairs(KWCDB and KWCDB.ops or {}) do
   if (e.status or 'ACTIVE')=='ACTIVE' and O.IsSOS(e) then refreshPages();break end
  end
 end
end)
-- Returns true and the new entry, or false and the reason (already announced).
function O.RequestBackup()
 local function refuse(reason) K.Say(reason);return false,reason end
 if not IsInGuild() or (K.GuildScope and not K.GuildScope()) then return refuse('Guild is not ready. Backup was not requested.') end
 local me=K.LocalGuildMember()
 if not me then return refuse('Guild roster verification is required to request backup.') end
 if not K.InstanceAlerts or K.InstanceAlerts.State()~='open' then return refuse('Backup requests are for the open world only.') end
 if O.ActiveSOS() then return refuse('You already have an active backup request. Resolve it first.') end
 local now=time()
 local latest=lastSOS
 for _,e in ipairs(KWCDB.ops or {}) do
  if mySOS(e,me) then latest=math.max(latest,tonumber(tostring(e.id):match('^(%d+)%-')) or 0) end
 end
 if now-latest<SOS_COOLDOWN then return refuse('Please wait '..(SOS_COOLDOWN-(now-latest))..' seconds before requesting backup again.') end
 -- Only what the client reports. No enemy counts are ever filled in.
 local ok,value=pcall(function() return GetRealZoneText and GetRealZoneText() end)
 local zone=ok and readableText(value,38) or nil
 if zone then zone=zone:gsub(';',' ') end
 local coords
 if zone and K.Geo then
  local map,x,y=K.Geo.PlayerPosition()
  if map then coords=K.Geo.Format(x,y) end
 end
 zone=zone or 'Unknown zone'
 local before=KWCDB.ops[1]
 local mark=K.Net.Mark()
 O.CreateCTA('[URGENT] '..zone..' - '..SOS_MARK..(coords and (' - '..coords) or ''),
  {zone=zone,objective=SOS_MARK,priority='URGENT',urgent=true,notes='',coords=coords or ''})
 local entry=KWCDB.ops[1]
 if not entry or entry==before or not O.IsSOS(entry) then return refuse('Backup request could not be created.') end
 entry.sos=true
 dispatch(entry.id,mark,true)
 lastSOS=now
 return true,entry
end
function O.AddBounty(text,details)
 if K.GuildScope and not K.GuildScope() then K.Say('Guild is not ready.');return false end
 if not IsInGuild() then K.Say('You must be in a guild.');return false end
 text=K.Clean(text,155)
 if text=='' then K.Say('Enter an enemy name.');return false end
 -- One active bounty per identical target/details: prevents repeat clicks or
 -- reopening the form from publishing duplicates (including after reload).
 local target=details and details.target and K.Clean(details.target,45):lower()
 for _,existing in ipairs(KWCDB.bounties or {}) do
  local other=existing.details and existing.details.target and K.Clean(existing.details.target,45):lower()
  if existing.status=='ACTIVE' and ((target and other==target) or (not target and existing.text==text)) then
   K.Say('Bounty already active for this target. Open the Bounty Board to edit it.')
   return false
  end
 end
 local id=tostring(time())..'-'..tostring(math.random(1000,9999))
 add(KWCDB.bounties,UnitName('player'),text,id)
 if details then KWCDB.bounties[1].details=details end
 if K.Sync then K.Sync.Broadcast('BOUNTY',KWCDB.bounties[1]) end
 K.Send('BOUNTY',id..':'..text)
 if KWCDB.settings.autoGuildReports then K.Say('Bounty ready: use Bounty Board > Guild report to prepare a chat draft.') end
 K.UI.Refresh()
 return true,id
end
function O.QuickCTA(zone,objective,urgent)
 zone=K.Clean(zone,45);objective=K.Clean(objective,90)
 if zone=='' or objective=='' then K.Say('Enter a zone and objective.');return end
 O.CreateCTA('['..(urgent and 'URGENT' or 'Normal')..'] '..zone..' - '..objective)
end
function O.DetailedCTA(zone,objective,horde,alliance,priority,coords,notes)
 zone=K.Clean(zone,38);objective=K.Clean(objective,55)
 local h=tonumber(horde);local a=tonumber(alliance)
 if zone=='' or objective=='' then K.Say('Location and objective required.');return end
 if not h or not a or h<0 or a<0 or h>999 or a>999 or h~=math.floor(h) or a~=math.floor(a) then
  K.Say('Enter valid Horde and Alliance counts (0-999).');return
 end
 priority=O.NormalizePriority(priority)
 coords=K.Clean(coords,18);notes=K.Clean(notes,35)
 local text='['..priority..'] '..zone..' | H:A '..h..':'..a..' | '..objective
 if coords~='' then text=text..' | '..coords end
 if notes~='' then text=text..' | '..notes end
 O.CreateCTA(text,{zone=zone,objective=objective,horde=h,alliance=a,priority=priority,urgent=priority=='URGENT',notes=notes,coords=coords})
end
function O.ShareDraft(entry,kind)
 if not entry or not entry.text then return end
 local text='[Keepers CTA] '..K.Clean(entry.text,165)
 if kind=='guild' then text='/g '..text end
 if ChatFrame_OpenChat then ChatFrame_OpenChat(text) else K.Say('Chat drafting unavailable on this client.') end
end
function O.QuickBounty(target,reason,reward)
 target=K.Clean(target,45);reason=K.Clean(reason,75);reward=K.Clean(reward,30)
 if target=='' then K.Say('Enter an enemy name.');return false end
 return O.AddBounty(target..(reason~='' and ' - '..reason or '')..(reward~='' and ' | Reward: '..reward or ''),{target=target,reason=reason,reward=reward,location=''})
end
local function findEntry(kind,id)
 local t=kind=='CTA' and KWCDB.ops or KWCDB.bounties
 for _,e in ipairs(t) do if e.id==id then return e end end
end
local function isOwner(e,sender)
 return K.SameGuildMember(e.author,sender)
end
local function canManage(e,sender)
 return isOwner(e,sender) or (K.IsSenderOfficer and K.IsSenderOfficer(sender))
end
function O.Edit(kind,id,newText)
 if K.GuildScope and not K.GuildScope() then return end
 if kind~='CTA' and kind~='BOUNTY' then return end
 local e=findEntry(kind,id)
 if not e then K.Say('Entry not found.');return end
 local who=K.CharacterDisplayName(UnitName('player'),true)
 if not (isOwner(e,who) or K.IsOfficer()) then K.Say('Only the poster or an officer can edit this entry.');return end
 newText=K.Clean(newText,155)
 if newText=='' then K.Say('Entry cannot be empty.');return end
 local sos=kind=='CTA' and O.IsSOS(e)
 if sos and not newText:find(SOS_MARK,1,true) then
  e.sos=true
  local zone=e.details and e.details.zone or tostring(e.text):match('^%[%a+%]%s*(.-)%s+%-%s') or 'Unknown zone'
  newText=K.Clean('[URGENT] '..zone..' - '..SOS_MARK..' - '..newText,155)
 end
 e.text=newText;e.updated=K.Now();e.updatedBy=who
 e.revision=(e.revision or 0)+1;e.modifiedAt=time()
 O.SendFirst(sos and e or nil,function() if K.Sync then K.Sync.Broadcast(kind,e) end end)
 K.Log(kind,'Edited entry '..id)
 K.UI.Refresh()
end
function O.ChangeStatus(kind,id,status)
 if K.GuildScope and not K.GuildScope() then return end
 local allowed={CTA={RESOLVED=true,CANCELLED=true,ACTIVE=true},BOUNTY={CANCELLED=true,ACTIVE=true,COMPLETED=true}}
 if not allowed[kind] or not allowed[kind][status] then return end
 local e=findEntry(kind,id)
 if not e then K.Say('Entry not found.');return end
 local who=K.CharacterDisplayName(UnitName('player'),true)
 if not (isOwner(e,who) or K.IsOfficer()) then K.Say('Only the poster or an officer can change this status.');return end
 if kind=='CTA' and status=='ACTIVE' and O.SOSRemaining(e)==0 then K.Say('That backup request has expired. Send a new one.');return end
 e.status=status;e.updated=K.Now();e.updatedBy=who;e.revision=(e.revision or 0)+1;e.modifiedAt=time()
 O.SendFirst(kind=='CTA' and e or nil,function()
  K.Send('STATUS',kind..','..id..','..status)
  if K.Sync then K.Sync.Broadcast(kind,e) end
 end)
 K.Log(kind,who..' changed '..id..' to '..status)
 K.UI.Refresh()
end
function O.Delete(kind,id)
 if K.GuildScope and not K.GuildScope() then return false,'Guild scope is not ready.' end
 if kind~='CTA' and kind~='BOUNTY' then return false,'Unsupported record kind.' end
 local e=findEntry(kind,id)
 if not e then local reason='Record ID '..tostring(id)..' is not present on the local board.';K.Say(reason);return false,reason end
 if not K.Sync or not K.Sync.Delete then local reason='Deletion synchronization module is unavailable.';K.Say(reason);return false,reason end
 local who=K.VerifiedDeletionActor(e.author)
 if not who then
  local reason='The current character is not verified as the creator or an authorized officer.'
  if K.DeletionAuthorization then local _,why=K.DeletionAuthorization(e.author);reason=why or reason end
  reason='Deletion authorization denied: '..tostring(reason);K.Say(reason);return false,reason
 end
 local ok,result=K.Sync.Delete(kind,e)
 if not ok then local reason='Deletion refused: '..tostring(result or 'unspecified validation failure');K.Say(reason);return false,reason end
 K.Log(kind,'Deleted '..id..' by '..who)
 K.Say(result or 'Record deleted locally. Guild sync will update online and offline members.')
 return true,result
end
function O.CanDelete(e)
 return e and K.VerifiedDeletionActor(e.author)~=nil or false
end
function O.DeletionDiagnostics(id)
 local function describe(kind,e)
  local d=K.Sync and K.Sync.DeletionDiagnostics and K.Sync.DeletionDiagnostics(kind,e) or {reason='Deletion sync diagnostics are unavailable.'}
  local auth=d.authorizationDetails or {}
  K.Say(('Delete diagnostic | %s | id=%s | author=%s'):format(kind,tostring(e and e.id),tostring(e and e.author)))
  K.Say(('Stored reference: %s | same-ID rows: %s | author conflict: %s | similar text, other IDs: %s | tombstone: %s'):format(tostring(d.storedReference),tostring(d.duplicates),tostring(d.authorConflict or false),tostring(d.similarTextOtherIDs or 0),d.tombstone and ('by '..tostring(d.tombstone.by)..' at '..tostring(d.tombstone.at)) or 'none'))
  K.Say(('Guild state=%s scope=%s local=%s GUID=%s roster rank=%s player rank=%s companion=%s companion rank=%s'):format(tostring(auth.state),tostring(auth.guild),tostring(auth.actor),tostring(auth.guid),tostring(auth.rank),tostring(auth.playerRank),tostring(auth.companionAuthorized),tostring(auth.companionRank)))
  K.Say(('Recorded author roster match=%s identity source=%s | transport guild/API/net/guard=%s/%s/%s/%s'):format(tostring(auth.authorRosterName),tostring(auth.identitySource),tostring(d.guildTransportReady),tostring(d.addonTransportReady),tostring(d.netSendReady),tostring(d.guardSupported)))
  K.Say(('Delete decision: %s'):format(tostring(d.reason)))
 end
 if not id and O.SelectedBountyID then id=O.SelectedBountyID() end
 if not id or id=='' then
  local allowed,why,auth=false,'Detailed authorization diagnostic unavailable.',nil
  if K.DeletionAuthorization then allowed,why,auth=K.DeletionAuthorization(nil) end
  K.Say(('Deletion identity check | guild=%s state=%s local=%s GUID=%s rank=%s companion=%s: %s'):format(tostring(auth and auth.guild),tostring(auth and auth.state),tostring(auth and auth.actor),tostring(auth and auth.guid),tostring(auth and auth.rank),tostring(auth and auth.companionAuthorized),tostring(why)))
  K.Say('Select a bounty in the War Room, then run /kt deletediag; or pass the exact bounty ID.')
  return 0
 end
 local found=0
 for _,e in ipairs(KWCDB and KWCDB.bounties or {}) do
  if e.id==id then describe('BOUNTY',e);found=found+1 end
 end
 if found==0 then K.Say('Delete diagnostic: no local bounty matched exact ID '..tostring(id)) end
 return found
end
function O.RememberClaim(e,who,stamp)
 local identity=K.CurrentGuildMember(who)
 if not identity then return false end
 e.claims=e.claims or {}
 e.claimTimes=e.claimTimes or {}
 if e.claimTimes[identity] and e.claimTimes[identity]<=stamp then return false end
 for prior in pairs(e.claims) do
  if K.SameGuildMember(prior,identity) then e.claims[prior]=nil end
 end
 e.claimTimes[identity]=stamp
 e.claims[identity]=date('%Y-%m-%d %H:%M',stamp)
 return true
end
function O.ClaimBounty(id)
 if K.GuildScope and not K.GuildScope() then return end
 local e=findEntry('BOUNTY',id);if not e or (e.status and e.status~='ACTIVE') then return end
 local who=UnitName('player') or '?'
 local stamp=time()
 if not O.RememberClaim(e,who,stamp) then return end
 if K.Sync then K.Sync.BroadcastBountyActivity(e,'L',who,stamp) end
 K.Send('CLAIM',id..','..who)
 K.Say('Claim submitted. Poster or officer must confirm completion.')
 K.UI.Refresh()
end
-- Preserve the counts, while visually identifying which faction has the advantage.
function O.FactionText(e)
 local raw=tostring(e and e.text or '')
 local d=e and e.details
 local h,a=d and tonumber(d.horde),d and tonumber(d.alliance)
 if not h or not a then
  local x,y=raw:match('H:(%d+)%s+A:(%d+)')
  if x then h,a=tonumber(x),tonumber(y) end
 end
 if not h or not a then return raw end
 raw=raw:gsub('H:%d+%s+A:%d+','H:A '..h..':'..a)
 raw=raw:gsub('H:A%s+%d+:%d+','H:A '..h..':'..a)
 local color=h>a and 'ffff5555' or a>h and 'ff5599ff' or 'ffb9c2cc'
 return raw:gsub('H:A '..h..':'..a,'|c'..color..'H:A '..h..':'..a..'|r',1)
end
function O.ApplyResponse(entry,who,status,revision)
 if status~='Coming' and status~='Maybe' and status~='Busy' then return false end
 local id=entry.id
 local identity=K.CurrentGuildMember(who)
 if not identity then return false end
 local responses=KWCDB.responses[id] or {}
 local versions=entry.responseRevisions or {}
 local previous=versions[identity]
 if previous and (not revision or revision<previous or
  (revision==previous and status<=(responses[identity] or ''))) then return false end
 KWCDB.responses[id]=responses
 for prior in pairs(responses) do
  if prior~=identity and K.SameGuildMember(prior,identity) then responses[prior]=nil end
 end
 responses[identity]=status
 versions[identity]=revision
 entry.responseRevisions=versions
 return true
end
function O.Respond(id,status)
 if K.GuildScope and not K.GuildScope() then return end
 if not id or (status~='Coming' and status~='Maybe' and status~='Busy') then return end
 O.ExpireSOS()
 local entry=findEntry('CTA',id)
 if not entry or (entry.status or 'ACTIVE')~='ACTIVE' then return end
 local who=K.LocalGuildMember()
 if not who then return end
 local revision=math.max(time(),((entry.responseRevisions or {})[who] or 0)+1)
 if not O.ApplyResponse(entry,who,status,revision) then return end
 O.SendFirst(entry,function()
  if K.Sync then K.Sync.BroadcastResponse(entry,who,status,revision) end
  K.Send('RESPONSE',id..':'..status)
 end)
 K.Say('CTA response saved: '..status..'. Guild broadcast attempted.');K.UI.Refresh()
end
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~='KWC3' or channel~='GUILD' or type(msg)~='string' or type(sender)~='string' then return end
 -- Guild addon channel already restricts delivery to guild; roster cache may be stale on login.
 if #msg>250 or not K.IsMember(sender) then return end
 local version,kind,payload=msg:match('^(%d+);([A-Z]+);(.+)$');if version~='2' then return end
 if kind=='SYNC' then if payload=='REQ' then replySnapshot() end;return end
 local id,body=payload:match('^([^:]+):(.+)$');if kind~='STATUS' and kind~='CLAIM' and kind~='UPDATE' and (not id or not body) then return end
 if kind=='SIGHT' then
  if not K.GuildScope() then return end
  local e=findEntry('BOUNTY',id)
  if e and (e.status or 'ACTIVE')=='ACTIVE' then
   local zone,note=body:match('^([^,]*),(.*)$')
   if zone and zone~='' then
    zone,note=K.Clean(zone,38),K.Clean(note,50)
    if not O.RememberSighting(e,sender,zone,note) then return end
    O.AnnounceSighting(e,sender,zone,note,true)
   end
  end
  K.UI.Refresh();return
 elseif kind=='UPDATE' then
  local k,entryId,rev,description=payload:match('^([A-Z]+),([^,]+),(%d+),(.+)$')
  -- Lua patterns lack alternation, so parse then validate the kind.
  if not k then k,entryId,rev,description=payload:match('^([A-Z]+),([^,]+),(%d+),(.+)$') end
  local e=(k=='CTA' or k=='BOUNTY') and findEntry(k,entryId)
  if e and not e.boardVersioned and canManage(e,sender) and tonumber(rev)>(e.revision or 0) then
   e.text=K.Clean(description,155);e.revision=tonumber(rev);e.updated=K.Now();e.updatedBy=sender
  end
  K.UI.Refresh();return
 elseif kind=='EDIT' then
  local k,entryId= id:match('^([A-Z]+),(.+)$')
  local e=(k=='CTA' or k=='BOUNTY') and findEntry(k,entryId)
  if e and not e.boardVersioned and canManage(e,sender) and body~='' then
   e.text=K.Clean(body,155);e.updated=K.Now();e.updatedBy=sender
   K.UI.Refresh()
  end
  return
 elseif kind=='STATUS' then
  local k,entryId,status=payload:match('^([A-Z]+),([^,]+),([A-Z]+)$')
  local allowed={CTA={RESOLVED=true,CANCELLED=true,ACTIVE=true},BOUNTY={COMPLETED=true,CANCELLED=true,ACTIVE=true}}
  local e=(allowed[k] and allowed[k][status]) and findEntry(k,entryId)
  if e and not e.boardVersioned and canManage(e,sender) then e.status=status;e.updated=K.Now();e.updatedBy=sender end
  K.UI.Refresh();return
 elseif kind=='CLAIM' then
  local entryId,claimant=payload:match('^([^,]+),([^,]+)$')
  local e=findEntry('BOUNTY',entryId)
  if e and (e.status or 'ACTIVE')=='ACTIVE' and claimant and K.SameGuildMember(claimant,sender) then
   O.RememberClaim(e,claimant,time())
  end
  K.UI.Refresh();return
 elseif kind=='RESPONSE' then
  local entry=findEntry('CTA',id)
  if not entry or (entry.status or 'ACTIVE')~='ACTIVE' then return end
  if body~='Coming' and body~='Busy' and body~='Maybe' then return end
  if not O.ApplyResponse(entry,sender,body) then return end
 elseif (kind=='CTA' or kind=='BOUNTY') then
  local created=add(kind=='CTA' and KWCDB.ops or KWCDB.bounties,sender,body,id);if not created then return end;K.Log(kind,'From '..sender..': '..body)
  local lapsed=kind=='CTA' and O.SOSRemaining(created)==0
  if lapsed then O.ExpireSOS() end
  if kind=='CTA' and not lapsed and KWCDB.settings.alerts~=false and alertsAllowed() then K.Say('CALL TO ARMS: '..body) end
 end
 K.UI.Refresh()
end)
