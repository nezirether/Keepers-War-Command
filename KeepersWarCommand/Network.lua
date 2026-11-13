-- DEV42: shared, conservative guild addon transport. No public chat messages.
local K=KWC
K.Net={}
local N=K.Net
local queue, pending={},{}
local elapsed=0
local recoveryTurn=false
local sent,failed,dropped=0,0,0
local function key(prefix,msg,channel,target) return prefix..'\001'..channel..'\001'..(target or '')..'\001'..msg end
function N.Send(prefix,msg,channel,target,priority)
 if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
 if type(msg)~='string' or #msg>250 then return false end
 channel=channel or 'GUILD'
 local scope=K.GuildScope and K.GuildScope()
 local group=channel=='PARTY' or channel=='RAID'
 if not group and (not IsInGuild() or not scope) then return false end
 local id=tostring(scope)..'\001'..key(prefix,msg,channel,target)
 if pending[id] then return true end
 if priority=='RECOVERY' then
  local count=0
  for _,queued in ipairs(queue) do if queued.recovery then count=count+1 end end
  if count>=24 or #queue>=300 then return false end
 end
 if #queue>=350 then dropped=dropped+1;return false end
 local item={prefix=prefix,msg=msg,channel=channel,target=target,id=id,attempts=0,scope=scope,group=group,recovery=priority=='RECOVERY',alert=priority=='ALERT'}
 pending[id]=true
 if priority=='ALERT' then table.insert(queue,1,item) else queue[#queue+1]=item end
 return true
end
local frame=CreateFrame('Frame')
frame:SetScript('OnUpdate',function(_,dt)
 elapsed=elapsed+dt
 if elapsed<0.85 or #queue==0 then return end
 elapsed=0
 local index=1
 if not queue[1].alert then
  recoveryTurn=not recoveryTurn
  for i,item in ipairs(queue) do
   if item.recovery==recoveryTurn then index=i;break end
  end
 end
 local item=table.remove(queue,index)
 if not item.group and (not IsInGuild() or item.scope~=(K.GuildScope and K.GuildScope())) then pending[item.id]=nil;return end
 local ok,result=pcall(C_ChatInfo.SendAddonMessage,item.prefix,item.msg,item.channel,item.target)
 local throttled=(not ok) or result==false or (type(result)=='number' and result~=0)
 if throttled then
  failed=failed+1;item.attempts=item.attempts+1
  if item.attempts<3 then queue[#queue+1]=item;elapsed=-3 else pending[item.id]=nil;dropped=dropped+1 end
 else pending[item.id]=nil;sent=sent+1 end
end)
function N.CancelPrefix(prefix,scope)
 for i=#queue,1,-1 do
  local item=queue[i]
  if item.prefix==prefix and item.scope==scope then
   pending[item.id]=nil
   table.remove(queue,i)
  end
 end
end
function N.Status() return #queue,sent,failed,dropped end
