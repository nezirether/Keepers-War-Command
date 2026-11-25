-- War Room page: Raid Operations - guild raid sign-ups (KWCRS), live group
-- assignments (KWCR3) and Keepers Raid Tools (mounted into the War Room).
local K=KWC
local Kit,S,P,W=K.Kit,K.WarRoomSkin,K.WarRoomPages,K.WarRoom2
local OWNER=S.OWNER
local RS=function() return K.RaidSignup end
local RC=function() return K.RaidCommand end

local page={id='raids',title='Raid Operations',subtitle='Schedule raids, sign up, assign duties and run raid tools.',group='guild'}
local state={tab='signups',selected=nil,mode='view',member=nil,tool='Attendance'}
local panes={}
local STATUSES={'Attending','Late','Tentative','Absent','Withdrawn'}
local STATUS_TONE={Attending='good',Late='warn',Tentative='info',Absent='faint',Withdrawn='faint'}
local function act(fn) return function() Kit.Safe(fn);W.Refresh(true) end end

------------------------------------------------------------------ sign-ups
local su={}
local function events() return RS().Ordered and RS().Ordered() or {} end
local function findEvent(id) for _,e in ipairs(events()) do if e.id==id then return e end end end
local function tally(id)
 local t={Attending=0,Late=0,Tentative=0,Absent=0,Withdrawn=0}
 for _,r in pairs(RS().Responses(id)) do if t[r.status] then t[r.status]=t[r.status]+1 end end
 return t
end
local function myStatus(id)
 local me=RS().Me()
 for name,r in pairs(RS().Responses(id)) do if K.SameGuildMember(name,me) then return r.status end end
end
local function buildSignups(pane)
 local left,right=P.Split(pane,360)
 su.bar=P.Toolbar(left,{action='Schedule raid',onAction=function() state.mode='compose';su.filled=false;page:Update() end,actionWidth=140,
  secondary='Sync sign-ups',onSecondary=function() RS().Sync(false) end,secondaryWidth=130})
 su.list=Kit.List(left,58,6,function(row) S.RowBuild(row);row:SetScript('OnClick',function(r) state.selected=r.item.id;state.mode='view';page:Update() end) end,function(row,e)
  local t=tally(e.id);local mine=myStatus(e.id)
  row:Tone(e.cancelled and 'faint' or 'accent')
  row.title:SetText(K.Clean(e.title,60));row.sub:SetText(K.Clean(e.when,45)..'   '..S.Code('good')..t.Attending..' attending|r  '..S.Code('warn')..t.Late..' late|r  '..S.Code('info')..t.Tentative..' maybe|r')
  row.meta:SetText(e.cancelled and 'CANCELLED' or '');row.meta2:SetText(mine or 'No reply')
  row:Select(state.selected==e.id)
 end)
 P.ListHeading(left,su.list,su.bar,'Scheduled raids')
 Kit.Paint(su.list.thumb,OWNER,'line','fill')
 su.list.empty=S.Empty(su.list,'No raids scheduled','War Council and the Warchief schedule raids here. Sign-ups sync to every member.',400,'EmptyRaid');su.list.empty:SetPoint('TOPLEFT',4,-6)
 local _,c=P.DrawerBody(right)
 su.stack=P.Stack(c,310)
 su.head=P.DrawerHead(c,310)
 su.roster=P.Section(c,'Sign-ups',310)
 su.myLabel=S.Text(c,'kicker','faint');su.myLabel:SetText('YOUR REPLY')
 su.reply=CreateFrame('Frame',nil,c);su.reply:SetSize(310,64)
 su.rb={}
 for i,stt in ipairs(STATUSES) do
  local b=S.Button(su.reply,stt,'secondary',act(function() RS().Respond(state.selected,stt) end),98,28)
  su.rb[i]=b
 end
 P.Flow(su.rb,su.reply,310,0,6)
 su.offLabel=S.Text(c,'kicker','faint');su.offLabel:SetText('WAR COUNCIL')
 su.off=CreateFrame('Frame',nil,c);su.off:SetSize(310,30)
 su.edit=S.Button(su.off,'Edit','secondary',function() state.mode='edit';su.filled=false;page:Update() end,70,28)
 su.cancel=S.Button(su.off,'Cancel raid','secondary',act(function() RS().Cancel(state.selected) end),110,28)
 su.del=S.Button(su.off,'Delete','danger',function()
  local id=state.selected
  S.Confirm('Delete this raid?','Every guildmate loses the event and its sign-ups. This cannot be undone.','Delete',function() RS().Delete(id);state.selected=nil;W.Refresh(true) end)
 end,90,28)
 P.Flow({su.edit,su.cancel,su.del},su.off,310,0,8)
 su.empty=S.Empty(c,'Select a raid','',300)
 -- form
 su.title=S.Field(c,'Raid',310,60,'Venomous Abyss - full clear')
 su.when=S.Field(c,'When (include your time zone)',310,45,'Fri 8pm Eastern')
 su.title.next=su.when
 su.save=S.Button(c,'Schedule','primary',function()
  local t,w=su.title:Get(),su.when:Get()
  if t=='' then su.title:Error('Raid name is required.');return end
  if w=='' then su.when:Error('Date and time are required.');return end
  local ok
  if state.mode=='edit' then ok=RS().Edit(state.selected,t,w) else ok=RS().Create(t,w) end
  if not ok then return end
  state.mode='view';su.filled=false;W.Refresh(true);page:Update()
 end,130,32);su.save.keepWidth=true
 su.back=S.Button(c,'Cancel','ghost',function() state.mode='view';su.filled=false;page:Update() end,90,32);su.back.keepWidth=true
end
local function renderSignups()
 local list=events()
 if state.mode=='view' and not state.selected and list[1] then state.selected=list[1].id end
 su.list:SetData(list)
 local officer=K.IsOfficer()
 su.bar.action:SetEnabledState(officer,'Only War Council and the Warchief can schedule guild raids.')
 local st=su.stack;st:Reset()
 for _,k in ipairs({'head','roster','myLabel','reply','offLabel','off','empty','title','when','save','back'}) do su[k]:Hide() end
 if state.mode~='view' then
  local e=state.mode=='edit' and findEvent(state.selected)
  su.head:Set(e and 'Edit raid' or 'Schedule a raid',e and e.title or 'Guild raid');st:Place(su.head,nil,12)
  if not su.filled then su.title:Set(e and e.title or '');su.when:Set(e and e.when or '');su.filled=true end
  st:Place(su.title,52,8);st:Place(su.when,52,14);st:Place(su.save,32,0)
  su.back:ClearAllPoints();su.back:SetPoint('LEFT',su.save,'RIGHT',10,0);su.back:Show()
  return
 end
 local e=state.selected and findEvent(state.selected)
 if not e then st:Place(su.empty,40);return end
 su.head:Set(e.cancelled and 'Cancelled' or 'Guild raid',e.title..'\n'..S.Code('muted')..e.when..'|r');st:Place(su.head,nil,12)
 local groups={}
 for _,stt in ipairs(STATUSES) do groups[stt]={} end
 for name,r in pairs(RS().Responses(e.id)) do if groups[r.status] then table.insert(groups[r.status],P.Short(name)) end end
 local lines={}
 for _,stt in ipairs(STATUSES) do table.sort(groups[stt]);lines[#lines+1]=S.Code(STATUS_TONE[stt])..stt..' ('..#groups[stt]..')|r  '..table.concat(groups[stt],', ') end
 su.roster:Set(table.concat(lines,'\n'));st:Place(su.roster,nil,14)
 if not e.cancelled then
  local mine=myStatus(e.id)
  for i,b in ipairs(su.rb) do Kit.Paint(b.bg,OWNER,STATUSES[i]==mine and 'accentSoft' or 'raised','fill') end
  st:Place(su.myLabel,14,6);st:Place(su.reply,64,12)
 end
 if officer then st:Place(su.offLabel,14,6);st:Place(su.off,30,8) end
end

------------------------------------------------------------------ raid command
local rc={}
local function buildCommand(pane)
 local left,right=P.Split(pane,360)
 rc.status=S.Text(left,'section','text');rc.status:SetPoint('TOPLEFT',0,-4)
 rc.sub=S.Text(left,'small','muted');rc.sub:SetPoint('TOPLEFT',rc.status,'BOTTOMLEFT',0,-4)
 rc.list=Kit.List(left,46,4,function(row) S.RowBuild(row);row:SetScript('OnClick',function(r) state.member=r.item.name;page:Update() end) end,function(row,p)
  local glyph=p.role=='TANK' and 'Tank_Glyph' or p.role=='HEALER' and 'Healer_Glyph' or p.role=='DAMAGER' and 'Damage_Glyph'
  S.RowIcon(row,glyph and (Kit.MEDIA..'WarRoomClassic\\'..glyph) or S.AssetPath('iconGroup'))
  row:Tone(p.ready and 'good' or (p.ack and 'info' or 'faint'))
  row.title:SetText('G'..p.group..'  '..p.name..'  '..S.Code('faint')..(p.role~='NONE' and p.role or (p.class or ''))..'|r')
  row.sub:SetText(p.duty or S.Code('faint')..'No assignment|r')
  row.meta:SetText(p.ack and 'ACK' or 'WAIT');row.meta2:SetText(p.ready and 'READY' or 'not ready')
  row:Select(state.member==p.name)
 end)
 rc.list:SetPoint('TOPLEFT',0,-50);rc.list:SetPoint('BOTTOMRIGHT')
 Kit.Paint(rc.list.thumb,OWNER,'line','fill')
 rc.list.empty=S.Empty(rc.list,'Not in a group','Join a party or raid to see its roster, your duty and readiness.',400);rc.list.empty:SetPoint('TOPLEFT',4,-6)
 local _,c=P.DrawerBody(right)
 rc.stack=P.Stack(c,310)
 rc.mine=P.Section(c,'Your assignment',310)
 rc.me=CreateFrame('Frame',nil,c);rc.me:SetSize(310,30)
 rc.ack=S.Button(rc.me,'Got it','primary',act(function() RC().Ack() end),90,28)
 rc.ready=S.Button(rc.me,'Mark ready','secondary',act(function() RC().ToggleReady() end),110,28)
 rc.req=S.Button(rc.me,'Request sync','ghost',act(function() RC().Request() end),110,28)
 P.Flow({rc.ack,rc.ready,rc.req},rc.me,310,0,6)
 rc.leadLabel=S.Text(c,'kicker','faint');rc.leadLabel:SetText('LEADER: ASSIGN DUTY')
 rc.sel=S.Text(c,'body','muted')
 rc.duty=S.Field(c,'Duty for the selected raider',310,90,'Tank Nekzali adds, interrupt on 2')
 rc.lead=CreateFrame('Frame',nil,c);rc.lead:SetSize(310,30)
 rc.assign=S.Button(rc.lead,'Assign','primary',act(function() if state.member and RC().Assign(state.member,rc.duty:Get()) then rc.duty:Set('') end end),90,28)
 rc.unassign=S.Button(rc.lead,'Clear duty','secondary',act(function() if state.member then RC().Unassign(state.member) end end),100,28)
 rc.publish=S.Button(rc.lead,'Publish all','ghost',act(function() RC().Publish() end),100,28)
 P.Flow({rc.assign,rc.unassign,rc.publish},rc.lead,310,0,6)
 rc.tplName=S.Field(c,'Save assignments as template',310,40,'Template name')
 rc.tplSave=S.Button(c,'Save template','secondary',act(function() if RC().SaveTemplate(rc.tplName:Get()) then rc.tplName:Set('') end end),130,28);rc.tplSave.keepWidth=true
 rc.tpls={}
 for i=1,6 do local b=S.Button(c,'','ghost',nil,310,26);b.keepWidth=true;rc.tpls[i]=b end
 rc.note=S.Para(c,310,'faint',12);rc.note:SetText('Only the group leader edits and publishes. Assignments travel on the group addon channel and never in chat.')
end
local function renderCommand()
 local s=RC().State()
 rc.list:SetData(s.roster)
 rc.status:SetText(#s.roster>0 and (#s.roster..' raiders  -  '..s.ready..' ready  -  '..s.acks..' acknowledged') or 'No active group')
 rc.sub:SetText(s.leader~='' and ('Leader: '..P.Short(s.leader)..(s.isLeader and '  (you)' or '')) or 'Assignments not synchronized')
 local st=rc.stack;st:Reset()
 for _,k in ipairs({'mine','me','leadLabel','sel','duty','lead','tplName','tplSave','note'}) do rc[k]:Hide() end
 for _,b in ipairs(rc.tpls) do b:Hide() end
 rc.mine:Set(s.myDuty or S.Code('faint')..'No assignment yet.|r');st:Place(rc.mine,nil,8)
 rc.ready:SetLabel(s.myReady and 'Not ready' or 'Mark ready')
 rc.ack:SetEnabledState(s.myDuty~=nil and not s.myAck,s.myAck and 'Already acknowledged.' or 'You have no assignment to acknowledge.')
 local grouped=#s.roster>0
 rc.ready:SetEnabledState(grouped,'Join a group first.');rc.req:SetEnabledState(grouped,'Join a group first.')
 st:Place(rc.me,30,16)
 if s.isLeader then
  st:Place(rc.leadLabel,14,6)
  rc.sel:SetText(state.member and ('Selected: '..state.member) or 'Select a raider on the left.');st:Place(rc.sel,16,6)
  st:Place(rc.duty,52,8);st:Place(rc.lead,30,14)
  st:Place(rc.tplName,52,6);st:Place(rc.tplSave,28,10)
  for i,b in ipairs(rc.tpls) do
   local name=s.templates[i]
   if name then b:SetLabel('Load template: '..name);b:SetScript('OnClick',act(function() RC().LoadTemplate(name) end));st:Place(b,26,4) end
  end
  st:Space(8)
 end
 st:Place(rc.note,nil,6)
end

------------------------------------------------------------------ raid tools (KRT)
local rt={}
local TOOLS={'Attendance','Roster','Ready Check','Auto-Invite','Combat Tools',"Don't Release",'Notes'}
local function buildTools(pane)
 rt.bar=CreateFrame('Frame',nil,pane);rt.bar:SetPoint('TOPLEFT');rt.bar:SetPoint('TOPRIGHT');rt.bar:SetHeight(28)
 local opts={};for _,t in ipairs(TOOLS) do opts[#opts+1]={t} end
 rt.seg=S.Segmented(rt.bar,opts,function() return state.tool end,function(v) state.tool=v;rt.mounted=nil;page:Update() end)
 P.TabStrip(rt.bar,rt.seg,function() rt.bar:SetHeight(rt.seg:GetHeight()) end)
 rt.host=CreateFrame('Frame',nil,pane);rt.host:SetPoint('TOPLEFT',rt.bar,'BOTTOMLEFT',0,-12);rt.host:SetPoint('BOTTOMRIGHT',0,22)
 Kit.Fill(rt.host,OWNER,'surface');Kit.Border(rt.host,OWNER,'lineSoft')
 W.raidHost=rt.host
 rt.msg=S.Empty(rt.host,'Raid tools unavailable','',500);rt.msg:SetPoint('TOPLEFT',16,-16)
 rt.credit=S.Text(pane,'small','faint');rt.credit:SetPoint('BOTTOMRIGHT',pane,'BOTTOMRIGHT',0,2)
 rt.credit:SetText('Keepers Raid Tools - adapted from Purplexity Raid Tools by nivthefox')
end
local function renderTools()
 rt.seg:Update()
 if rt.mounted==state.tool then return end
 if InCombatLockdown and InCombatLockdown() then rt.msg:Set('Raid tools open after combat','Configuration panels are unavailable in combat.');rt.msg:Show();return end
 local ok=K.RaidTools and K.RaidTools.Mount and K.RaidTools.Mount(rt.host,state.tool)
 rt.msg:SetShown(not ok)
 if not ok then rt.msg:Set('Raid tools unavailable','The '..state.tool..' panel could not be opened. /reload and try again; report it if it persists.') end
 rt.mounted=ok and state.tool or nil
end

------------------------------------------------------------------ page
function page.Build(self,host)
 local seg=S.Segmented(host,{{'signups','Sign-ups'},{'command','Raid command'},{'tools','Raid tools'},{'spoils','WarSpoils'},{'preview','Policy preview'}},function() return state.tab end,function(v)
  if state.tab=='tools' and v~='tools' and K.RaidTools and K.RaidTools.Close then K.RaidTools.Close();rt.mounted=nil end
  state.tab=v;self:Update()
 end,130)
 P.TabStrip(host,seg);self.seg=seg
 for _,k in ipairs({'signups','command','tools','spoils','preview'}) do
  local f=CreateFrame('Frame',nil,host);f:SetPoint('TOPLEFT',seg,'BOTTOMLEFT',0,-14);f:SetPoint('BOTTOMRIGHT');panes[k]=f
 end
 buildSignups(panes.signups);buildCommand(panes.command);buildTools(panes.tools);P.BuildWarSpoils(panes.spoils);P.BuildSpoilsPreview(panes.preview)
 host:SetScript('OnHide',function() if rt.mounted and K.RaidTools and K.RaidTools.Close then K.RaidTools.Close();rt.mounted=nil end end)
end
function page.OnShow(self,arg)
 if type(arg)=='string' then state.tab='tools';state.tool=arg
 elseif type(arg)=='table' and arg.tab=='spoils' then state.tab='spoils'
 elseif type(arg)=='table' and arg.compose then state.tab='signups';state.mode='compose';su.filled=false end
 if self.seg then self.seg:Update() end
end
function page.Update(self)
 if not self.seg then return end
 self.seg:Update()
 for k,f in pairs(panes) do f:SetShown(k==state.tab) end
 if state.tab=='signups' then renderSignups() elseif state.tab=='command' then renderCommand() elseif state.tab=='tools' then renderTools() elseif state.tab=='spoils' then panes.spoils.WarSpoilsLayout() end
end
function page.Badge() local n=0;for _,e in ipairs(K.RaidSignup.Ordered and K.RaidSignup.Ordered() or {}) do if not e.cancelled then n=n+1 end end;return n end
W.Register(page)
