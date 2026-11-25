-- War Room page: Guild LFG (guild-only group finder; synced over KWL1).
local K=KWC
local Kit,S,P,W=K.Kit,K.WarRoomSkin,K.WarRoomPages,K.WarRoom2
local OWNER=S.OWNER
local L=function() return K.GuildLFG end

local page={id='lfg',title='Guild LFG',subtitle='Find guildmates for dungeons, raids, world PvP and more.',group='guild'}
local ACTIVITIES={'Dungeon','Questing','World PvP','Battlegrounds','Raid','Farming','Other'}
local ROLES={'Tank','Healer','DPS','Any'}
local state={filter='ALL',query='',selected=nil,mode='view'}
local list,toolbar,waiting
local view,form={},{}

local function all()
 local mine=L().Browse({mine=true})
 local open=L().Browse({})
 local seen,out={},{}
 for _,set in ipairs({open,mine}) do
  for _,r in ipairs(set) do
   if not seen[r.id] and (state.filter=='ALL' or (state.filter=='MINE' and r.mine)) and P.Matches(r.name..' '..r.activity..' '..r.description..' '..r.owner,state.query) then
    seen[r.id]=true;out[#out+1]=r
   end
  end
 end
 table.sort(out,function(a,b) if (a.status=='open')~=(b.status=='open') then return a.status=='open' end;return (a.createdAt or 0)>(b.createdAt or 0) end)
 return out
end
local function find(id) for _,r in ipairs(all()) do if r.id==id then return r end end end
local function roles(r) local t={};for _,x in ipairs(ROLES) do if r.roles[x] then t[#t+1]=x end end;return table.concat(t,', ') end
local function fill(row,r)
 row:Tone(r.status=='open' and 'info' or 'faint')
 row.title:SetText(r.activity..':  '..r.name)
 row.sub:SetText('Needs '..r.needed..' of '..r.groupSize..'  -  '..roles(r)..'  -  lvl '..r.minLevel..'-'..r.maxLevel..'  -  '..P.Short(r.owner))
 row.meta:SetText(r.status=='open' and ('ends '..math.max(0,math.floor(((r.expiresAt or 0)-time())/60))..'m') or r.status)
 row.meta2:SetText(r.interested and 'Interested' or (r.mine and 'Yours' or ''))
 row:Select(state.selected==r.id)
end
local function act(fn) return function() Kit.Safe(fn);W.Refresh(true) end end

local function buildView(pane)
 local _,c=P.DrawerBody(pane)
 view.stack=P.Stack(c,330)
 view.head=P.DrawerHead(c,330)
 view.info=P.Section(c,'Group',330)
 view.desc=P.Section(c,'Details',330)
 view.who=P.Section(c,'Interested guildmates',330)
 view.invites={}
 for i=1,6 do local b=S.Button(c,'','secondary',nil,330,26);b.keepWidth=true;view.invites[i]=b end
 view.msg=Kit.Text(c,OWNER,'narrow',13,'warn')
 view.actions=CreateFrame('Frame',nil,c);view.actions:SetSize(330,40)
 local A=view.actions
 view.btn={
  join=S.Button(A,"I'm interested",'primary',act(function() if not L().Interest(state.selected,true) then view.err='Could not register interest (listing closed or full).' end end),140),
  leave=S.Button(A,'Withdraw interest','secondary',act(function() L().Interest(state.selected,false) end),150),
  whisper=S.Button(A,'Whisper leader','secondary',act(function() L().Whisper(state.selected) end),140),
  edit=S.Button(A,'Edit','secondary',function() state.mode='edit';form.filled=false;page:Update() end,80),
  renew=S.Button(A,'Renew','secondary',act(function() local r=find(state.selected);if r then local ok,err=L().Update(r.id,r.revision,'renew');if not ok then view.err=err end end end),90),
  close=S.Button(A,'Close listing','secondary',act(function() local r=find(state.selected);if r then local ok,err=L().Update(r.id,r.revision,'close');if not ok then view.err=err end end end),120),
  delete=S.Button(A,'Delete','danger',function()
   local r=find(state.selected);if not r then return end
   S.Confirm('Delete this listing?','Guildmates stop seeing it immediately. This cannot be undone.','Delete',function() L().Update(r.id,r.revision,'delete');state.selected=nil;W.Refresh(true) end)
  end,90),
 }
 view.empty=S.Empty(c,'No group selected','Pick a listing or start one. Listings expire on their own; nothing is posted in public chat.',330)
end
local function renderView(r)
 local st=view.stack;st:Reset()
 for _,k in ipairs({'head','info','desc','who','msg','actions','empty'}) do view[k]:Hide() end
 for _,b in ipairs(view.invites) do b:Hide() end
 if not r then st:Place(view.empty,60);return end
 view.head:Set(r.activity..'  -  '..r.status,r.name);st:Place(view.head,nil,14)
 view.info:Set('Leader: '..P.Short(r.owner)..'\nNeeds '..r.needed..' more for a group of '..r.groupSize..'\nRoles: '..roles(r)..'\nLevels '..r.minLevel..' to '..r.maxLevel..'\n'..S.Code('faint')..'Expires in '..math.max(0,math.floor(((r.expiresAt or 0)-time())/60))..' minutes|r');st:Place(view.info,nil,14)
 if r.description~='' then view.desc:Set(r.description);st:Place(view.desc,nil,14) end
 if r.mine then
  local names=r.interestedMembers or {}
  table.sort(names)
  view.who:Set(#names>0 and (#names..' interested. Invite when ready:') or S.Code('faint')..'Nobody yet.|r');st:Place(view.who,nil,6)
  for i,b in ipairs(view.invites) do
   local n=names[i]
   if n and r.status=='open' then
    b:SetLabel('Invite '..P.Short(n));b:SetScript('OnClick',act(function() if not L().Invite(r.id,n) then view.err='Invite not possible now (offline, in combat, or you are not group leader).' end end))
    st:Place(b,26,4)
   end
  end
  st:Space(8)
 end
 if view.err then view.msg:SetText(view.err);st:Place(view.msg,16,8);view.err=nil end
 local B=view.btn;local open=r.status=='open'
 B.join:SetShown(open and not r.mine and not r.interested);B.leave:SetShown(open and not r.mine and r.interested)
 B.whisper:SetShown(not r.mine);B.edit:SetShown(r.mine and open);B.renew:SetShown(r.mine and r.status~='deleted')
 B.close:SetShown(r.mine and open);B.delete:SetShown(r.mine)
 local h=P.Flow({B.join,B.leave,B.whisper,B.edit,B.renew,B.close,B.delete},view.actions,st.width,0,8)
 view.actions:SetHeight(h);st:Place(view.actions,h,10)
end

local function buildForm(pane)
 local _,c=P.DrawerBody(pane)
 form.stack=P.Stack(c,330)
 form.head=P.DrawerHead(c,330)
 form.actLabel=S.Text(c,'kicker','muted');form.actLabel:SetText('ACTIVITY')
 form.activity='Dungeon'
 form.act=S.Button(c,'Dungeon','secondary',function()
  for i,a in ipairs(ACTIVITIES) do if a==form.activity then form.activity=ACTIVITIES[i%#ACTIVITIES+1];break end end
  form.act:SetLabel(form.activity..'   (click to change)')
 end,330,28);form.act.keepWidth=true
 form.name=S.Field(c,'Title',330,64,'Scarlet Monastery: Library')
 form.desc=S.Field(c,'Details (optional)',330,160,'Meet at the summoning stone')
 form.roleLabel=S.Text(c,'kicker','muted');form.roleLabel:SetText('ROLES WANTED')
 form.roleRow=CreateFrame('Frame',nil,c);form.roleRow:SetSize(330,26)
 form.roles={DPS=true}
 form.roleSw={}
 for i,r in ipairs(ROLES) do
  local sw=S.Switch(form.roleRow,r,function() return form.roles[r] end,function(v)
   if r=='Any' and v then form.roles={Any=true} elseif v then form.roles.Any=nil;form.roles[r]=true else form.roles[r]=nil end
   for _,x in ipairs(form.roleSw) do x:Update() end
  end,82)
  sw:SetPoint('LEFT',(i-1)*84,0);form.roleSw[i]=sw
 end
 form.nums=CreateFrame('Frame',nil,c);form.nums:SetSize(330,52)
 form.minL=S.Field(form.nums,'Min level',74,3,'1');form.minL:SetPoint('TOPLEFT',0,0)
 form.maxL=S.Field(form.nums,'Max level',74,3,'60');form.maxL:SetPoint('TOPLEFT',84,0)
 form.need=S.Field(form.nums,'Needed',74,2,'1');form.need:SetPoint('TOPLEFT',168,0)
 form.size=S.Field(form.nums,'Group size',78,2,'5');form.size:SetPoint('TOPLEFT',252,0)
 form.life=S.Field(c,'Listing lasts (minutes, 15-240)',330,3,'60')
 form.err=Kit.Text(c,OWNER,'narrow',13,'danger')
 form.submit=S.Button(c,'Post listing','primary',function()
  local input={activity=form.activity,name=form.name:Get(),description=form.desc:Get(),roles={},
   minLevel=tonumber(form.minL:Get()),maxLevel=tonumber(form.maxL:Get()),needed=tonumber(form.need:Get()),
   groupSize=tonumber(form.size:Get()),lifetimeMinutes=tonumber(form.life:Get())}
  for r in pairs(form.roles) do input.roles[r]=true end
  if input.name=='' then form.name:Error('Title is required.');return end
  if not next(input.roles) then form.err:SetText('Choose at least one role.');return end
  if not K.GuildLFGModel.ValidFields(input,time()) then form.err:SetText('Check levels (min <= max), needed (< group size), size 2-40 and duration 15-240.');return end
  local ok,err
  if state.mode=='edit' then local r=find(state.selected);if r then ok,err=L().Update(r.id,r.revision,'edit',input) end
  else ok,err=L().Create(input);if ok then state.selected=ok end end
  if not ok then form.err:SetText(err or 'Not posted.');return end
  state.mode='view';form.filled=false;W.Refresh(true);page:Update()
 end,150,32);form.submit.keepWidth=true
 form.cancel=S.Button(c,'Cancel','ghost',function() state.mode='view';form.filled=false;page:Update() end,90,32);form.cancel.keepWidth=true
end
local function renderForm(r)
 local st=form.stack;st:Reset()
 local editing=state.mode=='edit' and r
 form.head:Set(editing and 'Edit listing' or 'New listing',editing and r.name or 'Gather the Keepers');st:Place(form.head,nil,12)
 if not form.filled then
  local lvl=UnitLevel and UnitLevel('player') or 1
  form.activity=editing and r.activity or 'Dungeon';form.act:SetLabel(form.activity..'   (click to change)')
  form.name:Set(editing and r.name or '');form.desc:Set(editing and r.description or '')
  form.roles={};if editing then for k in pairs(r.roles) do form.roles[k]=true end else form.roles.DPS=true end
  for _,x in ipairs(form.roleSw) do x:Update() end
  form.minL:Set(editing and r.minLevel or math.max(1,lvl-5));form.maxL:Set(editing and r.maxLevel or math.min(255,lvl+5))
  form.need:Set(editing and r.needed or 4);form.size:Set(editing and r.groupSize or 5);form.life:Set(editing and r.lifetimeMinutes or 60)
  form.err:SetText('');form.filled=true
 end
 st:Place(form.actLabel,14,6);st:Place(form.act,28,10);st:Place(form.name,52,8);st:Place(form.desc,52,10)
 st:Place(form.roleLabel,14,6);st:Place(form.roleRow,26,12);st:Place(form.nums,52,8);st:Place(form.life,52,8)
 st:Place(form.err,16,8)
 form.submit:SetLabel(editing and 'Save changes' or 'Post listing');st:Actions({form.submit,form.cancel})
end

function page.Build(self,host)
 local left,right=P.Split(host,380)
 toolbar=P.Toolbar(left,{search=function(t) state.query=t;if list then list:ScrollTo(1) end;self:Update() end,searchHint='Search groups',
  segments={{'ALL','All groups'},{'MINE','Mine'}},get=function() return state.filter end,set=function(v) state.filter=v;self:Update() end,segWidth=90,
  action='New listing',onAction=function() state.mode='compose';form.filled=false;self:Update() end,actionWidth=130})
 list=Kit.List(left,60,6,function(row) S.RowBuild(row);row:SetScript('OnClick',function(r) state.selected=r.item.id;state.mode='view';self:Update() end) end,fill)
 P.ListHeading(left,list,toolbar,'Listings')
 Kit.Paint(list.thumb,OWNER,'line','fill')
 list.empty=S.Empty(list,'No groups forming','Start one with "New listing". Guildmates in your level range who opted in are notified.',420,'EmptyLFG')
 list.empty:SetPoint('TOPLEFT',4,-6)
 waiting=S.Empty(left,'Waiting for guild identity','',270);waiting:SetPoint('TOPLEFT',list,'TOPLEFT',4,-6)
 left:HookScript('OnSizeChanged',function(_,width)
  if width>8 then waiting:SetWidth(width-8);waiting.b:SetWidth(width-8) end
 end)
 view.pane=CreateFrame('Frame',nil,right);view.pane:SetAllPoints(right)
 form.pane=CreateFrame('Frame',nil,right);form.pane:SetAllPoints(right)
 buildView(view.pane);buildForm(form.pane)
end
function page.Update(self)
 if not list then return end
 local ready=K.GuildReadiness and K.GuildReadiness()
 if ready~='Ready' then
  waiting:Set('Guild LFG is waiting: '..tostring(ready),'It starts automatically once your guild roster and identity are verified. /kt lfgdebug explains the state.')
  waiting:Show();list:Hide();toolbar.action:SetEnabledState(false,'Guild identity is not verified yet.')
  view.pane:Show();form.pane:Hide();renderView(nil);return
 end
 waiting:Hide();list:Show();toolbar.action:SetEnabledState(true)
 local rows=all()
 if state.mode=='view' and not state.selected and rows[1] then state.selected=rows[1].id end
 list:SetData(rows)
 local r=state.selected and find(state.selected)
 view.pane:SetShown(state.mode=='view');form.pane:SetShown(state.mode~='view')
 if state.mode=='view' then renderView(r) else renderForm(state.mode=='edit' and r or nil) end
end
function page.OnShow(self,arg)
 if type(arg)=='table' and arg.compose then state.mode='compose';form.filled=false end
end
function page.Badge() local ok,n=pcall(function() return (K.GuildLFG.Summary()) end);return ok and n or 0 end
W.Register(page)
