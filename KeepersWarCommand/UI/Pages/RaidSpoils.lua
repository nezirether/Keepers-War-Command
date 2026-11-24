local K=KWC
local Kit,S,P=K.Kit,K.WarRoomSkin,K.WarRoomPages
local Engine=K.WarSpoils
local actions={
 {'S','Open raid','Raid name'},
 {'R','Register',''},
 {'A','Attendance',''},
 {'B','Boss credit','Boss occurrence ID'},
 {'L','Record contested loot','Drop ID','Item name','Other funded claimant'},
 {'C','Correction','Signed point change','Reason'},
 {'E','Close raid',''},
}
local eventLabels={S='Raid opened',E='Raid closed',R='Registration',A='Attendance',B='Boss credit',L='Contested loot',C='Correction'}

function P.BuildWarSpoils(host)
 local left,right=P.Split(host,346)
 local tab,mode,message='raiders',1,''
 local list,character,reference,note,rival,commit,details,session
 local function fill(row,item)
  row:Tone(item.tone);row.title:SetText(item.title);row.sub:SetText(item.description)
  row.meta:SetText(item.value);row.meta2:SetText(item.meta or '')
 end
 local function update()
  local state,unavailable=Engine.View()
  local out={}
  if state then
   if tab=='raiders' then
    for guid,r in pairs(state.raiders) do
     local name=K.Identity.RosterName(guid) or r.name
     out[#out+1]={title=name,character=name,tone='accent',value=r.points..' WarSpoils',
      description=('%d raids | %d bosses | %d contested wins'):format(r.raids,r.bosses,r.wins)}
    end
    table.sort(out,function(a,b) return a.title<b.title end)
   else
    for i=state.count,1,-1 do
     local e=state.events[i]
     local r=state.raiders[e.subject]
     local actor=K.Identity.RosterName(e.actor) or e.actor
     local name=r and (K.Identity.RosterName(e.subject) or r.name)
     local actionRef=e.kind=='L' and (e.ref:match('/(.+)$') or '') or e.ref
     out[#out+1]={title=eventLabels[e.kind]..(name and (' - '..name) or ''),
      description=('#%d by %s%s%s'):format(i,actor,e.raid and (' | raid '..e.raid) or '',
       e.note~='' and (' | '..e.note) or actionRef~='' and (' | '..actionRef) or ''),
      value=e.delta and ('%+d'):format(e.delta) or '',meta=Kit.Age(e.at),tone='info'}
    end
   end
  end
  list:SetData(out)
  session:Set(state and state.session and ('Open raid #'..state.session.id..': '..state.session.name)
   or 'No raid open')
  if unavailable then details:Set(unavailable)
  elseif state and state.db.conflict then
   details:Set('Recovery stopped on a conflicting ledger record. Preserve this SavedVariables file for reconciliation.')
  else
   details:Set(message~='' and message or 'The verified Warchief records transactions. Use the same boss occurrence or drop ID for all related entries.')
  end
  commit:SetEnabledState(Engine.CanWrite(),'Requires the current verified Warchief and a healthy ledger.')
 end
 local bar=P.Toolbar(left,{
  segments={{'raiders','Balances'},{'ledger','Ledger'}},get=function() return tab end,
  set=function(v) tab=v;list:ScrollTo(1);update() end,
  action='Request sync',actionWidth=108,onAction=function() Engine.Request() end,
 })
 list=Kit.List(left,51,4,function(row)
  S.RowBuild(row)
  row:SetScript('OnClick',function(r) if r.item.character then character:Set(r.item.character) end end)
 end,fill)
 P.ListHeading(left,list,bar,'WarSpoils records')
 list.empty=S.Empty(list,'No WarSpoils records yet','Registered raiders and transactions will appear here.',260)
 list.empty:SetPoint('TOPLEFT',4,-6)
 local _,body=P.DrawerBody(right)
 local stack=P.Stack(body,305)
 local heading=P.DrawerHead(body,305)
 heading:Set('Raid operations','WarSpoils ledger')
 session=P.Section(body,'Raid session',305)
 details=P.Section(body,'Ledger status',305)
 local picker=S.Button(body,'Open raid','secondary',function()
  mode=mode%#actions+1
  message='';reference:Set('');note:Set('');rival:Set('')
  host.WarSpoilsLayout()
 end,210,30);picker.keepWidth=true
 character=S.Field(body,'Character name',305,42,'Guild character')
 reference=S.Field(body,'Reference',305,55,'')
 note=S.Field(body,'Note',305,55,'')
 rival=S.Field(body,'Other funded claimant',305,42,'Guild character')
 commit=S.Button(body,'Record', 'primary',function()
  local form=actions[mode]
  local name,other=character:Get(),rival:Get()
  local text=mode==1 and reference:Get() or note:Get()
  local ref=mode==1 and '' or reference:Get()
  local function record()
   local ok,result=Engine.Record(form[1],name,ref,text,other)
   message=result or 'Could not record this transaction.'
   if ok then reference:Set('');note:Set('');rival:Set('') end
   host.WarSpoilsLayout()
  end
  if form[1]=='L' then
   S.Confirm('Record contested loot?','Record '..text..' for '..name..' and deduct 3 WarSpoils.','Record award',record)
  else record() end
 end,98,30);commit.keepWidth=true
 heading:Show()
 function host.WarSpoilsLayout()
  update()
  local form=actions[mode]
  stack:Reset()
  stack:Place(heading,nil,10);stack:Place(session,nil,10)
  picker:SetLabel(form[2]..' (click to change)')
  stack:Place(picker,nil,10)
  for _,f in ipairs({character,reference,note,rival}) do f:Hide() end
  if form[1]~='S' and form[1]~='E' then stack:Place(character,52,4) end
  if form[3]~='' then reference.label:SetText(form[3]);stack:Place(reference,52,4) end
  if form[4] then note.label:SetText(form[4]);stack:Place(note,52,4) end
  if form[5] then stack:Place(rival,52,4) end
  stack:Place(commit,30,12);stack:Place(details,nil,8)
 end
 host.WarSpoilsLayout()
end
