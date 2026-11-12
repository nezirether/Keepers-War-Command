local K=KWC;local R={results={},selected=nil,pending=false,lastSearch=-100,queuePos=1};K.Recruiter=R
local function db()
 local d=KWCDB.recruiter;d.candidates=d.candidates or {};d.ignored=d.ignored or {};d.queue=d.queue or {'1-10','11-20','21-30','31-40','41-50','51-60'};d.searches=d.searches or 0;d.drafts=d.drafts or 0;d.inviteDrafts=d.inviteDrafts or 0;d.joins=d.joins or 0;return d
end
local function key(n) return tostring(n or ''):lower() end
function R.Search(q)
 q=K.Clean(q,70);if q=='' then K.Say('Enter a /who filter.');return end
 if R.pending and GetTime and GetTime()-R.lastSearch>25 then R.pending=false end
 if R.pending then K.Say('Previous /who is still pending.');return end
 if GetTime and GetTime()-R.lastSearch<8 then K.Say('Please wait 8 seconds between searches.');return end
 if not C_FriendList or not C_FriendList.SendWho then K.Say('WHO API unavailable.');return end
 if C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi,false) end
 local ok,err=pcall(C_FriendList.SendWho,q);if not ok then K.Say('WHO failed: '..tostring(err));return end
 R.pending=true;R.lastSearch=GetTime and GetTime() or 0;db().searches=db().searches+1;K.Say('Searching '..q)
end
function R.Next()
 local d=db();local q=d.queue[R.queuePos] or d.queue[1];if not q then return end
 local before=d.searches;R.Search(q);if d.searches>before then R.queuePos=R.queuePos%#d.queue+1 end
end
function R.Select(i) local c=R.results[tonumber(i) or 0];if c then R.selected=c.name;K.UI.Refresh() end end
function R.Candidate() return R.selected and db().candidates[key(R.selected)] end
function R.Whisper()
 local c=R.Candidate();if not c then K.Say('Select a candidate.');return end
 local pitch=KWCDB.settings.pitch
 if ChatFrame_OpenChat then ChatFrame_OpenChat('/w '..c.name..' '..pitch) end
 c.status='whisper prepared';c.lastContact=time();db().drafts=db().drafts+1;K.Log('RECRUIT','Whisper prepared for '..c.name..' (not sent automatically)');K.UI.Refresh()
end
function R.PrepareInvite()
 local c=R.Candidate();if not c then K.Say('Select a candidate.');return end
 if not IsInGuild() or (CanGuildInvite and not CanGuildInvite()) then K.Say('You lack guild invite permission.');return end
 if ChatFrame_OpenChat then ChatFrame_OpenChat('/ginvite '..c.name) end
 c.status='invite prepared';db().inviteDrafts=db().inviteDrafts+1;K.Log('RECRUIT','Invite command drafted for '..c.name..' (not confirmed)');K.UI.Refresh()
end
function R.Ignore()
 local c=R.Candidate();if not c then return end;db().ignored[key(c.name)]=true;c.status='ignored';R.selected=nil;K.UI.Refresh()
end
function R.ConfirmJoin(name)
 local d=db();local c=d.candidates[key(name)] or d.candidates[key(name):match('^[^-]+')]
 if c and c.status~='joined' then c.status='joined';c.joined=time();d.joins=d.joins+1;K.Log('RECRUIT','Guild roster confirms '..name) end
end
function R.Report()
 local d=db();local n=0;for _ in pairs(d.candidates) do n=n+1 end
 K.Say('Searches '..d.searches..' | candidates '..n..' | whisper drafts '..d.drafts..' | invite drafts '..d.inviteDrafts..' | roster joins '..d.joins)
end
K.On('WHO_LIST_UPDATE',function()
 if not R.pending then return end;R.pending=false;R.results={};R.selected=nil
 if not C_FriendList or not C_FriendList.GetWhoInfo or not C_FriendList.GetNumWhoResults then return end
 local d=db();local total=C_FriendList.GetNumWhoResults() or 0;total=math.max(0,math.min(tonumber(total) or 0,50))
 for i=1,math.min(total,50) do
  local info=C_FriendList.GetWhoInfo(i)
  if type(info)=='table' then
   local name=info.fullName or info.name;local guild=info.fullGuildName or info.guild
   if type(name)=='string' and name~='' and (not guild or guild=='') and not d.ignored[key(name)] then
    local c=d.candidates[key(name)] or {name=name,firstSeen=time(),status='discovered'}
    c.name=name;c.level=info.level;c.class=info.fullClassName or info.filename;c.zone=info.area;c.lastSeen=time();d.candidates[key(name)]=c
    table.insert(R.results,c)
   end
  end
 end
 K.Say('WHO results: '..total..' total, '..#R.results..' unguilded candidates.');K.UI.Refresh()
end)
