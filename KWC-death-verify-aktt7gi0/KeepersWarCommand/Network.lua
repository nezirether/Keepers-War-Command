-- DEV42: shared, conservative guild addon transport. No public chat messages.
local K=KWC
K.Net={}
local N=K.Net
local queue, pending={},{}
local elapsed=0
local sent,failed,dropped=0,0,0
local function key(prefix,msg,channel,target) return prefix..'\001'..channel..'\001'..(target or '')..'\001'..msg end
function N.Send(prefix,msg,channel,target,priority)
 if not IsInGuild() or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
 if type(msg)~='string' or #msg>250 then return false end
 channel=channel or 'GUILD'
 local id=key(prefix,msg,channel,target)
 if pending[id] then return true end
 if #queue>=350 then dropped=dropped+1;return false end
 local item={prefix=prefix,msg=msg,channel=channel,target=target,id=id,attempts=0}
 pending[id]=true
 if priority=='ALERT' then table.insert(queue,1,item) else queue[#queue+1]=item end
 return true
end
local frame=CreateFrame('Frame')
frame:SetScript('OnUpdate',function(_,dt)
 elapsed=elapsed+dt
 if elapsed<0.85 or #queue==0 then return end
 elapsed=0
 if not IsInGuild() then queue={};pending={};return end
 local item=table.remove(queue,1)
 local ok,result=pcall(C_ChatInfo.SendAddonMessage,item.prefix,item.msg,item.channel,item.target)
 local throttled=(not ok) or result==false or (type(result)=='number' and result~=0)
 if throttled then
  failed=failed+1;item.attempts=item.attempts+1
  if item.attempts<3 then queue[#queue+1]=item;elapsed=-3 else pending[item.id]=nil;dropped=dropped+1 end
 else pending[item.id]=nil;sent=sent+1 end
end)
function N.Status() return #queue,sent,failed,dropped end
