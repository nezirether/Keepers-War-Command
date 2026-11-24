-- DEV42: shared, conservative guild addon transport. No public chat messages.
local K=KWC
K.Net={}
local N=K.Net
local queue, pending={},{}
local nextSequence=0
local elapsed=0
local recoveryTurn=false
-- Replies to Raid Tools requests (opts.reply) are sent on every other turn ahead of
-- other traffic, so a requester's reply window cannot expire while a reply waits behind
-- an unrelated backlog. The other turns follow the usual order, so guild sync keeps at
-- least every second send while replies are queued; replies are bounded by their own
-- GROUP_PIECE_CAP budget.
local replyTurn=false
local sent,failed,dropped,lockdowns=0,0,0,0
local unavailable={}
-- Group traffic (items queued with an options table, for example Keepers Raid Tools)
-- is bounded separately so it can never starve guild sync. It has two budgets of
-- GROUP_PIECE_CAP pieces each: replies to requests (opts.reply) and all other group
-- traffic. A full send budget therefore never refuses a reply. In each budget, one
-- message larger than the cap (for example a long raid note) may be queued at a time,
-- outside the cap, so every message AceComm could send remains deliverable and an
-- oversized message never refuses ordinary sends.
local GROUP_PIECE_CAP=64
local GROUP_QUEUE_LIMIT=300
-- Item limits (QUEUE_LIMIT 350, GROUP_QUEUE_LIMIT 300, the RECOVERY 300 limit) count only
-- items that are not replies. Reply items (opts.reply) are held in a reserve outside
-- them, bounded by the reply budget (GROUP_PIECE_CAP ordinary pieces plus one oversized
-- item, so at most GROUP_PIECE_CAP+1 items). A guild backlog therefore never refuses a
-- reply, and queued replies never take room from guild sync. Total: at most 350+65 items.
local QUEUE_LIMIT=350
-- Completion callbacks kept per queued item. A duplicate send beyond the limit replaces
-- the newest callback, so the original and the latest caller are always notified.
local CALLBACK_LIMIT=4
-- Send result codes; literals are the fallback when Enum.SendAddonMessageResult is missing.
local function resultCode(name,alias,literal)
 local codes=Enum and Enum.SendAddonMessageResult
 return codes and (codes[name] or (alias and codes[alias])) or literal
end
-- Messaging lockdown (for example inside PvP matches and encounters) refuses every
-- addon message. It pauses the queue without spending attempts or dropping items.
local function inLockdown()
 if not C_ChatInfo or not C_ChatInfo.InChatMessagingLockdown then return false end
 local ok,locked=pcall(C_ChatInfo.InChatMessagingLockdown)
 if not ok or (issecretvalue and issecretvalue(locked)) then return false end
 return locked==true
end
local function key(prefix,msg,channel,target) return prefix..'\001'..channel..'\001'..(target or '')..'\001'..msg end
local function truthy(fn)
 if not fn then return false end
 local ok,value=pcall(fn)
 if not ok or (issecretvalue and issecretvalue(value)) then return false end
 return value~=nil and value~=false
end
local function inGroup() return truthy(IsInRaid) or truthy(IsInGroup) end
-- Group epoch: queued group traffic (broadcasts and group whispers) is bound to the group
-- it was queued in. The epoch moves whenever the player is seen entering or leaving a
-- group (GROUP_JOINED, GROUP_LEFT, GROUP_ROSTER_UPDATE, and each queue turn), so an item
-- queued in one raid is dropped instead of being sent to a raid joined later, even when
-- leave and join both happen while the item is held (for example by lockdown).
local groupEpoch,wasGrouped=0,nil
local function observeGroup()
 local now=inGroup()
 if wasGrouped~=nil and now~=wasGrouped then groupEpoch=groupEpoch+1 end
 wasGrouped=now
 return groupEpoch
end
-- Group event entry point (also used by headless tests, whose frames fire no events).
function N.GroupEvent(event)
 if event=='GROUP_JOINED' or event=='GROUP_LEFT' then groupEpoch=groupEpoch+1 end
 observeGroup()
end
-- Group broadcast channels. INSTANCE_CHAT reaches instance groups (for example
-- Raid Tools version queries in a dungeon finder group), whose members need not
-- share a guild. IsInGroup() without a category covers home and instance groups.
local GROUP_CHANNELS={PARTY=true,RAID=true,INSTANCE_CHAT=true}
-- Delivery-only group membership check for whispers to group members who may not be
-- in the guild. It grants no authority. Secret or ambiguous names fail closed.
-- Returns the unit and a lower-case Name-Realm key.
local function groupMember(target)
 if type(target)~='string' or target=='' or not inGroup() then return end
 local raid=truthy(IsInRaid)
 local wanted=target:lower()
 local qualified=wanted:find('-',1,true)~=nil
 local home=GetNormalizedRealmName and GetNormalizedRealmName()
 if issecretvalue and issecretvalue(home) then home=nil end
 local foundUnit,foundKey
 for i=1,raid and 40 or 4 do
  local unit=(raid and 'raid' or 'party')..i
  local name,realm
  if UnitFullName then name,realm=UnitFullName(unit) end
  if name==nil and UnitName then name,realm=UnitName(unit) end
  local secret=issecretvalue and (issecretvalue(name) or issecretvalue(realm))
  if not secret and type(name)=='string' and name~='' then
   local short=(name:match('^[^-]+') or name):lower()
   local full=name:lower()
   if not full:find('-',1,true) then
    local r=(type(realm)=='string' and realm~='' and realm) or (type(home)=='string' and home) or ''
    full=full..'-'..r:lower()
   end
   if (qualified and full==wanted) or (not qualified and short==wanted) then
    if foundUnit then return end
    foundUnit,foundKey=unit,full
   end
  end
 end
 return foundUnit,foundKey
end
N.GroupMember=groupMember
local function connected(unit)
 if not UnitIsConnected then return true end
 local ok,online=pcall(UnitIsConnected,unit)
 if not ok or (issecretvalue and issecretvalue(online)) then return false end
 return online==true
end
-- Remaining pieces held by bounded group items.
local function groupPieces()
 local count=0
 for _,queued in ipairs(queue) do
  if queued.bulk then count=count+(queued.parts and (#queued.parts-queued.cursor+1) or 1) end
 end
 return count
end
-- Pieces held by ordinary (not oversized) group items of one budget, and whether an
-- oversized item of that budget is queued.
local function budgetUsage(reply)
 local held,oversized=0,false
 for _,queued in ipairs(queue) do
  if queued.bulk and (queued.reply==true)==reply then
   if queued.oversized then oversized=true
   else held=held+(queued.parts and (#queued.parts-queued.cursor+1) or 1) end
  end
 end
 return held,oversized
end
-- Items that count toward the item limits: everything except replies (see QUEUE_LIMIT).
local function limitedItems()
 local count=#queue
 for _,queued in ipairs(queue) do if queued.reply then count=count-1 end end
 return count
end
-- Removes an item's pending marker and runs its completion callbacks (opts.onComplete)
-- with true when its last piece was sent, or false when it left the queue unsent.
-- Callbacks are isolated with pcall so a failing callback cannot stall the queue.
local function finish(item,sentOk)
 pending[item.id]=nil
 local callbacks=item.callbacks
 item.callbacks=nil
 if callbacks then
  for i=1,#callbacks do pcall(callbacks[i],sentOk==true) end
 end
end
local function enqueue(prefix,parts,channel,target,priority,opts)
 if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
 if type(prefix)~='string' or type(parts)~='table' or #parts==0 then return false end
 for i=1,#parts do if type(parts[i])~='string' or #parts[i]>250 then return false end end
 if opts~=nil and type(opts)~='table' then return false end
 channel=channel or 'GUILD'
 local scope=K.GuildScope and K.GuildScope()
 local groupWhisper=opts and opts.groupWhisper and channel=='WHISPER'
 local group=GROUP_CHANNELS[channel]==true or groupWhisper==true
 if not group and (not IsInGuild() or not scope) then return false end
 local groupUnit,groupKey
 if groupWhisper then
  groupUnit,groupKey=groupMember(target)
  if not groupUnit then return false end
 end
 -- AceComm reassembles whispers by sender, not by the spelling of the target.
 local streamTarget=groupKey or target
 local multi=#parts>1
 local msg=multi and table.concat(parts) or parts[1]
 local id=tostring(scope)..'\001'..key(prefix,msg,channel,streamTarget)
 if multi then id=id..'\001'..#parts end
 -- The epoch is part of a group item's identity, so a send in a new group never merges
 -- into a stale item from the previous group (which will be dropped).
 local epoch=group and observeGroup() or nil
 if epoch then id=id..'\001g'..epoch end
 local onComplete=opts and type(opts.onComplete)=='function' and opts.onComplete or nil
 local existing=pending[id]
 if existing then
  -- A pending duplicate is not queued again; its caller is notified with the original.
  -- At most CALLBACK_LIMIT callbacks are kept: past the limit the newest one is replaced.
  if onComplete and type(existing)=='table' then
   local callbacks=existing.callbacks or {}
   existing.callbacks=callbacks
   if #callbacks>=CALLBACK_LIMIT then callbacks[#callbacks]=onComplete
   else callbacks[#callbacks+1]=onComplete end
  end
  return true
 end
 local reply=opts~=nil and opts.reply==true
 -- Non-reply items never exceed #queue, so the count is only needed near the limits.
 local limited=#queue>=GROUP_QUEUE_LIMIT and limitedItems() or #queue
 if priority=='RECOVERY' then
  local count=0
  for _,queued in ipairs(queue) do if queued.recovery then count=count+1 end end
  if count>=24 or limited>=300 then return false end
 end
 local oversized=opts~=nil and #parts>GROUP_PIECE_CAP
 if opts then
  if not reply and limited>=GROUP_QUEUE_LIMIT then return false end
  local held,big=budgetUsage(reply)
  if oversized then
   if big then return false end
  elseif held+#parts>GROUP_PIECE_CAP then return false end
 end
 -- Replies are bounded by their budget above, not by the item limit (see QUEUE_LIMIT).
 if not reply and limited>=QUEUE_LIMIT then dropped=dropped+1;return false end
 local item={prefix=prefix,msg=parts[1],channel=channel,target=target,id=id,attempts=0,scope=scope,group=group,
  groupEpoch=epoch,recovery=priority=='RECOVERY',alert=priority=='ALERT'}
 if multi then item.parts=parts;item.cursor=1 end
 if opts then
  item.bulk=true
  item.groupWhisper=groupWhisper or nil
  item.requireGroup=GROUP_CHANNELS[channel]==true
  item.reply=opts.reply==true or nil
  item.oversized=oversized or nil
  -- A self-contained single piece the caller marks as order-independent may be sent
  -- between the pieces of a multi-piece message on its stream (see activeStreams).
  item.unordered=(opts.unordered==true and not multi) or nil
 end
 item.stream=prefix..'\001'..channel..'\001'..(streamTarget or '')
 nextSequence=nextSequence+1
 item.sequence=nextSequence
 if onComplete then item.callbacks={onComplete} end
 -- The marker is the item itself (truthy), so a duplicate can attach its callback.
 pending[id]=item
 if priority=='ALERT' then table.insert(queue,1,item) else queue[#queue+1]=item end
 return true
end
function N.Send(prefix,msg,channel,target,priority,opts)
 if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
 if type(msg)~='string' or #msg>250 then return false end
 return enqueue(prefix,{msg},channel,target,priority,opts)
end
-- Queue one message made of ordered pieces (each at most 250 bytes). The pieces are sent
-- one per turn in order. A receiver reassembles them per prefix, channel and sender, so
-- no other multi-piece item on the same stream may start until this one is finished.
function N.SendParts(prefix,parts,channel,target,priority,opts)
 if type(parts)~='table' then return false end
 local copy={}
 for i=1,#parts do copy[i]=parts[i] end
 return enqueue(prefix,copy,channel,target,priority,opts)
end
-- Multi-piece items already part-way through their stream (at most one per stream).
local function activeStreams()
 local active
 for _,queued in ipairs(queue) do
  if queued.parts and queued.cursor>1 then active=active or {};active[queued.stream]=queued end
 end
 return active
end
-- AceComm receivers spool only multi-piece frames (\001-\003) per prefix, channel and
-- sender; an unmarked or \004-escaped single piece is dispatched at once and leaves the
-- spool untouched. An unordered single piece therefore cannot corrupt an in-progress
-- message, so it is never blocked. Ordered items still wait to keep their send order.
local function blocked(active,first,item)
 if item.unordered or not item.bulk then return false end
 local owner=active and active[item.stream]
 return (owner~=nil and owner~=item) or first[item.stream]~=item
end
local frame=CreateFrame('Frame')
frame:SetScript('OnUpdate',function(_,dt)
 elapsed=elapsed+dt
 if elapsed<0.85 or #queue==0 then return end
 elapsed=0
 -- Observed before the lockdown check, so group changes during a hold are still seen.
 local currentEpoch=observeGroup()
 if inLockdown() then lockdowns=lockdowns+1;elapsed=-3;return end
 local index=1
 local turned=not queue[1].alert
 local toggled=false
 -- Ordering lock: nothing else on a stream is sent while a multi-piece item on it is part-way
 -- through. A blocked pick falls through to the first unblocked item (which may be the
 -- in-progress item itself), so unrelated traffic keeps flowing.
 local active=activeStreams()
 -- Scheduler priorities may select a later message before an earlier one's first
 -- piece succeeds. Track enqueue order independently of retry queue positions.
 local first={}
 for _,queued in ipairs(queue) do
  if queued.bulk and not queued.unordered then
   local prior=first[queued.stream]
   if not prior or queued.sequence<prior.sequence then first[queued.stream]=queued end
  end
 end
 if turned then
  replyTurn=not replyTurn
  local replyIndex
  if replyTurn then
   for i,item in ipairs(queue) do
    if item.reply and not blocked(active,first,item) then replyIndex=i;break end
   end
  end
  if replyIndex then index=replyIndex
  else
   toggled=true
   recoveryTurn=not recoveryTurn
   for i,item in ipairs(queue) do
    if item.recovery==recoveryTurn then index=i;break end
   end
  end
 end
 if blocked(active,first,queue[index]) then
  for i,queued in ipairs(queue) do
   if not blocked(active,first,queued) then index=i;break end
  end
 end
 local item=table.remove(queue,index)
 if not item.group and (not IsInGuild() or item.scope~=(K.GuildScope and K.GuildScope())) then finish(item,false);return end
 if item.group and (item.groupEpoch~=currentEpoch or (item.requireGroup and not inGroup())) then
  dropped=dropped+1;finish(item,false);return
 end
 local whisperKey
 if item.channel=='WHISPER' then
  local now=time()
  for peer,expires in pairs(unavailable) do if expires<=now then unavailable[peer]=nil end end
  local member,online
  if item.groupWhisper then
   local unit,full=groupMember(item.target)
   member,online=full,unit and connected(unit)
   whisperKey=member and ('group\001'..member)
  else
   local _
   member,_,online=K.CurrentGuildMember(item.target)
   whisperKey=member and (item.scope..'\001'..member)
  end
  if not whisperKey or unavailable[whisperKey] or (issecretvalue and issecretvalue(online)) or online~=true then
   finish(item,false);return
  end
 end
 local msg=item.parts and item.parts[item.cursor] or item.msg
 local ok,result=pcall(C_ChatInfo.SendAddonMessage,item.prefix,msg,item.channel,item.target)
 local throttled=(not ok) or result==false or (type(result)=='number' and result~=0)
 -- Only the repository-verified literal 11 means lockdown. Enum names are not trusted for
 -- this code: a different mapping would make offline-whisper result 12 hold the queue.
 if ok and result==11 then
  -- Keep the item at its place, keep its attempts, and never mark a whisper peer unavailable.
  lockdowns=lockdowns+1
  table.insert(queue,index,item)
  if toggled then recoveryTurn=not recoveryTurn end
  if turned then replyTurn=not replyTurn end
  elapsed=-3
 elseif throttled then
  failed=failed+1;item.attempts=item.attempts+1
  local retry=item.channel~='WHISPER' or result==resultCode('AddonMessageThrottle','AddOnMessageThrottle',3)
   or result==resultCode('ChannelThrottle',nil,8)
  if whisperKey and not retry then unavailable[whisperKey]=time()+30 end
  if retry and item.attempts<3 then
   -- A started multi-piece item keeps its place so its remaining pieces stay in order.
   if item.parts and item.cursor>1 then table.insert(queue,index,item) else queue[#queue+1]=item end
   elapsed=-3
  else dropped=dropped+1;finish(item,false) end
 else
  sent=sent+1
  if item.parts and item.cursor<#item.parts then
   -- Next piece: let one other queued item go first so a long message cannot starve the queue.
   item.cursor=item.cursor+1;item.attempts=0
   table.insert(queue,math.min(index+1,#queue+1),item)
  else finish(item,true) end
 end
end)
-- Group membership events move the epoch at once. Registration is guarded so a client
-- without one of these events cannot break loading.
if frame.RegisterEvent then
 for _,event in ipairs({'GROUP_ROSTER_UPDATE','GROUP_JOINED','GROUP_LEFT'}) do pcall(frame.RegisterEvent,frame,event) end
end
frame:SetScript('OnEvent',function(_,event) N.GroupEvent(event) end)
function N.CancelPrefix(prefix,scope)
 for i=#queue,1,-1 do
  local item=queue[i]
  if item.prefix==prefix and item.scope==scope then
   table.remove(queue,i)
   finish(item,false)
  end
 end
end
-- The fifth value (lockdown pauses) and sixth value (queued group pieces) are additive;
-- existing four- and five-value callers are unaffected.
function N.Status() return #queue,sent,failed,dropped,lockdowns,groupPieces() end
