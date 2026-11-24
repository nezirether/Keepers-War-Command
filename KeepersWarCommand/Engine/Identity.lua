-- KWC 2.0 character identity: stable GUID-based identity with verified rename
-- handling. Character names change; Player GUIDs do not.
--
-- Evidence levels (strongest first):
--  1. Live roster: the same Player GUID is listed under a new name in this
--     client's guild roster, and this client previously recorded that GUID
--     under the old name. -> verified rename, migrate automatically.
--  2. Peer identity (KWID1 'I'): a guildmate announces its own GUID. The
--     announcement is accepted only when this client's live roster lists the
--     sender's name with that same GUID; then rule 1 applies to any older name
--     this client recorded for the GUID.
--  3. Self-claimed previous name (KWID1 'I' alias list): never merged on its
--     own. Kept as a pending claim for an officer to approve.
--  4. Officer link (KWID1 'L'): War Council/Warchief, verified by live roster
--     rank on receipt, links an old record name to a current member's GUID.
--     Used for renames that happened before 2.0 recorded any GUIDs.
-- Records are never merged because two names merely look alike.
local K=KWC
local I={migrators={}};K.Identity=I
local PREFIX='KWID1'
I.PREFIX=PREFIX
local MAX_ALIASES,MAX_LOG,MAX_CLAIMS=12,60,40

local function secret(v) return issecretvalue and issecretvalue(v) end
local function validGUID(g) return type(g)=='string' and not secret(g) and g:match('^Player%-%w+%-%w+$')~=nil end
I.ValidGUID=validGUID
local function lower(s) return type(s)=='string' and s:lower() or nil end
-- Comparable form of a character name: lower case, realm removed, spaces trimmed.
local function bare(s)
 if type(s)~='string' or secret(s) then return nil end
 s=(s:match('^[^-]+') or s):lower():match('^%s*(.-)%s*$')
 return s~='' and s or nil
end
I.Bare=bare

local function book(create)
 if not KWCDB then return end
 local guild=K.GuildScope and K.GuildScope()
 if not guild then return end
 local root=KWCDB.identity
 if type(root)~='table' or (root.version~=nil and root.version~=1) then
  if root~=nil and type(root)=='table' then return end -- unknown future schema: never overwrite
  if not create then return end
  root={version=1,guilds={}};KWCDB.identity=root
 end
 root.version=1;root.guilds=root.guilds or {}
 local g=root.guilds[guild]
 if not g and create then g={byGUID={},log={},claims={}};root.guilds[guild]=g end
 if g then g.byGUID=g.byGUID or {};g.log=g.log or {};g.claims=g.claims or {} end
 return g,guild
end
I.Book=book

-- Live roster index: GUID -> roster name and lower name -> GUID.
local rosterByGUID,rosterByName,rosterAt={},{},0
local function readRoster()
 if not IsInGuild or not IsInGuild() or not GetNumGuildMembers or not GetGuildRosterInfo then return false end
 local ok,n=pcall(GetNumGuildMembers)
 if not ok or type(n)~='number' or secret(n) or n<=0 then return false end
 local byG,byN={},{}
 for i=1,math.min(n,2000) do
  local info={pcall(GetGuildRosterInfo,i)}
  if info[1] then
   local name,guid=info[2],info[18]
   if type(name)=='string' and not secret(name) and validGUID(guid) then
    byG[guid]=name;byN[name:lower()]=guid
   end
  end
 end
 rosterByGUID,rosterByName,rosterAt=byG,byN,time()
 return true
end
function I.RosterGUID(name)
 if type(name)~='string' or secret(name) then return nil end
 local id=K.CurrentGuildMember and K.CurrentGuildMember(name)
 return id and rosterByName[id] or rosterByName[name:lower()]
end
function I.RosterName(guid) return rosterByGUID[guid] end

function I.RegisterMigrator(label,fn) I.migrators[#I.migrators+1]={label=label,fn=fn} end

local function log(g,entry)
 table.insert(g.log,1,entry)
 while #g.log>MAX_LOG do table.remove(g.log) end
end

-- Moves history from oldName to newName for one verified GUID.
-- Migrators receive (old, new, guid, ctx) where ctx.skip(key) tells them whether
-- a stored key must be left alone because it belongs to a current member.
local function migrate(g,guid,oldName,newName,evidence,actor)
 local ctx={moved={}}
 -- A stored key that still resolves to a current roster member is someone
 -- else's live identity and is never touched.
 function ctx.skip(key)
  if type(key)~='string' then return true end
  local live=K.CurrentGuildMember and K.CurrentGuildMember(key)
  return live~=nil and live~=lower(newName)
 end
 function ctx.matches(key) return bare(key)~=nil and bare(key)==bare(oldName) end
 for _,m in ipairs(I.migrators) do
  local ok,count=pcall(m.fn,oldName,newName,guid,ctx)
  if ok and type(count)=='number' and count>0 then ctx.moved[#ctx.moved+1]=m.label..' '..count
  elseif not ok then ctx.moved[#ctx.moved+1]=m.label..' error' ;if K.Log then K.Log('IDENTITY',m.label..': '..tostring(count)) end end
 end
 log(g,{at=time(),guid=guid,from=oldName,to=newName,evidence=evidence,actor=actor,moved=table.concat(ctx.moved,', ')})
 if K.Log then K.Log('IDENTITY','Rename '..tostring(oldName)..' -> '..tostring(newName)..' ('..evidence..')') end
 return ctx.moved
end

-- Records (guid, current name). Returns true when a verified rename was applied.
local function observe(g,guid,name,evidence)
 if not validGUID(guid) or type(name)~='string' or secret(name) then return false end
 local rec=g.byGUID[guid]
 local now=time()
 if not rec then
  g.byGUID[guid]={name=name,first=now,seen=now,aliases={}}
  return false
 end
 rec.seen=now;rec.aliases=rec.aliases or {}
 if lower(rec.name)==lower(name) then rec.name=name;return false end
 local old=rec.name
 rec.aliases[old]=now
 local n=0;for _ in pairs(rec.aliases) do n=n+1 end
 if n>MAX_ALIASES then
  local oldest,at=nil,math.huge
  for a,t in pairs(rec.aliases) do if t<at then oldest,at=a,t end end
  rec.aliases[oldest]=nil
 end
 rec.name=name;rec.renamed=now
 migrate(g,guid,old,name,evidence)
 I.renames=(I.renames or 0)+1
 return true
end
I._observe=observe

function I.Scan()
 local state=K.GuildReadiness and K.GuildReadiness()
 if state~='Ready' then return 0 end
 if not readRoster() then return 0 end
 local g=book(true);if not g then return 0 end
 local renamed=0
 for guid,name in pairs(rosterByGUID) do
  if observe(g,guid,name,'live roster GUID') then renamed=renamed+1 end
 end
 if renamed>0 and K.UI and K.UI.Refresh then K.UI.Refresh() end
 return renamed
end

-- Canonical current name for any known name of a guild character (current or
-- verified former). Unknown names are returned unchanged.
function I.Current(name)
 if type(name)~='string' or secret(name) then return name end
 local g=book(false);if not g then return name end
 local b=bare(name)
 for _,rec in pairs(g.byGUID) do
  if bare(rec.name)==b then return rec.name end
  for alias in pairs(rec.aliases or {}) do
   if bare(alias)==b and not (K.CurrentGuildMember and K.CurrentGuildMember(name)) then return rec.name end
  end
 end
 return name
end
function I.Record(guid) local g=book(false);return g and g.byGUID[guid] end
function I.Log() local g=book(false);return g and g.log or {} end
function I.Claims() local g=book(false);return g and g.claims or {} end
function I.Status()
 local g=book(false)
 local n=0;if g then for _ in pairs(g.byGUID) do n=n+1 end end
 return {known=n,renames=I.renames or 0,rosterAt=rosterAt,log=g and #g.log or 0,claims=g and #g.claims or 0}
end

------------------------------------------------------------------ peer messages
local function send(msg)
 if not K.Net or not K.Net.Send or #msg>240 then return false end
 return K.Net.Send(PREFIX,msg,'GUILD')
end
local lastAnnounce=0
-- Announce this character's own GUID and the names it has been known by.
function I.Announce(force)
 local now=time()
 if not force and now-lastAnnounce<600 then return false end
 local g=book(true);if not g then return false end
 local guid=UnitGUID and UnitGUID('player')
 if not validGUID(guid) then return false end
 lastAnnounce=now
 local rec=g.byGUID[guid]
 local aliases={}
 for a in pairs(rec and rec.aliases or {}) do
  local clean=a:gsub('[|;%c]','')
  if #table.concat(aliases,';')+#clean<150 then aliases[#aliases+1]=clean end
 end
 return send('I|'..guid..'|'..table.concat(aliases,';'))
end

-- Approve a link (officer). Old name must not belong to any current member.
function I.OfficerLink(oldName,currentName)
 if not (K.IsOfficer and K.IsOfficer()) then return false,'Officer rank required.' end
 oldName=K.Clean(oldName,60):match('^%s*(.-)%s*$')
 if oldName=='' then return false,'Enter the old character name.' end
 if K.CurrentGuildMember and K.CurrentGuildMember(oldName) then return false,'That name belongs to a current guild member.' end
 readRoster()
 local guid=I.RosterGUID(currentName)
 if not guid then return false,'Current member not found on the live roster.' end
 local g=book(true);if not g then return false,'Guild identity unavailable.' end
 local rec=g.byGUID[guid] or {name=rosterByGUID[guid],first=time(),seen=time(),aliases={}}
 g.byGUID[guid]=rec
 for og,other in pairs(g.byGUID) do
  if og~=guid and (bare(other.name)==bare(oldName)) then return false,'That old name is recorded for a different character.' end
 end
 rec.aliases[oldName]=time()
 local me=UnitName and UnitName('player') or '?'
 migrate(g,guid,oldName,rec.name,'officer link',me)
 for i=#g.claims,1,-1 do if g.claims[i].guid==guid and bare(g.claims[i].old)==bare(oldName) then table.remove(g.claims,i) end end
 send('L|'..guid..'|'..oldName:gsub('[|;%c]',''))
 if K.UI and K.UI.Refresh then K.UI.Refresh() end
 return true
end

local function onMessage(prefix,msg,channel,sender)
 if prefix~=PREFIX or channel~='GUILD' or type(msg)~='string' or type(sender)~='string' then return end
 if #msg>250 or secret(msg) or secret(sender) then return end
 if not (K.IsMember and K.IsMember(sender)) then return end
 local g=book(true);if not g then return end
 readRoster()
 local kind,guid,rest=msg:match('^([IL])|(Player%-%w+%-%w+)|(.*)$')
 if not kind then return end
 if kind=='I' then
  -- The sender may speak only for itself: its live roster entry must carry this GUID.
  if I.RosterGUID(sender)~=guid then return end
  local current=rosterByGUID[guid] or sender
  observe(g,guid,current,'peer identity verified by roster')
  local rec=g.byGUID[guid]
  for alias in rest:gmatch('[^;]+') do
   if #alias<=60 and not (rec.aliases and rec.aliases[alias]) and not (K.CurrentGuildMember and K.CurrentGuildMember(alias)) then
    local dup=false
    for _,c in ipairs(g.claims) do if c.guid==guid and bare(c.old)==bare(alias) then dup=true end end
    if not dup and #g.claims<MAX_CLAIMS then g.claims[#g.claims+1]={guid=guid,old=alias,current=current,at=time()} end
   end
  end
 elseif kind=='L' then
  -- Officer link: authority comes only from the sender's live roster rank.
  if not (K.IsSenderOfficer and K.IsSenderOfficer(sender)) then return end
  local oldName=rest
  if oldName=='' or #oldName>60 or (K.CurrentGuildMember and K.CurrentGuildMember(oldName)) then return end
  local current=rosterByGUID[guid];if not current then return end
  for og,other in pairs(g.byGUID) do if og~=guid and bare(other.name)==bare(oldName) then return end end
  local rec=g.byGUID[guid] or {name=current,first=time(),seen=time(),aliases={}}
  g.byGUID[guid]=rec;rec.aliases=rec.aliases or {}
  if rec.aliases[oldName] then return end
  rec.aliases[oldName]=time()
  migrate(g,guid,oldName,current,'officer link received',sender)
  for i=#g.claims,1,-1 do if g.claims[i].guid==guid and bare(g.claims[i].old)==bare(oldName) then table.remove(g.claims,i) end end
 end
 if K.UI and K.UI.Refresh then K.UI.Refresh() end
end
I._onMessage=onMessage

K.On('CHAT_MSG_ADDON',onMessage)
K.On('ADDON_LOADED',function(addon)
 if addon=='KeepersWarCommand' and C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix,PREFIX) end
end)
local pendingScan=false
K.On('GUILD_ROSTER_UPDATE',function()
 if pendingScan then return end
 pendingScan=true
 local function run() pendingScan=false;local ok,err=pcall(I.Scan);if not ok and K.Log then K.Log('IDENTITY',tostring(err)) end;pcall(I.Announce) end
 if C_Timer and C_Timer.After then C_Timer.After(2,run) else run() end
end)

------------------------------------------------------------------ migrators
-- Each returns the number of records moved. Data is moved only from keys that
-- match the verified old name, never from a key a current member owns, and a
-- newer record already under the new key is kept.
local function moveKey(t,old,new,ctx,keep)
 if type(t)~='table' then return 0 end
 local n=0
 for key,value in pairs(t) do
  if key~=new and ctx.matches(key) and not ctx.skip(key) then
   local existing=t[new]
   if existing==nil then t[new]=value elseif keep then t[new]=keep(existing,value) end
   t[key]=nil;n=n+1
  end
 end
 return n
end
I.MoveKey=moveKey
local function newerRev(a,b) return ((type(b)=='table' and b.rev or 0)>(type(a)=='table' and a.rev or 0)) and b or a end

-- PvP records are keyed by display name.
I.RegisterMigrator('pvp',function(old,new,_,ctx)
 local display=(new:match('^[^-]+') or new)
 return moveKey(KWCDB.pvp,old,display,ctx,function(a,b) return K.PvP and K.PvP.Merge and K.PvP.Merge(a,b) or a end)
end)
-- Guild Records statistics boards (guild partition, lower-case roster keys).
I.RegisterMigrator('guild records',function(old,new,_,ctx)
 local db=KWCDB.guildRecords;if type(db)~='table' then return 0 end
 local n=moveKey(db.members,old,new:lower(),ctx)
 moveKey(db.sharing,old,new:lower(),ctx)
 return n
end)
-- Shared death counts (per guild, lower-case roster keys, revision-ordered).
for _,spec in ipairs({{'lifetime deaths','lifetimeDeathsExcludingBG'},{'open-world deaths','openWorldDeaths'}}) do
 I.RegisterMigrator(spec[1],function(old,new,_,ctx)
  local root=KWCDB[spec[2]];local guild=K.GuildScope and K.GuildScope()
  local g=type(root)=='table' and type(root.guilds)=='table' and guild and root.guilds[guild]
  if type(g)~='table' then return 0 end
  return moveKey(g.members,old,new:lower(),ctx,newerRev)
 end)
end
-- Cached roster rows (display only).
I.RegisterMigrator('roster cache',function(old,new,_,ctx) return moveKey(KWCDB.roster,old,new:lower(),ctx) end)
-- CTA authorship, command seats, lieutenants and responses; bounty authorship,
-- claims and sightings. Display names follow the character.
I.RegisterMigrator('boards',function(old,new,_,ctx)
 local n=0
 local display=(new:match('^[^-]+') or new)
 local function fix(v) if type(v)=='string' and ctx.matches(v) and not ctx.skip(v) then n=n+1;return display end;return v end
 for _,e in ipairs(KWCDB.ops or {}) do
  e.author=fix(e.author);e.commander=fix(e.commander);e.updatedBy=fix(e.updatedBy);e.lieutenant=fix(e.lieutenant)
  if type(e.commandSeats)=='table' then n=n+moveKey(e.commandSeats,old,display,ctx) end
  if type(e.lieutenants)=='table' then
   n=n+moveKey(e.lieutenants,old,display,ctx)
   for k,v in pairs(e.lieutenants) do e.lieutenants[k]=fix(v) end
  end
 end
 for id,resp in pairs(KWCDB.responses or {}) do n=n+moveKey(resp,old,new:lower(),ctx) end
 for _,e in ipairs(KWCDB.ops or {}) do if type(e.responseRevisions)=='table' then moveKey(e.responseRevisions,old,new:lower(),ctx) end end
 for _,b in ipairs(KWCDB.bounties or {}) do
  b.author=fix(b.author);b.updatedBy=fix(b.updatedBy)
  if type(b.claims)=='table' then n=n+moveKey(b.claims,old,new:lower(),ctx) end
  if type(b.claimTimes)=='table' then moveKey(b.claimTimes,old,new:lower(),ctx) end
  for _,s in ipairs(b.sightings or {}) do s.who=fix(s.who) end
 end
 return n
end)
-- Raid sign-up responses.
I.RegisterMigrator('raid sign-ups',function(old,new,_,ctx)
 local d=KWCDB.raidSignups;if type(d)~='table' or type(d.responses)~='table' then return 0 end
 local n=0
 for _,resp in pairs(d.responses) do n=n+moveKey(resp,old,new,ctx,newerRev) end
 return n
end)
-- Keepers Raid Tools attendance: [raidDay]["Name-Realm"]. Existing days keep
-- their record; an entry already present under the new name wins.
I.RegisterMigrator('raid attendance',function(old,new,_,ctx)
 local db=KWCDB.raidTools and KWCDB.raidTools.attendance
 if type(db)~='table' then return 0 end
 local n=0
 for day,rows in pairs(db) do
  if type(rows)=='table' then
   local realm=nil
   for key in pairs(rows) do if ctx.matches(key) then realm=key:match('%-(.+)$') end end
   local target=new:find('-',1,true) and new or (realm and (new..'-'..realm) or new)
   n=n+moveKey(rows,old,target,ctx)
  end
 end
 return n
end)
-- Guild Services professions directory (guild partition, lower-case roster keys).
I.RegisterMigrator('guild services',function(old,new,_,ctx)
 local db=KWCDB.guildServices;if type(db)~='table' or type(db.characters)~='table' then return 0 end
 return moveKey(db.characters,old,new:lower(),ctx)
end)
-- Board delete claims are keyed "kind:id:authorIdentity"; keep them attached to
-- the renamed author so a deleted record can never come back after a rename.
I.RegisterMigrator('delete claims',function(old,new,_,ctx)
 local claims=KWCDB.boardDeleteClaims;if type(claims)~='table' then return 0 end
 local n=0
 for key,value in pairs(claims) do
  local head,who=key:match('^(.+):([^:]+)$')
  if head and ctx.matches(who) and not ctx.skip(who) then
   local nk=head..':'..new:lower()
   if claims[nk]==nil then claims[nk]=value end
   claims[key]=nil;n=n+1
  end
 end
 return n
end)
