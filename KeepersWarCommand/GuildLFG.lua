-- Guild LFG uses the existing guild partition, send queue and officer recovery request.
local K, Model = KWC, KWC.GuildLFGModel
local L = {}; K.GuildLFG = L
local prefix = 'KWL1'
local activities = {'Dungeon','Questing','World PvP','Battlegrounds','Raid','Farming','Other'}
local roles = {'Tank','Healer','DPS','Any'}
local states = {open=1,closed=2,deleted=3}
local readiness=K.GuildReadiness
local function context()
 local status,guild,actor=readiness()
 if status~='Ready' then return end
 KWCDB.guildLFG=KWCDB.guildLFG or {}
 local board=Model.Open(KWCDB.guildLFG,guild,actor,time)
 return board,KWCDB.guildLFG[guild],guild,actor
end
local function split(s)
 local fields={}
 for field in (s..'|'):gmatch('(.-)|') do fields[#fields+1]=field end
 return fields
end
local function encodeListing(r)
 local f=r.fields
 local row={'L',r.id,r.revision,r.generation or 1,r.status,r.createdAt,r.updatedAt,r.expiresAt}
 if f then
  local activity,mask=0,0
  for i,v in ipairs(activities) do if f.activity==v then activity=i end end
  for i,v in ipairs(roles) do if f.roles[v] then mask=mask+2^(i-1) end end
  row[#row+1]=table.concat({activity,mask,f.minLevel,f.maxLevel,f.needed,f.groupSize,f.lifetimeMinutes,f.startAt or 0,f.name,f.description},'|')
 end
 return table.concat(row,'|')
end
local function encodeInterest(id,actor,r)
 return table.concat({'I',id,actor,r.generation,r.revision,r.interested and 1 or 0},'|')
end
local function fits(row,guild)
 -- Board recovery adds RS, guild, request token, and the dataset tag.
 return #row+#guild+24+9<=250
end
local function announce(row,guild)
 return K.Net.Send(prefix,guild..'|'..row,'GUILD')
end
local function prefs()
 local settings=KWCDB.settings
 settings.guildLFG=settings.guildLFG or {}
 return settings.guildLFG
end
local function notify(key,msg)
 if prefs()[key] and UIErrorsFrame and UIErrorsFrame.AddMessage then
  UIErrorsFrame:AddMessage(msg,0.85,0.9,1)
 end
end
local function present(r)
 return r and K.IsMember(r.owner) and r.status=='open' and r.expiresAt>time()
end
local function activeInterest(r,name)
 local x=r and r.requests and r.requests[name]
 return x and x.generation==(r.generation or 1) and x.interested
end
local function matches(r)
 local p=prefs()
 local level=UnitLevel and UnitLevel('player')
 local f=r.fields
 return f and type(level)=='number' and level>=f.minLevel and level<=f.maxLevel
  and (not p.activity or f.activity==p.activity)
  and (not p.role or f.roles.Any or f.roles[p.role])
end
local function merge(row,sender,relay)
 local _,db,guild,me=context()
 if not db or not fits(row,guild) or row:find('[%c]') then return end
 local f=split(row)
 local id=f[2]
 local owner,serial
 if id then owner,serial=id:match('^([^/]+)/(%d+)$') end
 if not serial or #serial>12 or K.CurrentGuildMember(owner)~=owner then return end
 local r=db.listings[id]
 if f[1]=='L' then
  if not relay and not K.SameGuildMember(owner,sender) then return end
  local revision,generation,created,updated,expires=tonumber(f[3]),tonumber(f[4]),tonumber(f[6]),tonumber(f[7]),tonumber(f[8])
  local state=states[f[5]]
  if not revision or revision%1~=0 or revision<1 or revision>1000000 or not generation or generation%1~=0
   or generation<1 or generation>revision or not state or not created or not updated or not expires
   or created%1~=0 or updated%1~=0 or expires%1~=0 or created<1500000000 or created>updated or updated>time()+300 or expires<created or expires>updated+14400 then return end
  if r then
   if created~=r.createdAt or state<states[r.status] or generation<(r.generation or 1) then return end
   if state==states[r.status] and (revision<r.revision or (revision==r.revision and row<=encodeListing(r))) then return end
  end
  local fields
  if state<3 then
   local desired,mask={},tonumber(f[10])
   if #f~=18 or not mask or mask%1~=0 or mask<1 or mask>8 then return end
   for i,v in ipairs(roles) do if math.floor(mask/2^(i-1))%2==1 then desired[v]=true end end
   local start=tonumber(f[16])
   if not start or start%1~=0 or start<0 or start>updated+14400 then return end
   fields=Model.ValidFields({activity=activities[tonumber(f[9]) or 0],roles=desired,minLevel=tonumber(f[11]),
    maxLevel=tonumber(f[12]),needed=tonumber(f[13]),groupSize=tonumber(f[14]),lifetimeMinutes=tonumber(f[15]),
    name=f[17],description=f[18]},updated)
   if fields and start>0 then fields.startAt=start end
   if not fields then return end
  elseif #f~=8 then return end
  r={id=id,owner=owner,revision=revision,generation=generation,status=f[5],createdAt=created,updatedAt=updated,
   expiresAt=expires,fields=fields,interest={},requests=r and r.requests or {},lastMatchNotice=r and r.lastMatchNotice,lastInviteNotice=r and r.lastInviteNotice,relayedBy=relay}
  if owner==me and relay then db.sequence=math.max(db.sequence,tonumber(serial)) end
  db.listings[id]=r
  if state==1 then
   for name,x in pairs(r.requests) do if x.generation==generation and x.interested then r.interest[name]=true end end
   if not relay and owner~=me and present(r) and matches(r) and r.lastMatchNotice~=revision then
    r.lastMatchNotice=revision
    notify('matching','Guild LFG: '..fields.name..' matches your filters.')
   end
  end
 elseif f[1]=='I' and #f==6 then
  local actor=f[3]
  if not K.IsMember(actor) or K.SameGuildMember(actor,owner)
   or (not relay and not K.SameGuildMember(actor,sender)) then return end
  actor=K.CurrentGuildMember(actor)
  local generation,rev=tonumber(f[4]),tonumber(f[5])
  if not generation or generation<1 or generation>1000000 or generation%1~=0 or not rev or rev%1~=0
   or rev<1 or rev>time()+300 or (f[6]~='0' and f[6]~='1') then return end
  if not r or generation>(r.generation or 1) then
   -- Do not allocate unbounded dependencies for unknown listing IDs.
   db.pending=db.pending or {}
   local key=id..'|'..actor
   local size=0
   for k,x in pairs(db.pending) do
    if x.expires<=time() then db.pending[k]=nil else size=size+1 end
   end
   local old=db.pending[key]
   if (not old and size<96) or (old and (generation>old.generation or
    (generation==old.generation and (rev>old.rev or (rev==old.rev and f[6]=='0'))))) then
    db.pending[key]={id=id,row=row,sender=sender,relay=relay,expires=time()+180,generation=generation,rev=rev}
   end
   return
  end
  if not present(r) or generation~=(r.generation or 1) then return end
  r.requests=r.requests or {}
  local old=r.requests[actor]
  local interested=f[6]=='1'
  if old and old.generation==generation and (rev<old.revision or (rev==old.revision and (interested or not old.interested))) then return end
  r.requests[actor]={generation=generation,revision=rev,interested=interested,relayedBy=relay}
  r.interest[actor]=interested or nil
  if not relay and interested and (not old or not old.interested) and r.owner==me then
   notify('interest','Guild LFG: '..actor..' is interested in '..r.fields.name..'.')
  end
 end
 if f[1]=='L' then
  for key,x in pairs(db.pending or {}) do
   if x.expires<=time() or (x.id==id and x.generation<=r.generation) then
    db.pending[key]=nil
    if x.expires>time() and x.id==id and (not x.relay or K.IsSenderOfficer(x.relay)) then merge(x.row,x.sender,x.relay) end
   end
  end
 end
 L.Refresh()
end
local function snapshot(page)
 local _,db=context()
 if not db then return {} end
 local ids,rows={},{}
 for id,r in pairs(db.listings) do
  if r.status~='open' or present(r) then ids[#ids+1]=id end
 end
 table.sort(ids)
 for _,id in ipairs(ids) do
  local r=db.listings[id]
  rows[#rows+1]=encodeListing(r)
  if present(r) then
   local names={}
   for name,x in pairs(r.requests or {}) do if x.generation==r.generation then names[#names+1]=name end end
   table.sort(names)
   for _,name in ipairs(names) do rows[#rows+1]=encodeInterest(id,name,r.requests[name]) end
  end
 end
 local result={}
 if #rows>0 then
  local first=(page%math.ceil(#rows/8))*8+1
  for i=first,math.min(first+7,#rows) do result[#result+1]=rows[i] end
 end
 return result
end
K.Sync.RegisterRecoveryDataset('LFG',snapshot,function(row,sender) merge(row,sender,sender) end)
K.On('CHAT_MSG_ADDON',function(p,msg,channel,sender)
 if p~=prefix or channel~='GUILD' or type(msg)~='string' or #msg>250 or not K.IsMember(sender) then return end
 local guild,row=msg:match('^(%d+)|(.+)$')
 if guild and guild==K.GuildScope() then merge(row,sender) end
end)
K.On('ADDON_LOADED',function(addon)
 if addon=='KeepersWarCommand' and C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  pcall(C_ChatInfo.RegisterAddonMessagePrefix,prefix)
 end
end)
function L.Create(input)
 local board,db,guild,me=context()
 if not board then return nil,'Guild identity is unavailable.' end
 local owned=board.Browse({mine=true})
 local active=0
 for _,r in ipairs(owned) do if r.status=='open' then active=active+1 end end
 if active>=5 then return nil,'Close a listing before creating another.' end
 -- Keep a fresh SavedVariables installation from reusing low sequence IDs
 -- that guild peers may still hold for this character.
 db.sequence=math.max(db.sequence,time()*100)
 local id,err=board.Create(input)
 if not id then return nil,err end
 local row=encodeListing(db.listings[id])
 if not fits(row,guild) then db.listings[id]=nil;return nil,'Shorten the activity name or description.' end
 announce(row,guild)
 return id
end
function L.Update(id,revision,action,input)
 local board,db,guild=context()
 if not board then return false,'Guild identity is unavailable.' end
 local old=db.listings[id]
 local backup
 if old then
  backup={}
  for k,v in pairs(old) do backup[k]=v end
 end
 local ok,err=board.Update(id,revision,action,input)
 if not ok then return false,err end
 local r=db.listings[id]
 local row=encodeListing(r)
 if not fits(row,guild) then db.listings[id]=backup;return false,'Shorten the activity name or description.' end
 if action=='delete' or action=='close' or r.generation~=backup.generation then r.requests={} end
 announce(row,guild)
 return true
end
function L.Interest(id,wanted)
 local board,db,guild,me=context()
 local r=db and db.listings[id]
 if not present(r) or not board.SetInterest(id,wanted) then return false end
 r.requests=r.requests or {}
 local old=r.requests[me]
 local x={generation=r.generation,revision=math.max(time(),(old and old.revision or 0)+1),interested=wanted}
 local row=encodeInterest(id,me,x)
 if not fits(row,guild) then r.interest[me]=not wanted or nil;return false end
 r.requests[me]=x
 announce(row,guild)
 return true
end
function L.Browse(filter)
 local board=context()
 if not board then return {} end
 local rows=board.Browse(filter)
 for i=#rows,1,-1 do if not K.IsMember(rows[i].owner) then table.remove(rows,i) end end
 return rows
end
function L.Summary()
 local _,db=context()
 local count,people=0,{}
 if db then
  for _,r in pairs(db.listings) do
   if present(r) then
    count=count+1;people[r.owner]=true
    for name in pairs(r.requests or {}) do if K.IsMember(name) and activeInterest(r,name) then people[name]=true end end
   end
  end
 end
 local total=0
 for _ in pairs(people) do total=total+1 end
 return count,total
end
local function inviteAPI() return (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit end
local function inviteTarget(id,name)
 local _,db,_,me=context()
 local r=db and db.listings[id]
 if not present(r) or r.owner~=me or not activeInterest(r,name) then return end
 local identity,_,online=K.CurrentGuildMember(name)
 if not identity or not online or type(inviteAPI())~='function' then return end
 if InCombatLockdown and InCombatLockdown() then return end
 if IsInGroup and IsInGroup() and not (UnitIsGroupLeader and UnitIsGroupLeader('player'))
  and not (UnitIsGroupAssistant and UnitIsGroupAssistant('player')) then return end
 return identity
end
function L.Invite(id,name)
 local target=inviteTarget(id,name)
 if not target then return false end
 local ok,result=pcall(inviteAPI(),target)
 return ok and result~=false
end
local function whisperAPI()
 return (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_OpenChat
end
function L.Whisper(id)
 local _,db=context()
 local r=db and db.listings[id]
 if not present(r) or type(whisperAPI())~='function' then return false end
 if ChatFrameUtil and type(ChatFrameUtil.SendTell)=='function' then return pcall(ChatFrameUtil.SendTell,r.owner) end
 return pcall(ChatFrame_OpenChat,'/w '..r.owner..' ')
end
K.On('PARTY_INVITE_REQUEST',function(inviter)
 if not KWCDB or not prefs().invitation or type(inviter)~='string'
  or (issecretvalue and issecretvalue(inviter)) then return end
 local _,db,_,me=context()
 if not db then return end
 for _,r in pairs(db.listings) do
  if present(r) and activeInterest(r,me) and K.SameGuildMember(r.owner,inviter) then
   if r.lastInviteNotice~=r.revision then
    r.lastInviteNotice=r.revision
    notify('invitation','Guild LFG: '..inviter..' invited you.')
   end
   return
  end
 end
end)

local tab, selected, editing='Browse Groups'
local filter, draft={},nil
local viewGuild
local refreshPending=false
local lastReadiness,lastReadyGuild,lastActor
local expiryTimer
local function scheduleExpiry(at)
 if expiryTimer and expiryTimer.Cancel then expiryTimer:Cancel() end
 expiryTimer=nil
 if at and C_Timer and C_Timer.NewTimer then
  expiryTimer=C_Timer.NewTimer(math.max(1,at-time()),function() L.Refresh() end)
 end
end
local retryDelays={1,2,4,8}
local retryStep,retryTicket=0,0
local retryPending=false
local lastRosterRequest
local function stopRetry()
 retryTicket=retryTicket+1
 retryPending=false
 retryStep=0
end
local function requestRoster()
 local fn=(C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster
 if type(fn)~='function' or not IsInGuild() then return end
 if lastRosterRequest and time()-lastRosterRequest<2 then return end
 lastRosterRequest=time()
 pcall(fn)
end
local function retry()
 if retryPending or retryStep>=#retryDelays or not C_Timer or not C_Timer.After then return end
 retryPending=true
 retryStep=retryStep+1
 local ticket=retryTicket
 C_Timer.After(retryDelays[retryStep],function()
  if ticket~=retryTicket then return end
  retryPending=false
  K.RefreshGuildScope()
  if readiness()~='Ready' and K.GuildScope() then requestRoster() end
  if K.UI and K.UI.LFGRefresh then K.UI.LFGRefresh() end
 end)
end
local function diagnostic()
 local status,_,_,reason=readiness()
 local count=IsInGuild and IsInGuild() and GetNumGuildMembers and GetNumGuildMembers() or 0
 K.Say(('Guild LFG: %s. Club ID: %s. Roster entries: %s.'):format(
  status,K.GuildScope() and 'available' or 'unavailable',tostring(count))..(reason and (' Match: '..reason..'.') or ''))
end
function L.Debug(arg)
 K.RefreshGuildScope()
 if KWCDB and (arg=='on' or arg=='off') then prefs().readinessDebug=arg=='on' end
 diagnostic()
end
function L.Refresh()
 if tab=='Create Listing' or refreshPending or not C_Timer or not C_Timer.After then return end
 refreshPending=true
 C_Timer.After(0.5,function()
  refreshPending=false
  if tab~='Create Listing' and K.UI and K.UI.LFGRefresh then K.UI.LFGRefresh() end
 end)
end
local function cycle(options,value)
 for i,v in ipairs(options) do if v==value then return options[i%#options+1] end end
 return options[1]
end
local function roleText(set)
 local names={}
 for _,v in ipairs(roles) do if set[v] then names[#names+1]=v end end
 return table.concat(names,', ')
end
local function input(parent,label,edit,caption,value,x,y,w,save)
 label(parent,caption,x,y,w)
 local box=edit(parent,tostring(value or ''),x,y-21,w)
 box:SetScript('OnTextChanged',function(self) save(self:GetText()) end)
 return box
end
local function displayName(name)
 local row=K.RosterRecord and K.RosterRecord(name)
 if row and K.SameGuildMember(name,row.name) then return row.name end
 return name
end
-- Shared readiness recovery for both guild feature pages.
function L.DrawWaiting(parent,label,button,redraw,status)
 label(parent,status,18,-62,520,'GameFontNormal')
 if status=='Not currently in a guild' then stopRetry();return end
 label(parent,'Shared data is available after your guild and character are verified.',18,-94,520)
 button(parent,'Retry',18,-135,125,function()
  stopRetry()
  K.RefreshGuildScope()
  requestRoster()
  redraw()
 end)
 if K.GuildScope() then requestRoster() end
 retry()
end
function L.Draw(parent,label,button,edit,surface,redraw)
 K.RefreshGuildScope()
 local status,guild,actor=readiness()
 lastReadiness,lastReadyGuild,lastActor=status,guild,actor
 local rawButton=button
 local makeButton=button
 button=function(p,caption,x,y,w,action,help,selectedTab)
  return makeButton(p,caption,x,y,w,function()
   local _,current,currentActor=readiness()
   if guild==current and actor==currentActor then action() else redraw() end
  end,help,selectedTab)
 end
 if guild~=viewGuild then
  viewGuild=guild;selected=nil;editing=nil;draft=nil;filter={};tab='Browse Groups'
  if guild then filter.activity,filter.role=prefs().activity,prefs().role end
 end
 label(parent,'Looking for Group',18,-12,520,'GameFontNormalLarge')
 if status~='Ready' then L.DrawWaiting(parent,label,rawButton,redraw,status);return end
 stopRetry()
 for i,name in ipairs({'Browse Groups','Create Listing','My Listings'}) do
  button(parent,(tab==name and '> ' or '')..name,18+(i-1)*182,-61,170,function()
   tab=name;editing=nil;selected=nil;redraw()
  end,nil,tab==name)
 end
 local y=-114
 if tab=='Create Listing' then
  draft=draft or {activity='Dungeon',roles={Any=true},minLevel='1',maxLevel='60',groupSize='5',needed='1',lifetimeMinutes='60'}
  local d=draft
  label(parent,editing and 'Edit listing' or 'Create a guild listing',18,y,530,'GameFontNormal')
  button(parent,d.activity,18,y-36,170,function() d.activity=cycle(activities,d.activity);redraw() end)
  input(parent,label,edit,'Activity name',d.name,206,y-35,340,function(v) d.name=v end)
  label(parent,'Roles needed',18,y-100,520)
  for i,role in ipairs(roles) do
   button(parent,(d.roles[role] and '+ ' or '')..role,18+(i-1)*136,y-125,122,function()
    if role=='Any' then d.roles={Any=true}
    else d.roles.Any=nil;d.roles[role]=not d.roles[role] or nil;if not next(d.roles) then d.roles.Any=true end end
    redraw()
   end)
  end
  for i,item in ipairs({{'Min level','minLevel'},{'Max level','maxLevel'},{'Needed','needed'},{'Party size','groupSize'},{'Minutes','lifetimeMinutes'}}) do
   local key=item[2]
   input(parent,label,edit,item[1],d[key],18+(i-1)*108,y-179,94,function(v) d[key]=v end)
  end
  input(parent,label,edit,'Short description',d.description,18,y-238,528,function(v) d.description=v end)
  input(parent,label,edit,'Start in minutes (optional)',d.startMinutes,18,y-293,220,function(v) d.startMinutes=v end)
  local notice=label(parent,'',18,y-400,528)
  button(parent,editing and 'Save Listing' or 'Create',18,y-353,170,function()
   local value={}
   for k,v in pairs(d) do value[k]=v end
   for _,key in ipairs({'minLevel','maxLevel','needed','groupSize','lifetimeMinutes'}) do value[key]=tonumber(d[key]) or -1 end
   value.startAt=nil
   if d.startMinutes and d.startMinutes~='' then value.startAt=time()+60*(tonumber(d.startMinutes) or -1) end
   local ok,err
   if editing then ok,err=L.Update(editing.id,editing.revision,'edit',value)
   else ok,err=L.Create(value) end
   if ok then
    selected=editing and editing.id or ok
    tab='My Listings';draft=nil;editing=nil;redraw()
   else notice:SetText(err or 'Listing could not be saved.') end
  end)
  return
 end
 if tab=='Browse Groups' then
  local cats={'All activities'}
  for _,v in ipairs(activities) do cats[#cats+1]=v end
  button(parent,filter.activity or cats[1],18,y,157,function()
   local nextValue=cycle(cats,filter.activity);filter.activity=nextValue~=cats[1] and nextValue or nil;selected=nil;redraw()
  end)
  button(parent,filter.role or 'All roles',185,y,115,function()
   local nextValue=cycle({'All roles','Tank','Healer','DPS'},filter.role)
   filter.role=nextValue~='All roles' and nextValue or nil;selected=nil;redraw()
  end)
  local level=input(parent,label,edit,'Level',filter.level,311,y+10,71,function(v) filter.level=tonumber(v) end)
  button(parent,'Apply',390,y,65,function() filter.level=tonumber(level:GetText());selected=nil;redraw() end)
  button(parent,'Refresh',463,y,83,function() K.Sync.Request(true);redraw() end,
   'Request current listings from compatible guildmates.')
  y=y-48
  local p=prefs()
  p.activity,p.role=filter.activity,filter.role
  for i,setting in ipairs({{'interest','Interest'},{'invitation','Invites'},{'matching','Matches'}}) do
   local key=setting[1]
   button(parent,setting[2]..(p[key] and ': On' or ': Off'),18+(i-1)*180,y,165,function()
    p[key]=not p[key];redraw()
   end)
  end
  y=y-48
 end
 local rows=L.Browse(tab=='My Listings' and {mine=true} or filter)
 local nextExpiry
 for _,row in ipairs(rows) do
  if row.status=='open' and (not nextExpiry or row.expiresAt<nextExpiry) then nextExpiry=row.expiresAt end
 end
 scheduleExpiry(nextExpiry)
 local current
 for _,row in ipairs(rows) do if row.id==selected then current=row;break end end
 if current then
  local r=current
  surface(parent,18,y,528,155,0.10)
  label(parent,r.name,32,y-10,495,'GameFontNormal')
  label(parent,displayName(r.owner)..'  /  '..r.activity..'  /  '..r.status,32,y-35,495)
  label(parent,'Level '..r.minLevel..'-'..r.maxLevel..'  /  '..roleText(r.roles)..'  /  '..(r.groupSize-r.needed)..'/'..r.groupSize..' listed',32,y-58,495)
  local desc=label(parent,r.description~='' and r.description or 'No description.',32,y-81,495)
  if desc.SetWordWrap then desc:SetWordWrap(true) end
  if r.startAt then label(parent,'Starts '..date('%H:%M',r.startAt),32,y-132,495) end
  y=y-168
  if r.mine then
   local x=18
   for _,a in ipairs({{'Edit','edit'},{'Renew','renew'},{'Close','close'},{'Delete','delete'}}) do
    local action=a[2]
    if action=='delete' or (r.status=='open' or (action=='renew' and r.status=='expired')) then
     button(parent,a[1],x,y,116,function()
      if action=='edit' then
       editing=r;draft=r;tab='Create Listing'
       if r.startAt and r.startAt>time() then draft.startMinutes=math.ceil((r.startAt-time())/60) end
      else L.Update(r.id,r.revision,action) end
      redraw()
     end)
     x=x+133
    end
   end
   y=y-48
   for _,name in ipairs(r.interestedMembers or {}) do
    if y < -1400 then break end
    if K.IsMember(name) and r.status=='open' then
     label(parent,displayName(name),20,y-8,350)
     if inviteTarget(r.id,name) then
      button(parent,'Invite',420,y,124,function() L.Invite(r.id,name);redraw() end,'Send this interested guildmate a party invitation.')
     end
     y=y-39
    end
   end
  elseif r.status=='open' then
   button(parent,r.interested and 'Withdraw Interest' or 'Interested',18,y,175,function() L.Interest(r.id,not r.interested);redraw() end,
    r.interested and 'Remove your interest from this listing.' or 'Let the listing owner know you want to join.')
   if type(whisperAPI())=='function' then
    button(parent,'Whisper Leader',208,y,170,function() L.Whisper(r.id) end,'Open a whisper to the listing owner.')
   end
   y=y-48
  end
 end
 if #rows==0 then label(parent,'No listings match this view.',18,y,525);return end
 label(parent,'ACTIVITY / LEADER',18,y,370,'GameFontNormal')
 label(parent,'PARTY / AGE',421,y,125,'GameFontNormal')
 y=y-25
 for _,r in ipairs(rows) do
  if y < -3650 then label(parent,'Use the filters to narrow this list.',18,y,520);break end
  surface(parent,18,y+3,528,39,0.085)
  button(parent,(r.mine and '[Mine] ' or '')..r.name,18,y,275,function() selected=r.id;redraw() end,
   'Open this listing to see the details and available actions.',selected==r.id)
  label(parent,displayName(r.owner),304,y-9,108)
  label(parent,(r.groupSize-r.needed)..'/'..r.groupSize..'  /  '..math.max(0,math.floor((time()-r.createdAt)/60))..'m',421,y-9,124)
  y=y-42
 end
end

local readinessDeferred=false
local function refreshReadiness()
 if InCombatLockdown and InCombatLockdown() then readinessDeferred=true;return end
 readinessDeferred=false
 if K.UI and K.UI.LFGRefresh then K.UI.LFGRefresh() end
end
K.On('PLAYER_REGEN_ENABLED',function() if readinessDeferred then refreshReadiness() end end)
local function onReadiness()
 local status,guild,actor=readiness()
 if status==lastReadiness and guild==lastReadyGuild and actor==lastActor then return end
 lastReadiness,lastReadyGuild,lastActor=status,guild,actor
 if KWCDB and prefs().readinessDebug then diagnostic() end
 if status=='Ready' or status=='Not currently in a guild' then stopRetry() end
 refreshReadiness()
end
for _,event in ipairs({'PLAYER_ENTERING_WORLD','INITIAL_CLUBS_LOADED','CLUB_ADDED','CLUB_REMOVED','CLUB_UPDATED','GUILD_ROSTER_UPDATE','PLAYER_GUILD_UPDATE'}) do
 K.On(event,onReadiness)
end
