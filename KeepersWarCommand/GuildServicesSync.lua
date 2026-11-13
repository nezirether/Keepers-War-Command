local K,S=KWC,KWC.GuildServices
local PREFIX='KWPRO1'
local localBooks={}
local pending=false
local function enabled(record)
 return record and record.sharing==true
end
local function row(kind,actor,revision,at,body)
 return table.concat({kind,actor,revision,at,body or ''},'|')
end
local function actorRecord(db,actor)
 local record=db.characters[actor]
 if record then return record end
 local count=0
 for _ in pairs(db.characters) do count=count+1 end
 if count>=1000 then return end
 record={professions={},withdrawn=0}
 db.characters[actor]=record
 return record
end
local function split(value,separator)
 local parts={}
 for part in (value..separator):gmatch('(.-)'..separator) do parts[#parts+1]=part end
 return parts
end
local function apply(payload,sender,relay)
 local db,_,me=S.Context()
 if not db or #payload>250 or payload:find('[%c]') then return end
 local kind,actor,rev,at,body=payload:match('^([PW])|([^|]+)|(%d+)|(%d+)|(.*)$')
 if not actor or K.CurrentGuildMember(actor)~=actor or actor==me
  or (not relay and not K.SameGuildMember(sender,actor)) then return end
 rev,at=tonumber(rev),tonumber(at)
 if not rev or not at or at<1500000000 or at>time()+300 or rev<1 or rev>time()+300 then return end
 if kind=='W' then
  if body~='' then return end
  local record=actorRecord(db,actor)
  if not record or rev<=record.withdrawn then return end
  record.withdrawn=rev;record.withdrawnAt=at
  for name,p in pairs(record.professions) do if p.rev<=rev then record.professions[name]=nil end end
  return
 end
 local f=split(body,'|')
 if #f~=3 or S.ProfessionName(f[1])~=f[1] then return end
 local rank=tonumber(f[2])
 if not rank or rank%1~=0 or rank< -1 or rank>10000 then return end
 local recipes,seen={},{}
 if f[3]~='' then
  for _,entry in ipairs(split(f[3],',')) do
   local id,item=entry:match('^(%d+):(%d+)$')
   id,item=tonumber(id),tonumber(item)
   if not id or id<1 or id>=100000000 or item>=100000000 or seen[id] or #recipes>=16 then return end
   seen[id]=true
   recipes[#recipes+1]={id=id,item=item>0 and item or nil}
  end
 end
 local record=actorRecord(db,actor)
 if not record or rev<=record.withdrawn then return end
 local old=record.professions[f[1]]
 if old and (rev<old.rev or (rev==old.rev and body<=old.body)) then return end
 record.professions[f[1]]={rank=rank,recipes=recipes,rev=rev,at=at,body=body,relay=relay}
end

local function broadcast(guild,payload,priority)
 return K.Net.Send(PREFIX,guild..'|'..payload,'GUILD',nil,priority)
end
local function nextRevision(record)
 record.clock=math.max(time(),(record.clock or 0)+1)
 return record.clock
end
function S.IsSharing()
 local db,_,actor=S.Context()
 return db and enabled(db.characters[actor]) or false
end
function S.SetSharing(value)
 local db,guild,actor=S.Context()
 if not db then return false end
 local record=actorRecord(db,actor)
 if not record then return false end
 record.sharing=value==true
 if value then
  S.Refresh()
 else
  record.withdrawn,record.withdrawnAt=nextRevision(record),time()
  record.professions={}
  if K.Net.CancelPrefix then K.Net.CancelPrefix(PREFIX,guild) end
  broadcast(guild,row('W',actor,record.withdrawn,record.withdrawnAt),'ALERT')
 end
 return true
end
function S.Refresh(includeRecipes)
 local db,guild,actor=S.Context()
 if not db then return end
 local skills=S.ReadSkills()
 if includeRecipes then
  local name,recipes,rank=S.ReadRecipes()
  if name then localBooks[name]=recipes;skills[name]=rank or skills[name] or false end
 end
 S.localSkills=skills
 local record=db.characters[actor]
 if not enabled(record) then return end
 local names={}
 for name in pairs(skills) do names[#names+1]=name end
 table.sort(names)
 for _,name in ipairs(names) do
  local rank=skills[name] or -1
  local head=name..'|'..rank..'|'
  local old=record.professions[name]
  local recipes=localBooks[name] or (old and old.recipes) or {}
  local packed,kept={},{}
  for _,recipe in ipairs(recipes) do
   local item=recipe.id..':'..(recipe.item or 0)
   packed[#packed+1]=item
   if #packed>16 or #row('P',actor,time(),time(),head..table.concat(packed,','))+#guild+34>250 then
    packed[#packed]=nil;break
   end
   kept[#kept+1]=recipe
  end
  local body=head..table.concat(packed,',')
  if not old or old.body~=body then
   local rev,at=nextRevision(record),time()
   local p={rank=rank,recipes=kept,rev=rev,at=at,body=body}
   record.professions[name]=p
   broadcast(guild,row('P',actor,rev,at,body))
  end
 end
end
local function page(pageIndex)
 local db,_,me=S.Context()
 if not db then return {} end
 local rows,actors={},{}
 for actor in pairs(db.characters) do actors[#actors+1]=actor end
 table.sort(actors)
 for _,actor in ipairs(actors) do
  if K.CurrentGuildMember(actor)==actor then
   local r=db.characters[actor]
   if r.withdrawn>0 then rows[#rows+1]=row('W',actor,r.withdrawn,r.withdrawnAt) end
   if actor~=me or enabled(r) then
    local names={}
    for name in pairs(r.professions) do names[#names+1]=name end
    table.sort(names)
    for _,name in ipairs(names) do
     local p=r.professions[name]
     rows[#rows+1]=row('P',actor,p.rev,p.at,p.body)
    end
   end
  end
 end
 if #rows==0 then return {} end
 local result={}
 local first=(pageIndex%math.ceil(#rows/6))*6+1
 for i=first,math.min(#rows,first+5) do result[#result+1]=rows[i] end
 return result
end
K.Sync.RegisterRecoveryDataset('PRO',page,function(payload,sender) apply(payload,sender,sender) end)
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~=PREFIX or channel~='GUILD' or type(msg)~='string' or #msg>250 or not K.IsMember(sender) then return end
 local guild,payload=msg:match('^(%d+)|(.+)$')
 if guild and guild==K.GuildScope() then apply(payload,sender) end
end)
K.On('ADDON_LOADED',function(addon)
 if addon=='KeepersWarCommand' and C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  pcall(C_ChatInfo.RegisterAddonMessagePrefix,PREFIX)
 end
end)
local recipePending=false
local function schedule(recipes)
 recipePending=recipePending or recipes
 if pending then return end
 if not C_Timer or not C_Timer.After then S.Refresh(recipePending);recipePending=false;return end
 pending=true
 local guild=K.GuildScope()
 C_Timer.After(0.8,function()
  pending=false
  local scan=recipePending;recipePending=false
  if guild==K.GuildScope() then S.Refresh(scan) end
 end)
end
for _,event in ipairs({'PLAYER_ENTERING_WORLD','SKILL_LINES_CHANGED','CHAT_MSG_SKILL','INITIAL_CLUBS_LOADED'}) do
 K.On(event,function() schedule(false) end)
end
for _,event in ipairs({'TRADE_SKILL_SHOW','TRADE_SKILL_LIST_UPDATE','TRADE_SKILL_DATA_SOURCE_CHANGED','NEW_RECIPE_LEARNED'}) do
 K.On(event,function() schedule(true) end)
end
local function republishWithdrawal()
 local db,guild,actor=S.Context()
 local record=db and db.characters[actor]
 if record and not enabled(record) and record.withdrawn>0 then
  broadcast(guild,row('W',actor,record.withdrawn,record.withdrawnAt),'ALERT')
 end
end
K.On('PLAYER_ENTERING_WORLD',republishWithdrawal)
K.On('INITIAL_CLUBS_LOADED',republishWithdrawal)
K.On('PLAYER_GUILD_UPDATE',function() S.localSkills=nil;schedule(false);republishWithdrawal() end)
