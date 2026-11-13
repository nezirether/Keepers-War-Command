local K=KWC
local S={}
K.GuildServices=S

-- The character directory lives inside the same partition as guild boards.
function S.Context()
 local state,guild,actor=K.GuildReadiness()
 if state~='Ready' then return end
 local db=KWCDB.guildServices
 if not db then db={schema=1,characters={}};KWCDB.guildServices=db end
 if db.schema~=1 or type(db.characters)~='table' then return end
 return db,guild,actor
end

function S.Roster()
 local _,guild=S.Context()
 if not guild then return {} end
 local rows={}
 for i=1,GetNumGuildMembers() or 0 do
  local name,rank,_,level,class,_,_,_,online=GetGuildRosterInfo(i)
  if type(name)=='string' then
   rows[#rows+1]={name=name,rank=rank,level=level,class=class,online=online}
  end
 end
 table.sort(rows,function(a,b) return a.name:lower()<b.name:lower() end)
 return rows,S.rosterGuild==guild and S.rosterAt or nil
end
K.On('GUILD_ROSTER_UPDATE',function()
 S.rosterGuild,S.rosterAt=K.GuildScope(),time()
end)
K.On('PLAYER_GUILD_UPDATE',function() S.rosterGuild,S.rosterAt=nil,nil end)
