-- KT Raid Command v2: independent group-only raid operations.
-- Deliberately no protected actions, no MRT dependency, no existing KWC sync changes.
local K=KWC
local R={};K.RaidCommand=R
local PREFIX='KWCR2'
local selected,selectedTemplate,editorDuty='',nil,''
local lastRequest=0
local function say(s) K.Say('KT Raid: '..s) end
local function clean(s,n) return tostring(s or ''):gsub('[|\r\n]',' '):sub(1,n or 80) end
local function db()
 KWCDB.raidCommand=KWCDB.raidCommand or {}
 local d=KWCDB.raidCommand
 d.templates=d.templates or {};d.assignments=d.assignments or {};d.acks=d.acks or {};d.ready=d.ready or {}
 d.session=d.session or '';d.leader=d.leader or '';d.revision=d.revision or 0
 return d
end
local function me() return UnitName('player') or '' end
local function norm(s) return tostring(s or ''):lower():match('^[^-]+') end
local function same(a,b) return norm(a) and norm(a)==norm(b) end
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
   local name=UnitName(unit)
   if name and name~='' then
    local role=UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or 'NONE'
    local class=select(2,UnitClass(unit)) or ''
    local subgroup=1
    if raid and GetRaidRosterInfo then
     local index=tonumber(unit:match('%d+'))
     local _,_,g=GetRaidRosterInfo(index);subgroup=g or 1
    end
    result[#result+1]={name=name,unit=unit,role=role,class=class,group=subgroup,online=UnitIsConnected(unit)~=false}
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
 for _,p in ipairs(members()) do if same(name,p.name) then return p.name end end
 return nil
end
local function leader()
 return GetNumGroupMembers and GetNumGroupMembers()>0 and UnitIsGroupLeader and UnitIsGroupLeader('player')
end
local function senderLeader(name)
 for _,p in ipairs(members()) do
  if same(name,p.name) and UnitIsGroupLeader and UnitIsGroupLeader(p.unit) then return true end
 end
 return false
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
 local d=db();d.session=clean(me(),20)..'-'..tostring(time())
 d.leader=me();d.revision=0;d.assignments={};d.acks={};d.ready={}
 return d
end
local function publish()
 if not leader() then say('Only the group leader can publish assignments.');return end
 local d=db()
 if d.session=='' or not same(d.leader,me()) then d=newSession() end
 d.revision=d.revision+1
 d.acks={};d.ready={}
 send('BEGIN',d.session,d.revision,me(),'')
 for name,duty in pairs(d.assignments) do send('TASK',d.session,d.revision,name,duty) end
 send('END',d.session,d.revision,me(),'')
 say('Published '..tostring(R.CountAssignments())..' assignments.')
end
function R.CountAssignments() local n=0;for _ in pairs(db().assignments) do n=n+1 end;return n end
local function resend()
 if not leader() then return end
 local d=db();if d.session=='' or not same(d.leader,me()) then return end
 send('BEGIN',d.session,d.revision,me(),'')
 for name,duty in pairs(d.assignments) do send('TASK',d.session,d.revision,name,duty) end
 send('END',d.session,d.revision,me(),'')
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
 if kind=='ACK' then d.acks[me()]=true else d.ready[me()]=not d.ready[me()] end
 send(kind,d.session,d.revision,me(),kind=='ACK' and '1' or (d.ready[me()] and '1' or '0'))
end
local function onMessage(prefix,msg,where,sender)
 if prefix~=PREFIX or type(msg)~='string' or #msg>240 then return end
 if where~='PARTY' and where~='RAID' then return end
 if not memberName(sender) then return end
 local kind,session,rev,name,value=msg:match('^([A-Z]+)|([^|]*)|(%d+)|([^|]*)|([^|]*)$')
 if not kind or #session>48 or #name>65 or #value>90 then return end
 rev=tonumber(rev);if not rev or rev>100000000 then return end
 local d=db()
 if kind=='REQ' then
  if leader() then resend() end
 elseif kind=='BEGIN' then
  if not senderLeader(sender) or not same(sender,name) or rev==0 then return end
  if d.session~=session or rev>d.revision then
   d.session=session;d.leader=sender;d.revision=rev;d.assignments={};d.acks={};d.ready={}
  end
 elseif kind=='TASK' then
  if not senderLeader(sender) or d.session~=session or rev~=d.revision then return end
  local target=memberName(name)
  if target then d.assignments[target]=value end
 elseif kind=='END' then
  if not senderLeader(sender) or d.session~=session or rev~=d.revision then return end
 elseif kind=='ACK' or kind=='READY' then
  if d.session~=session or rev~=d.revision or not same(name,sender) then return end
  local target=memberName(sender);if not target then return end
  if kind=='ACK' then d.acks[target]=(value=='1') else d.ready[target]=(value=='1') end
 end
 -- Do not rebuild the page during typing; player can click Refresh View.
end
K.On('CHAT_MSG_ADDON',onMessage)
K.On('GROUP_ROSTER_UPDATE',function()
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
local templateDraft
function R.Draw(parent,label,button,edit)
 local roster=members();local d=db();local lead=leader();local total=#roster
 local ready,acks=counts()
 label(parent,'KT RAID COMMAND',12,-12,560,'GameFontNormalLarge')
 label(parent,'Raid operations  /  Readiness  /  Personal assignments',12,-48,560)
 if total==0 then
  label(parent,'NO ACTIVE PARTY OR RAID',12,-101,560,'GameFontNormal')
  label(parent,'Join a group to view its live roster and assignments.',12,-139,560)
  label(parent,'Saved raid templates',12,-207,550,'GameFontNormal')
 else
  label(parent,'RAIDERS: '..total..'    READY: '..ready..'    ACKNOWLEDGED: '..acks,12,-96,560,'GameFontNormal')
  label(parent,'Leader: '..(d.leader~='' and d.leader or 'Not synchronized'),12,-126,560)
  label(parent,'YOUR ASSIGNMENT',12,-166,550,'GameFontNormal')
  label(parent,myDuty() or 'No assignment yet. Your raid leader can assign one.',12,-198,560)
  label(parent,'Acknowledged: '..(d.acks[me()] and 'YES' or 'NO')..'     Ready: '..(d.ready[me()] and 'YES' or 'NO'),12,-227,550)
  button(parent,'Got It',12,-260,125,function()mark('ACK');K.UI.RaidRefresh() end)
  button(parent,d.ready[me()] and 'Not Ready' or 'Mark Ready',147,-260,125,function()mark('READY');K.UI.RaidRefresh() end)
  button(parent,'Request Sync',282,-260,125,function()request() end)
  button(parent,'Refresh View',417,-260,125,function()K.UI.RaidRefresh() end)
 end
 local y=total>0 and -320 or -250
 label(parent,'RAID TEMPLATES',12,y,560,'GameFontNormal')
 local templates={};for name in pairs(d.templates) do templates[#templates+1]=name end;table.sort(templates)
 local tY=y-40
 if #templates==0 then label(parent,'No saved templates yet.',12,tY,560);tY=tY-30 end
 for i,name in ipairs(templates) do if i>8 then break end
  button(parent,(selectedTemplate==name and '> ' or '')..name,12,tY,290,function()selectedTemplate=name;K.UI.RaidRefresh() end)
  if lead then button(parent,'Load',314,tY,90,function()
   local saved=d.templates[name]
   if type(saved)~='table' then return end
   if d.session=='' or not same(d.leader,me()) then newSession() end
   d.assignments={};for n,duty in pairs(saved) do
    local live=memberName(n);if live then d.assignments[live]=clean(duty,90) end
   end
   publish();K.UI.RaidRefresh()
  end) end
  tY=tY-42
 end
 if not lead then
  if total>0 then label(parent,'Only the group leader can edit and publish assignments.',12,tY-10,560) end
  label(parent,'GROUP ROSTER',12,tY-55,560,'GameFontNormal')
  local ry=tY-90
  for i,p in ipairs(roster) do
   if i>40 then break end
   local duty=d.assignments[p.name] or 'No assignment'
   label(parent,('G%d  %s  (%s)'):format(p.group,p.name,p.role),12,ry,550)
   label(parent,'  '..duty..'   ['..(d.acks[p.name] and 'ACK' or 'WAIT')..'] ['..(d.ready[p.name] and 'READY' or 'NOT READY')..']',12,ry-22,550)
   ry=ry-55
  end
  return
 end
 local editY=tY-12
 label(parent,'LEADER ASSIGNMENT EDITOR',12,editY,550,'GameFontNormal')
 label(parent,'Choose a raider from the roster, then enter their duty.',12,editY-33,550)
 label(parent,'Selected: '..(selected or 'None'),12,editY-62,560)
 local duty=edit(parent,editorDuty,12,editY-89,540)
 duty:SetScript('OnTextChanged',function(self)editorDuty=self:GetText() end)
 button(parent,'Set Assignment',12,editY-129,165,function()
  if not selected or not memberName(selected) then say('Choose a raider below.');return end
  local v=clean(duty:GetText(),90);if v=='' then say('Enter an assignment.');return end
  if d.session=='' or not same(d.leader,me()) then newSession() end
  d.assignments[memberName(selected)]=v;editorDuty=v
  publish();K.UI.RaidRefresh()
 end)
 button(parent,'Remove Duty',187,editY-129,130,function()
  if selected then d.assignments[memberName(selected) or selected]=nil;publish();K.UI.RaidRefresh() end
 end)
 button(parent,'Publish All',327,editY-129,125,function()publish();K.UI.RaidRefresh() end)
 label(parent,'Save template as',12,editY-183,250)
 local templateName=edit(parent,templateDraft or selectedTemplate or '',12,editY-208,320)
 templateName:SetScript('OnTextChanged',function(self)templateDraft=self:GetText() end)
 button(parent,'Save Template',342,editY-208,200,function()
  local name=clean(templateName:GetText(),40)
  if name=='' then say('Enter a template name.');return end
  local snapshot={};for n,v in pairs(d.assignments) do snapshot[n]=v end
  d.templates[name]=snapshot;selectedTemplate=name;templateDraft=nil
  say('Saved template: '..name);K.UI.RaidRefresh()
 end)
 local ry=editY-278
 label(parent,'LIVE RAID ROSTER  /  SELECT PLAYER',12,ry,550,'GameFontNormal')
 ry=ry-38
 for i,p in ipairs(roster) do
  if i>40 then break end
  local name=p.name
  button(parent,(selected and same(selected,name) and '> ' or '')..'G'..p.group..' '..name,12,ry,245,function()
   selected=name;editorDuty=d.assignments[name] or '';K.UI.RaidRefresh()
  end)
  label(parent,p.role~='NONE' and p.role or p.class,265,ry-9,92)
  label(parent,d.acks[name] and 'ACK' or 'WAIT',357,ry-9,65)
  label(parent,d.ready[name] and 'READY' or 'NOT READY',428,ry-9,112)
  if d.assignments[name] then label(parent,d.assignments[name],25,ry-36,515) end
  ry=ry-(d.assignments[name] and 73 or 48)
 end
end
function R.Toggle() if K.UI then K.UI.Toggle('Raid Tools: Command') end end
