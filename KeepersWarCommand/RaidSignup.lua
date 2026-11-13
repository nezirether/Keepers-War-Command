-- KT Raid Sign-Ups DEV27: independent guild-wide schedule and RSVP protocol.
-- Guild communication only; no raid/party membership or protected actions required.
local K=KWC
local S={};K.RaidSignup=S
local PREFIX='KWRS1'
local statuses={Attending=true,Absent=true,Late=true,Tentative=true,Withdrawn=true}
local selected=nil
local lastReq=0
local lastReply={}
local recovery,cursor,lastRecovery=nil,0,0
local pending,pendingGuild={},nil
local diag={sent=0,received=0,applied=0,rejected=0,requests=0}
function S.Diagnostics() return diag end
local function db()
 KWCDB.raidSignups=KWCDB.raidSignups or {events={},responses={}}
 local d=KWCDB.raidSignups;d.events=d.events or {};d.responses=d.responses or {};return d
end
local function clean(v,n) return tostring(v or ''):gsub('[|\r\n]',' '):sub(1,n or 90) end
local function me() return UnitName('player') or '' end
local function same(a,b) return K.SameGuildMember(a,b) end
local function canonical(v)
 local r=K.RosterRecord and K.RosterRecord(v)
 return r and K.SameGuildMember(r.name,v) and r.name or tostring(v or '')
end
local function scope() return K.GuildScope and K.GuildScope() end
local function send(kind,fields,target)
 if not IsInGuild() or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
 local msg=kind..'|'..table.concat(fields,'|')
 if #msg>250 then return false end
 local ok=K.Net.Send(PREFIX,msg,target and 'WHISPER' or 'GUILD',target,target and 'RECOVERY' or nil);if ok then diag.sent=diag.sent+1 end;return ok
end
local function eventFields(e)
 return {e.id,clean(e.title,60),clean(e.when,45),clean(e.author,65),tostring(e.rev or 1),e.deleted and '2' or e.cancelled and '1' or '0'}
end
local function sendEvent(e) return send('EV',eventFields(e)) end
local function sendRSVP(id,name,r)
 return send('RS',{id,clean(name,65),r.status,tostring(r.rev or 1)})
end
local function refresh()
 -- Explicit UI refresh only: never erase a partially typed raid creation form.
end
local function uniqueID()
 return tostring(time())..'-'..tostring(math.random(100000,999999))
end
function S.Create(title,when)
 if not scope() or not K.IsOfficer() then K.Say('Only War Council / War Chief can schedule guild raids.');return end
 title=clean(title,60);when=clean(when,45)
 if title=='' or when=='' then K.Say('Enter raid name and date/time (include timezone).');return end
 local d=db();local id=uniqueID()
 local e={id=id,title=title,when=when,author=canonical(me()),rev=time(),cancelled=false}
 d.events[id]=e;d.responses[id]={};selected=id
 sendEvent(e);K.Say('Raid sign-up created: '..title);return true
end
function S.Cancel(id)
 local d=db();local e=d.events[id]
 if not e or e.deleted or not scope() or not K.IsOfficer() then return end
 e.cancelled=true;e.rev=math.max(time(),(e.rev or 0)+1);sendEvent(e)
 K.Say('Raid cancelled. Responses retained for history.')
end
function S.Edit(id,title,when)
 local e=db().events[id]
 title,when=clean(title,60),clean(when,45)
 if not e or e.cancelled or not scope() or not K.IsOfficer() or title=='' or when=='' then return false end
 e.title,e.when=title,when
 e.rev=math.max(time(),(e.rev or 0)+1)
 sendEvent(e);return true
end
function S.Delete(id)
 local e=db().events[id]
 if not e or e.deleted or not scope() or not K.IsOfficer() then return false end
 e.cancelled,e.deleted=true,true
 e.rev=math.max(time(),(e.rev or 0)+1)
 sendEvent(e);return true
end
function S.Respond(id,status)
 if not statuses[status] or not scope() then return end
 local d=db();local e=d.events[id];if not e or e.cancelled then return end
 local name=canonical(me());d.responses[id]=d.responses[id] or {}
 local prior
 for alias,record in pairs(d.responses[id]) do
  if same(alias,name) then
   if not prior or (record.rev or 0)>(prior.rev or 0) then prior=record end
   if alias~=name then d.responses[id][alias]=nil end
  end
 end
 local rev=math.max(time(),(prior and prior.rev or 0)+1)
 local r={status=status,rev=rev};d.responses[id][name]=r
 sendRSVP(id,name,r);K.Say('Raid sign-up: '..status)
end
function S.Sync(silent)
 if not IsInGuild() then return end
 if time()-lastReq<35 then return false end
 lastReq=time();diag.requests=diag.requests+1;local ok
 local guild=scope()
 local officers=guild and K.Sync and K.Sync.RecoveryOfficers and K.Sync.RecoveryOfficers()
 if officers and #officers>0 then
  local page=math.floor(cursor/#officers)%100
  local target=officers[cursor%#officers+1]
  cursor=cursor+1
  local token=time()..'-'..math.random(100000,999999)
  recovery={guild=guild,token=token,target=target,expires=time()+34}
  ok=send('RQ',{guild,token,page},target)
 end
 if not ok then ok=send('REQ',{clean(me(),65)}) end
 if not silent then K.Say('Requested raid sign-ups from online guildmates.') end
 return ok
end
local function newer(status,rev,old)
 return not old or rev>(old.rev or 0) or (rev==(old.rev or 0) and old.status~='Withdrawn'
  and (status=='Withdrawn' or status>old.status))
end
local function applyRSVP(d,id,name,status,rev,relay)
 local rs=d.responses[id] or {};d.responses[id]=rs
 local key=canonical(name)
 for prior,r in pairs(rs) do
  if same(prior,name) then
   if not newer(status,rev,r) then return end
   if prior~=key then rs[prior]=nil end
  end
 end
 rs[key]={status=status,rev=rev,relayedBy=relay}
 diag.applied=diag.applied+1
end
K.On('PLAYER_GUILD_UPDATE',function() pending={};recovery=nil;cursor=0;lastReq=0 end)
local function pendingForGuild()
 local guild=scope()
 if pendingGuild~=guild then pending={};pendingGuild=guild end
 for key,r in pairs(pending) do if r.expires<=time() then pending[key]=nil end end
 return pending
end
local function replyRecovery(sender,guild,token,page)
 if not K.IsSenderOfficer(me()) or time()-lastRecovery<4 then return end
 lastRecovery=time()
 local rows={}
 local d=db()
 local ids={}
 for id in pairs(d.events) do ids[#ids+1]=id end
 table.sort(ids)
 for _,id in ipairs(ids) do
  local e=d.events[id]
  rows[#rows+1]={'RE',eventFields(e)}
  local names={}
  if not e.cancelled then
   for name in pairs(d.responses[id] or {}) do names[#names+1]=name end
  end
  table.sort(names)
  for _,name in ipairs(names) do
   local r=d.responses[id][name]
   rows[#rows+1]={'RR',{id,clean(name,65),r.status,r.rev}}
  end
 end
 if #rows==0 then return end
 local first=(page%math.ceil(#rows/10))*10+1
 for i=first,math.min(first+9,#rows) do
  local row=rows[i]
  send(row[1],{guild,token,table.concat(row[2],'|')},sender)
 end
end
local function onMessage(prefix,msg,where,sender)
 if prefix~=PREFIX or type(msg)~='string' or #msg>250 then return end
 local relay
 if where=='WHISPER' then
  local kind,guild,token,body=msg:match('^([A-Z]+)|(%d+)|(%d+%-%d+)|(.+)$')
  if not guild or guild~=scope() or #token>24 or not K.IsMember(sender) then return end
  if kind=='RQ' then
   if body:match('^%d%d?$') then replyRecovery(sender,guild,token,tonumber(body)) end
   return
  end
  if not recovery or recovery.guild~=guild or recovery.token~=token or time()>recovery.expires
   or not same(recovery.target,sender) or not K.IsSenderOfficer(sender) then return end
  if kind~='RE' and kind~='RR' then return end
  msg=(kind=='RE' and 'EV|' or 'RS|')..body
  relay=sender
 elseif where~='GUILD' then return end
 -- Guild channel itself authenticates guild membership; roster scans may lag behind.
 if not K.IsMember(sender) then return end
 diag.received=diag.received+1
 local kind=msg:match('^([^|]+)|')
 if kind=='REQ' then
  if same(sender,me()) then return end
  local who=K.CurrentGuildMember(sender)
  if not who or not C_Timer or not C_Timer.After then return end
  local guild=K.GuildScope and K.GuildScope()
  if time()-(lastReply[who] or 0)<60 then return end
  lastReply[who]=time()
  local d=db();local sent=0
  -- One response wave per requester, spread over several seconds.
  for _,e in pairs(d.events) do
   if sent>=30 then break end
   local eventID=e.id
   if K.IsSenderOfficer(me()) and K.SameGuildMember(e.author,me()) then
    C_Timer.After(2+sent*0.6+math.random()*0.2,function()
     if guild~=(K.GuildScope and K.GuildScope()) or not K.IsSenderOfficer(me()) then return end
     local current=db().events[eventID]
     if current and K.SameGuildMember(current.author,me()) then sendEvent(current) end
    end)
    sent=sent+1
   end
   local rs=d.responses[e.id] or {}
   for name in pairs(rs) do
    if sent>=85 then break end
    if K.SameGuildMember(name,me()) then
     local player=name
     C_Timer.After(2+sent*0.6+math.random()*0.2,function()
      if guild~=(K.GuildScope and K.GuildScope()) then return end
      local current=db()
      local response=(current.responses[eventID] or {})[player]
      if current.events[eventID] and not current.events[eventID].cancelled and response
       and K.SameGuildMember(player,me()) then sendRSVP(eventID,player,response) end
     end)
     sent=sent+1
    end
   end
  end
 elseif kind=='EV' then
  local id,title,when,author,rev,flag=msg:match('^EV|([^|]+)|([^|]*)|([^|]*)|([^|]*)|(%d+)|([012])$')
  rev=tonumber(rev)
  if not id or #id>40 or #title>60 or #when>45 or #author>65 or not rev or rev>time()+300 then return end
  -- Initial creation requires the event author to be a verified officer. Cached event relay
  -- is accepted only for existing records; untrusted relays cannot create events.
  local d=db();local old=d.events[id]
  if not K.IsSenderOfficer(sender) or (not old and not relay and not same(sender,author)) then
   diag.rejected=diag.rejected+1;return
  end
  if old and not K.SameGuildMember(old.author,author) then return end
  if not K.IsMember(author) then return end
  if old then
   local oldFlag=old.deleted and '2' or old.cancelled and '1' or '0'
   if flag<oldFlag or (flag==oldFlag and rev<(old.rev or 0)) then return end
   if rev==old.rev and flag..title..'|'..when<=oldFlag..old.title..'|'..old.when then return end
  end
  d.events[id]={id=id,title=title,when=when,author=author,rev=rev,cancelled=flag~='0',deleted=flag=='2',relayedBy=relay}
  local queued=pendingForGuild()
  for key,r in pairs(queued) do
   if r.id==id then
    queued[key]=nil
    if flag=='0' and K.IsMember(r.name) and (not r.relay or K.IsSenderOfficer(r.relay)) then
     applyRSVP(d,id,r.name,r.status,r.rev,r.relay)
    end
   end
  end
  d.responses[id]=d.responses[id] or {}
  diag.applied=diag.applied+1
 elseif kind=='RS' then
  local id,name,status,rev=msg:match('^RS|([^|]+)|([^|]+)|([^|]+)|(%d+)$')
  rev=tonumber(rev)
  if not id or #id>40 or #name>65 or not statuses[status] or not rev or rev>time()+300 then return end
  if (not relay and not same(sender,name)) or not K.IsMember(name) then return end
  local d=db()
  if not d.events[id] then
   local queued=pendingForGuild()
   local key=id..'|'..K.CurrentGuildMember(name)
   local prior=queued[key]
   if not newer(status,rev,prior) then return end
   local count=0
   for _ in pairs(queued) do count=count+1 end
   if prior or count<128 then queued[key]={id=id,name=name,status=status,rev=rev,relay=relay,expires=time()+120} end
   return
  end
  if d.events[id].cancelled then return end
  applyRSVP(d,id,name,status,rev,relay)
 end
 refresh()
end
K.On('CHAT_MSG_ADDON',onMessage)
local function registerPrefix()
 if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix,PREFIX) end
end
registerPrefix()
K.On('PLAYER_ENTERING_WORLD',registerPrefix)
K.On('GUILD_ROSTER_UPDATE',function()
 if IsInGuild() and time()-lastReq>180 then S.Sync(true) end
end)
local function ordered()
 local out={};for _,e in pairs(db().events) do if not e.deleted then out[#out+1]=e end end
 table.sort(out,function(a,b)
  if a.cancelled~=b.cancelled then return not a.cancelled end
  if a.when~=b.when then return a.when<b.when end
  return a.id>b.id
 end)
 return out
end
local draftTitle,draftWhen
function S.Draw(parent,label,button,edit)
 local d=db()
 label(parent,'RAID SIGN-UPS',12,-12,560,'GameFontNormalLarge')
 label(parent,'Schedule guild raids and RSVP without Discord. Available outside a raid group.',12,-49,555)
 button(parent,'Refresh / Sync',12,-84,170,function()S.Sync() end)
 local y=-141
 if K.IsOfficer() then
  label(parent,'SCHEDULE A GUILD RAID',12,y,560,'GameFontNormal')
  label(parent,'Raid name',12,y-37,250)
  label(parent,'Date and time (include timezone)',282,y-37,280)
  local title=edit(parent,draftTitle or 'Molten Core',12,y-61,260)
  local when=edit(parent,draftWhen or '2026-11-14 19:00 PST',282,y-61,270)
  title:SetScript('OnTextChanged',function(self)draftTitle=self:GetText() end)
  when:SetScript('OnTextChanged',function(self)draftWhen=self:GetText() end)
  button(parent,'Create Raid Sign-Up',12,y-103,235,function()
   if S.Create(title:GetText(),when:GetText()) then draftTitle,draftWhen=nil,nil end;K.UI.Toggle('Raid Tools: Sign-Ups')
  end)
  y=y-166
 end
 label(parent,'GUILD RAID CALENDAR',12,y,560,'GameFontNormal')
 y=y-43
 local events=ordered()
 if #events==0 then
  label(parent,'No raids scheduled yet. Ask a War Council officer to create one.',12,y,550)
  return
 end
 for i,e in ipairs(events) do
  if i>25 then break end
  local id=e.id
  button(parent,(selected==id and '> ' or '')..e.title,12,y,315,function()
   selected=id;K.UI.Toggle('Raid Tools: Sign-Ups')
  end)
  label(parent,e.when,340,y-9,218)
  y=y-45
 end
 if not selected or not d.events[selected] or d.events[selected].deleted then selected=events[1].id end
 local e=d.events[selected]
 y=y-30
 label(parent,'SELECTED RAID',12,y,550,'GameFontNormal')
 label(parent,e.title..'  |  '..e.when,12,y-39,550)
 label(parent,'Scheduled by '..e.author..(e.cancelled and '  |  CANCELLED' or ''),12,y-65,550)
 y=y-105
 if not e.cancelled then
  local choices={'Attending','Absent','Late','Tentative'}
  for i,status in ipairs(choices) do
   local x=12+(i-1)*138
   button(parent,status,x,y,128,function()
    S.Respond(selected,status);K.UI.Toggle('Raid Tools: Sign-Ups')
   end)
  end
  y=y-52
 end
 local myStatus='Not signed up'
 for n,r in pairs(d.responses[selected] or {}) do if same(n,me()) and r.status~='Withdrawn' then myStatus=r.status end end
 label(parent,'Your response: '..myStatus,12,y,540,'GameFontNormal')
 y=y-43
 local counts={Attending=0,Absent=0,Late=0,Tentative=0}
 if not e.cancelled and myStatus~='Not signed up' then
  button(parent,'Withdraw RSVP',395,y-25,148,function()S.Respond(selected,'Withdrawn');K.UI.Toggle('Raid Tools: Sign-Ups') end)
  y=y-45
 end
 local names={};for n,r in pairs(d.responses[selected] or {}) do if r.status~='Withdrawn' then names[#names+1]=n end end
 table.sort(names)
 for _,n in ipairs(names) do local r=d.responses[selected][n];if counts[r.status] then counts[r.status]=counts[r.status]+1 end end
 label(parent,('ATTENDING: %d    ABSENT: %d    LATE: %d    TENTATIVE: %d'):format(counts.Attending,counts.Absent,counts.Late,counts.Tentative),12,y,560)
 y=y-39
 for _,n in ipairs(names) do
  local r=d.responses[selected][n]
  label(parent,n,12,y,290)
  label(parent,r.status,330,y,200)
  y=y-27
 end
 if #names==0 then label(parent,'No responses yet.',12,y,550);y=y-35 end
 if K.IsOfficer() then
  if not e.cancelled then
   local title=edit(parent,e.title,12,y-22,260)
   local when=edit(parent,e.when,282,y-22,260)
   button(parent,'Save Changes',12,y-60,150,function() if S.Edit(e.id,title:GetText(),when:GetText()) then K.UI.Toggle('Raid Tools: Sign-Ups') end end)
   button(parent,'Cancel Scheduled Raid',170,y-60,230,function() S.Cancel(e.id);K.UI.Toggle('Raid Tools: Sign-Ups') end)
  else
   button(parent,'Delete Cancelled Raid',12,y-22,220,function() S.Delete(e.id);K.UI.Toggle('Raid Tools: Sign-Ups') end)
  end
 end
end
