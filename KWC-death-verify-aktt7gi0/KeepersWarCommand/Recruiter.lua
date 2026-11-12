local K=KWC;local R={results={},selected=nil,pending=false,lastSearch=-100,queuePos=1};K.Recruiter=R
local function db()
 local d=KWCDB.recruiter;d.candidates=d.candidates or {};d.ignored=d.ignored or {};d.queue=d.queue or {'1-10','11-20','21-30','31-40','41-50','51-60'};d.searches=d.searches or 0;d.drafts=d.drafts or 0;d.inviteDrafts=d.inviteDrafts or 0;d.joins=d.joins or 0;return d
end
local function key(n)
 local id=tostring(n or ''):lower()
 local realm=GetNormalizedRealmName and GetNormalizedRealmName()
 if realm and realm~='' and id:sub(-#realm-1)=='-'..realm:lower() then
  return id:sub(1,-#realm-2)
 end
 return id
end
local function savedCandidate(d,name)
 local id=key(name)
 if d.candidates[id] or d.ignored[id] then return d.candidates[id],d.ignored[id] end
 local raw=tostring(name or ''):lower()
 local candidate=d.candidates[raw]
 local ignored=d.ignored[raw]
 if id==raw then
  local realm=GetNormalizedRealmName and GetNormalizedRealmName()
  if realm and realm~='' and not id:find('-',1,true) then
   local qualified=id..'-'..realm:lower()
   candidate,ignored=d.candidates[qualified],d.ignored[qualified]
  end
 end
 return candidate,ignored
end
local function refresh()
 if K.UI and K.UI.RecruitmentRefresh then K.UI.RecruitmentRefresh() end
end

function R.Restore()
 if R.loaded then return end
 R.loaded=true
 local d=db()
 R.received=d.lastResultKeys~=nil
 for _,id in ipairs(d.lastResultKeys or {}) do
  local candidate=d.candidates[id]
  if candidate and not d.ignored[id] and candidate.status~='joined' then
   R.results[#R.results+1]=candidate
  end
 end
 R.selected=d.selectedCandidate
 if not R.Candidate() then R.selected=nil end
end

function R.Search(q)
 R.Restore()
 q=K.Clean(q,70):match('^%s*(.-)%s*$')
 if q=='' then K.Say('Enter a /who filter.');return false end
 local now=GetTime()
 if not R.SearchReady() then return false end
 local d=db()
 if not C_FriendList or not C_FriendList.SendWho or not C_FriendList.GetNumWhoResults or
    not C_FriendList.GetWhoInfo then K.Say('WHO API unavailable.');return false end
 local request={query=q}
 local first,last=q:match('^(%d+)%s*%-%s*(%d+)$')
 request.minLevel,request.maxLevel=tonumber(first),tonumber(last)
 if request.minLevel and request.minLevel>request.maxLevel then
  K.Say('Enter the lower level first.');return false
 end
 if C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi,false) end
 R.pending=request
 local ok,err=pcall(C_FriendList.SendWho,q)
 if not ok then R.pending=nil;K.Say('WHO failed: '..tostring(err));return false end
 R.lastSearch=now
 d.lastWhoAt=now
 d.lastQuery=q
 d.searches=d.searches+1
 R.error=nil
 if C_Timer and C_Timer.After then
  C_Timer.After(25,function()
   if R.pending~=request then return end
   R.pending=nil
   R.error='WHO did not return results. Try again.'
   refresh()
  end)
  C_Timer.After(8,refresh)
 end
 refresh()
 return true
end
function R.Next()
 local d=db()
 local q=d.queue[R.queuePos] or d.queue[1]
 if not q or not R.Search(q) then return false end
 R.queuePos=R.queuePos%#d.queue+1
 return true
end
function R.Select(i)
 local c=R.results[tonumber(i) or 0]
 if c then
  R.selected=c.name
  db().selectedCandidate=c.name
  refresh()
 end
end
function R.Candidate()
 local d=db()
 local c,ignored=savedCandidate(d,R.selected)
 if c and not ignored and c.status~='joined' then return c end
end
function R.SearchReady()
 local now=GetTime()
 local last=db().lastWhoAt
 return not R.pending and now-R.lastSearch>=8 and (not last or now<last or now-last>=8)
end
function R.Whisper()
 local c=R.Candidate();if not c then K.Say('Select a candidate.');return end
 local pitch=KWCDB.settings.pitch
 if ChatFrame_OpenChat then ChatFrame_OpenChat('/w '..c.name..' '..pitch) end
 c.status='whisper prepared';c.lastContact=time();db().drafts=db().drafts+1;K.Log('RECRUIT','Whisper prepared for '..c.name..' (not sent automatically)');refresh()
end
function R.PrepareInvite()
 local c=R.Candidate();if not c then K.Say('Select a candidate.');return end
 if not IsInGuild() or (CanGuildInvite and not CanGuildInvite()) then K.Say('You lack guild invite permission.');return end
 if ChatFrame_OpenChat then ChatFrame_OpenChat('/ginvite '..c.name) end
 c.status='invite prepared';db().inviteDrafts=db().inviteDrafts+1;K.Log('RECRUIT','Invite command drafted for '..c.name..' (not confirmed)');refresh()
end
function R.Ignore()
 local c=R.Candidate()
 if not c then return end
 local d=db()
 local id=key(c.name)
 d.ignored[id]=true
 c.status='ignored'
 R.selected=nil
 d.selectedCandidate=nil
 for i=#R.results,1,-1 do if R.results[i]==c then table.remove(R.results,i) end end
 refresh()
end
function R.ConfirmJoin(name)
 local d=db();local c=savedCandidate(d,name)
 if c and c.status~='joined' then
  c.status='joined';c.joined=time();d.joins=d.joins+1
  K.Log('RECRUIT','Guild roster confirms '..name)
  for i=#R.results,1,-1 do if R.results[i]==c then table.remove(R.results,i) end end
  if R.selected==c.name then R.selected=nil;d.selectedCandidate=nil end
  refresh()
 end
end
function R.Report()
 local d=db();local n=0;for _ in pairs(d.candidates) do n=n+1 end
 K.Say('Searches '..d.searches..' | candidates '..n..' | whisper drafts '..d.drafts..' | invite drafts '..d.inviteDrafts..' | roster joins '..d.joins)
end
K.On('WHO_LIST_UPDATE',function()
 local request=R.pending
 if not request then return end
 local d=db()
 local count,total=C_FriendList.GetNumWhoResults()
 count=math.max(0,math.min(tonumber(count) or 0,50))
 local rows,matchingLevels={},0
 for i=1,count do
  local info=C_FriendList.GetWhoInfo(i)
  if type(info)=='table' then
   local level=tonumber(info.level)
   if not request.minLevel or (level and level>=request.minLevel and level<=request.maxLevel) then
    matchingLevels=matchingLevels+1
    rows[#rows+1]=info
   end
  end
 end
 -- WHO_LIST_UPDATE has no query ID. Reject clearly unrelated level-range results.
 if count>0 and matchingLevels==0 then return end
 R.pending=nil
 local results,ids,seen={},{},{}
 for _,info in ipairs(rows) do
  local name=info.fullName
  local guild=info.fullGuildName
  if type(name)=='string' and name~='' and (guild==nil or (type(guild)=='string' and not guild:find('%S'))) then
   local id=key(name)
   local c,ignored=savedCandidate(d,name)
   if not seen[id] and not ignored and (not c or c.status~='joined') then
    seen[id]=true
    c=c or {name=name,firstSeen=time(),status='discovered'}
    c.name=name
    c.level=info.level
    c.class=(info.classStr and info.classStr~='' and info.classStr) or info.filename
    c.zone=info.area
    c.lastSeen=time()
    d.candidates[id]=c
    results[#results+1]=c
    ids[#ids+1]=id
   end
  end
 end
 R.results=results
 R.received=true
 d.lastResultKeys=ids
 local selected=savedCandidate(d,R.selected)
 R.selected=seen[key(R.selected)] and selected and selected.name or nil
 d.selectedCandidate=R.selected
 if KWCDB.settings.recruitmentDebug then
  K.Say(('WHO results: %d returned, %d total, %d eligible'):format(count,tonumber(total) or count,#results))
 end
 refresh()
end)
