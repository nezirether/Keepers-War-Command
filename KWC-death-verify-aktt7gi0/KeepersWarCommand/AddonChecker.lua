-- Guild addon presence discovery. Presence is observational, not proof of installation.
local K=KWC
local A={peers={},lastRequest=0,lastAnnounce=0}
K.AddonChecker=A
local PREFIX='KWCCHK'
local function short(name)
 return tostring(name or ''):match('^[^-]+'):lower()
end
local function send(kind)
 if not IsInGuild() or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
 local msg=kind..'|'..tostring(K.version or 'unknown')
 return K.Net.Send(PREFIX,msg,'GUILD')
end
function A.Request()
 if not IsInGuild() then K.Say('Addon Checker requires a guild.');return false end
 local now=time()
 if now-A.lastRequest<15 then K.Say('Addon Checker: wait a few seconds before checking again.');return false end
 A.lastRequest=now
 local sent=send('Q')
 if not sent then K.Say('Addon check could not be sent.') end
 return sent
end
function A.Status()
 return A.lastRequest>0 and 'Check requested; replies appear below as clients respond.' or 'Select Check Online Guildmates to discover clients.'
end
local isSelf
isSelf=function(sender)
 local me=UnitName and UnitName('player') or ''
 local full=GetUnitName and GetUnitName('player',true) or me
 local a=short(sender)
 local b=short(full)
 local c=short(me)
 if a==b or a==c then return true end
 -- Forever may return the first name from UnitName and the full name in guild traffic.
 if c~='' and a:match('^([^ ]+)')==c:match('^([^ ]+)') then return true end
 return false
end
function A.Entries()
 local result={}
 for _,v in pairs(A.peers) do if not isSelf(v.name) then result[#result+1]=v end end
 table.sort(result,function(a,b)return (a.lastSeen or 0)>(b.lastSeen or 0) end)
 return result
end
-- Status is evidence of a reply, not a proof of installation.
-- Use full two-part names when available; only accept a short-name alias
-- when it identifies exactly one roster member.
function A.ForRoster(name)
 if type(name)~='string' then return nil end
 local roster=KWCDB and KWCDB.roster or {}
 local query=(name:match('^[^-]+') or name):lower()
 local match=nil
 for _,peer in pairs(A.peers) do
  local pn=(peer.name:match('^[^-]+') or peer.name):lower()
  if pn==query then
   if not match or (peer.lastSeen or 0)>(match.lastSeen or 0) then match=peer end
  end
 end
 if match then return match end
 if not query:find(' ',1,true) then return nil end
 local first=query:match('^(%S+) ')
 local count=0
 for _,r in pairs(roster) do
  if type(r)=='table' and type(r.name)=='string' and (r.name:match('^[^-]+') or r.name):lower():match('^'..first..' ') then count=count+1 end
 end
 if count~=1 then return nil end
 for _,peer in pairs(A.peers) do
  local pn=(peer.name:match('^[^-]+') or peer.name):lower()
  if pn==first then return peer end
 end
 return nil
end
function A.Self()
 return (GetUnitName and GetUnitName('player',true)) or UnitName('player') or 'You',K.version
end
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~=PREFIX or channel~='GUILD' or type(msg)~='string' or type(sender)~='string' then return end
 local kind,ver=msg:match('^([QR])|([%w%.%-_]+)$')
 if not kind or not ver or #ver>30 then return end
 if isSelf(sender) then return end
 local key=sender:lower()
 A.peers[key]={name=sender,version=ver,lastSeen=time(),legacy=false}
 if kind=='Q' then
  local now=time()
  if now-A.lastAnnounce>=5 then
   A.lastAnnounce=now
   if C_Timer and C_Timer.After then C_Timer.After(0.5,function()send('R') end) else send('R') end
  end
 end
 if K.UI and K.UI.CheckerRefresh then K.UI.CheckerRefresh() end
end)
-- Older War Command releases do not speak KWCCHK. Their normal guild
-- sync traffic is still evidence of a running client, but NOT its version.
-- Only accept our own legacy protocol prefixes, never generic addon traffic.
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if (prefix~='KWC3' and prefix~='KWC4') or channel~='GUILD' or type(sender)~='string' or type(msg)~='string' then return end
 if #msg>250 or not IsInGuild() then return end
 if isSelf(sender) then return end
 -- A minimal format check avoids treating unrelated/malformed traffic as evidence.
 if prefix=='KWC3' and not msg:match('^2;[A-Z]+;') then return end
 if prefix=='KWC4' and not (msg:match('^Q|%d+') or msg:match('^S|[CB]|')) then return end
 local key=sender:lower()
 local previous=A.peers[key]
 if previous and not previous.legacy then return end -- modern reply takes priority
 A.peers[key]={name=sender,version='Unknown (legacy)',lastSeen=time(),legacy=true}
 if K.UI and K.UI.CheckerRefresh then K.UI.CheckerRefresh() end
end)
K.On('PLAYER_ENTERING_WORLD',function()
 if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix,PREFIX) end
 if C_Timer and C_Timer.After then C_Timer.After(12,function() if IsInGuild() then send('R') end end) end
end)
