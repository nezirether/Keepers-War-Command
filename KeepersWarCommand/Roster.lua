local K=KWC;K.Roster={}
function K.Roster.Scan()
 if not IsInGuild() or not KWCDB or not GetGuildRosterInfo then return end
 local count=GetNumGuildMembers and GetNumGuildMembers() or 0;if count==0 then return end
 for i=1,count do
  local name,rank,rankIndex,level,class,zone,note,officerNote,online=GetGuildRosterInfo(i)
  if type(name)=='string' and name~='' then
   local id=name:lower();local r=KWCDB.roster[id] or {firstSeen=time()}
   r.scannedAt=time();r.name=name;r.rank=rank;r.rankIndex=rankIndex;r.level=level;r.class=class;r.zone=zone;r.online=online and true or false;r.offlineScans=online and 0 or ((r.offlineScans or 0)+1)
   if online then r.lastSeen=time() end;KWCDB.roster[id]=r
   if K.Recruiter then K.Recruiter.ConfirmJoin(name) end
  end
 end
 -- Require two consecutive offline roster scans before initiating succession.
 if K.Operations and K.Operations.TrySuccession then K.Operations.TrySuccession() end
 if K.UI then K.UI.Refresh() end
end
K.On('GUILD_ROSTER_UPDATE',K.Roster.Scan)
K.On('PLAYER_GUILD_UPDATE',function()if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end end)

K.On('PLAYER_ENTERING_WORLD',function() if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end end)
