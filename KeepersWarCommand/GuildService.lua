-- DEV30 Guild Service: CTA evidence, officer-approved bounty claims, commendations.
-- Separate storage and protocol. No mutations to existing CTA/bounty/PvP records.
local K=KWC;local S={};K.GuildService=S
local lastSample=0;local lastRequest=0;local lastPeerReply=0
local function db()
 KWCDB.guildService=KWCDB.guildService or {cta={},claims={},pending={},lastRequest=0}
 return KWCDB.guildService
end
local function canon(n)
 n=tostring(n or ''):match('^[^-]+') or ''
 if K.PvP and K.PvP.CanonicalDisplayName then return K.PvP.CanonicalDisplayName(n) or n end
 return n
end
local function selfName() return canon(UnitName('player')) end
local function validId(id) return type(id)=='string' and #id>0 and #id<=80 and id:match('^[%w%-_]+$') end
local function find(kind,id)
 for _,e in ipairs(kind=='CTA' and (KWCDB.ops or {}) or (KWCDB.bounties or {})) do if e.id==id then return e end end
end
local function send(kind,id,name,value)
 if not validId(id) then return end
 K.Send('SERVICE',table.concat({kind,id,K.Clean(name,75),tostring(value or '0')},','))
end
local function recordCTA(id,name,kind,at)
 if not validId(id) or not find('CTA',id) then return false end
 name=canon(name);if name=='' or #name>75 then return false end
 local d=db();d.cta[id]=d.cta[id] or {}
 local m=d.cta[id][name] or {name=name,first=at or time(),last=0,observations=0,group=false,zone=false}
 if kind=='GROUP' then m.group=true elseif kind=='ZONE' then m.zone=true else return false end
 local stamp=tonumber(at) or time()
 if stamp>m.last then m.last=stamp;m.observations=math.min(100000,(m.observations or 0)+1) end
 d.cta[id][name]=m
 return true
end
local function currentZone()
 return (GetZoneText and GetZoneText() or ''):lower()
end
local function sample()
 if not KWCDB or not IsInGuild() or time()-lastSample<45 then return end
 lastSample=time()
 local zone=currentZone()
 for _,e in ipairs(KWCDB.ops or {}) do
  if (e.status or 'ACTIVE')=='ACTIVE' then
   local wanted=e.details and e.details.zone
   if type(wanted)=='string' and #wanted>2 and wanted:lower()==zone then
    local me=selfName()
    if recordCTA(e.id,me,'ZONE') then send('ZONE',e.id,me,time()) end
    if IsInRaid and IsInRaid() then
     for i=1,math.min(GetNumGroupMembers() or 0,40) do
      local u='raid'..i
      if UnitExists(u) and UnitIsVisible and UnitIsVisible(u) then
       local n=canon(UnitName(u));if recordCTA(e.id,n,'GROUP') then send('GROUP',e.id,n,time()) end
      end
     end
    elseif IsInGroup and IsInGroup() then
     for i=1,4 do
      local u='party'..i
      if UnitExists(u) and UnitIsVisible and UnitIsVisible(u) then
       local n=canon(UnitName(u));if recordCTA(e.id,n,'GROUP') then send('GROUP',e.id,n,time()) end
      end
     end
    end
   end
  end
 end
end
local function approve(id,name)
 if not K.IsOfficer() then K.Say('Only War Council or Warchief may approve bounty claims.');return end
 if not find('BOUNTY',id) then K.Say('Bounty record unavailable.');return end
 name=canon(name);local d=db();d.claims[id]=d.claims[id] or {}
 if d.claims[id][name] then K.Say('Claim already approved.');return end
 d.claims[id][name]={by=selfName(),at=time()}
 send('APPROVE',id,name,time());K.Say('Bounty claim approved for '..name)
 if K.UI then K.UI.Refresh() end
end
function S.Approve(id,name)approve(id,name) end
function S.Pending(id)
 local e=find('BOUNTY',id);local out={}
 if e then for n in pairs(e.claims or {}) do
  if not ((db().claims[id] or {})[canon(n)]) then out[#out+1]=canon(n) end
 end end
 table.sort(out);return out
end
function S.CTARecords(id)return db().cta[id] or {} end
function S.Totals(name)
 name=canon(name);local c,b=0,0;local d=db()
 for id,people in pairs(d.cta) do
  local e=find('CTA',id)
  local m=people[name]
  if e and e.status=='RESOLVED' and m and (m.group or m.zone) then c=c+1 end
 end
 for id,people in pairs(d.claims) do if find('BOUNTY',id) and people[name] then b=b+1 end end
 return b,c
end
function S.Commendations(name)
 local b,c=S.Totals(name)
 return {{title='First Blood',earned=b>=1,progress=b,goal=1},
 {title='Bounty Hunter',earned=b>=10,progress=b,goal=10},
 {title='Answer the Call',earned=c>=10,progress=c,goal=10},
 {title='CTA Veteran',earned=c>=25,progress=c,goal=25}}
end
function S.DrawCTA(parent,label,button)
 label(parent,'CTA AFTER-ACTION RECORDS',12,-12,550,'GameFontNormalLarge')
 label(parent,'Observed in the CTA zone or visibly present in a group. Not a combat guarantee.',12,-51,550)
 local y=-100
 for _,e in ipairs(KWCDB.ops or {}) do
  if (e.status or 'ACTIVE')~='ACTIVE' then
   label(parent,tostring(e.text or 'CTA'):sub(1,65)..'  ['..tostring(e.status)..']',12,y,550,'GameFontNormal');y=y-30
   local names={};for n in pairs(S.CTARecords(e.id)) do names[#names+1]=n end;table.sort(names)
   for _,n in ipairs(names) do
    local m=S.CTARecords(e.id)[n]
    label(parent,n..'  -  '..(m.group and 'Group observed' or 'Zone observed'),26,y,520);y=y-23
   end
   if #names==0 then label(parent,'No attendance evidence recorded.',26,y,520);y=y-23 end
   y=y-22
  end
 end
 if y==-100 then label(parent,'No completed CTAs to display.',12,y,540) end
end
function S.DrawCommendations(parent,label)
 label(parent,'GUILD COMMENDATIONS',12,-12,550,'GameFontNormalLarge')
 label(parent,'Earned from observed CTA attendance and approved bounty claims.',12,-51,550)
 local name=selfName();local b,c=S.Totals(name)
 label(parent,name..'   |   '..b..' bounties   |   '..c..' CTAs',12,-95,545,'GameFontNormal')
 local y=-155
 for _,a in ipairs(S.Commendations(name)) do
  label(parent,(a.earned and '[EARNED]  ' or '[LOCKED]  ')..a.title,12,y,530,'GameFontNormal')
  label(parent,tostring(a.progress)..' / '..a.goal..' verified records',30,y-27,520);y=y-85
 end
 label(parent,'Legacy achievements and points remain saved; this page does not delete them.',12,y-20,550)
end
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~='KWC3' or channel~='GUILD' or type(msg)~='string' or not K.IsMember(sender) then return end
 local version,kind,payload=msg:match('^(%d+);([^;]+);(.*)$')
 if version~='2' or kind~='SERVICE' then return end
 local op,id,name,stamp=payload:match('^(%u+),([%w%-_]+),([^,]+),(%d+)$')
 if not op or not validId(id) or #name>75 then return end
 stamp=tonumber(stamp)
 if not stamp or math.abs(time()-stamp)>86400*45 then return end
 if op=='ZONE' then
  if not K.SameGuildMember(sender,name) then return end
  recordCTA(id,name,'ZONE',stamp)
 elseif op=='CACHEZONE' then
  if not K.SameGuildMember(sender,name) then return end
  recordCTA(id,name,'ZONE',stamp)
 elseif op=='GROUP' then
  -- Group observations are reports from another client, not cryptographic proof.
  recordCTA(id,name,'GROUP',stamp)
 elseif op=='APPROVE' then
  if not K.IsSenderOfficer(sender) or not K.IsMember(name) or not find('BOUNTY',id) then return end
  local d=db();d.claims[id]=d.claims[id] or {}
  if not d.claims[id][canon(name)] then d.claims[id][canon(name)]={by=canon(sender),at=stamp} end
 elseif op=='REQ' then
  if time()-lastPeerReply<25 then return end
  lastPeerReply=time()
  local d=db()
  for eid,people in pairs(d.cta) do
   if find('CTA',eid) then for n,m in pairs(people) do
    if m.zone then send('CACHEZONE',eid,n,m.last) end
    if m.group then send('GROUP',eid,n,m.last) end
   end end
  end
  if K.IsOfficer() then
   for eid,people in pairs(d.claims) do
    if find('BOUNTY',eid) then for n,v in pairs(people) do send('APPROVE',eid,n,v.at) end end
   end
  end
 end
 if K.UI then K.UI.Refresh() end
end)
function S.Request()
 if time()-lastRequest<15 then return end
 lastRequest=time();K.Send('SERVICE','REQ,request,'..K.Clean(selfName(),75)..','..time())
end
K.On('PLAYER_ENTERING_WORLD',function()S.Request();sample() end)
K.On('ZONE_CHANGED_NEW_AREA',sample)
K.On('GROUP_ROSTER_UPDATE',sample)
local ticker=CreateFrame('Frame');local elapsed=0
 ticker:SetScript('OnUpdate',function(_,dt)elapsed=elapsed+dt;if elapsed>60 then elapsed=0;sample() end end)
