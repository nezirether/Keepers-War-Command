-- War Room page: Calls to Arms (create / view / respond / command / resolve).
-- All rules are enforced by Engine/Operations.lua; this page mirrors them so
-- buttons are hidden or visibly disabled with a reason instead of failing.
local K=KWC
local Kit,S,P,W=K.Kit,K.WarRoomSkin,K.WarRoomPages,K.WarRoom2
local OWNER=S.OWNER
local O=function() return K.Operations end

local page={id='cta',title='Calls to Arms',subtitle='Rally the guild: post, respond, lead and resolve world PvP calls.',group='ops'}
local state={filter='ACTIVE',query='',selected=nil,mode='view'}
local PRIORITY_TONE={URGENT='danger',HIGH='warn',NORMAL='accent',LOW='faint'}

local function entries()
 local out={}
 for _,e in ipairs(KWCDB and KWCDB.ops or {}) do
  local status=e.status or 'ACTIVE'
  local keep=state.filter=='ALL' or (state.filter=='ACTIVE' and status=='ACTIVE') or (state.filter=='CLOSED' and status~='ACTIVE')
  if keep and P.Matches(e.text..' '..tostring(e.author),state.query) then out[#out+1]=e end
 end
 table.sort(out,function(a,b)
  local sa,sb=(a.status or 'ACTIVE')=='ACTIVE',(b.status or 'ACTIVE')=='ACTIVE'
  if sa~=sb then return sa end
  return (a.created or 0)>(b.created or 0)
 end)
 return out
end
local function find(id) for _,e in ipairs(KWCDB and KWCDB.ops or {}) do if e.id==id then return e end end end
local function priorityOf(e)
 local d=e.details
 if d and d.priority then return d.priority end
 local p=tostring(e.text or ''):match('^%[(%u+)%]')
 return O().NormalizePriority(p)
end
local function headline(e)
 local d=e.details
 if d and d.zone and d.objective then return d.zone..'  -  '..d.objective end
 return (tostring(e.text or ''):gsub('^%[%a+%]%s*',''))
end
local function counts(e)
 local c,m,b=0,0,0
 for _,r in pairs((KWCDB.responses or {})[e.id] or {}) do if r=='Coming' then c=c+1 elseif r=='Maybe' then m=m+1 elseif r=='Busy' then b=b+1 end end
 return c,m,b
end
local function faction(e)
 local d=e.details
 local h,a=d and tonumber(d.horde),d and tonumber(d.alliance)
 if not h then local x,y=tostring(e.text):match('H:A (%d+):(%d+)');h,a=tonumber(x),tonumber(y) end
 if not h then return nil end
 local hc,ac=S.Code(h>=a and 'horde' or 'muted'),S.Code(a>h and 'alliance' or 'muted')
 return hc..'Horde '..h..'|r  vs  '..ac..'Alliance '..a..'|r'
end
local function iCan(e)
 local me=P.Me()
 local owner=K.SameGuildMember(e.author,me) or tostring(e.author):lower()==me:lower()
 return owner or K.IsOfficer(),owner
end

------------------------------------------------------------------ list
local list,empty,toolbar
local function fillRow(row,e)
 local pr=priorityOf(e);local active=(e.status or 'ACTIVE')=='ACTIVE'
 S.RowIcon(row,S.AssetPath(pr=='URGENT' and 'urgentGlyph' or pr=='NORMAL' and 'normalGlyph' or 'iconSword'))
 row:Tone(active and PRIORITY_TONE[pr] or 'faint')
 row.title:SetText(headline(e))
 local c=counts(e)
 local f=faction(e)
 row.sub:SetText((f and (f..'   ') or '')..S.Code('muted')..'Cmdr '..P.Short(O().Commander(e))..'  -  '..c..' coming|r')
 row.meta:SetText(Kit.Age(e.created))
 row.meta2:SetText(active and pr or (e.status or ''))
 row:Select(state.selected==e.id)
end

------------------------------------------------------------------ drawer: view
local view={}
local form={}
local function act(fn) return function() Kit.Safe(fn);W.Refresh(true) end end
local function buildView(pane)
 local scroll,c=P.DrawerBody(pane)
 view.scroll,view.content=scroll,c
 local w=330
 view.stack=P.Stack(c,w)
 view.head=P.DrawerHead(c,w)
 view.situation=P.Section(c,'Situation',w)
 view.leaders=P.Section(c,'Leadership',w)
 view.responses=P.Section(c,'Responses',w)
 view.respondLabel=S.Text(c,'kicker','faint');view.respondLabel:SetText('YOUR RESPONSE')
 view.respond=CreateFrame('Frame',nil,c);view.respond:SetSize(w,30)
 view.rb={}
 for i,st in ipairs({'Coming','Maybe','Busy'}) do
  local variant=st=='Coming' and 'success' or st=='Maybe' and 'warning' or 'danger'
  local b=S.Button(view.respond,st,variant,act(function() O().Respond(state.selected,st) end),104,30)
  b:SetPoint('LEFT',(i-1)*112,0);view.rb[st]=b
 end
 view.joinLabel=S.Text(c,'kicker','faint');view.joinLabel:SetText('JOIN REQUESTS')
 view.joins={}
 for i=1,5 do
  local b=S.Button(c,'',"secondary",nil,w,26);b.keepWidth=true
  view.joins[i]=b
 end
 view.actionsLabel=S.Text(c,'kicker','faint');view.actionsLabel:SetText('ACTIONS')
 view.actions=CreateFrame('Frame',nil,c);view.actions:SetSize(w,40)
 local A=view.actions
 view.btn={
  join=S.Button(A,'Request to join','secondary',act(function() K.CTAJoin.Request(state.selected) end),150),
  edit=S.Button(A,'Edit','secondary',function() state.mode='edit';form.filled=false;page:Update() end,80),
  victory=S.Button(A,'Victory','primary',act(function() K.Celebrations.CompleteCTA(state.selected,'VICTORY') end),100),
  objective=S.Button(A,'Objective completed','secondary',act(function() K.Celebrations.CompleteCTA(state.selected,'OBJECTIVE') end),160),
  withdrawn=S.Button(A,'Withdraw','secondary',act(function() K.Celebrations.CompleteCTA(state.selected,'WITHDRAWN') end),100),
  resolve=S.Button(A,'Resolve','primary',act(function() O().ChangeStatus('CTA',state.selected,'RESOLVED') end),100),
  cancel=S.Button(A,'Stand down','secondary',act(function() O().ChangeStatus('CTA',state.selected,'CANCELLED') end),110),
  reopen=S.Button(A,'Reopen','primary',act(function() O().ChangeStatus('CTA',state.selected,'ACTIVE') end),100),
  assume=S.Button(A,'Assume command','secondary',act(function() O().AssumeCommand(state.selected) end),150),
  report=S.Button(A,'Draft guild report','ghost',act(function() O().Report('CTA',state.selected) end),160),
  delete=S.Button(A,'Delete','danger',function()
   local id=state.selected
   S.Confirm('Delete this Call to Arms?','It is removed for every guildmate and a tombstone stops old copies from coming back. This cannot be undone.','Delete',function()
    if O().Delete('CTA',id) then state.selected=nil end;W.Refresh(true)
   end)
  end,90),
 }
 view.btn.assume.tipBody='War Council and Warchief can take an additional command seat on an active CTA.'
 view.btn.report.tipBody='Prepares a /g line in your chat box. Nothing is sent until you press Enter.'
 -- Lieutenant assignment (commanders only)
 view.ltLabel=S.Text(c,'kicker','faint');view.ltLabel:SetText('LIEUTENANT')
 view.lt=S.Field(c,'Guildmate who takes over if you disconnect',w,60,'Character name')
 view.ltBtn=S.Button(c,'Assign lieutenant','secondary',act(function()
  local n=view.lt:Get();if n=='' then view.lt:Error('Enter a guildmate name.');return end
  if not K.IsMember(n) then view.lt:Error('Not found on the live guild roster.');return end
  if O().AssignLieutenant(state.selected,n) then view.lt:Set('') end
 end),170)
 view.ltBtn.keepWidth=true
 view.empty=S.Empty(c,'Nothing selected','Pick a call on the left, or post a new one. Your responses sync to every guildmate running KWC.',w)
end

local function joinRows(e)
 local names=K.CTAJoin and K.CTAJoin.Pending(e.id) or {}
 for i,b in ipairs(view.joins) do
  local n=names[i]
  if n then
   b:SetLabel('Invite '..P.Short(n));b.tipBody='Invites when the game allows it (group leader, out of combat).'
   b:SetScript('OnClick',act(function() K.CTAJoin.Invite(e.id,n) end))
  end
  b:SetShown(n~=nil);b.want=n~=nil
 end
 return #names
end

local function renderView(e)
 local st=view.stack;st:Reset()
 for _,k in ipairs({'head','situation','leaders','responses','respondLabel','respond','joinLabel','actionsLabel','actions','ltLabel','lt','ltBtn','empty'}) do view[k]:Hide() end
 for _,b in ipairs(view.joins) do b:Hide() end
 if not e then st:Place(view.empty,60);return end
 local active=(e.status or 'ACTIVE')=='ACTIVE'
 local pr=priorityOf(e)
 view.head:Set(pr..'  -  '..(e.status or 'ACTIVE'),headline(e))
 st:Place(view.head,nil,14)
 local d=e.details or {}
 local lines={}
 local outcome=K.Celebrations.Outcome(e.id)
 if outcome then lines[#lines+1]='Confirmed outcome: '..outcome.outcome..' • '..outcome.actor end
 local f=faction(e);if f then lines[#lines+1]=f end
 if d.coords and d.coords~='' then lines[#lines+1]='Coordinates: '..d.coords end
 if d.notes and d.notes~='' then lines[#lines+1]='Notes: '..d.notes end
 if not d.zone then lines[#lines+1]=K.Clean(e.text,165) end
 lines[#lines+1]=S.Code('faint')..'Posted by '..P.Short(e.author)..'  '..Kit.Age(e.created)..' ago'..(e.updatedBy and ('  -  edited by '..P.Short(e.updatedBy)) or '')..'|r'
 view.situation:Set(table.concat(lines,'\n'));st:Place(view.situation,nil,14)
 local L=O().CTALeadership(e)
 local cmdrs={};for _,n in ipairs(O().Commanders(e)) do cmdrs[#cmdrs+1]=P.Short(n) end
 local lt={};for cmd,l in pairs(e.lieutenants or {}) do lt[#lt+1]=P.Short(l)..' (for '..P.Short(cmd)..')' end
 local warlord=O().Warlord()
 local lead={'Commander: '..table.concat(cmdrs,', ')}
 if #L.officers>0 then lead[#lead+1]='Co-commanders: '..table.concat(L.officers,', ') end
 if L.warchief then lead[#lead+1]='Warchief responding: '..L.warchief end
 if warlord then lead[#lead+1]='Warlord (in your group): '..P.Short(warlord) end
 if #lt>0 then lead[#lead+1]='Lieutenants: '..table.concat(lt,', ') end
 view.leaders:Set(table.concat(lead,'\n'));st:Place(view.leaders,nil,14)
 local groups={Coming={},Maybe={},Busy={}}
 for name,r in pairs((KWCDB.responses or {})[e.id] or {}) do if groups[r] then table.insert(groups[r],P.Short(name)) end end
 for _,g in pairs(groups) do table.sort(g) end
 local function line(k,tone) return S.Code(tone)..k..' ('..#groups[k]..')|r  '..(#groups[k]>0 and table.concat(groups[k],', ') or S.Code('faint')..'none|r') end
 view.responses:Set(line('Coming','good')..'\n'..line('Maybe','warn')..'\n'..line('Busy','faint'));st:Place(view.responses,nil,16)
 local mine=((KWCDB.responses or {})[e.id] or {})[K.LocalGuildMember and K.LocalGuildMember() or '']
 if active then
  st:Place(view.respondLabel,14,6)
  for k,b in pairs(view.rb) do
   b:SetEnabledState(true)
   Kit.Paint(b.bg,OWNER,mine==k and 'accentSoft' or 'raised','fill')
   b.tipBody=mine==k and 'Your current response.' or nil
  end
  st:Place(view.respond,30,16)
 end
 local me=P.Me()
 local isCommander=O().IsCommander(e,me)
 if active and isCommander then
  local n=joinRows(e)
  if n>0 then
   st:Place(view.joinLabel,14,6)
   for _,b in ipairs(view.joins) do if b.want then st:Place(b,26,4) end end
   st:Space(10)
  end
 end
 local canManage,owner=iCan(e)
 local B=view.btn
 B.join:SetShown(active and not isCommander)
 B.edit:SetShown(canManage and active)
 B.resolve:SetShown(canManage and active)
 B.victory:SetShown(canManage and active);B.objective:SetShown(canManage and active);B.withdrawn:SetShown(canManage and active)
 B.cancel:SetShown(canManage and active)
 B.reopen:SetShown(canManage and not active)
 B.assume:SetShown(active and K.IsOfficer() and not isCommander)
 if B.assume:IsShown() then local ok=O().CanAssumeCommand(e);B.assume:SetEnabledState(ok,'Requires live War Council/Warchief rank and an active, synced CTA.') end
 B.report:SetShown(true)
 B.delete:SetShown(O().CanDelete(e))
 local order={B.join,B.edit,B.victory,B.objective,B.withdrawn,B.resolve,B.cancel,B.reopen,B.assume,B.report,B.delete}
 local h=P.Flow(order,view.actions,st.width,0,8)
 view.actions:SetHeight(h)
 st:Place(view.actionsLabel,14,6);st:Place(view.actions,h,16)
 if active and isCommander then
  st:Place(view.ltLabel,14,6);st:Place(view.lt,52,4);st:Place(view.ltBtn,30,10)
 end
end

------------------------------------------------------------------ drawer: compose/edit
local function buildForm(pane)
 local scroll,c=P.DrawerBody(pane)
 form.scroll,form.content=scroll,c
 local w=330
 form.stack=P.Stack(c,w)
 form.head=P.DrawerHead(c,w)
 form.zone=S.Field(c,'Zone',w,38,'Where is the fight?')
 form.coords=S.Field(c,'Coordinates (optional)',w,18,'e.g. 54.2, 61.8')
 form.objective=S.Field(c,'Objective',w,55,'Defend Tarren Mill')
 form.counts=CreateFrame('Frame',nil,c);form.counts:SetSize(w,52)
 form.horde=S.Field(form.counts,'Horde present',158,3,'0');form.horde:SetPoint('TOPLEFT')
 form.alliance=S.Field(form.counts,'Alliance seen',158,3,'0');form.alliance:SetPoint('TOPRIGHT')
 form.prLabel=S.Text(c,'kicker','muted');form.prLabel:SetText('PRIORITY')
 form.priority='NORMAL'
 form.pr=S.Segmented(c,{{'LOW','Low'},{'NORMAL','Normal'},{'HIGH','High'},{'URGENT','Urgent'}},function() return form.priority end,function(v) form.priority=v end,80)
 form.pr.keepWidth=true
 form.notes=S.Field(c,'Notes (optional)',w,35,'Bring healers')
 form.zone.next,form.coords.next,form.objective.next,form.horde.next,form.alliance.next=form.coords,form.objective,form.horde,form.alliance,form.notes
 form.here=S.Link(c,'Use my location',function() form.zone:Set(P.HereZone());form.coords:Set(P.HereCoords()) end)
 form.here.keepWidth=true
 form.submit=S.Button(c,'Publish to guild','primary',nil,170,32);form.submit.keepWidth=true
 form.cancel=S.Button(c,'Cancel','ghost',function() state.mode='view';form.filled=false;page:Update() end,90,32);form.cancel.keepWidth=true
 form.note=S.Para(c,w,'faint',12)
 form.note:SetText('Publishing sends the call over the guild addon channel only. Nothing is posted in public chat.')
 form.submit:SetScript('OnClick',function()
  local zone,obj=form.zone:Get(),form.objective:Get()
  local h,a=tonumber(form.horde:Get()=='' and '0' or form.horde:Get()),tonumber(form.alliance:Get()=='' and '0' or form.alliance:Get())
  local bad=false
  if zone=='' then form.zone:Error('Zone is required.');bad=true end
  if obj=='' then form.objective:Error('Objective is required.');bad=true end
  if not h or h<0 or h>999 or h~=math.floor(h) then form.horde:Error('0-999');bad=true end
  if not a or a<0 or a>999 or a~=math.floor(a) then form.alliance:Error('0-999');bad=true end
  if bad then return end
  if state.mode=='edit' then
   Kit.Safe(O().UpdateCTA,state.selected,zone,h,a,obj,form.priority,form.notes:Get())
  else
   local before=KWCDB.ops[1]
   Kit.Safe(O().DetailedCTA,zone,obj,h,a,form.priority,form.coords:Get(),form.notes:Get())
   if KWCDB.ops[1] and KWCDB.ops[1]~=before then state.selected=KWCDB.ops[1].id end
  end
  state.mode='view';form.filled=false;W.Refresh(true);page:Update()
 end)
end
local function renderForm(e)
 local st=form.stack;st:Reset()
 local editing=state.mode=='edit' and e
 form.head:Set(editing and 'Edit call' or 'New call to arms',editing and headline(e) or 'Rally the Keepers')
 st:Place(form.head,nil,14)
 if not form.filled then
  local d=editing and e.details or {}
  form.zone:Set(d.zone or (editing and '' or P.HereZone()))
  form.coords:Set(d.coords or (editing and '' or P.HereCoords()))
  form.objective:Set(d.objective or '')
  form.horde:Set(d.horde or '');form.alliance:Set(d.alliance or '')
  form.priority=editing and priorityOf(e) or 'NORMAL';form.pr:Update()
  form.notes:Set(d.notes or '')
  form.filled=true
 end
 st:Place(form.zone,52,8)
 st:Place(form.here,18,8)
 form.coords:SetShown(not editing)
 if not editing then st:Place(form.coords,52,8) end
 st:Place(form.objective,52,8);st:Place(form.counts,52,10)
 st:Place(form.prLabel,14,6);st:Place(form.pr,28,14)
 st:Place(form.notes,52,16)
 form.submit:SetLabel(editing and 'Save changes' or 'Publish to guild')
 st:Actions({form.submit,form.cancel},14);st:Place(form.note,nil,10)
end

------------------------------------------------------------------ page
function page.Build(self,host)
 local left,right=P.Split(host,380)
 toolbar=P.Toolbar(left,{search=function(t) state.query=t;if list then list:ScrollTo(1) end;self:Update() end,searchHint='Search calls',
  segments={{'ACTIVE','Active'},{'CLOSED','Closed'},{'ALL','All'}},get=function() return state.filter end,
  set=function(v) state.filter=v;self:Update() end,segWidth=72,
  action='New call to arms',onAction=function() state.mode='compose';form.filled=false;self:Update();form.zone.edit:SetFocus() end,actionWidth=160})
 list=Kit.List(left,60,6,function(row) S.RowBuild(row);row:SetScript('OnClick',function(r) state.selected=r.item.id;state.mode='view';self:Update() end) end,fillRow)
 P.ListHeading(left,list,toolbar,'Calls')
 Kit.Paint(list.thumb,OWNER,'line','fill')
 empty=S.Empty(list,'No calls here yet','When a guildmate posts a Call to Arms it appears here instantly. Post one with "New call to arms".',420,'EmptyCTA')
 empty:SetPoint('TOPLEFT',4,-6);list.empty=empty
 view.pane=CreateFrame('Frame',nil,right);view.pane:SetAllPoints(right)
 form.pane=CreateFrame('Frame',nil,right);form.pane:SetAllPoints(right)
 buildView(view.pane);buildForm(form.pane)
end
function page.OnShow(self,arg)
 if type(arg)=='table' then
  if arg.compose then state.mode='compose';form.filled=false end
  if arg.select then state.selected=arg.select;state.mode='view';state.filter='ALL' end
 end
 if toolbar and toolbar.seg then toolbar.seg:Update() end
end
function page.Update(self)
 if not list then return end
 local rows=entries()
 if state.mode=='view' and not state.selected and rows[1] then state.selected=rows[1].id end
 list:SetData(rows)
 local e=state.selected and find(state.selected)
 if state.mode=='view' then
  form.pane:Hide();view.pane:Show();renderView(e)
 else
  -- Background sync never overwrites a form in progress (fields persist until cancel/submit).
  view.pane:Hide();form.pane:Show();renderForm(state.mode=='edit' and e or nil)
 end
end
function page.Badge()
 local n=0;for _,e in ipairs(KWCDB and KWCDB.ops or {}) do if (e.status or 'ACTIVE')=='ACTIVE' then n=n+1 end end;return n
end
W.Register(page)
