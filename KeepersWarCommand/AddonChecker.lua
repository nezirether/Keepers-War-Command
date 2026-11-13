-- Version reports are scoped to the live guild and keyed by verified roster identity.
local K=KWC
local A={peers={},lastRequest=0,lastAnnounce=0,requests=0,responses=0,protocol='KWCCHK/1'}
K.AddonChecker=A
local PREFIX='KWCCHK'
local scope
local function currentScope()
 local guild=K.GuildScope()
 if scope~=guild then scope=guild;A.peers={};A.lastRequest=0;A.lastAnnounce=0 end
 return guild
end
local function send(kind)
 if not currentScope() then return false end
 return K.Net.Send(PREFIX,kind..'|'..K.version,'GUILD')
end
function A.Request()
 if not currentScope() or not K.LocalGuildMember() then K.Say('Addon Checker needs a verified guild and character.');return false end
 local now=time()
 if now-A.lastRequest<15 then K.Say('Addon Checker: wait a few seconds before checking again.');return false end
 A.lastRequest=now
 local sent=send('Q')
 if sent then A.requests=A.requests+1 else K.Say('Addon check could not be queued.') end
 return sent
end
function A.Status()
 return A.lastRequest>0 and 'Check requested; replies appear below as clients respond.' or 'Select Check Online Guildmates to discover clients.'
end
function A.Self()
 return (K.LocalGuildMember() and (GetUnitName and GetUnitName('player',true) or UnitName('player'))) or UnitName('player') or 'You',K.version
end
function A.ForRoster(name)
 local id=K.CurrentGuildMember(name)
 if not id then return end
 if id==K.LocalGuildMember() then return {localClient=true,version=K.version,lastSeen=time(),name=name} end
 if not currentScope() then return end
 local peer=A.peers[id]
 if peer and time()-peer.lastSeen<600 then return peer end
end
function A.Entries()
 local result={}
 if not currentScope() then return result end
 for id,peer in pairs(A.peers) do
  if K.CurrentGuildMember(id)==id and time()-peer.lastSeen<600 then result[#result+1]=peer end
 end
 table.sort(result,function(a,b)
  if a.lastSeen==b.lastSeen then return a.name<b.name end
  return a.lastSeen>b.lastSeen
 end)
 return result
end
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if channel~='GUILD' or type(msg)~='string' or #msg>250 then return end
 if prefix~=PREFIX and prefix~='KWC3' and prefix~='KWC4' then return end
 local guild=currentScope()
 local id=guild and K.CurrentGuildMember(sender)
 if not id or id==K.LocalGuildMember() then return end
 if prefix==PREFIX then
  local kind,version=msg:match('^([QR])|([%w%.%-_]+)$')
  if not kind or #version>30 then
   -- Only an explicit, recognizable version envelope indicates incompatibility.
   local wire=msg:match('^V(%d+)|[QR]|[%w%.%-_]+$')
   if not wire or wire=='1' then return end
   A.peers[id]={name=sender,unsupported=true,lastSeen=time()}
  else
   A.peers[id]={name=sender,version=version,lastSeen=time()}
   if kind=='R' then A.responses=A.responses+1 end
   if kind=='Q' and time()-A.lastAnnounce>=5 then
    A.lastAnnounce=time()
    if C_Timer and C_Timer.After then C_Timer.After(0.5,function()
     if guild==currentScope() and K.LocalGuildMember() then send('R') end
    end)
    else send('R') end
   end
  end
 else
  local wire=prefix=='KWC3' and msg:match('^(%d+);[A-Z0-9]+;')
  if wire and wire~='2' then
   local previous=A.peers[id]
   if not previous or time()-previous.lastSeen>=600 or previous.legacy then
    A.peers[id]={name=sender,unsupported=true,lastSeen=time()}
    if K.UI and K.UI.CheckerRefresh then K.UI.CheckerRefresh() end
   end
   return
  end
  if not (wire=='2' or
   prefix=='KWC4' and (msg:match('^Q|%d+$') or msg:match('^S|[CB]|'))) then return end
  local old=A.peers[id]
  if old and time()-old.lastSeen<600 then return end
  A.peers[id]={name=sender,legacy=true,lastSeen=time()}
 end
 if K.UI and K.UI.CheckerRefresh then K.UI.CheckerRefresh() end
end)
K.On('ADDON_LOADED',function(addon)
 if addon=='KeepersWarCommand' and C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  pcall(C_ChatInfo.RegisterAddonMessagePrefix,PREFIX)
 end
end)
K.On('PLAYER_GUILD_UPDATE',currentScope)
