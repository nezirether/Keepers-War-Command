-- DEV30 Guild Service: CTA evidence, and officer-approved bounty claims.
-- Separate storage and protocol. No mutations to existing CTA/bounty/PvP records.
local K=KWC;local S={};K.GuildService=S
local lastSample=0
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
 local stamp=tonumber(at) or time()
 local flag=kind=='GROUP' and 'group' or kind=='ZONE' and 'zone'
 if not flag then return false end
 if m[flag..'At'] and m[flag..'At']>=stamp then return false end
 m[flag]=true
 m[flag..'At']=stamp
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
 if not K.IsSenderOfficer(K.LocalGuildMember()) then K.Say('Only War Council or Warchief may approve bounty claims.');return end
 if not find('BOUNTY',id) then K.Say('Bounty record unavailable.');return end
 name=canon(name);local d=db();d.claims[id]=d.claims[id] or {}
 if d.claims[id][name] then K.Say('Claim already approved.');return end
 d.claims[id][name]={by=selfName(),at=time()}
 send('APPROVE',id,name,time());K.Say('Bounty claim approved for '..name)
 if K.UI then K.UI.Refresh() end
end
function S.Approve(id,name)approve(id,name) end
local function recordApproval(id,name,stamp,actor,relay)
 if not K.IsMember(name) or not find('BOUNTY',id) then return false end
 local d=db();d.claims[id]=d.claims[id] or {}
 local identity=canon(name)
 local old=d.claims[id][identity]
 if old and (old.at>stamp or (old.at==stamp and old.by>=canon(actor))) then return false end
 d.claims[id][identity]={by=canon(actor),at=stamp,relayedBy=relay}
 return true
end
function S.RecoveryRows(kind,id,emit)
 local d=db()
 if kind=='CTA' or kind=='C' then
  for who,report in pairs(d.cta[id] or {}) do
   if K.IsMember(who) then
    if report.zone then emit('Z',who,report.zoneAt or report.last) end
    if report.group then emit('H',who,report.groupAt or report.last) end
   end
  end
 else
  for who,approval in pairs(d.claims[id] or {}) do
   if K.IsMember(who) and K.IsMember(approval.by) then emit('A',who,approval.at,approval.by) end
  end
 end
end
function S.ApplyRecovery(event,id,name,stamp,value,sender)
 if event=='A' then
  if not K.IsSenderOfficer(value) then return false end
  return recordApproval(id,name,stamp,value,sender)
 end
 return value=='' and recordCTA(id,name,event=='Z' and 'ZONE' or 'GROUP',stamp)
end
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
-- 2.0: legacy layout S.DrawCTA removed (UI lives in UI/Pages).
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
  if not K.IsSenderOfficer(sender) or not recordApproval(id,name,stamp,sender) then return end
 else return end
 if K.UI then K.UI.Refresh() end
end)
function S.Request()
 return K.Sync and K.Sync.Request(true)
end
K.On('PLAYER_ENTERING_WORLD',sample)
K.On('ZONE_CHANGED_NEW_AREA',sample)
K.On('GROUP_ROSTER_UPDATE',sample)
local ticker=CreateFrame('Frame');local elapsed=0
 ticker:SetScript('OnUpdate',function(_,dt)elapsed=elapsed+dt;if elapsed>60 then elapsed=0;sample() end end)
