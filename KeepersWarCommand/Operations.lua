local K=KWC;local O={};K.Operations=O
local function add(t,author,body,id)
 for _,e in ipairs(t) do if e.id==id then return e end end
 local kind=t==KWCDB.ops and 'C' or 'B'
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
   K.Send(kind,e.id..':'..K.Clean(e.text,155))
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
 K.Say(tostring(sender)..' requested active '..(kind=='CTA' and 'CTAs' or 'bounties')..'. Open the '..(kind=='CTA' and 'CTA' or 'Bounty')..' Board and use Report Active to Guild, then press Enter.')
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
 local e=get('CTA',id)
 if not ownerOrOfficer(e) then K.Say('Only the poster or an officer may edit.');return end
 local h,a=tonumber(horde),tonumber(alliance)
 if not h or not a or h<0 or a<0 or h>999 or a>999 or h~=math.floor(h) or a~=math.floor(a) then K.Say('Enter Horde and Alliance counts from 0 to 999.');return end
 zone=K.Clean(zone,34);objective=K.Clean(objective,54);notes=K.Clean(notes,28)
 if zone=='' or objective=='' then K.Say('Zone and objective are required.');return end
 local level=O.NormalizePriority(priority)
 e.details={zone=zone,horde=h,alliance=a,objective=objective,priority=level,urgent=level=='URGENT',notes=notes}
 e.text='['..level..'] '..zone..' | H:'..h..' A:'..a..' | '..objective..(notes~='' and ' | '..notes or '')
 e.revision=(e.revision or 0)+1;e.updated=K.Now();e.updatedBy=UnitName('player')
 e.modifiedAt=time();syncUpdate('CTA',e);K.Log('CTA','Updated '..e.id);K.UI.Refresh()
end
-- DEV8: independent command seats. Concurrent officer claims are additive.
local function key(name) return tostring(name or ''):lower():match('^[^-]+') end
function O.Commanders(e)
 if not e then return {} end
 local seats=e.commandSeats
 if type(seats)~='table' then return {e.commander or e.author} end
 local names={};for name,active in pairs(seats) do if active then names[#names+1]=name end end
 table.sort(names);return names
end
function O.Commander(e) return table.concat(O.Commanders(e),', ') end
function O.IsCommander(e,name)
 for _,v in ipairs(O.Commanders(e)) do if key(v)==key(name) then return true end end
 return false
end
function O.CanAssumeCommand(e)
 return e and (e.status or 'ACTIVE')=='ACTIVE' and K.IsOfficer() and not O.IsCommander(e,UnitName('player'))
end
function O.ApplyCommandEvent(e,event)
 if not e or not event or not event.id or not event.actor then return false end
 e.commandEvents=e.commandEvents or {}
 if e.commandEvents[event.id] then return false end
 local typ=event.type;local actor=event.actor;local target=event.target
 if typ=='A' then
  if not (K.IsSenderOfficer and K.IsSenderOfficer(actor)) then return false end
 elseif typ=='L' then
  if not O.IsCommander(e,actor) or not target or target=='' then return false end
 elseif typ=='P' then
  if not target or not O.IsCommander(e,target) then return false end
  if key(actor)~=key((e.lieutenants or {})[target]) then return false end
  -- Replay is based on the event chain, not today's online status.
  -- Live generation of P still requires confirmed offline in TrySuccession.
 elseif typ=='R' then
  if not O.IsCommander(e,actor) or not target or target=='' then return false end
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
 local e=get('BOUNTY',id)
 if not ownerOrOfficer(e) then K.Say('Only the poster or an officer may edit.');return end
 target=K.Clean(target,36);location=K.Clean(location,35);reason=K.Clean(reason,48);reward=K.Clean(reward,25)
 if target=='' then K.Say('Target name is required.');return end
 e.details={target=target,location=location,reason=reason,reward=reward}
 e.text=target..(location~='' and ' @ '..location or '')..(reason~='' and ' - '..reason or '')..(reward~='' and ' | Reward: '..reward or '')
 e.revision=(e.revision or 0)+1;e.updated=K.Now();e.updatedBy=UnitName('player')
 e.modifiedAt=time();syncUpdate('BOUNTY',e);K.Log('BOUNTY','Updated '..e.id);K.UI.Refresh()
end
function O.AddSighting(id,zone,note)
 local e=get('BOUNTY',id)
 if not e or (e.status or 'ACTIVE')~='ACTIVE' then K.Say('Active bounty not found.');return end
 zone=K.Clean(zone,38);note=K.Clean(note,50)
 if zone=='' then K.Say('Location required.');return end
 local who=UnitName('player') or '?'
 e.sightings=e.sightings or {}
 table.insert(e.sightings,1,{who=who,zone=zone,note=note,at=K.Now()})
 while #e.sightings>15 do table.remove(e.sightings) end
 K.Send('SIGHT',id..':'..zone..','..note)
 K.Log('SIGHTING',who..' saw '..(e.details and e.details.target or e.text)..' at '..zone)
 K.UI.Refresh()
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
 if not IsInGuild() then K.Say('You must be in a guild.');return end
 text=K.Clean(text,155);if text=='' then K.Say('Usage: /kt cta Hillsbrad - Defend Tarren Mill');return end
 local id=tostring(time())..'-'..tostring(math.random(1000,9999));add(KWCDB.ops,UnitName('player'),text,id)
 KWCDB.ops[1].commander=UnitName('player');KWCDB.ops[1].lieutenant=nil
 if details then KWCDB.ops[1].details=details end
 if K.Sync then K.Sync.Broadcast('CTA',KWCDB.ops[1]) end
 K.Send('CTA',id..':'..text);if KWCDB.settings.autoGuildReports then K.Say('CTA ready: use CTA Board > Guild report to prepare a chat draft.') end;K.Log('CTA',text);K.Say('CTA published locally and broadcast attempted.');K.UI.Refresh()
end
function O.AddBounty(text,details)
 if not IsInGuild() then K.Say('You must be in a guild.');return end
 text=K.Clean(text,155);if text=='' then return end
 local id=tostring(time())..'-'..tostring(math.random(1000,9999));add(KWCDB.bounties,UnitName('player'),text,id);if details then KWCDB.bounties[1].details=details end;if K.Sync then K.Sync.Broadcast('BOUNTY',KWCDB.bounties[1]) end;K.Send('BOUNTY',id..':'..text);if KWCDB.settings.autoGuildReports then K.Say('Bounty ready: use Bounty Board > Guild report to prepare a chat draft.') end;K.UI.Refresh()
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
 local text='['..priority..'] '..zone..' | H:'..h..' A:'..a..' | '..objective
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
 if target=='' then K.Say('Enter an enemy name.');return end
 O.AddBounty(target..(reason~='' and ' - '..reason or '')..(reward~='' and ' | Reward: '..reward or ''),{target=target,reason=reason,reward=reward,location=''})
end
local function findEntry(kind,id)
 local t=kind=='CTA' and KWCDB.ops or KWCDB.bounties
 for _,e in ipairs(t) do if e.id==id then return e end end
end
local function isOwner(e,sender)
 local a=tostring(e.author or ''):lower():match('^[^-]+')
 local b=tostring(sender or ''):lower():match('^[^-]+')
 return a==b
end
local function canManage(e,sender)
 return isOwner(e,sender) or (K.IsSenderOfficer and K.IsSenderOfficer(sender))
end
function O.Edit(kind,id,newText)
 if kind~='CTA' and kind~='BOUNTY' then return end
 local e=findEntry(kind,id)
 if not e then K.Say('Entry not found.');return end
 local who=UnitName('player')
 if not (isOwner(e,who) or K.IsOfficer()) then K.Say('Only the poster or an officer can edit this entry.');return end
 newText=K.Clean(newText,155)
 if newText=='' then K.Say('Entry cannot be empty.');return end
 e.text=newText;e.updated=K.Now();e.updatedBy=who
 e.revision=(e.revision or 0)+1;e.modifiedAt=time()
 if K.Sync then K.Sync.Broadcast(kind,e) end
 K.Log(kind,'Edited entry '..id)
 K.UI.Refresh()
end
function O.ChangeStatus(kind,id,status)
 local allowed={CTA={RESOLVED=true,CANCELLED=true,ACTIVE=true},BOUNTY={CANCELLED=true,ACTIVE=true,COMPLETED=true}}
 if not allowed[kind] or not allowed[kind][status] then return end
 local e=findEntry(kind,id)
 if not e then K.Say('Entry not found.');return end
 local who=UnitName('player')
 if not (isOwner(e,who) or K.IsOfficer()) then K.Say('Only the poster or an officer can change this status.');return end
 e.status=status;e.updated=K.Now();e.updatedBy=who;e.revision=(e.revision or 0)+1;e.modifiedAt=time()
 K.Send('STATUS',kind..','..id..','..status)
 if K.Sync then K.Sync.Broadcast(kind,e) end
 K.Log(kind,who..' changed '..id..' to '..status)
 K.UI.Refresh()
end
function O.Delete(kind,id)
 if kind~='CTA' and kind~='BOUNTY' then return false end
 local e=findEntry(kind,id)
 if not e then K.Say('Entry not found.');return false end
 local who=UnitName('player') or ''
 if not canManage(e,who) then K.Say('Only the creator, War Council, or Warchief may delete this record.');return false end
 if not K.Sync or not K.Sync.Delete then K.Say('Deletion sync unavailable.');return false end
 if not K.Sync.Delete(kind,e) then K.Say('Deletion failed.');return false end
 K.Log(kind,'Deleted '..id..' by '..who)
 K.Say('Record deleted locally. Guild deletion sent; offline members update after sync.')
 return true
end
function O.CanDelete(e)
 return e and canManage(e,UnitName('player') or '') or false
end
function O.ClaimBounty(id)
 local e=findEntry('BOUNTY',id);if not e or (e.status and e.status~='ACTIVE') then return end
 local who=UnitName('player') or '?'
 e.claims=e.claims or {};e.claims[who]=K.Now()
 K.Send('CLAIM',id..','..who)
 K.Say('Claim submitted. Poster or officer must confirm completion.')
 K.UI.Refresh()
end
function O.Respond(id,status)
 if not id or (status~='Coming' and status~='Maybe' and status~='Busy') then return end
 local who=UnitName('player') or '?';KWCDB.responses[id]=KWCDB.responses[id] or {};KWCDB.responses[id][who]=status
 K.Send('RESPONSE',id..':'..status);K.Say('CTA response saved: '..status..'. Guild broadcast attempted.');K.UI.Refresh()
end
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~='KWC3' or channel~='GUILD' or type(msg)~='string' or type(sender)~='string' then return end
 -- Guild addon channel already restricts delivery to guild; roster cache may be stale on login.
 if #msg>250 then return end
 local version,kind,payload=msg:match('^(%d+);([A-Z]+);(.+)$');if version~='2' then return end
 if kind=='SYNC' then if payload=='REQ' then replySnapshot() end;return end
 local id,body=payload:match('^([^:]+):(.+)$');if kind~='STATUS' and kind~='CLAIM' and kind~='UPDATE' and (not id or not body) then return end
 if kind=='SIGHT' then
  local e=findEntry('BOUNTY',id)
  if e and (e.status or 'ACTIVE')=='ACTIVE' then
   local zone,note=body:match('^([^,]*),(.*)$')
   if zone and zone~='' then
    e.sightings=e.sightings or {};table.insert(e.sightings,1,{who=sender,zone=K.Clean(zone,38),note=K.Clean(note,50),at=K.Now()})
    while #e.sightings>15 do table.remove(e.sightings) end
   end
  end
  K.UI.Refresh();return
 elseif kind=='UPDATE' then
  local k,entryId,rev,description=payload:match('^([A-Z]+),([^,]+),(%d+),(.+)$')
  -- Lua patterns lack alternation, so parse then validate the kind.
  if not k then k,entryId,rev,description=payload:match('^([A-Z]+),([^,]+),(%d+),(.+)$') end
  local e=(k=='CTA' or k=='BOUNTY') and findEntry(k,entryId)
  if e and canManage(e,sender) and tonumber(rev)>(e.revision or 0) then
   e.text=K.Clean(description,155);e.revision=tonumber(rev);e.updated=K.Now();e.updatedBy=sender
  end
  K.UI.Refresh();return
 elseif kind=='EDIT' then
  local k,entryId= id:match('^([A-Z]+),(.+)$')
  local e=(k=='CTA' or k=='BOUNTY') and findEntry(k,entryId)
  if e and canManage(e,sender) and body~='' then
   e.text=K.Clean(body,155);e.updated=K.Now();e.updatedBy=sender
   K.UI.Refresh()
  end
  return
 elseif kind=='STATUS' then
  local k,entryId,status=payload:match('^([A-Z]+),([^,]+),([A-Z]+)$')
  local allowed={CTA={RESOLVED=true,CANCELLED=true,ACTIVE=true},BOUNTY={COMPLETED=true,CANCELLED=true,ACTIVE=true}}
  local e=(allowed[k] and allowed[k][status]) and findEntry(k,entryId)
  if e and canManage(e,sender) then e.status=status;e.updated=K.Now();e.updatedBy=sender end
  K.UI.Refresh();return
 elseif kind=='CLAIM' then
  local entryId,claimant=payload:match('^([^,]+),([^,]+)$')
  local e=findEntry('BOUNTY',entryId)
  if e and (e.status or 'ACTIVE')=='ACTIVE' and claimant and claimant:lower()==sender:match('^[^-]+'):lower() then
   e.claims=e.claims or {};e.claims[claimant]=K.Now()
  end
  K.UI.Refresh();return
 elseif kind=='RESPONSE' then
  if body~='Coming' and body~='Busy' and body~='Maybe' then return end
  KWCDB.responses[id]=KWCDB.responses[id] or {};KWCDB.responses[id][sender]=body
 elseif (kind=='CTA' or kind=='BOUNTY') then
  local created=add(kind=='CTA' and KWCDB.ops or KWCDB.bounties,sender,body,id);if not created then return end;K.Log(kind,'From '..sender..': '..body)
  if kind=='CTA' and KWCDB.settings.alerts~=false then K.Say('CALL TO ARMS: '..body) end
 end
 K.UI.Refresh()
end)
