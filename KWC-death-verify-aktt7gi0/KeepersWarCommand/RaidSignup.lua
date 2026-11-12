-- KT Raid Sign-Ups DEV27: independent guild-wide schedule and RSVP protocol.
-- Guild communication only; no raid/party membership or protected actions required.
local K=KWC
local S={};K.RaidSignup=S
local PREFIX='KWRS1'
local statuses={Attending=true,Absent=true,Late=true,Tentative=true}
local selected=nil
local lastReq=0
local lastReply={}
local diag={sent=0,received=0,applied=0,rejected=0,requests=0}
function S.Diagnostics() return diag end
local function db()
 KWCDB.raidSignups=KWCDB.raidSignups or {events={},responses={}}
 local d=KWCDB.raidSignups;d.events=d.events or {};d.responses=d.responses or {};return d
end
local function clean(v,n) return tostring(v or ''):gsub('[|\r\n]',' '):sub(1,n or 90) end
local function me() return UnitName('player') or '' end
local function norm(v) return tostring(v or ''):lower():match('^[^-]+') end
local function same(a,b) return norm(a) and norm(a)==norm(b) end
local function canonical(v)
 local r=K.RosterRecord and K.RosterRecord(v)
 return r and r.name or tostring(v or '')
end
local function member(v) return K.IsMember(v) or same(v,me()) end
local function send(kind,fields)
 if not IsInGuild() or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
 local msg=kind..'|'..table.concat(fields,'|')
 if #msg>240 then return false end
 local ok=K.Net.Send(PREFIX,msg,'GUILD');if ok then diag.sent=diag.sent+1 end;return ok
end
local function sendEvent(e)
 return send('EV',{e.id,clean(e.title,60),clean(e.when,45),clean(e.author,65),tostring(e.rev or 1),e.cancelled and '1' or '0'})
end
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
 if not K.IsOfficer() then K.Say('Only War Council / War Chief can schedule guild raids.');return end
 title=clean(title,60);when=clean(when,45)
 if title=='' or when=='' then K.Say('Enter raid name and date/time (include timezone).');return end
 local d=db();local id=uniqueID()
 local e={id=id,title=title,when=when,author=canonical(me()),rev=time(),cancelled=false}
 d.events[id]=e;d.responses[id]={};selected=id
 sendEvent(e);K.Say('Raid sign-up created: '..title);return true
end
function S.Cancel(id)
 local d=db();local e=d.events[id]
 if not e or not K.IsOfficer() then return end
 e.cancelled=true;e.rev=math.max(time(),(e.rev or 0)+1);sendEvent(e)
 K.Say('Raid cancelled. Responses retained for history.')
end
function S.Respond(id,status)
 if not statuses[status] or not IsInGuild() then return end
 local d=db();local e=d.events[id];if not e or e.cancelled then return end
 local name=canonical(me());d.responses[id]=d.responses[id] or {}
 local prior=d.responses[id][name]
 local rev=math.max(time(),(prior and prior.rev or 0)+1)
 local r={status=status,rev=rev};d.responses[id][name]=r
 sendRSVP(id,name,r);K.Say('Raid sign-up: '..status)
end
function S.Sync(silent)
 if not IsInGuild() then return end
 if time()-lastReq<35 then return false end
 lastReq=time();diag.requests=diag.requests+1;local ok=send('REQ',{clean(me(),65)})
 if not silent then K.Say('Requested raid sign-ups from online guildmates.') end
 return ok
end
local function onMessage(prefix,msg,where,sender)
 if prefix~=PREFIX or where~='GUILD' or type(msg)~='string' or #msg>240 then return end
 -- Guild channel itself authenticates guild membership; roster scans may lag behind.
 if type(sender)~='string' or sender=='' then return end
 diag.received=diag.received+1
 local kind=msg:match('^([^|]+)|')
 if kind=='REQ' then
  if same(sender,me()) then return end
  local who=norm(sender)
  if time()-(lastReply[who] or 0)<60 then return end
  lastReply[who]=time()
  local d=db();local sent=0
  -- One response wave per requester, spread over several seconds.
  for _,e in pairs(d.events) do
   if sent>=30 then break end
   local event=e
   C_Timer.After(2+sent*0.6+math.random()*0.2,function()sendEvent(event) end);sent=sent+1
   local rs=d.responses[e.id] or {}
   for name,r in pairs(rs) do if sent>=85 then break end;local eventID,player,response=e.id,name,r
    C_Timer.After(2+sent*0.6+math.random()*0.2,function()sendRSVP(eventID,player,response) end);sent=sent+1 end
  end
 elseif kind=='EV' then
  local id,title,when,author,rev,flag=msg:match('^EV|([^|]+)|([^|]*)|([^|]*)|([^|]*)|(%d+)|([01])$')
  rev=tonumber(rev)
  if not id or #id>40 or #title>60 or #when>45 or #author>65 or not rev or rev>2147483647 then return end
  -- Initial creation requires the event author to be a verified officer. Cached event relay
  -- is accepted only for existing records; untrusted relays cannot create events.
  local d=db();local old=d.events[id]
  if not old and (not same(sender,author) or not K.IsSenderOfficer(sender)) then
   diag.rejected=diag.rejected+1;return
  end
  if old and not same(old.author,author) then return end
  if old and rev<=(old.rev or 0) then return end
  if old and not same(sender,author) and not K.IsSenderOfficer(sender) then return end
  d.events[id]={id=id,title=title,when=when,author=author,rev=rev,cancelled=flag=='1'}
  d.responses[id]=d.responses[id] or {}
  diag.applied=diag.applied+1
 elseif kind=='RS' then
  local id,name,status,rev=msg:match('^RS|([^|]+)|([^|]+)|([^|]+)|(%d+)$')
  rev=tonumber(rev)
  if not id or #id>40 or #name>65 or not statuses[status] or not rev or rev>2147483647 then return end
  local d=db();if not d.events[id] then return end
  -- Peers may relay cached RSVP entries; a live self-authored response always
  -- wins over older copies by monotonic revision. Guild identity required.
  if not member(name) and not same(sender,name) then return end
  local rs=d.responses[id] or {};d.responses[id]=rs
  local oldName=nil
  for n in pairs(rs) do if same(n,name) then oldName=n;break end end
  local old=oldName and rs[oldName]
  if old and rev<=(old.rev or 0) then return end
  if oldName then rs[oldName]=nil end
  rs[canonical(name)]={status=status,rev=rev}
  diag.applied=diag.applied+1
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
 local out={};for _,e in pairs(db().events) do out[#out+1]=e end
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
 if not selected or not d.events[selected] then selected=events[1].id end
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
 for n,r in pairs(d.responses[selected] or {}) do if same(n,me()) then myStatus=r.status end end
 label(parent,'Your response: '..myStatus,12,y,540,'GameFontNormal')
 y=y-43
 local counts={Attending=0,Absent=0,Late=0,Tentative=0}
 local names={};for n in pairs(d.responses[selected] or {}) do names[#names+1]=n end
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
 if K.IsOfficer() and not e.cancelled then
  button(parent,'Cancel Scheduled Raid',12,y-22,240,function()S.Cancel(selected);K.UI.Toggle('Raid Tools: Sign-Ups') end)
 end
end
