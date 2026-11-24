-- KT Raid Command v2: independent group-only raid operations.
-- Deliberately no protected actions, no MRT dependency, no existing KWC sync changes.
local K=KWC
local R={};K.RaidCommand=R
local PREFIX='KWCR3'
local selected,selectedTemplate,editorDuty='',nil,''
local lastRequest,lastReply=0,0
local staged={}
local currentLeader
local function say(s) K.Say('KT Raid: '..s) end
local function clean(s,n) return tostring(s or ''):gsub('[|\r\n]',' '):sub(1,n or 80) end
local function db()
 KWCDB.raidCommand=KWCDB.raidCommand or {}
 local d=KWCDB.raidCommand
 KWCDB.raidCommandTemplates=KWCDB.raidCommandTemplates or d.templates or {}
 d.templates=KWCDB.raidCommandTemplates;d.assignments=d.assignments or {};d.acks=d.acks or {};d.ready=d.ready or {}
 d.readyRevisions=d.readyRevisions or {}
 d.session=d.session or '';d.leader=d.leader or '';d.revision=d.revision or 0
 return d
end
local function me() return UnitName('player') or '' end
local function identity(name,realm)
 if type(name)~='string' or name=='' then return end
 name=name:lower()
 if name:find('-',1,true) then return name end
 if not realm or realm=='' then realm=GetNormalizedRealmName and GetNormalizedRealmName() end
 return realm and realm~='' and (name..'-'..realm:lower()) or name
end
local function same(a,b) return identity(a)~=nil and identity(a)==identity(b) end
local function members()
 local result={}
 local count=GetNumGroupMembers and GetNumGroupMembers() or 0
 if count==0 then return result end
 local raid=IsInRaid and IsInRaid()
 local units={}
 if raid then for i=1,count do units[#units+1]='raid'..i end
 else units={'player'};for i=1,math.max(0,count-1) do units[#units+1]='party'..i end end
 for _,unit in ipairs(units) do
  if UnitExists(unit) and UnitIsPlayer(unit) then
   local name,realm=UnitName(unit)
   if name and name~='' then
    local role=UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or 'NONE'
    local class=select(2,UnitClass(unit)) or ''
    local subgroup=1
    if raid and GetRaidRosterInfo then
     local index=tonumber(unit:match('%d+'))
     local _,_,g=GetRaidRosterInfo(index);subgroup=g or 1
    end
    result[#result+1]={name=name,identity=identity(name,realm),unit=unit,role=role,class=class,group=subgroup,online=UnitIsConnected(unit)~=false}
   end
  end
 end
 table.sort(result,function(a,b)
  if a.group~=b.group then return a.group<b.group end
  return a.name:lower()<b.name:lower()
 end)
 return result
end
local function memberName(name)
 for _,p in ipairs(members()) do if identity(name)==p.identity then return p.name end end
 return nil
end
local function leader()
 return GetNumGroupMembers and GetNumGroupMembers()>0 and UnitIsGroupLeader and UnitIsGroupLeader('player')
end
local function senderLeader(name)
 for _,p in ipairs(members()) do
  if identity(name)==p.identity and UnitIsGroupLeader and UnitIsGroupLeader(p.unit) then return true end
 end
 return false
end
local function leaderIdentity()
 for _,p in ipairs(members()) do
  if UnitIsGroupLeader and UnitIsGroupLeader(p.unit) then return p.identity end
 end
end
local function channel() return IsInRaid and IsInRaid() and 'RAID' or 'PARTY' end
local function send(kind,session,revision,name,value)
 if not GetNumGroupMembers or GetNumGroupMembers()==0 then return false end
 if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
 local msg=table.concat({kind,clean(session,48),tostring(revision or 0),clean(name,65),clean(value,90)},'|')
 if #msg>240 then return false end
 return K.Net.Send(PREFIX,msg,channel())
end
local function newSession()
 local d=db()
 d.sessionClock=math.max(time(),(d.sessionClock or 0)+1)
 d.session=tostring(d.sessionClock)
 d.leader=me();d.revision=0;d.assignments={};d.acks={};d.ready={};d.readyRevisions={}
 return d
end
local function sendSnapshot(d)
 local names={}
 for name in pairs(d.assignments) do names[#names+1]=name end
 table.sort(names)
 send('BEGIN',d.session,d.revision,me(),#names)
 for _,name in ipairs(names) do send('TASK',d.session,d.revision,name,d.assignments[name]) end
 send('END',d.session,d.revision,me(),#names)
end
local function publish()
 if not leader() then say('Only the group leader can publish assignments.');return end
 local d=db()
 if not d.session:match('^%d+$') or not same(d.leader,me()) then
  local assignments=d.assignments
  d=newSession()
  d.assignments=assignments
 end
 d.revision=d.revision+1
 d.acks={};d.ready={};d.readyRevisions={}
 sendSnapshot(d)
 say('Published '..tostring(R.CountAssignments())..' assignments.')
end
function R.CountAssignments() local n=0;for _ in pairs(db().assignments) do n=n+1 end;return n end
local function resend()
 if not leader() or time()-lastReply<5 then return end
 local d=db();if not d.session:match('^%d+$') or not same(d.leader,me()) then return end
 lastReply=time()
 sendSnapshot(d)
end
local function request()
 if not GetNumGroupMembers or GetNumGroupMembers()==0 then say('Join a party or raid first.');return end
 lastRequest=time();send('REQ','0',0,me(),'');say('Requested current raid assignments.')
end
local function myDuty()
 local d=db()
 for name,duty in pairs(d.assignments) do if same(name,me()) then return duty end end
 return nil
end
local function mark(kind)
 local d=db()
 if d.session=='' or not memberName(me()) then say('No active raid session.');return end
 if kind=='ACK' and not myDuty() then say('You have no assignment to acknowledge.');return end
 if not senderLeader(d.leader) then return end
 if kind=='ACK' then
  d.acks[me()]=true
  send(kind,d.session,d.revision,me(),'1')
 else
  local who=identity(me())
  local version=math.max(time(),(d.readyRevisions[who] or 0)+1)
  d.readyRevisions[who]=version
  d.ready[me()]=not d.ready[me()]
  send(kind,d.session,d.revision,me(),version..':'..(d.ready[me()] and '1' or '0'))
 end
end
-- Keep the last complete snapshot until all unique tasks and both markers
-- agree. An incomplete revision never clears or publishes assignments.
local function stage(kind,session,rev,name,value,sender)
 if not senderLeader(sender) then return end
 local source=identity(sender)
 currentLeader=source
 local stamp=session:match('^%d+$') and tonumber(session)
 if not stamp or stamp<=0 or stamp>time()+300 or rev==0 then return end
 local d=db()
 if same(d.leader,sender) then
  local previous=tonumber(d.session) or 0
  if stamp<previous or (stamp==previous and rev<=d.revision) then return end
 end
 local target,count
 if kind=='TASK' then
  target=memberName(name)
  if not target or value=='' then return end
 else
  if not same(sender,name) or not value:match('^%d%d?$') then return end
  count=tonumber(value)
  if count>40 then return end
 end
 local key=source..'|'..session..'|'..rev
 local size=0
 for id,batch in pairs(staged) do
  if batch.source~=source or batch.expires<=time() then staged[id]=nil else size=size+1 end
 end
 local batch=staged[key]
 if not batch then
  if size>=8 then return end
  batch={source=source,expires=time()+90,tasks={},size=0}
  staged[key]=batch
  if C_Timer and C_Timer.After then C_Timer.After(45,function()
   if staged[key]~=batch or leaderIdentity()~=source or time()-lastRequest<20 then return end
   lastRequest=time()
   send('REQ','0',0,me(),'')
  end) end
 end
 if batch.invalid then return end
 if kind=='TASK' then
  if batch.tasks[target] and batch.tasks[target]~=value then batch.invalid=true;return end
  if not batch.tasks[target] then
   if batch.size>=40 then batch.invalid=true;return end
   batch.tasks[target]=value
   batch.size=batch.size+1
  end
 else
  if batch.count and batch.count~=count then batch.invalid=true;return end
  batch.count=count
  batch[kind]=true
 end
 if batch.count and batch.size>batch.count then batch.invalid=true;return end
 if not batch.BEGIN or not batch.END or batch.size~=batch.count then return end
 d.session,d.leader,d.revision=session,sender,rev
 d.assignments,d.acks,d.ready,d.readyRevisions=batch.tasks,{},{},{}
 staged[key]=nil
end
local function onMessage(prefix,msg,where,sender)
 if prefix~=PREFIX or type(msg)~='string' or #msg>240 then return end
 if where~='PARTY' and where~='RAID' then return end
 if where~=channel() or not memberName(sender) then return end
 local kind,session,rev,name,value=msg:match('^([A-Z]+)|([^|]*)|(%d+)|([^|]*)|([^|]*)$')
 if not kind or #session>48 or #name>65 or #value>90 then return end
 rev=tonumber(rev);if not rev or rev>100000000 then return end
 local d=db()
 if kind=='REQ' then
  if same(sender,name) and leader() then resend() end
 elseif kind=='BEGIN' or kind=='TASK' or kind=='END' then
  stage(kind,session,rev,name,value,sender)
 elseif kind=='ACK' or kind=='READY' then
  if d.session~=session or rev~=d.revision or not same(name,sender)
   or not senderLeader(d.leader) then return end
  local target=memberName(sender)
  if not target then return end
  if kind=='ACK' then
   if value=='1' and d.assignments[target] then d.acks[target]=true end
  else
   local version,state=value:match('^(%d+):([01])$')
   version=tonumber(version)
   local who=identity(sender)
   if not version or version<=0 or version>time()+300 or version<=(d.readyRevisions[who] or 0) then return end
   d.readyRevisions[who]=version
   d.ready[target]=state=='1'
  end
 end
 -- Do not rebuild the page during typing; player can click Refresh View.
end
K.On('CHAT_MSG_ADDON',onMessage)
K.On('GROUP_ROSTER_UPDATE',function()
 local authority=leaderIdentity()
 if authority~=currentLeader then
  staged={}
  local d=db()
  if not authority or (d.leader~='' and identity(d.leader)~=authority) then
   d.session,d.leader,d.revision='','',0
   d.assignments,d.ready,d.acks,d.readyRevisions={},{},{},{}
  end
  currentLeader=authority
 end
 if GetNumGroupMembers and GetNumGroupMembers()>0 and time()-lastRequest>20 then
  lastRequest=time();send('REQ','0',0,me(),'')
 end
end)
K.On('PLAYER_ENTERING_WORLD',function()
 if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  pcall(C_ChatInfo.RegisterAddonMessagePrefix,PREFIX)
 end
end)
local function counts()
 local d=db();local ready,acks=0,0
 for _,p in ipairs(members()) do if d.ready[p.name] then ready=ready+1 end;if d.acks[p.name] then acks=acks+1 end end
 return ready,acks
end
-- 2.0: the legacy layout (R.Draw) is replaced by this nonvisual API. Every action
-- keeps the 1.8.2 rules: only the group leader edits/publishes; members ACK/READY.
function R.State()
 local d=db();local ready,acks=counts()
 local roster={}
 for i,p in ipairs(members()) do
  if i>40 then break end
  roster[#roster+1]={name=p.name,group=p.group,role=p.role,class=p.class,online=p.online,
   duty=d.assignments[p.name],ack=d.acks[p.name] and true or false,ready=d.ready[p.name] and true or false}
 end
 local templates={};for name in pairs(d.templates) do templates[#templates+1]=name end;table.sort(templates)
 return {session=d.session,leader=d.leader,isLeader=leader() and true or false,myDuty=myDuty(),
  myAck=d.acks[me()] and true or false,myReady=d.ready[me()] and true or false,
  ready=ready,acks=acks,roster=roster,templates=templates,assignments=R.CountAssignments()}
end
function R.Ack() mark('ACK');if K.UI then K.UI.RaidRefresh() end end
function R.ToggleReady() mark('READY');if K.UI then K.UI.RaidRefresh() end end
function R.Request() request() end
function R.Assign(name,duty)
 if not leader() then say('Only the group leader can edit assignments.');return false end
 local live=memberName(name);if not live then say('Choose a raider in your group.');return false end
 local v=clean(duty,90);if v=='' then say('Enter an assignment.');return false end
 local d=db()
 if d.session=='' or not same(d.leader,me()) then newSession();d=db() end
 d.assignments[live]=v
 publish();if K.UI then K.UI.RaidRefresh() end
 return true
end
function R.Unassign(name)
 if not leader() then say('Only the group leader can edit assignments.');return false end
 local d=db();d.assignments[memberName(name) or name]=nil
 publish();if K.UI then K.UI.RaidRefresh() end
 return true
end
function R.Publish() publish();if K.UI then K.UI.RaidRefresh() end end
function R.SaveTemplate(name)
 name=clean(name,40);if name=='' then say('Enter a template name.');return false end
 local d=db();local snapshot={};for n,v in pairs(d.assignments) do snapshot[n]=v end
 d.templates[name]=snapshot;say('Saved template: '..name);if K.UI then K.UI.RaidRefresh() end
 return true
end
function R.LoadTemplate(name)
 if not leader() then say('Only the group leader can load templates.');return false end
 local d=db();local saved=d.templates[name]
 if type(saved)~='table' then return false end
 if d.session=='' or not same(d.leader,me()) then newSession();d=db() end
 d.assignments={};for n,duty in pairs(saved) do
  local live=memberName(n);if live then d.assignments[live]=clean(duty,90) end
 end
 publish();if K.UI then K.UI.RaidRefresh() end
 return true
end
function R.Toggle() if K.UI then K.UI.Toggle('Raids') end end
