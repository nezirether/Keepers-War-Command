local K=KWC
local R={}
K.GuildRecords=R
local PREFIX='KWREC1'
local MAX=999999999
R.categories={
 {name='Hall of Shame',boards={
  {60,"Spirit Healer's Favorite Customer",'Total deaths'},
  {114,'Thunder Bluff Express','Deaths from falling'},
  {115,"Trogdor's Fire Insurance",'Deaths from fire and lava'},
  {320,"Lok'tar Oops'gar",'Duels lost'},
  {112,'Darkspear Swim Team','Deaths from drowning'},
 }},
 {name='Hall of Glory',boards={
  {319,"Mak'gora Champion",'Duels won'},
  {98,'Peon of the Month','Quests completed'},
 }},
 {name="Trogdor's Oddities",boards={
  {1456,'The Eternal Fisherman','Fish and other things caught'},
  {347,'The Snack Warchief','Food eaten'},
  {922,'Mana Potion Addict','Mana potions consumed'},
  {349,"Warchief's Personal Taxi",'Flight paths taken'},
  {330,'Gadgetzan Frequent Customer','Auction purchases'},
  {1047,'Barrens Chat Legend','Total facepalms'},
  {108,'Barrens Pest Control','Critters killed'},
  {353,'Back to the Barrens','Hearthstone uses'},
  {1045,'Zug Zug Hype Squad','Total cheers'},
  {1067,'Tiny Violin, Big Grudge',"Times playing the world's smallest violin"},
 }},
}
-- Keep the original packets readable by older Guild Records builds. Extra
-- Oddities use a separate packet group to stay inside the addon message limit.
local PVP_DEATHS=1501
-- Keep the existing two-field death packet intact for older clients.
local groups={R.categories[1].boards,R.categories[2].boards,{},{},{{'retired'},{'battleground'}},
 {{PVP_DEATHS},{'worldEstimate'}},{{'totalDeaths'},{'verifiedBGDeaths'},{'nonBGDeaths'},{PVP_DEATHS},{321}}}
local ORIGINAL_ODDITIES=6
for i,board in ipairs(R.categories[3].boards) do
 local group=i<=ORIGINAL_ODDITIES and groups[3] or groups[4]
 group[#group+1]=board
end
local function packetSlot(category,index)
 if category==3 and index>ORIGINAL_ODDITIES then return 4,index-ORIGINAL_ODDITIES end
 return category,index
end

local function context()
 local ready,guild,actor=K.GuildReadiness()
 if ready~='Ready' then return nil,ready end
 KWCDB.guildRecords=KWCDB.guildRecords or {members={},sharing={}}
 local db=KWCDB.guildRecords
 if not db.lifetimeOnly then
  for _,entry in pairs(db.members) do
   for _,group in pairs(entry.groups) do
    for index,row in pairs(group.rows) do
     if type(row)=='table' then group.rows[index]=row.total end
    end
    group.week,group.body=nil,nil
   end
  end
  db.lifetimeOnly=true
 end
 return db,guild,actor
end
local function count(value)
 if (issecretvalue and issecretvalue(value)) then return end
 if type(value)=='string' then
  -- Accept plain counts and client-formatted groups of three digits.
  value=value:match('^%s*(.-)%s*$')
  if not value:match('^%d+$') then
   value=value:gsub('\194\160',' '):gsub('\226\128\175',' ')
   local separator=value:match('^%d%d?%d?([,%. ])')
   if not separator then return end
   local first=value:find(separator,1,true)
   for i=first,#value,4 do
    if value:sub(i,i)~=separator or not value:sub(i+1,i+3):match('^%d%d%d$') then return end
   end
   value=value:gsub('[,%. ]','')
  end
  value=tonumber(value)
 end
 if type(value)=='number' and value>=0 and value<=MAX and value%1==0 then return value end
end
-- Forever Interface 16001, confirmed in the live Statistics pane:
-- 122: 60; 21: 1501; 125: 321; 124: 57, 59, 56, 64182.
-- Select map totals only. The same category contains boss-specific subcounts.
local TOTAL_DEATHS=60
local BG_DEATHS={57,59,56,64182}
local slots={}
local function statistic(category,index)
 local ok,raw,skip,id=pcall(GetStatistic,category,index)
 if not ok or (issecretvalue and (issecretvalue(raw) or issecretvalue(skip) or issecretvalue(id))) then return end
 if type(id)~='number' or skip==true then return end
 return id,raw
end
local function scan(wanted)
 local values,seen={},{}
 if type(GetStatistic)~='function' then return values end
 local function collect(category,index)
  local id,value=statistic(category,index)
  if not id or not wanted[id] then return end
  local n=count(value)
  if n==nil and wanted[id]=='zeroIfEmpty' and type(value)=='string' and value:match('^%s*%-%-%s*$') then n=0 end
  if not seen[id] or (values[id]==nil and n~=nil) then slots[id]={category,index};values[id]=n end
  seen[id]=true
 end
 for id in pairs(wanted) do
  local slot=slots[id]
  if slot then collect(slot[1],slot[2]) end
 end
 local missing=false
 for id in pairs(wanted) do if not seen[id] then missing=true;break end end
 if not missing or type(GetStatisticsCategoryList)~='function' or type(GetCategoryNumAchievements)~='function' then return values end
 local ok,categories=pcall(GetStatisticsCategoryList)
 if not ok or type(categories)~='table' then return values end
 for _,category in pairs(categories) do
  if type(category)=='number' then
   local readable,size=pcall(GetCategoryNumAchievements,category)
   if readable and type(size)=='number' and not (issecretvalue and issecretvalue(size)) then
    for i=1,math.min(size,1000) do collect(category,i) end
   end
  end
 end
 return values
end
local deathIDs={[TOTAL_DEATHS]=true,[PVP_DEATHS]=true,[321]=true}
for _,id in ipairs(BG_DEATHS) do deathIDs[id]='zeroIfEmpty' end
local function deaths(values)
 local total,bg=values[TOTAL_DEATHS],0
 for _,id in ipairs(BG_DEATHS) do
  if values[id]==nil then bg=nil;break end
  bg=bg+values[id]
 end
 if total and bg and bg>total then bg=nil end
 return {total=total,bg=bg,nonBG=total and bg and total-bg or nil,pvp=values[PVP_DEATHS],instance=values[321]}
end
function R.DeathStatistics() return deaths(scan(deathIDs)) end
function R.BattlegroundDeaths() return R.DeathStatistics().bg end
function R.LifetimeDeathsExcludingBG() return R.DeathStatistics().nonBG end
function R.PvPDeaths() return R.DeathStatistics().pvp end
function R.WorldDeathEstimate()
 local s=R.DeathStatistics()
 if s.pvp and s.bg and s.pvp>=s.bg then return s.pvp-s.bg end
end
local function read(id) return scan({[id]=true})[id] end
local function member(db,actor)
 local entry=db.members[actor]
 if not entry then
  entry={withdrawn=0,groups={}}
  db.members[actor]=entry
 end
 return entry
end
local function refreshUI()
 if K.UI and K.UI.GuildRecordsRefresh then K.UI.GuildRecordsRefresh() end
end
local digits='0123456789abcdefghijklmnopqrstuvwxyz'
local function compact(value)
 local result=''
 repeat
  local digit=value%36+1
  result=digits:sub(digit,digit)..result
  value=math.floor(value/36)
 until value==0
 return result
end
local function encodeBody(index,rows)
 local body={}
 for i=1,#groups[index] do
  local total=groups[index][i][1]~='retired' and rows[i] and compact(rows[i])
  body[i]=total and (total..','..total..',-') or '-'
 end
 return table.concat(body,';')
end
-- Keep the KWREC1 packet readable by existing builds. Fill the retired
-- fields with a neutral baseline and an empty previous score.
local function wirePeriod(revision)
 return math.floor((revision+259200)/604800)
end
local function encode(actor,index,group)
 return table.concat({actor,index,group.rev,wirePeriod(group.rev),encodeBody(index,group.rows)},'|')
end
local function apply(payload,sender,relay)
 local db,_,me=context()
 if not db or #payload>230 or payload:find('[%c]') then return end
 local actor,index,rev,body=payload:match('^([^|]+)|(%d)|(%d+)|%d+|(.*)$')
 if not actor or actor==me or K.CurrentGuildMember(actor)~=actor or
    (not relay and not K.SameGuildMember(actor,sender)) then return end
 index,rev=tonumber(index),tonumber(rev)
 local now=time()
 if rev<1 or rev>now+300 then return end
 if index==0 then
  if body~='' then return end
  local entry=member(db,actor)
  if rev<=entry.withdrawn then return end
  entry.withdrawn=rev
  for group,data in pairs(entry.groups) do
   if data.rev<=rev then entry.groups[group]=nil end
  end
  refreshUI()
  return
 end
 local boards=groups[index]
 if not boards then return end
 local rows,i={},0
 for field in (body..';'):gmatch('(.-);') do
  i=i+1
  if field~='-' then
   local total,base,previous=field:match('^([0-9a-z]+),([0-9a-z]+),([0-9a-z%-]+)$')
   total,base=count(total and tonumber(total,36)),count(base and tonumber(base,36))
   local prior=count(previous and tonumber(previous,36))
   if total==nil or base==nil or base>total or (previous~='-' and prior==nil) then return end
   if boards[i] and boards[i][1]~='retired' then rows[i]=total end
  end
 end
 if i~=#boards or (index~=1 and index~=5 and index~=6 and index~=7 and not next(rows)) then return end
 if index==7 then
  local total,bg,nonBG=rows[1],rows[2],rows[3]
  if (total and bg and (bg>total or nonBG~=total-bg)) or
     (nonBG~=nil and (total==nil or bg==nil)) then return end
 end
 local entry=member(db,actor)
 local old=entry.groups[index]
 if rev<=entry.withdrawn or (old and (rev<old.rev or
    (rev==old.rev and encodeBody(index,rows)<=encodeBody(index,old.rows)))) then return end
 entry.groups[index]={rev=rev,rows=rows}
 refreshUI()
end

local function send(guild,payload)
 return K.Net.Send(PREFIX,guild..'|'..payload,'GUILD')
end
local function withdraw(actor,rev)
 return table.concat({actor,0,rev,wirePeriod(rev),''},'|')
end
local function revision(entry)
 entry.clock=math.max(time(),(entry.clock or 0)+1)
 return entry.clock
end
function R.Sharing()
 local db,_,actor=context()
 return db~=nil and db.sharing[actor]~=false
end
local lastSent={}
local function publish(guild,key,packet,now)
 local previous=lastSent[key]
 if (not previous or previous.packet~=packet or now-previous.at>=900) and send(guild,packet) then
  lastSent[key]={packet=packet,at=now}
 end
end
function R.Sample()
 local db,guild,actor=context()
 if not db then return end
 local now=time()
 local key=guild..'|'..actor..'|'
 if db.sharing[actor]==nil then db.sharing[actor]=true end
 if db.sharing[actor]==false then
  local entry=db.members[actor]
  if entry and entry.withdrawn>0 then
   local marker=withdraw(actor,entry.withdrawn)
   if not lastSent[key..'0'] then publish(guild,key..'0',marker,now) end
  end
  return
 end
 local entry=member(db,actor)
 local changed=false
 local wanted={}
 for id,mode in pairs(deathIDs) do wanted[id]=mode end
 for _,boards in ipairs(groups) do
  for _,board in ipairs(boards) do if type(board[1])=='number' and not wanted[board[1]] then wanted[board[1]]=true end end
 end
 local values=scan(wanted)
 local historical=deaths(values)
 for index,boards in ipairs(groups) do
  local old=entry.groups[index]
  local rows={}
  for i,board in ipairs(boards) do
   local stat=board[1]
   local value
   if stat=='battleground' or stat=='verifiedBGDeaths' then value=historical.bg
   elseif stat=='totalDeaths' then value=historical.total
   elseif stat=='nonBGDeaths' then value=historical.nonBG
   elseif stat=='worldEstimate' then
    if historical.pvp and historical.bg and historical.pvp>=historical.bg then value=historical.pvp-historical.bg end
   elseif type(stat)=='number' then value=values[stat] end
   rows[i]=value
   if value==nil and type(stat)=='number' and stat~=TOTAL_DEATHS and stat~=PVP_DEATHS and index~=7 and old then rows[i]=old.rows[i] end
  end
  if next(rows) or (old and (index==1 or index>=5)) then
   local group={rows=rows}
   if not old or encodeBody(index,rows)~=encodeBody(index,old.rows) then
    group.rev=revision(entry)
    entry.groups[index]=group
    changed=true
   end
   publish(guild,key..index,encode(actor,index,entry.groups[index]),now)
  end
 end
 if changed then refreshUI() end
end
function R.SetSharing(enabled)
 local db,guild,actor=context()
 if not db or db.sharing[actor]==enabled then return end
 db.sharing[actor]=enabled
 lastSent={}
 if enabled then
  R.Sample()
 else
  local entry=member(db,actor)
  entry.withdrawn=revision(entry)
  entry.groups={}
  K.Net.CancelPrefix(PREFIX,guild)
  publish(guild,guild..'|'..actor..'|0',withdraw(actor,entry.withdrawn),time())
 end
end
local function rankings(groupIndex,slot)
 local rows={}
 local db,_,me=context()
 if not db then return rows end
 for name,entry in pairs(db.members) do
  local group=entry.groups[groupIndex]
  local value=group and group.rows[slot]
  if value~=nil and K.CurrentGuildMember(name)==name and (name~=me or db.sharing[me]) then
   local roster=K.RosterRecord and K.RosterRecord(name)
   rows[#rows+1]={name=name,display=roster and roster.name or name,value=value}
  end
 end
 table.sort(rows,function(a,b)
  if a.value~=b.value then return a.value>b.value end
  return a.name<b.name
 end)
 return rows
end
function R.Rankings(category,index)
 return rankings(packetSlot(category,index))
end
function R.DeathRankings(view)
 if view=='pvp' then return rankings(6,1) end
 if view=='estimate' then return rankings(6,2) end
 local slot,field=1,'total'
 if view=='battleground' then slot,field=2,'bg'
 elseif view=='nonBG' then slot,field=3,'nonBG' end
 local result=rankings(7,slot)
 local me=K.LocalGuildMember()
 for i=#result,1,-1 do if result[i].name==me then table.remove(result,i) end end
 local name=UnitName and UnitName('player')
 if name and not (issecretvalue and issecretvalue(name)) then
  result[#result+1]={name=me or name,display=name,value=R.DeathStatistics()[field],self=true}
 end
 return result
end
function R.DeathBreakdown(name)
 local db,_,me=context()
 if not name or name==me or name==UnitName('player') then return R.DeathStatistics() end
 local member=db and db.members[name]
 local group=member and member.groups[7]
 local r=group and group.rows or {}
 return {total=r[1],bg=r[2],nonBG=r[3],pvp=r[4],instance=r[5]}
end
function R.Readable(category,index)
 local db,_,me=context()
 local board=R.categories[category].boards[index]
 local own=db and db.members[me]
 local groupIndex,slot=packetSlot(category,index)
 local group=own and own.groups[groupIndex]
 return read(board[1])~=nil or (group and group.rows[slot]~=nil) or #R.Rankings(category,index)>0
end

K.Sync.RegisterRecoveryDataset('GR',function(page)
 local db,_,me=context()
 local rows={}
 if not db then return rows end
 local names={}
 for name in pairs(db.members) do
  if K.CurrentGuildMember(name)==name then names[#names+1]=name end
 end
 table.sort(names)
 -- Six records per request, using the shared officer-attested transport.
 local all={}
 for _,name in ipairs(names) do
  local entry=db.members[name]
  if entry.withdrawn>0 then all[#all+1]=withdraw(name,entry.withdrawn) end
  if name~=me or db.sharing[me] then
   for index=1,#groups do
    local group=entry.groups[index]
    if group and (index~=5 or group.rows[2]~=nil) then all[#all+1]=encode(name,index,group) end
   end
  end
 end
 if #all==0 then return rows end
 local first=(page%math.ceil(#all/6))*6+1
 for i=first,math.min(first+5,#all) do rows[#rows+1]=all[i] end
 return rows
end,function(payload,sender) apply(payload,sender,true) end)

K.On('ADDON_LOADED',function(addon)
 if addon=='KeepersWarCommand' and C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  pcall(C_ChatInfo.RegisterAddonMessagePrefix,PREFIX)
 end
end)
K.On('CHAT_MSG_ADDON',function(prefix,message,channel,sender)
 if prefix~=PREFIX or channel~='GUILD' or (issecretvalue and issecretvalue(message)) or type(message)~='string' or #message>250 then return end
 local guild,payload=message:match('^(%d+)|(.+)$')
 if guild and guild==K.GuildScope() then apply(payload,sender,false) end
end)
local pending=false
local function schedule()
 if pending or not C_Timer or not C_Timer.After then return end
 pending=true
 C_Timer.After(10,function() pending=false;R.Sample() end)
end
K.On('PLAYER_ENTERING_WORLD',schedule)
K.On('PLAYER_LOGIN',function() R.Sample();schedule() end)
local readyGuild
K.On('GUILD_ROSTER_UPDATE',function()
 local db,guild=context()
 guild=db and guild or nil
 if guild~=readyGuild then
  readyGuild=guild
  R.Sample()
  schedule()
  refreshUI()
 end
end)
K.On('CRITERIA_UPDATE',schedule)
K.On('PLAYER_GUILD_UPDATE',function() lastSent={};schedule();refreshUI() end)
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(300,R.Sample) end

local categoryIndex,boardIndex,page=1,1,1
-- 2.0: legacy layout R.Draw removed (UI lives in UI/Pages).

-- 2.0: legacy layout R.DrawChampions removed (UI lives in UI/Pages).
