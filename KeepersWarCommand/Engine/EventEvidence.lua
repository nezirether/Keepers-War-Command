-- Optional event envelope. Older clients receive the original report unchanged.
local K=KWC
local E={handlers={}};K.EventEvidence=E
local serial=0
local session=tostring(time())..'-'..tostring(math.floor((GetTime and GetTime() or 0)*1000))
local bridge={}
local function key(kind,sender,payload)
 local guid=K.Identity and K.Identity.RosterGUID(sender)
 local actor=guid or K.CurrentGuildMember(sender)
 return actor and (kind..'|'..actor..'|'..payload)
end
local function prune()
 local n=0;local oldest,stamp
 for id,record in pairs(bridge) do
  if time()-record.at>3 then bridge[id]=nil
  else
   n=n+1
   if not stamp or record.at<stamp then oldest,stamp=id,record.at end
  end
 end
 if n>=256 and oldest then bridge[oldest]=nil end
end
function E.On(kind,fn) E.handlers[kind]=fn end
function E.Send(kind,payload)
 local sent=K.Send(kind,payload)
 local guid=UnitGUID and UnitGUID('player')
 serial=serial+1
 local stamp=time()
 if type(guid)=='string' and guid:match('^Player%-%w+%-%w+$') then
  local envelope=table.concat({kind,guid,session,serial,stamp,payload},'|')
  if #envelope<230 then K.Net.Send('KWC3','2;EVENT1;'..envelope,'GUILD') end
 end
 return sent
end
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~='KWC3' or channel~='GUILD' or type(msg)~='string' or not K.IsMember(sender) then return end
 prune()
 local kind,guid,boot,seq,stamp,payload=msg:match('^2;EVENT1;([A-Z]+)|(Player%-%w+%-%w+)|([%d%-]+)|(%d+)|(%d+)|(.+)$')
 if kind then
  local handler=E.handlers[kind]
  if not handler or #msg>250 or not K.Identity or K.Identity.RosterGUID(sender)~=guid then return end
  stamp=tonumber(stamp)
  if not stamp or math.abs(time()-stamp)>30 then return end
  local id=guid..':'..boot..':'..seq
  if not K.Toast.Claim('wire:'..kind,id) then return end
  local k=key(kind,sender,payload);if not k then return end
  local rec=bridge[k]
  if rec and rec.legacy and not rec.pending then
   bridge[k]=nil
   return
  end
  bridge[k]={at=time(),modern=true}
  handler(prefix,'2;'..kind..';'..payload,channel,sender,id)
  return
 end
 kind,payload=msg:match('^2;([A-Z]+);(.+)$')
 local handler=E.handlers[kind]
 if not handler then return end
 local k=key(kind,sender,payload);if not k then return end
 local rec=bridge[k]
 if rec and rec.modern then bridge[k]=nil;return end
 if rec and rec.pending then return end
 local pending={at=time(),legacy=true,pending=true};bridge[k]=pending
 local function deliver()
  if bridge[k]~=pending then return end
  pending.pending=false
  handler(prefix,msg,channel,sender,nil)
 end
 if C_Timer and C_Timer.After then C_Timer.After(0.5,deliver) else deliver() end
end)
