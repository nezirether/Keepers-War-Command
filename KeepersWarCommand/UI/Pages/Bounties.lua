-- War Room page: Bounty Board (post / view / sight / claim / complete / reopen).
-- Rules live in Engine/Operations.lua (owner or officer edits; creator, War
-- Council or Warchief deletes; tombstones prevent resurrection).
local K=KWC
local Kit,S,P,W=K.Kit,K.WarRoomSkin,K.WarRoomPages,K.WarRoom2
local OWNER=S.OWNER
local O=function() return K.Operations end

local page={id='bounties',title='Bounty Board',subtitle='Mark enemies, report sightings, claim the kill.',group='ops'}
local state={filter='ACTIVE',query='',selected=nil,mode='view'}
local view,form,sight={},{},{}
local list,toolbar,board,drawer,back

local function find(id) for _,e in ipairs(KWCDB and KWCDB.bounties or {}) do if e.id==id then return e end end end
local function target(e) return e.details and e.details.target or tostring(e.text or ''):match('^([^@%-|]+)') or e.text end
local function entries()
 local out={}
 for _,e in ipairs(KWCDB and KWCDB.bounties or {}) do
  local st=e.status or 'ACTIVE'
  local keep=state.filter=='ALL' or (state.filter=='ACTIVE' and st=='ACTIVE') or (state.filter=='CLOSED' and st~='ACTIVE')
  if keep and P.Matches(tostring(e.text)..' '..tostring(e.author),state.query) then out[#out+1]=e end
 end
 table.sort(out,function(a,b)
  local sa,sb=(a.status or 'ACTIVE')=='ACTIVE',(b.status or 'ACTIVE')=='ACTIVE'
  if sa~=sb then return sa end
  local la=a.sightings and a.sightings[1] and a.sightings[1].receivedAt or a.created or 0
  local lb=b.sightings and b.sightings[1] and b.sightings[1].receivedAt or b.created or 0
  return la>lb
 end)
 return out
end
local function act(fn) return function() Kit.Safe(fn);W.Refresh(true) end end
local function canManage(e)
 local me=P.Me()
 return K.SameGuildMember(e.author,me) or tostring(e.author):lower()==me:lower() or K.IsOfficer()
end
local TONE={ACTIVE='warn',COMPLETED='good',CANCELLED='faint'}

local function fillRow(row,e)
 local st=e.status or 'ACTIVE'
 row:Tone(TONE[st] or 'faint')
 row.metaWidth=65
 S.RowIcon(row,S.AssetPath('iconScroll'))
 local rarity=tostring((e.details and e.details.rarity) or e.rarity or ''):lower()
 local frameKey=rarity=='epic' and 'bountyEpic' or rarity=='legendary' and 'bountyLegendary' or 'bountyStandard'
 if not row.v3BountyFrame then
  row.v3BountyFrame=S.AssetOverlay(row.iconWell,frameKey,'OVERLAY',7)
  row.v3BountyFrame:ClearAllPoints();row.v3BountyFrame:SetPoint('CENTER',row.iconWell,'CENTER')
 end
 row.v3BountyFrame:SetAsset(frameKey);row.v3BountyFrame:SetAspectHeight(34)
 row.v3BountyFrame:SetShown(S.AssetPath(frameKey)~=nil)
 row.title:SetText(target(e));row.tooltipName=target(e)
 local d=e.details or {}
 local s=e.sightings and e.sightings[1]
 local bits={}
 if s then bits[#bits+1]=S.Code('warn')..'Last seen '..s.zone..'|r'
 elseif d.location and d.location~='' then bits[#bits+1]='Last known '..d.location
 else bits[#bits+1]='No sighting reported' end
 if d.reward and d.reward~='' then bits[#bits+1]=S.Code('accentText')..d.reward..'|r' end
 row.sub:SetText(table.concat(bits,'   '))
 local wide=row:GetWidth()>=385
 row.location:SetShown(wide)
 if wide then
  row.location:SetWidth(math.floor(row:GetWidth()*.31))
  local posted=d.location or tostring(e.text or ''):match('@%s*([^|]+)')
  row.location:SetText(s and s.zone or (posted and posted~='' and posted) or 'Unknown')
  row.title:SetPoint('RIGHT',row.location,'LEFT',-10,0)
  row.sub:SetPoint('RIGHT',row.location,'LEFT',-10,0)
  row.sub:SetText(d.reward and d.reward~='' and d.reward or (st=='ACTIVE' and 'Open contract' or 'Closed contract'))
 end
 row.meta:SetText(s and (Kit.Age(s.receivedAt)..' ago') or Kit.Age(e.created))
 local claims=0;for _ in pairs(e.claims or {}) do claims=claims+1 end
 row.meta2:SetText(st=='ACTIVE' and (claims>0 and (claims..' claim'..(claims>1 and 's' or '')) or 'Hunt') or st)
 row:Select(state.selected==e.id)
end

------------------------------------------------------------------ view
local function buildView(pane)
 local _,c=P.DrawerBody(pane)
 local w=330
 view.stack=P.Stack(c,w)
 view.head=P.DrawerHead(c,w)
 view.terms=P.Section(c,'Contract',w)
 view.sightings=P.Section(c,'Sightings',w)
 view.claims=P.Section(c,'Claims',w)
 view.actions=CreateFrame('Frame',nil,c);view.actions:SetSize(w,40)
 local A=view.actions
 view.btn={
  more=S.Button(A,'More options','secondary',function() state.more=not state.more;page:Update() end,112),
  sight=S.Button(A,'Report sighting','primary',function() state.mode='sight';sight.filled=false;page:Update() end,150),
  claim=S.Button(A,'Claim kill','secondary',act(function() O().ClaimBounty(state.selected) end),110),
  edit=S.Button(A,'Edit','secondary',function() state.mode='edit';form.filled=false;page:Update() end,80),
  complete=S.Button(A,'Mark completed','secondary',act(function() O().ChangeStatus('BOUNTY',state.selected,'COMPLETED') end),140),
  cancel=S.Button(A,'Withdraw','secondary',act(function() O().ChangeStatus('BOUNTY',state.selected,'CANCELLED') end),100),
  reopen=S.Button(A,'Reopen','primary',act(function() O().ChangeStatus('BOUNTY',state.selected,'ACTIVE') end),100),
  report=S.Button(A,'Draft guild report','ghost',act(function() O().Report('BOUNTY',state.selected) end),160),
  delete=S.Button(A,'Delete','danger',function()
   local id=state.selected
   S.Confirm('Delete this bounty?','It is removed for every guildmate and cannot come back from an old copy. This cannot be undone.','Delete',function()
    if O().Delete('BOUNTY',id) then
     state.selected=nil;state.detail=false;state.more=false;state.mode='view'
     local nextRow=entries();state.selected=nextRow[1] and nextRow[1].id or nil
     page:Update()
    end
    W.Refresh(true)
   end)
  end,90),
 }
 view.btn.claim.tipBody='A claim tells the poster you took the kill. The poster or an officer confirms completion.'
 view.btn.report.tipBody='Prepares a /g line in your chat box. Nothing is sent until you press Enter.'
 view.empty=S.Empty(c,'No bounty selected','Post a bounty on an enemy player. Guildmates are alerted when the target shows up on their screen in the open world.',w)
end
local function renderView(e)
 local st=view.stack;st:Reset()
 for _,k in ipairs({'head','terms','sightings','claims','actions','empty'}) do view[k]:Hide() end
 if not e then st:Place(view.empty,60);return end
 local status=e.status or 'ACTIVE'
 view.head:Set('Bounty  -  '..status,target(e))
 st:Place(view.head,nil,14)
 local B=view.btn;local active=status=='ACTIVE';local manage=canManage(e)
 B.sight:SetShown(active);B.claim:SetShown(active)
 B.edit:SetShown(state.more and active and manage);B.complete:SetShown(state.more and active and manage);B.cancel:SetShown(state.more and active and manage)
 B.reopen:SetShown(not active and manage);B.more:SetLabel(state.more and 'Fewer options' or 'More options');B.report:SetShown(state.more);B.delete:SetShown(state.more and O().CanDelete(e))
 local h=P.Flow({B.sight,B.claim,B.reopen,B.more,B.edit,B.complete,B.cancel,B.report,B.delete},view.actions,st.width,0,8)
 view.actions:SetHeight(h)
 st:Place(view.actions,h,10)

 local d=e.details or {}
 local t={}
 t[#t+1]='Reward: '..((d.reward and d.reward~='') and d.reward or S.Code('faint')..'unspecified|r')
 if d.reason and d.reason~='' then t[#t+1]='Reason: '..d.reason end
 if d.location and d.location~='' then t[#t+1]='Posted location: '..d.location end
 if not e.details then t[#t+1]=K.Clean(e.text,165) end
 t[#t+1]=S.Code('faint')..'Posted by '..P.Short(e.author)..'  '..Kit.Age(e.created)..' ago|r'
 view.terms:Set(table.concat(t,'\n'));st:Place(view.terms,nil,14)
 local s={}
 for i,x in ipairs(e.sightings or {}) do
  if i>6 then s[#s+1]=S.Code('faint')..'+'..(#e.sightings-6)..' older|r';break end
  s[#s+1]=x.zone..(x.note~='' and (' - '..x.note) or '')..S.Code('faint')..'  '..P.Short(x.who)..', '..Kit.Age(x.receivedAt)..'|r'
 end
 view.sightings:Set(#s>0 and table.concat(s,'\n') or S.Code('faint')..'No sightings yet.|r');st:Place(view.sightings,nil,14)
 local c={}
 for who,at in pairs(e.claims or {}) do c[#c+1]=P.Short(who)..S.Code('faint')..'  '..tostring(at)..'|r' end
 table.sort(c)
 view.claims:Set(#c>0 and table.concat(c,'\n') or S.Code('faint')..'No claims yet.|r');st:Place(view.claims,nil,16)
end

------------------------------------------------------------------ compose / edit
local function buildForm(pane)
 local _,c=P.DrawerBody(pane)
 local w=330
 form.stack=P.Stack(c,w)
 form.head=P.DrawerHead(c,w)
 form.target=S.Field(c,'Target (enemy player)',w,36,'Character name')
 form.useTarget=S.Link(c,'Use my current target',function()
  local n=K.UI.GetBountyPlayerName('target')
  if n then form.target:Set(n) else form.target:Error('Target an enemy player first.') end
 end);form.useTarget.keepWidth=true
 form.location=S.Field(c,'Last known location',w,35,'Zone or landmark')
 form.reason=S.Field(c,'Reason',w,48,'Corpse camping lowbies')
 form.reward=S.Field(c,'Reward (optional)',w,25,'e.g. 50g')
 form.target.next,form.location.next,form.reason.next=form.location,form.reason,form.reward
 form.submit=S.Button(c,'Post bounty','primary',nil,150,32);form.submit.keepWidth=true
 form.cancel=S.Button(c,'Cancel','ghost',function() state.mode='view';form.filled=false;page:Update() end,90,32);form.cancel.keepWidth=true
 form.note=S.Para(c,w,'faint',12)
 form.note:SetText('One active bounty per target. Posting syncs over the guild addon channel; nothing is posted in public chat.')
 form.submit:SetScript('OnClick',function()
  local t,loc,why,rew=form.target:Get(),form.location:Get(),form.reason:Get(),form.reward:Get()
  if t=='' then form.target:Error('Target name is required.');return end
  if t:find('[%c|;]') then form.target:Error('Use a plain character name.');return end
  if state.mode=='edit' then
   Kit.Safe(O().UpdateBounty,state.selected,t,loc,why,rew)
  else
   local text=t..(loc~='' and ' @ '..loc or '')..(why~='' and ' - '..why or '')..(rew~='' and ' | Reward: '..rew or '')
   local ok,id=O().AddBounty(text,{target=K.Clean(t,36),location=K.Clean(loc,35),reason=K.Clean(why,48),reward=K.Clean(rew,25)})
   if not ok then form.target:Error('Not posted - see chat for the reason.');return end
   state.selected=id
  end
  state.detail=true;state.mode='view';form.filled=false;W.Refresh(true);page:Update()
 end)
end
local function renderForm(e)
 local st=form.stack;st:Reset()
 local editing=state.mode=='edit' and e
 form.head:Set(editing and 'Edit bounty' or 'New bounty',editing and P.Short(target(e)) or 'Put a price on their head')
 st:Place(form.head,nil,14)
 if not form.filled then
  local d=editing and e.details or {}
  form.target:Set(d.target or state.prefill or '');form.location:Set(d.location or (editing and '' or P.HereZone()))
  form.reason:Set(d.reason or '');form.reward:Set(d.reward or '')
  state.prefill=nil;form.filled=true
 end
 st:Place(form.target,52,4);st:Place(form.useTarget,18,10)
 st:Place(form.location,52,8);st:Place(form.reason,52,8);st:Place(form.reward,52,16)
 form.submit:SetLabel(editing and 'Save changes' or 'Post bounty')
 st:Actions({form.submit,form.cancel},14);st:Place(form.note,nil,10)
end

------------------------------------------------------------------ sighting form
local function buildSight(pane)
 local _,c=P.DrawerBody(pane)
 local w=330
 sight.stack=P.Stack(c,w)
 sight.head=P.DrawerHead(c,w)
 sight.zone=S.Field(c,'Where did you see them?',w,38,'Zone')
 sight.note=S.Field(c,'Note (optional)',w,50,'Heading north with a friend')
 sight.zone.next=sight.note
 sight.submit=S.Button(c,'Send sighting','primary',function()
  local z=sight.zone:Get()
  if z=='' then sight.zone:Error('Location is required.');return end
  local ok,res=pcall(O().AddSighting,state.selected,z,sight.note:Get())
  if not ok then K.Say('Interface error: '..tostring(res));return end
  if res then state.mode='view';sight.filled=false;W.Refresh(true);page:Update() else sight.zone:Error('Not sent - see chat for the reason.') end
 end,150,32);sight.submit.keepWidth=true
 sight.cancel=S.Button(c,'Cancel','ghost',function() state.mode='view';sight.filled=false;page:Update() end,90,32);sight.cancel.keepWidth=true
end
local function renderSight(e)
 local st=sight.stack;st:Reset()
 sight.head:Set('Report sighting',e and P.Short(target(e)) or '')
 st:Place(sight.head,nil,14)
 if not sight.filled then sight.zone:Set(state.sightZone or P.HereZone());sight.note:Set('');state.sightZone=nil;sight.filled=true end
 st:Place(sight.zone,52,8);st:Place(sight.note,52,16);st:Actions({sight.submit,sight.cancel})
end

------------------------------------------------------------------ page
function page.Build(self,host)
 K.Operations.SelectedBountyID=function()return state.selected end
 self.host=host
 local left=CreateFrame('Frame',nil,host);board=left
 local right=CreateFrame('Frame',nil,host);drawer=right
 S.Art(right,'panel','BACKGROUND')
 back=S.Button(right,'Back to board','secondary',function()
  state.detail=false;state.more=false;state.mode='view';self:Update()
 end,132,26)
 back:SetPoint('TOPLEFT',12,-6)
 host:HookScript('OnSizeChanged',function() if self.ready then self:Update() end end)
 toolbar=P.Toolbar(left,{search=function(t) state.query=t;if list then list:ScrollTo(1) end;self:Update() end,searchHint='Search targets',
  segments={{'ACTIVE','Active'},{'CLOSED','Closed'},{'ALL','All'}},get=function() return state.filter end,
  set=function(v) state.filter=v;self:Update() end,segWidth=72,
  action='New bounty',onAction=function() state.mode='compose';form.filled=false;self:Update();form.target.edit:SetFocus() end,actionWidth=130})
 list=Kit.List(left,42,2,function(row) S.RowBuild(row)
  row.location=S.Text(row,'body','muted');row.location:SetPoint('RIGHT',row,'RIGHT',-85,0)
  row:SetScript('OnClick',function(r) state.selected=r.item.id;state.detail=true;state.more=false;state.mode='view';self:Update() end) end,fillRow)
 local heading=P.ListHeading(left,list,toolbar,'Target')
 local zone=S.Text(heading,'kicker','paperText');zone:SetText('LAST LOCATION')
 local function align(_,width)
  zone:ClearAllPoints();zone:SetPoint('LEFT',heading,'LEFT',width-99-math.floor((width-14)*.31),0)
  zone:SetShown(width>=400)
 end
 heading:HookScript('OnSizeChanged',align);align(heading,heading:GetWidth())
 Kit.Paint(list.thumb,OWNER,'line','fill')
 list.empty=S.Empty(list,'The board is clear','Post a bounty to mark an enemy. Right-click a player frame and choose the bounty option where your client supports it.',420,'EmptyBounties')
 list.empty:SetPoint('TOPLEFT',4,-6)
 for _,x in ipairs({view,form,sight}) do x.pane=CreateFrame('Frame',nil,right);x.pane:SetPoint('TOPLEFT',right,'TOPLEFT',0,-36);x.pane:SetPoint('BOTTOMRIGHT',right,'BOTTOMRIGHT') end
 buildView(view.pane);buildForm(form.pane);buildSight(sight.pane);self.ready=true
end
function page.OnShow(self,arg)
 state.detail=false;state.more=false;state.mode='view'
 if type(arg)=='table' then
  if arg.compose then state.mode='compose';form.filled=false;state.prefill=arg.target end
  if arg.select then state.detail=true;state.selected=arg.select;state.filter='ALL';state.mode=arg.sighting and 'sight' or 'view';state.sightZone=arg.sighting;sight.filled=false end
 end
 if toolbar and toolbar.seg then toolbar.seg:Update() end
end
function page.Update(self)
 if not self.ready then return end
 local showDetail=state.detail or state.mode~='view'
 local width=self.host:GetWidth()
 local split=showDetail and width>=930
 board:ClearAllPoints();board:SetPoint('TOPLEFT')
 drawer:ClearAllPoints();drawer:SetPoint('TOPRIGHT');drawer:SetPoint('BOTTOMRIGHT')
 drawer:SetWidth(math.max(1,split and math.floor(width*.46) or width))
 if split then board:SetPoint('BOTTOMRIGHT',drawer,'BOTTOMLEFT',-12,0)
 else board:SetPoint('BOTTOMRIGHT',self.host,'BOTTOMRIGHT') end
 board:SetShown(not showDetail or split);drawer:SetShown(showDetail)
 for _,component in ipairs({view,form,sight}) do
  component.stack.width=math.max(1,drawer:GetWidth()-48)
  component.head.title:SetWidth(component.stack.width)
 end
 local rows=entries()
 if state.mode=='view' and not state.selected and rows[1] then state.selected=rows[1].id end
 list:SetData(rows)
 local e=state.selected and find(state.selected)
 view.pane:SetShown(state.mode=='view');form.pane:SetShown(state.mode=='compose' or state.mode=='edit');sight.pane:SetShown(state.mode=='sight')
 if not showDetail then return end
 if state.mode=='view' then renderView(e)
 elseif state.mode=='sight' then if not e then state.mode='view';return self:Update() end;renderSight(e)
 else renderForm(state.mode=='edit' and e or nil) end
end
function page.Badge()
 local n=0;for _,e in ipairs(KWCDB and KWCDB.bounties or {}) do if (e.status or 'ACTIVE')=='ACTIVE' then n=n+1 end end;return n
end
W.Register(page)
