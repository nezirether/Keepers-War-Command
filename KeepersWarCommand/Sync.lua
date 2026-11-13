-- KWC4 snapshot protocol: addon-only guild communication, never public chat.
local K=KWC
local S={};K.Sync=S
local PREFIX='KWC4'
local DELETE_PREFIX='KWCDEL1'
local lastRequest=0
local lastReply={}
local recoveryRequest
local lastRecoveryReply=0
local lastRecoveryBy={}
local recoveryDatasets={}
function S.RegisterRecoveryDataset(tag,snapshot,apply)
 recoveryDatasets[tag]={snapshot=snapshot,apply=apply}
end
local snapshotCursor=1
local tombstoneCursor=1
local autoStarted=false
local pendingLogin=false
local nextAuto=0
local health={requests=0,received=0,applied=0,rejected=0,sent=0,oversize=0,pending=0,peers={},lastRequest=0,lastReceived=0}
local boardStats={CTA={sent=0,received=0,applied=0,rejected=0},Bounty={sent=0,received=0,applied=0,rejected=0}}
function S.BoardDiagnostics() return boardStats end
function S.Health() return health end
local outcomes={}
local recent={}
function S.RecordOutcome(protocol,reason)
 local counts=outcomes[protocol] or {}
 outcomes[protocol]=counts
 counts[reason]=(counts[reason] or 0)+1
 recent[#recent+1]={protocol=protocol,reason=reason,at=time()}
 if #recent>24 then table.remove(recent,1) end
end
function S.Outcomes() return outcomes,recent end

local function fullSender(sender)
 return tostring(sender or ''):lower():match('^[^-]+')
end
local function peerSeen(sender)
 local name=K.CurrentGuildMember(sender)
 if not name or name=='' then return end
 local p=health.peers[name] or {received=0}
 p.lastSeen=time();p.received=p.received+1
 health.peers[name]=p
end
local function encode(s)
 return tostring(s or ''):gsub('%%','%%25'):gsub('|','%%7C'):gsub('[\r\n]',' ')
end
local function decode(s)
 return tostring(s or ''):gsub('%%7[Cc]','|'):gsub('%%25','%%')
end
local function send(msg)
 if not IsInGuild() or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
 if #msg>225 then health.oversize=health.oversize+1;return false end
 local success=K.Net.Send(PREFIX,msg,'GUILD')
 if success then health.sent=health.sent+1 end
 return success
end
local function tombstones()
 KWCDB.deletions=KWCDB.deletions or {}
 return KWCDB.deletions
end
local function deleted(kind,id)
 return tombstones()[kind..':'..id]
end
local function deleteClaim(kind,id,author,value)
 local identity=K.CurrentGuildMember(author)
 if not identity then return end
 local key=kind..':'..id..':'..identity
 KWCDB.boardDeleteClaims=KWCDB.boardDeleteClaims or {}
 local claims=KWCDB.boardDeleteClaims
 if value and (not claims[key] or value.at>claims[key].at) then
  value.kind,value.id=kind,id
  claims[key]=value
 end
 return claims[key]
end
local function removeLocal(kind,id)
 local t=kind=='C' and KWCDB.ops or KWCDB.bounties
 for i=#t,1,-1 do if t[i].id==id then table.remove(t,i) end end
 if kind=='C' then KWCDB.responses[id]=nil end
end
local function list(kind)
 return kind=='C' and KWCDB.ops or KWCDB.bounties
end
local function authorized(e,sender)
 if not e then return false end
 return K.SameGuildMember(e.author,sender) or (K.IsSenderOfficer and K.IsSenderOfficer(sender))
end
local function record(kind,e)
 -- 210 byte budget: ID, author, state, revision, timestamp, text.
 local data={kind,encode(e.id),encode(e.author),encode(e.status or 'ACTIVE'),tostring(e.revision or 0),tostring(e.modifiedAt or e.created or 0),encode(e.text)}
 local header=table.concat(data,'|')
 if #header>210 then
  data[7]=encode(tostring(e.text or ''):sub(1,math.max(10,210-(#header-#data[7]))))
 end
 return table.concat(data,'|')
end
local replayPendingEvents
local function apply(sender,msg,recovered)
 local category=msg:sub(1,1)=='C' and boardStats.CTA or msg:sub(1,1)=='B' and boardStats.Bounty
 if category then category.received=category.received+1 end
 local kind,id,author,status,rev,modified,description=msg:match('^([CB])|([^|]+)|([^|]+)|([^|]+)|(%d+)|(%d+)|(.+)$')
 if not kind then S.RecordOutcome(PREFIX,'Invalid board snapshot');health.rejected=health.rejected+1;if category then category.rejected=category.rejected+1 end;return end
 id=decode(id);author=decode(author);status=decode(status);description=decode(description)
 if #id>75 or #author>90 or #description>165 or id:find('[%c|]') or description:find('[%c]') then return end
 if recovered and (description:find('|[cCrRhHtTaA]') or not K.IsMember(author)) then return end
 if deleted(kind,id) or deleteClaim(kind,id,author) then S.RecordOutcome(PREFIX,'Record already deleted');return end
 if status~='ACTIVE' and status~='CANCELLED' and status~='COMPLETED' and status~='RESOLVED' then return end
 if (kind=='C' and status=='COMPLETED') or (kind=='B' and status=='RESOLVED') then return end
 rev=tonumber(rev);modified=tonumber(modified)
 if not rev or not modified or rev>1000000 or modified>time()+300 or modified<1500000000 then health.rejected=health.rejected+1;return end
 if not (K.IsMember and K.IsMember(sender)) then health.rejected=health.rejected+1;return end
 local t=list(kind)
 local existing
 for _,e in ipairs(t) do if e.id==id then existing=e;break end end
 if existing then
  -- Only accept a newer state from the original author or a known officer.
  if not authorized(existing,sender) then S.RecordOutcome(PREFIX,'Unauthorized board edit');return end
  if not K.SameGuildMember(existing.author,author) then return end
  local oldRev=existing.revision or 0
  local oldTime=existing.modifiedAt or existing.created or 0
  if rev<oldRev then S.RecordOutcome(PREFIX,'Stale revision');return end
  if existing.boardVersioned and rev==oldRev then
   if modified<oldTime then S.RecordOutcome(PREFIX,'Stale revision');return end
   if modified==oldTime then
    -- Fixed ordering for same-second revisions from authorized editors.
    local incoming=status..'|'..description
    local prior=(existing.status or 'ACTIVE')..'|'..(existing.text or '')
    if incoming<prior or (incoming==prior and not (existing.recoveredOnly and not recovered and K.SameGuildMember(sender,author))) then
     S.RecordOutcome(PREFIX,incoming==prior and 'Duplicate record' or 'Superseded record');return
    end
   end
  end
  existing.status=status;existing.text=description;existing.revision=rev
  existing.modifiedAt=modified;existing.updatedBy=sender;existing.boardVersioned=true
 else
  -- Unknown records must come from their claimed author. A guild peer
  -- cannot assert ownership on behalf of an absent character.
  if not recovered and not K.SameGuildMember(sender,author) then S.RecordOutcome(PREFIX,'Missing record provenance');health.rejected=health.rejected+1;return end
  table.insert(t,1,{id=id,author=author,status=status,text=description,revision=rev,created=modified,modifiedAt=modified,boardVersioned=true,time=K.Now(),relayedBy=recovered and sender or nil,recoveredOnly=recovered and true or nil})
  while #t>100 do table.remove(t) end
 end
 health.applied=health.applied+1
 if category then category.applied=category.applied+1 end
 if existing and recovered then existing.relayedBy=sender end
 if kind=='C' and not recovered then
  local e=existing or t[1]
  if K.SameGuildMember(sender,author) then e.recoveredOnly=nil end
  if S.ApplyPendingCommand then S.ApplyPendingCommand(e) end
  replayPendingEvents(e)
 end
 if K.UI and K.UI.Refresh then K.UI.Refresh() end
end
-- Independent command metadata protocol; keeps legacy CTA snapshots compatible.
-- Only a roster-verified officer can issue a transfer; no automatic takeover.
local function commandPacket(e)
 return 'T|'..encode(e.id)..'|'..tostring(e.commandRevision or 0)..'|'..tostring(e.commandAt or 0)..'|'..encode(e.commander or e.author)..'|'..encode(e.lieutenant or '')
end
function S.BroadcastCommand(e)
 if not e or not e.id then return false end
 return send(commandPacket(e))
end
local function applyCommand(sender,msg)
 local id,revision,stamp,commander,lieutenant=msg:match('^([^|]+)|(%d+)|(%d+)|([^|]+)|([^|]*)$')
 if not id then return end
 id=decode(id);commander=decode(commander);lieutenant=decode(lieutenant)
 if #id>75 or #commander>90 or #lieutenant>90 then return end
 if not K.SameGuildMember(sender,commander) then return end
 if not (K.IsSenderOfficer and K.IsSenderOfficer(sender)) then health.rejected=health.rejected+1;return end
 if deleted('C',id) then return end
 local entry
 for _,e in ipairs(KWCDB.ops or {}) do if e.id==id then entry=e;break end end
 if not entry then
  KWCDB.pendingCommand=KWCDB.pendingCommand or {}
  -- Cache only the newest pending transfer; do not let stale packets replace it.
  local prev=KWCDB.pendingCommand[id]
  local prevRev=prev and tonumber(prev.message:match('^[^|]+|(%d+)|')) or -1
  if tonumber(revision)>prevRev then KWCDB.pendingCommand[id]={sender=sender,message=msg} end
  return
 end
 if entry.recoveredOnly then return end
 local rev=tonumber(revision) or 0
 local old=tonumber(entry.commandRevision) or 0
 if (entry.status or 'ACTIVE')~='ACTIVE' then health.rejected=health.rejected+1;return end
 if entry.commandEvents and next(entry.commandEvents) then return end -- Never allow legacy T packets to overwrite DEV8 seats.
 if rev<=old or rev>1000000 then return end
 -- Every takeover appoints the actual previous commander as lieutenant.
 -- Reject invented lieutenants and skipped revisions, which could bypass
 -- the locally known chain of command.
 if rev~=old+1 or not K.SameGuildMember(lieutenant,entry.commander or entry.author) then
  health.rejected=health.rejected+1;return
 end
 local when=tonumber(stamp) or 0
 if when<=0 or when>time()+300 then health.rejected=health.rejected+1;return end
 entry.commander=commander;entry.lieutenant=lieutenant~='' and lieutenant or nil
 entry.commandRevision=rev;entry.commandAt=tonumber(stamp) or 0
 health.applied=health.applied+1
 if K.UI and K.UI.Refresh then K.UI.Refresh() end
end
function S.ApplyPendingCommand(e)
 if not e or not e.id or not KWCDB.pendingCommand then return end
 local pending=KWCDB.pendingCommand[e.id]
 if pending then KWCDB.pendingCommand[e.id]=nil;applyCommand(pending.sender,pending.message) end
end
-- DEV8 command events are individually idempotent. Concurrent officer claims
-- commute: two valid A events create two seats, regardless of arrival order.
function S.BroadcastCommandEvent(e,event)
 if not e or not event then return false end
 local packet=table.concat({'E',encode(e.id),encode(event.id),event.type,encode(event.actor),encode(event.target)},'|')
 return send(packet)
end
-- DEV11: bounded, deduplicated dependency queue. Do not allow the same
-- packet to consume the entire retry budget on every periodic reconciliation.
local function queueCommand(store,id,sender,msg,maxAttempts)
 store[id]=store[id] or {}
 local q=store[id]
 for _,item in ipairs(q) do
  if item.message==msg and item.sender==sender then return false end
 end
 if #q>=100 then health.rejected=health.rejected+1;return false end
 q[#q+1]={sender=sender,message=msg,attempts=maxAttempts or 0}
 return true
end
local function applyCommandEvent(sender,msg,attempts)
 local id,eventId,typ,actor,target=msg:match('^([^|]+)|([^|]+)|([ALPR])|([^|]+)|([^|]*)$')
 if not id then return end
 id=decode(id);eventId=decode(eventId);actor=decode(actor);target=decode(target)
 if #id>75 or #eventId>110 or #actor>90 or #target>90 then return end
 if not K.SameGuildMember(sender,actor) then health.rejected=health.rejected+1;return end
 if deleted('C',id) then return end
 local entry
 for _,e in ipairs(KWCDB.ops or {}) do if e.id==id then entry=e;break end end
 if entry and entry.recoveredOnly then return end
 if not entry then
  KWCDB.pendingCommandEvents=KWCDB.pendingCommandEvents or {}
  queueCommand(KWCDB.pendingCommandEvents,id,sender,msg,0)
  return
 end
 if (entry.status or 'ACTIVE')~='ACTIVE' then return end
 if typ=='A' and not (K.IsSenderOfficer and K.IsSenderOfficer(sender)) then health.rejected=health.rejected+1;return end
 if K.Operations and K.Operations.ApplyCommandEvent and K.Operations.ApplyCommandEvent(entry,{id=eventId,type=typ,actor=actor,target=target}) then
  health.applied=health.applied+1
  if K.UI then K.UI.Refresh() end
 else
  -- Dependency may not have arrived yet. Queue bounded retry rather than
  -- permanently dropping an out-of-order Lieutenant/Promotion event.
  KWCDB.deferredCommandEvents=KWCDB.deferredCommandEvents or {}
  if queueCommand(KWCDB.deferredCommandEvents,id,sender,msg,(attempts or 0)+1) then
   health.pending=health.pending+1
  end
 end
end
replayPendingEvents=function(e)
 local queues=KWCDB.pendingCommandEvents
 if not queues or not queues[e.id] then return end
 local events=queues[e.id];queues[e.id]=nil
 for _,v in ipairs(events) do applyCommandEvent(v.sender,v.message) end
end
local function retryDeferred()
 local all=KWCDB and KWCDB.deferredCommandEvents
 if not all then return end
 for id,queue in pairs(all) do
  all[id]=nil
  for _,item in ipairs(queue) do
   health.pending=math.max(0,health.pending-1)
   if (item.attempts or 0)<12 then
    applyCommandEvent(item.sender,item.message,item.attempts)
   else
    health.rejected=health.rejected+1
   end
  end
 end
end
-- Do not queue snapshots that current receivers must reject for lack of
-- authority. Authenticated peer relay requires a separate protocol decision.
local function recoveryEntries(sender)
 local entries={}
 for _,kind in ipairs({'C','B'}) do
  for _,e in ipairs(list(kind) or {}) do
   if e.id and e.text and not deleted(kind,e.id) and authorized(e,sender) then
    entries[#entries+1]={kind=kind,entry=e}
   end
  end
 end
 table.sort(entries,function(a,b)
  if tostring(a.entry.id)==tostring(b.entry.id) then return a.kind<b.kind end
  return tostring(a.entry.id)<tostring(b.entry.id)
 end)
 return entries
end
local function sendSnapshot()
 local guild=K.GuildScope()
 local sender=UnitName('player')
 local entries=recoveryEntries(sender)
 if #entries==0 then return end
 -- A response is bounded to 100 records, sent in 24-record bursts. The
 -- snapshot cursor rotates when a guild has more than 100 retained records.
 if snapshotCursor>#entries then snapshotCursor=1 end
 local total=math.min(#entries,100)
 local start=snapshotCursor
 snapshotCursor=((start+total-1)%#entries)+1
 for offset=0,total-1 do
  local item=entries[((start+offset-1)%#entries)+1]
  local function emit()
   if guild~=K.GuildScope() or not authorized(item.entry,sender) or deleted(item.kind,item.entry.id) then return end
   send('S|'..record(item.kind,item.entry))
   if item.kind=='C' then
    local events={}
    for _,ev in pairs(item.entry.commandEvents or {}) do
     if K.SameGuildMember(sender,ev.actor) then events[#events+1]=ev end
    end
    table.sort(events,function(a,b)
     local ta=tonumber(tostring(a.id):match(':(%d+):')) or 0
     local tb=tonumber(tostring(b.id):match(':(%d+):')) or 0
     if ta~=tb then return ta<tb end
     return tostring(a.id)<tostring(b.id)
    end)
    -- Pace event replay, too; each command event is an idempotent record.
    for j,ev in ipairs(events) do
     local function sendEvent() if guild==K.GuildScope() and K.SameGuildMember(sender,ev.actor) then S.BroadcastCommandEvent(item.entry,ev) end end
     if C_Timer and C_Timer.After then C_Timer.After((offset*0.20)+(j*0.05),sendEvent) else sendEvent() end
    end
    if not item.entry.commandEvents and (item.entry.commandRevision or 0)>0 then S.BroadcastCommand(item.entry) end
   end
  end
  if C_Timer and C_Timer.After then C_Timer.After(offset*0.20,emit) else emit() end
 end
end
-- Deletion tombstones are retained so old snapshots cannot resurrect removed entries.
-- Sender permissions are verified using the local guild roster, not message claims.
local function canDelete(sender,author)
 return K.SameGuildMember(sender,author) or (K.IsSenderOfficer and K.IsSenderOfficer(sender))
end
local function deletePacket(kind,id,author,stamp)
 return 'D|'..kind..'|'..encode(id)..'|'..encode(author)..'|'..tostring(stamp)
end
local function sendDelete(kind,id,author,stamp)
 return send(deletePacket(kind,id,author,stamp))
end
local function applyDelete(sender,kind,id,author,stamp,recovered)
 if (kind~='C' and kind~='B') or #id>75 or #author>90 or id:find('[%c|]') then return end
 local t=list(kind);local entry
 for _,e in ipairs(t) do if e.id==id then entry=e;break end end
 local old=deleted(kind,id)
 -- Do not allow a relayed deletion to claim a different author for a known entry.
 if entry and not K.SameGuildMember(entry.author,author) then return end
 if old and not K.SameGuildMember(old.author,author) then return end
 if not entry and not old and not recovered and (not K.GuildScope() or not K.SameGuildMember(sender,author)) then return end
 if not canDelete(sender,author) then S.RecordOutcome(PREFIX,'Unauthorized deletion');health.rejected=health.rejected+1;return end
 local current=old and (tonumber(old.at) or 0) or 0
 if stamp and stamp<=current then S.RecordOutcome(PREFIX,stamp==current and 'Duplicate deletion' or 'Stale deletion');return end
 if not stamp or stamp>time()+300 or stamp<1500000000 then health.rejected=health.rejected+1;return end
 local marker={author=author,at=stamp,by=sender}
 if not entry and not old then
  -- An unseen deletion is scoped to the asserted owner. It cannot reserve
  -- someone else's ID. Only the owner or a verified recovery officer can supply it.
  deleteClaim(kind,id,author,marker)
  return
 end
 tombstones()[kind..':'..id]=marker
 removeLocal(kind,id)
 health.applied=health.applied+1
 if K.UI and K.UI.Refresh then K.UI.Refresh() end
end
function S.Delete(kind,e)
 if not e or not e.id then return false end
 local code=kind=='CTA' and 'C' or kind=='BOUNTY' and 'B'
 if not code then return false end
 local sender=UnitName('player') or ''
 if not canDelete(sender,e.author) then return false end
 local stamp=time()
 tombstones()[code..':'..e.id]={author=e.author,at=stamp,by=sender}
 removeLocal(code,e.id)
 sendDelete(code,e.id,e.author,stamp)
 if K.UI and K.UI.Refresh then K.UI.Refresh() end
 return true
end
local function sendTombstones()
 local guild=K.GuildScope()
 local sender=UnitName('player')
 local entries={}
 for k,v in pairs(tombstones()) do
  local kind,id=k:match('^([CB]):(.+)$')
  if kind and id and v.author and v.at and canDelete(sender,v.author) then entries[#entries+1]={kind=kind,id=id,author=v.author,at=v.at} end
 end
 table.sort(entries,function(a,b)
  if a.at==b.at then return a.kind..a.id<b.kind..b.id end
  return a.at>b.at
 end)
 if #entries==0 then return end
 if tombstoneCursor>#entries then tombstoneCursor=1 end
 local total=math.min(#entries,200)
 local start=tombstoneCursor
 tombstoneCursor=((start+total-1)%#entries)+1
 for offset=0,total-1 do
  local e=entries[((start+offset-1)%#entries)+1]
  local function emit() if guild==K.GuildScope() and canDelete(sender,e.author) then sendDelete(e.kind,e.id,e.author,e.at) end end
  if C_Timer and C_Timer.After then C_Timer.After(offset*0.12,emit) else emit() end
 end
end
-- Request one bounded page from a roster-verified officer. Each retry
-- rotates to the next candidate; only the chosen officer can reply.
local recoveryCursor=0
local recoveryPages={}
local recoveryGuild
function S.RecoveryOfficers()
 local candidates={}
 if not GetNumGuildMembers or not GetGuildRosterInfo then return candidates end
 for i=1,GetNumGuildMembers() or 0 do
  local name,_,rank,_,_,_,_,_,online=GetGuildRosterInfo(i)
  if name and online and rank and rank<=1 and not K.SameGuildMember(name,K.LocalGuildMember()) then
   candidates[#candidates+1]=name
  end
 end
 table.sort(candidates)
 return candidates
end
local function requestRecovery(now)
 local guild=K.GuildScope()
 if not guild then return false end
 if recoveryGuild~=guild then recoveryGuild=guild;recoveryPages={};recoveryCursor=0 end
 local candidates=S.RecoveryOfficers()
 if #candidates==0 then return false end
 recoveryCursor=recoveryCursor+1
 local target=candidates[(recoveryCursor-1)%#candidates+1]
 local token=tostring(now)..'-'..tostring(math.random(100000,999999))
 local key=target
 local page=recoveryPages[key] or 0
 recoveryPages[key]=(page+1)%20
 recoveryRequest={target=target,token=token,expires=now+29,guild=guild}
 return K.Net.Send(PREFIX,'RQ|'..guild..'|'..token..'|'..page,'WHISPER',target,'ALERT')
end
local function onRecovery(msg,sender)
 local guild=K.GuildScope and K.GuildScope()
 if not guild then return end
 local now=time()
 local requestedGuild,token,page=msg:match('^RQ|(%d+)|(%d+%-%d+)|(%d%d?)$')
 if requestedGuild==guild and token and #token<=24 and tonumber(page)<20 then
  local peer=K.CurrentGuildMember(sender)
  if not peer or not K.IsSenderOfficer(K.LocalGuildMember()) or now-lastRecoveryReply<3 then return end
  for name,at in pairs(lastRecoveryBy) do
   if now-at>=30 then lastRecoveryBy[name]=nil end
  end
  if lastRecoveryBy[peer] then return end
  lastRecoveryBy[peer]=now
  lastRecoveryReply=now
  local entries=recoveryEntries(K.LocalGuildMember())
  local snapshots={}
  for _,item in ipairs(entries) do
   local e=item.entry
   if e.boardVersioned and not e.recoveredOnly then
    snapshots[#snapshots+1]='S|'..record(item.kind,e)
   end
  end
  local function sendPage(rows)
   local pages=math.ceil(#rows/12)
   if pages==0 then return end
   local first=(tonumber(page)%pages)*12+1
   for i=first,math.min(first+11,#rows) do
    K.Net.Send(PREFIX,'RS|'..guild..'|'..token..'|'..rows[i],'WHISPER',sender,'RECOVERY')
   end
  end
  local marks={}
  for key,marker in pairs(tombstones()) do
   if marker.author and marker.at then marks[#marks+1]=deletePacket(key:sub(1,1),key:sub(3),marker.author,marker.at) end
  end
  for key,marker in pairs(KWCDB.boardDeleteClaims or {}) do
   local kind,id=marker.kind,marker.id
   if not kind or not id then kind,id=key:match('^([CB]):(.-):[^:]+$') end
   if kind then marks[#marks+1]=deletePacket(kind,id,marker.author,marker.at) end
  end
  table.sort(marks)
  local extra={}
  for tag,dataset in pairs(recoveryDatasets) do
   for _,row in ipairs(dataset.snapshot(tonumber(page))) do extra[#extra+1]=tag..'|'..row end
  end
  -- Rotate which dataset gets first access to the shared recovery queue.
  local function sendExtra()
   for _,row in ipairs(extra) do
    K.Net.Send(PREFIX,'RS|'..guild..'|'..token..'|'..row,'WHISPER',sender,'RECOVERY')
   end
  end
  if tonumber(page)%2==0 then sendExtra() end
  sendPage(marks)
  sendPage(snapshots)
  if tonumber(page)%2==1 then sendExtra() end
  return
 end
 local responseGuild,response,snapshot=msg:match('^RS|(%d+)|(%d+%-%d+)|(.+)$')
 local request=recoveryRequest
 if responseGuild and responseGuild~=guild then S.RecordOutcome(PREFIX,'Guild mismatch');return end
 if responseGuild~=guild or not response or not request or response~=request.token or now>request.expires
  or request.guild~=guild or not K.SameGuildMember(sender,request.target)
  or not K.IsSenderOfficer(sender) then S.RecordOutcome(PREFIX,'Unverified recovery response');return end
 local tag,body=snapshot:match('^([A-Z]+)|(.+)$')
 if tag and recoveryDatasets[tag] then recoveryDatasets[tag].apply(body,sender);return end
 if snapshot:sub(1,2)=='S|' then apply(sender,snapshot:sub(3),true)
 else
  local kind,id,author,stamp=snapshot:match('^D|([CB])|([^|]+)|([^|]+)|(%d+)$')
  if kind then applyDelete(sender,kind,decode(id),decode(author),tonumber(stamp),true) end
 end
end
function S.IsBoardDeleted(kind,id,author) return deleted(kind,id) or deleteClaim(kind,id,author) end
function S.Request(silent)
 if not IsInGuild() then if not silent then K.Say('Guild membership required.') end;return end
 local now=time()
 if now-lastRequest<30 then if not silent then K.Say('Board sync cooldown: wait 30 seconds.') end;return false end
 lastRequest=now;health.lastRequest=now;health.requests=health.requests+1
 if requestRecovery(now) or (not (K.GuildScope and K.GuildScope()) and send('Q|'..tostring(now))) then if not silent then K.Say('Board sync requested. Other online members can reply with saved operations.') end;return true
 else if not silent then K.Say('Board sync request could not be sent.') end;return false end
end
-- Unified guild refresh: board records/tombstones plus current peer honor.
-- Each transport keeps its own cooldown; one failure must not block the other.
function S.RequestAll(silent)
 if not IsInGuild() then if not silent then K.Say('Guild membership required.') end;return false end
 if K.PvP and K.PvP.RefreshHonor then K.PvP.RefreshHonor() end
 local boards=S.Request(true)
 local honor=K.PvP and K.PvP.RequestGuildHonor and K.PvP.RequestGuildHonor(true)
 local raids=false
 if K.RaidSignup and K.RaidSignup.Sync and C_Timer and C_Timer.After then
  local guild=K.GuildScope()
  C_Timer.After(5,function() if guild==K.GuildScope() then K.RaidSignup.Sync(true) end end)
  raids=true
 end
 if not silent then
  if boards or honor or raids then K.Say('Guild sync requested: operations, deletions, honor and raid sign-ups. Online compatible clients respond automatically.')
  else K.Say('Guild sync is on cooldown (up to 30 seconds). Try again shortly.') end
 end
 return boards or honor or raids or false
end
function S.Broadcast(kind,e)
 if not e then return end
 e.boardVersioned=true
 local ok=send('S|'..record(kind=='CTA' and 'C' or 'B',e))
 local c=boardStats[kind=='CTA' and 'CTA' or 'Bounty'];if ok then c.sent=c.sent+1 end
 if kind=='CTA' then
  for _,event in pairs(e.commandEvents or {}) do S.BroadcastCommandEvent(e,event) end
 end
end
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~=PREFIX or (channel~='WHISPER' and channel~='GUILD') then return end
 if type(msg)~='string' or #msg>(channel=='GUILD' and 225 or 250) then S.RecordOutcome(PREFIX,'Invalid payload');return end
 if not K.GuildScope() then S.RecordOutcome(PREFIX,'Guild identity unavailable');return end
 if not K.IsMember(sender) then S.RecordOutcome(PREFIX,'Sender not verified');return end
 if channel=='WHISPER' then onRecovery(msg,sender);return end
 peerSeen(sender)
 health.received=health.received+1;health.lastReceived=time()
 if msg:sub(1,2)=='Q|' then
  S.RecordOutcome(PREFIX,'Request (no record change)')
  local me=UnitName and UnitName('player')
  if me and fullSender(sender)==fullSender(me) then return end
  local now=time();local who=fullSender(sender)
  if now-(lastReply[who] or 0)<45 then return end
  lastReply[who]=now
  -- Spread replies from large guilds to avoid a synchronized message burst.
  local delay=0.4+(math.random(0,30)/10)
  local guild=K.GuildScope()
  local function reply()
   if guild~=K.GuildScope() or not K.IsMember(sender) then return end
   sendTombstones();sendSnapshot()
  end
  if C_Timer and C_Timer.After then C_Timer.After(delay,reply) else reply() end
 elseif msg:sub(1,2)=='S|' then apply(sender,msg:sub(3))
 elseif msg:sub(1,2)=='T|' then applyCommand(sender,msg:sub(3))
 elseif msg:sub(1,2)=='E|' then applyCommandEvent(sender,msg:sub(3));retryDeferred()
 elseif msg:sub(1,2)=='D|' then
  local kind,id,author,stamp=msg:match('^D|([CB])|([^|]+)|([^|]+)|(%d+)$')
  if kind then applyDelete(sender,kind,decode(id),decode(author),tonumber(stamp)) else S.RecordOutcome(PREFIX,'Invalid deletion') end
 else S.RecordOutcome(PREFIX,'Unrecognized message type') end
end)

-- DEV5: unified automatic synchronization. All supported guild datasets travel via
-- the existing board snapshot/tombstone and honor request/reply protocols.
-- No public chat, no per-frame polling, and no requests when outside a guild.
local function autoRequest()
 if not KWCDB or not IsInGuild() then return false end
 if KWCDB.settings and KWCDB.settings.autoGuildSync==false then return false end
 -- Use the shared entry point so automatic and manual sync cannot drift apart.
 return S.RequestAll(true)
end
function S.OnWindowOpened()
 local now=time()
 if now<nextAuto then return end
 nextAuto=now+120
 autoRequest()
end
local function beginTimers()
 if autoStarted then return end
 autoStarted=true
 if C_Timer and C_Timer.NewTicker then
  C_Timer.NewTicker(15,retryDeferred)
  -- Five-minute reconciliation also catches missed messages / returning peers.
  C_Timer.NewTicker(300,autoRequest)
 end
end
local function afterLogin()
 if pendingLogin then return end
 pendingLogin=true
 beginTimers()
 if C_Timer and C_Timer.After then
  C_Timer.After(12,function() pendingLogin=false;autoRequest() end)
 else pendingLogin=false;autoRequest() end
end
K.On('PLAYER_ENTERING_WORLD',afterLogin)
K.On('PLAYER_GUILD_UPDATE',function()
 if IsInGuild() and C_Timer and C_Timer.After then C_Timer.After(8,autoRequest) end
end)
-- Roster changes are useful opportunities to reconcile newly-online members.
-- Throttled by existing board/honor request cooldowns and the 120s window.
K.On('GUILD_ROSTER_UPDATE',function()
 local now=time()
 if now<nextAuto then return end
 nextAuto=now+120
 if C_Timer and C_Timer.After then C_Timer.After(3,autoRequest) end
end)
function S.AutoSyncEnabled()
 return not (KWCDB and KWCDB.settings and KWCDB.settings.autoGuildSync==false)
end
function S.SetAutoSync(enabled)
 if not KWCDB then return end
 KWCDB.settings=KWCDB.settings or {}
 KWCDB.settings.autoGuildSync=enabled and true or false
 K.Say('Automatic guild synchronization '..(enabled and 'ON' or 'OFF')..'.')
 if enabled then autoRequest() end
end
