-- Receiver for authorized KWCC officer notices. Notices use the shared War Room
-- toast system and are labeled as officer messages, never Blizzard system text.
local K=KWC
local B={};K.OfficerBroadcast=B
local kinds={
 'Guild Announcement','Urgent War Council Notice','Call to Arms Announcement',
 'Event Announcement','Operational Update',
}
local seenLimit=100
local senderHistory={}

local channel=K.Toast.Channel({key='officerNotice',label='Officer Notice',icon='cta',tone='warn',defaultSlot=5,enabledKey='officerNotice'})

local function clean(value,max)
 if issecretvalue and issecretvalue(value) then return nil end
 if type(value)~='string' or #value>(max or 180) or value:find('[%c|]') then return nil end
 return value
end

local function show(title,message,kind,eventID,preview)
 local content={kicker=preview and 'OFFICER NOTICE • PREVIEW' or 'OFFICER NOTICE • '..kind,
  title=title,detail=(kind=='Urgent War Council Notice' and 'URGENT • ' or '')..message,
  eventID=eventID,tone='warn'}
 if preview then return channel:Present(content,false) end
 return K.Toast.Notice('officerNotice',title,content.detail,eventID and {label='Open War Room',fn=function()K.WarRoom2.Show('dashboard')end} or nil,eventID,content.kicker)
end

function B.Preview(title,message,urgent)
 title=clean(title,60);message=clean(message,180)
 if not title or title=='' or not message or message=='' then return false end
 return show(title,message,urgent and 'Urgent War Council Notice' or 'Guild Announcement',nil,true)
end

local function seenStore(guild)
 local root=KWCDB.officerNotices
 if root==nil then root={version=1,guilds={}};KWCDB.officerNotices=root end
 if type(root)~='table' or (root.version~=nil and root.version~=1) or type(root.guilds)~='table' then return end
 local store=root.guilds[guild]
 if store==nil then store={};root.guilds[guild]=store end
 if type(store)~='table' then return end
 for id,at in pairs(store) do
  if type(id)~='string' or type(at)~='number' or at%1~=0 then return end
 end
 return store
end

local function parse(message)
 local version,id,stamp,guild,index,title,body=message:match('^(%d+);OFFICERNOTICE;([^|]+)|(%d+)|([^|]+)|(%d+)|([^|]+)|([^|]+)$')
 if version~='2' or not id or #id>100 or not id:match('^Player%-%w+%-%w+:[%w%-]+:%d+$') then return end
 stamp,index=tonumber(stamp),tonumber(index)
 if not stamp or stamp%1~=0 or math.abs(time()-stamp)>300 or not index or index%1~=0 or not kinds[index] then return end
 title,body=clean(title,60),clean(body,180)
 if not title or title=='' or not body or body=='' then return end
 return id,stamp,guild,index,title,body
end

function B.Receive(message,sender,distribution)
 if distribution~='GUILD' or type(message)~='string' or #message>250 or not KWCDB then return false end
 if issecretvalue and (issecretvalue(message) or issecretvalue(sender)) then return false end
 local guild=K.GuildScope()
 if not guild or type(sender)~='string' or not K.IsSenderOfficer(sender) then return false end
 local id,stamp,claimedGuild,index,title,body=parse(message)
 if not id or claimedGuild~=guild then return false end
 local store=seenStore(guild)
 if not store then return false end
 if store[id] then return false end
 local now=time();local recent=senderHistory[sender] or {};local kept={}
 for _,at in ipairs(recent) do if now-at<60 then kept[#kept+1]=at end end
 if #kept>=5 then senderHistory[sender]=kept;return false end
 kept[#kept+1]=now;senderHistory[sender]=kept
 store[id]=stamp
 local count=0;local oldest,oldestAt
 for key,at in pairs(store) do
  count=count+1
  if not oldestAt or at<oldestAt then oldest,oldestAt=key,at end
 end
 if count>seenLimit and oldest then store[oldest]=nil end
 local label=kinds[index]
 show(title,'Sent by '..sender..'\n'..body,label,id,false)
 return true
end

K.On('CHAT_MSG_ADDON',function(prefix,message,distribution,sender)
 if prefix=='KWC3' and type(message)=='string' and message:find(';OFFICERNOTICE;',1,true) then
  B.Receive(message,sender,distribution)
 end
end)
