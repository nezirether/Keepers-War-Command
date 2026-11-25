-- Shared presentation policy for public alerts and verified personal moments.
local K=KWC
local C={queue={},streak=0,sequence=0};K.Celebrations=C
local T=K.Toast
local defaults={intensity='Balanced',pvp=true,streaks=false,bounties=true,milestones=true,cta=true,
 guild=false,sounds=true,animations=true,reducedMotion=false,guildAnnouncements=false,eventArt=true}
function C.Preferences()
 local settings=KWCDB and KWCDB.settings
 if not settings then return defaults end
 settings.celebrations=settings.celebrations or {}
 local p=settings.celebrations
 for key,value in pairs(defaults) do if p[key]==nil then p[key]=value end end
 return p
end
local function allowed() return K.InstanceAlerts and K.InstanceAlerts.Allowed() end
local function book()
 local scope=K.GuildScope and K.GuildScope()
 local guid=UnitGUID and UnitGUID('player')
 if not KWCDB or not scope or type(guid)~='string' then return end
 KWCDB.warChronicle=KWCDB.warChronicle or {}
 local guild=KWCDB.warChronicle[scope] or {};KWCDB.warChronicle[scope]=guild
 guild[guid]=guild[guid] or {events={},kills=0,best=0}
 return guild[guid]
end
function C.Stats() local b=book();return b and b.kills or 0,b and b.best or 0 end
function C.History() local b=book();return b and b.events or {} end
local function record(content)
 local b=book();if not b then return end
 table.insert(b.events,1,{title=content.title,detail=content.detail,at=time(),zone=content.meta,
  evidence=content.evidence,level=content.level or 'Standard'})
 while #b.events>100 do table.remove(b.events) end
end
local present
local function busy()
 for _,ch in ipairs(T.order) do if ch.automatic and ch.frame:IsShown() then return true end end
end
local function draw(ch,content)
 local level=content.level or 'Standard'
 local p=C.Preferences()
 local epic=p.intensity=='Epic'
 ch.frame.preferredWidth=level=='Legendary' and epic and 540 or level=='Heroic' and 460 or 404
 local shown=present(ch,content,true)
 if shown and p.sounds and p.intensity~='Quiet' and K.QOL and K.QOL.Enabled('alertSound') then
  local setting=ch.key=='pvpKill' and 'pvpKillSound' or ch.key=='worldPvPDeath' and 'worldPvPDeathSound'
   or ch.key=='bountyAlert' and 'bountySound' or ch.key=='ctaNotice' and 'ctaSound' or ch.key=='lfgNotice' and 'lfgSound'
  if (not setting or K.QOL.Enabled(setting)) and PlaySound then pcall(PlaySound,ch.key=='pvpKill' and 888 or 8959,'Master') end
 end
 return shown
end
function C.Route(ch,content)
 local p=C.Preferences()
 local category=content.category or (ch.key=='pvpKill' and 'pvp' or ch.key=='bountyAlert' and 'bounties' or ch.key=='ctaNotice' and 'cta')
 if not allowed() or p.intensity=='Off' or (category and p[category]==false) then return false end
 if not T.Claim(ch.key,content.eventID) then return false end
 local copy={}
 for key,value in pairs(content) do copy[key]=value end
 copy.eventID=nil
 if content.significant then record(content) end
 if busy() then
  if #C.queue>=12 then
   local lowest=1
   for i,item in ipairs(C.queue) do if (item.content.priority or 0)<(C.queue[lowest].content.priority or 0) then lowest=i end end
   if (copy.priority or 0)<(C.queue[lowest].content.priority or 0) then return false end
   table.remove(C.queue,lowest)
  end
  C.sequence=C.sequence+1
  C.queue[#C.queue+1]={channel=ch,content=copy,at=time(),sequence=C.sequence,guild=K.GuildScope()}
  return true
 end
 return draw(ch,copy)
end
local function wrap(ch)
 if ch.celebrationWrapped then return end
 ch.celebrationWrapped=true
 present=present or ch.Present
 ch.Present=function(self,content,automatic)
  if automatic then return C.Route(self,content) end
  self.frame.preferredWidth=content.level=='Legendary' and 540 or content.level=='Heroic' and 460 or 404
  return present(self,content,false)
 end
end
local channel=T.Channel
T.Channel=function(spec) local ch=channel(spec);wrap(ch);return ch end
for _,ch in ipairs(T.order) do wrap(ch) end
local moment=T.Channel({key='warCelebration',label='War celebration',icon='kill',defaultDuration=5,defaultSlot=5})
local tiers={Standard=moment}
for i,level in ipairs({'Heroic','Legendary'}) do
 tiers[level]=T.Channel({key='warCelebration'..level,label=level..' celebration',icon='kill',defaultDuration=5,defaultSlot=5+i})
end
function C.Moment(content,preview)
 return (tiers[content.level] or moment):Present(content,not preview)
end
function C.PreviewSound()
 if PlaySound then return pcall(PlaySound,888,'Master') end
 return false
end
function C.Preview(level)
 return C.Moment({level=level,kicker=level..' celebration preview',
  title=K.CharacterDisplayName(UnitName('player'),true),detail='Visual preview',meta='War Room',tone='accent'},true)
end
for level,ch in pairs(tiers) do
 local value=level
 ch.demo=function() C.Preview(value) end
end
local ticker=CreateFrame('Frame')
ticker:SetScript('OnUpdate',function()
 if C.ScanOperations then C.ScanOperations() end
 if not allowed() or C.Preferences().intensity=='Off' then
  C.queue={}
  for _,ch in ipairs(T.order) do if ch.automatic then ch:Hide() end end
  return
 end
 for i=#C.queue,1,-1 do
  local item=C.queue[i]
  local detector=item.channel.key=='worldPvPDeath' and K.WorldPvPDeaths or item.channel.key=='pvpKill' and K.WorldPvPKills
  local quiet=detector and detector.GetBattleStatus and detector.GetBattleStatus().active
  if quiet or time()-C.queue[i].at>10 or C.queue[i].guild~=K.GuildScope() then table.remove(C.queue,i) end end
 if #C.queue==0 or busy() then return end
 table.sort(C.queue,function(a,b)
  local x,y=a.content.priority or 0,b.content.priority or 0
  if x~=y then return x>y end
  return a.sequence<b.sequence
 end)
 local next=table.remove(C.queue,1);draw(next.channel,next.content)
end)
local titles={[3]='Bloodied',[5]='Rampage',[10]='Burninator',[15]="Warlord's Wrath",[20]='Legendary Burninator'}
function C.KillingBlow(target,eventID)
 if eventID and not T.Claim('streak',eventID) then return end
 if not allowed() then C.streak=0;return end
 C.streak=C.streak+1
 local b=book();if not b then return end
 b.kills=b.kills+1
 b.best=math.max(b.best,C.streak)
 local p=C.Preferences()
 local title=p.streaks and titles[C.streak]
 local milestone=p.milestones and (b.kills==1 or b.kills==25 or b.kills==100)
 if title or milestone then
  local actor=K.CharacterDisplayName(UnitName('player'),true)
  C.Moment({eventID=tostring(time())..':'..C.streak..':'..target,category=title and 'streaks' or 'milestones',
   kicker=title and 'Verified local streak' or 'KWC commendation',title=title or 'Confirmed killing blows',
   detail=actor..' â€¢ '..(title and C.streak..' this session' or b.kills..' observed killing blows'),
   level=C.streak>=20 and 'Legendary' or 'Heroic',priority=2,significant=true,
   evidence='Local PARTY_KILL attacker GUID',meta=GetRealZoneText and GetRealZoneText()})
 end
end
K.On('PLAYER_DEAD',function() C.streak=0 end)
K.On('PLAYER_ENTERING_WORLD',function() C.streak=0;C.queue={} end)
K.On('PLAYER_LOGOUT',function() C.streak=0;C.queue={} end)

local operationScope,operationStates,lastScan
function C.ScanOperations()
 if lastScan and time()-lastScan<1 then return end
 lastScan=time()
 local scope=K.GuildScope and K.GuildScope()
 if scope~=operationScope then operationScope=scope;operationStates=nil end
 if not scope then return end
 local seeded=operationStates~=nil
 operationStates=operationStates or {}
 local current={}
 for _,entry in ipairs(KWCDB.bounties or {}) do
  if entry.id then
   local prior=operationStates[entry.id]
   local status=entry.status or 'ACTIVE'
   current[entry.id]=status
   if seeded and prior=='ACTIVE' and status=='COMPLETED' then
    C.Moment({eventID=scope..':'..entry.id..':'..tostring(entry.revision or entry.updated),
     category='bounties',kicker='Bounty completed',title=K.CharacterDisplayName(entry.details and entry.details.target or entry.text or 'Guild bounty'),
     detail='Completion confirmed by '..K.CharacterDisplayName(entry.updatedBy or entry.author or 'Unknown'),
     level='Heroic',priority=2,significant=true,evidence='Authorized bounty lifecycle COMPLETED'})
   end
  end
 end
 operationStates=current
end
local resultsPending={}
local outcomes={VICTORY=true,OBJECTIVE=true,WITHDRAWN=true,UNRESOLVED=true}
local function resultBook()
 local scope=K.GuildScope and K.GuildScope()
 if not KWCDB or not scope then return end
 KWCDB.celebrationOutcomes=KWCDB.celebrationOutcomes or {}
 local store=KWCDB.celebrationOutcomes[scope] or {}
 KWCDB.celebrationOutcomes[scope]=store
 return store
end
local function operation(id)
 for _,entry in ipairs(KWCDB.ops or {}) do if entry.id==id then return entry end end
end
function C.AcceptOutcome(id,result,revision,stamp,sender)
 if not outcomes[result] or not K.CurrentGuildMember(sender) then return false end
 local entry=operation(id)
 if not entry or not (K.SameGuildMember(entry.author,sender) or K.IsSenderOfficer(sender)) then return false end
 if entry.status~='RESOLVED' or (entry.revision or 0)~=revision then return false end
 local store=resultBook();if not store then return false end
 local prior=store[id]
 if prior and prior.revision>=revision then return false end
 store[id]={outcome=result,revision=revision,at=stamp,actor=K.CharacterDisplayName(sender)}
 local keys={}
 for key,row in pairs(store) do keys[#keys+1]={key=key,at=row.at} end
 table.sort(keys,function(a,b)return a.at<b.at end)
 for i=1,math.max(0,#keys-100) do store[keys[i].key]=nil end
 if result=='VICTORY' or result=='OBJECTIVE' then
  C.Moment({eventID=K.GuildScope()..':cta:'..id..':'..revision,category=K.IsLocalSender(sender) and 'cta' or 'guild',
   title=entry.text,detail=(result=='VICTORY' and 'Victory confirmed by ' or 'Objective completed by ')..K.CharacterDisplayName(sender),
   kicker='Call to Arms',level='Heroic',priority=2,significant=true,evidence='Authorized explicit CTA outcome'})
 end
 return true
end
function C.CompleteCTA(id,result)
 if not outcomes[result] then return false end
 local entry=operation(id)
 if not entry or (entry.status or 'ACTIVE')~='ACTIVE' or not K.Operations.CanDelete(entry) then return false end
 K.Operations.ChangeStatus('CTA',id,'RESOLVED')
 if entry.status~='RESOLVED' then return false end
 local revision,stamp=entry.revision or 0,time()
 local sender=K.CharacterDisplayName(UnitName('player'),true)
 if not C.AcceptOutcome(id,result,revision,stamp,sender) then return false end
 K.Send('CTARESULT',table.concat({id,result,revision,stamp},';'))
 return true
end
function C.Outcome(id)
 local store=resultBook()
 local entry=operation(id)
 local row=store and store[id]
 return row and entry and entry.status=='RESOLVED' and row.revision==(entry.revision or 0) and row or nil
end
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~='KWC3' or channel~='GUILD' or type(msg)~='string' or not K.IsMember(sender) then return end
 local id,result,revision,stamp=msg:match('^2;CTARESULT;([^;]+);([A-Z]+);(%d+);(%d+)$')
 if not id or #id>90 or not outcomes[result] then return end
 revision,stamp=tonumber(revision),tonumber(stamp)
 if math.abs(time()-stamp)>30 then return end
 if C.AcceptOutcome(id,result,revision,stamp,sender) then return end
 local size=0;for _ in pairs(resultsPending) do size=size+1 end
 if size<32 then resultsPending[id]={result,revision,stamp,sender,K.GuildScope()} end
end)
local previousScan=C.ScanOperations
function C.ScanOperations()
 previousScan()
 for id,item in pairs(resultsPending) do
  if time()-item[3]>30 or item[5]~=K.GuildScope() or C.AcceptOutcome(id,item[1],item[2],item[3],item[4]) then resultsPending[id]=nil end
 end
end

-- Native successful encounters can be kept as evidence without showing an instance popup.
K.On('ENCOUNTER_END',function(id,name,difficulty,size,success)
 if success~=1 or type(id)~='number' or type(name)~='string' or not C.Preferences().guild then return end
 local event='encounter:'..id..':'..tostring(time())
 if not T.Claim('guild-encounter',event) then return end
 record({title=name,detail='Successful observed encounter � '..K.CharacterDisplayName(UnitName('player'),true),
  meta=GetRealZoneText and GetRealZoneText(),evidence='Native ENCOUNTER_END success=1',level='Heroic'})
end)
