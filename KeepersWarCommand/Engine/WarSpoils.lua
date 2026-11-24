-- WS1 append-only guild ledger. The verified rank-0 character is the single writer.
local K=KWC
local W={}
K.WarSpoils=W
local PREFIX,MAX='KWCWS1',20000
local cache,requestAt,replyAt=nil,0,{}
local function integer(n,min,max)
 return type(n)=='number' and n%1==0 and n>=min and n<=max
end
local function guid(v)
 return K.Identity.ValidGUID(v) and #v<=36
end
local function safeText(v,max)
 return type(v)=='string' and #v<=max and v:find('%S') and not v:find('[%c|]')
end
local function hash(previous,text)
 for i=1,#text do previous=(previous*131+text:byte(i))%2147483647 end
 return previous
end
local function authority(sender)
 local member,rank=K.CurrentGuildMember(sender)
 return member and rank==0 and (K.Identity.RosterGUID(sender) or K.Identity.RosterGUID(member))
end
local function verifiedGUID(name)
 local member=K.CurrentGuildMember(name)
 if member then return K.Identity.RosterGUID(name) or K.Identity.RosterGUID(member) end
end

local function decode(line)
 local seq,prev,at,actor,kind,subject,ref,note=line:match(
  '^(%d+)|(%d+)|(%d+)|([^|]+)|([A-Z])|([^|]*)|([^|]*)|([^|]*)$')
 seq,prev,at=tonumber(seq),tonumber(prev),tonumber(at)
 if not integer(seq,1,MAX) or not integer(prev,0,2147483646) or not integer(at,1,4102444800)
  or not guid(actor) or #line>215 then return end
 return {seq=seq,prev=prev,at=at,actor=actor,kind=kind,subject=subject,ref=ref,note=note}
end
local function apply(state,event)
 local kind,target,ref,note=event.kind,event.subject,event.ref,event.note
 if event.seq~=state.count+1 or event.prev~=state.hash then return nil,'Ledger sequence mismatch.' end
 local session=state.session
 if kind=='S' then
  if session or not safeText(note,55) or target~='' or ref~='' then return nil,'Close the open raid first and enter a raid name.' end
  state.session={id=event.seq,name=note,attended={},bosses={},awards={}}
 elseif kind=='E' then
  if not session or ref~=tostring(session.id) or target~='' or note~='' then return nil,'No matching open raid.' end
  state.session=nil
 elseif kind=='R' then
  if not guid(target) or state.raiders[target] or not safeText(note,42) or ref~='' then return nil,'A verified, unregistered guild character is required.' end
  state.raiders[target]={name=note,points=5,raids=0,bosses=0,wins=0}
  event.delta=5
 else
  local r=state.raiders[target]
  if not r then return nil,'Register that character first.' end
  if kind=='C' then
   local amount=tonumber(ref)
   if not integer(amount,-10,10) or amount==0 or not safeText(note,55)
     or not integer(r.points+amount,0,10) then return nil,'Enter a nonzero correction within 0–10 and a reason.' end
   event.delta=amount
  elseif not session then return nil,'Open a raid first.'
  elseif kind=='A' then
   if ref~=tostring(session.id) or session.attended[target] or note~='' then return nil,'Attendance already recorded or raid changed.' end
   session.attended[target]=true;r.raids=r.raids+1
   event.delta=math.min(1,10-r.points)
  elseif kind=='B' then
   if not session.attended[target] or not safeText(ref,32) or note~='' then return nil,'Eligible attendance and a boss occurrence ID are required.' end
   local key=ref:lower()..'|'..target
   if session.bosses[key] then return nil,'This boss occurrence was already credited for this character.' end
   session.bosses[key]=true;r.bosses=r.bosses+1
   event.delta=math.min(1,10-r.points)
  elseif kind=='L' then
   local rival,item=ref:match('^([^/]+)/(.+)$')
   local other=state.raiders[rival or '']
   if not session.attended[target] or r.points<3 or not other or other==r or other.points<3
    or not session.attended[rival] or not safeText(item,24) or not safeText(note,42)
    or session.awards[item:lower()] then return nil,'Require a unique drop ID and two distinct funded attendees.' end
   session.awards[item:lower()]=true;r.wins=r.wins+1
   event.delta=-3
  else return nil,'Unknown WarSpoils event.' end
  r.points=r.points+event.delta
 end
 event.raid=session and session.id or (kind=='S' and event.seq or nil)
 state.count=event.seq
 return true
end

local function load()
 if K.GuildReadiness()~='Ready' then return end
 local guild=K.GuildScope()
 KWCDB.warSpoils=KWCDB.warSpoils or {version=1,lines={}}
 local db=KWCDB.warSpoils
 if type(db)~='table' or db.version~=1 or type(db.lines)~='table' then
  return nil,'Unsupported or unreadable ledger data. Existing SavedVariables were preserved.'
 end
 if cache and cache.db==db and cache.guild==guild then return cache end
 local state={db=db,guild=guild,count=0,hash=0,raiders={},events={}}
 for i,line in ipairs(db.lines) do
  local e=type(line)=='string' and decode(line)
  if not e or e.seq~=i or not apply(state,e) then db.conflict=true;break end
  state.hash=hash(state.hash,line);state.events[i]=e
 end
 -- ipairs stops at the first hole. Refuse to extend a partial history.
 for index in pairs(db.lines) do
  if not integer(index,1,state.count) then db.conflict=true;break end
 end
 cache=state
 return state
end
function W.View() return load() end
function W.CanWrite()
 local state=load()
 local id=authority(K.LocalGuildMember())
 local unit=UnitGUID and UnitGUID('player')
 return state and not state.db.conflict and id and guid(unit) and id==unit
end

local function append(state,line,event)
 local ok,err=apply(state,event)
 if not ok then return nil,err end
 state.db.lines[event.seq]=line
 state.hash=hash(state.hash,line);state.events[event.seq]=event
 if K.UI and K.UI.Refresh then K.UI.Refresh() end
 return true
end

function W.Record(kind,character,ref,note,rival)
 local state=load()
 if not state or not W.CanWrite() then return nil,'Verified Warchief authority and a healthy ledger are required.' end
 if state.count>=MAX then return nil,'Ledger capacity reached.' end
 local subject=''
 if kind~='S' and kind~='E' then
  subject=verifiedGUID(character)
  if not subject then return nil,'Character has no verified guild GUID.' end
 end
 if kind=='R' then note=K.Identity.RosterName(subject) or character end
 if kind=='A' or kind=='E' then ref=state.session and tostring(state.session.id) end
 if kind=='L' then
  local other=verifiedGUID(rival)
  if not other then return nil,'Competing claimant has no verified guild GUID.' end
  ref=other..'/'..(ref or '')
 end
 local line=table.concat({state.count+1,state.hash,time(),UnitGUID('player'),kind,subject,ref or '',note or ''},'|')
 local event=decode(line)
 if not event then return nil,'Invalid ledger fields or record too long.' end
 local ok,err=append(state,line,event)
 if not ok then return nil,err end
 local queued=K.Net.Send(PREFIX,state.guild..'|D|'..line,'GUILD')
 return true,queued and 'Recorded and queued for guild sync.' or 'Recorded locally. Guild sync will retry on request.'
end

local function recover()
 local state=load()
 if not state or state.db.conflict or W.CanWrite() or time()-requestAt<15 then return end
 if K.Net.Send(PREFIX,state.guild..'|Q|'..state.count,'GUILD') then
  requestAt=time()
  return true
 end
end
W.Request=recover

K.On('CHAT_MSG_ADDON',function(prefix,message,channel,sender)
 if prefix~=PREFIX or type(message)~='string' or (issecretvalue and issecretvalue(message)) or #message>250 then return end
 local state=load()
 if not state or state.db.conflict then return end
 local guild,kind,body=message:match('^(%d+)|([QD])|(.+)$')
 if guild~=state.guild then return end
 if kind=='Q' and channel=='GUILD' and W.CanWrite() then
  local member=K.CurrentGuildMember(sender)
  local count=body:match('^%d+$') and tonumber(body)
  if not member or not integer(count,0,state.count) then return end
  local now=time()
  if now-(replyAt[member] or 0)<15 then return end
  for i=count+1,math.min(count+8,state.count) do
   if not K.Net.Send(PREFIX,guild..'|D|'..state.db.lines[i],'WHISPER',sender,'RECOVERY') then break end
   replyAt[member]=now
  end
 elseif kind=='D' and (channel=='GUILD' or channel=='WHISPER') and authority(sender) then
  local event=decode(body)
  if not event or event.at>time()+300 then return end
  if channel=='GUILD' and event.actor~=authority(sender) then return end
  if event.seq<=state.count then
   if state.db.lines[event.seq]~=body then state.db.conflict=true end
  elseif event.seq==state.count+1 then
   if not append(state,body,event) then state.db.conflict=true end
  else recover() end
 end
end)
K.On('ADDON_LOADED',function(addon)
 if addon=='KeepersWarCommand' and C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
 end
end)
K.On('PLAYER_LOGIN',function()
 if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(30,recover) end
end)
K.On('PLAYER_GUILD_UPDATE',function() cache=nil;requestAt=0;replyAt={} end)
