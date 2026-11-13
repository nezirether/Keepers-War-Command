-- DEV23: opt-in CTA group requests. No protected action is bypassed.
local K=KWC
local J={pending={},lastRequest=0};K.CTAJoin=J
local function short(n) return tostring(n or ''):lower():match('^[^-]+') end
local function full(n)
 local r=K.RosterRecord(n);return r and r.name or tostring(n or '')
end
local function same(a,b) return short(a)==short(b) end
local function findCTA(id)
 for _,e in ipairs(KWCDB and KWCDB.ops or {}) do if e.id==id then return e end end
end
local function isLeader(e)
 local me=UnitName('player') or ''
 if same(me,e.author) then return true end
 local response=(KWCDB.responses or {})[e.id] or {}
 for name,status in pairs(response) do
  if status=='Coming' and same(name,me) then
   local r=K.RosterRecord(me)
   return r and type(r.rankIndex)=='number' and r.rankIndex<=1
  end
 end
 return false
end
function J.Request(id)
 local e=findCTA(id)
 if not e or e.status~='ACTIVE' then K.Say('This CTA is not active.');return end
 if time()-J.lastRequest<15 then K.Say('Please wait before requesting again.');return end
 J.lastRequest=time()
 -- A request is not a confirmed group invitation.
 if K.Send('JOINREQ',id..':'..(UnitName('player') or '')) then
  K.Say('Join the Fight request broadcast to CTA leadership.')
 else K.Say('Could not broadcast the group request.') end
end
local function tryInvite(name)
 if InCombatLockdown and InCombatLockdown() then return false,'combat' end
 if IsInGroup and IsInGroup() and not (UnitIsGroupLeader and UnitIsGroupLeader('player')) and not (UnitIsGroupAssistant and UnitIsGroupAssistant('player')) then return false,'not group leader' end
 local fn=(C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
 if type(fn)~='function' then return false,'invite API unavailable' end
 local ok,result=pcall(fn,name)
 if not ok or result==false then return false,'game declined invite' end
 return true
end
function J.Invite(id,name)
 local e=findCTA(id)
 if not e or not isLeader(e) or not J.pending[id] or not J.pending[id][name] then return end
 local ok,reason=tryInvite(name)
 if ok then J.pending[id][name]=nil;K.Say('Invite attempted for '..name..'.')
 else K.Say('Cannot invite automatically ('..reason..'). Invite '..name..' manually when safe.') end
 if K.UI then K.UI.Refresh() end
end
function J.Pending(id)
 local result={}
 for name in pairs(J.pending[id] or {}) do result[#result+1]=name end
 table.sort(result);return result
end
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~='KWC3' or channel~='GUILD' or type(msg)~='string' or not msg:match('^2;JOINREQ;') then return end
 if not K.IsMember(sender) then return end
 local id,claimed=msg:match('^2;JOINREQ;([^:]+):(.+)$')
 local e=id and findCTA(id)
 if not e or e.status~='ACTIVE' or not isLeader(e) or not same(sender,claimed) then return end
 local name=full(sender)
 J.pending[id]=J.pending[id] or {}
 if J.pending[id][name] then return end
 J.pending[id][name]=time()
 K.Say(name..' requested to join CTA. Open CTA Details to invite.')
 -- Attempt only when the game permits; retain a clickable fallback otherwise.
 J.Invite(id,name)
end)
