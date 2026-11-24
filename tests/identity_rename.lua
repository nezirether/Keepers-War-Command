-- Character rename acceptance tests (simulated multi-client guild).
-- Acceptance: a member changes their name, logs back in, keeps complete history
-- and appears under the new name across KWC features.
local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Ash Ember',rank=3,guid='Player-1-0000000A'})
w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})
w:AddMember({name='Filibuster Fent',rank=3,guid='Player-1-0000000C'})
w:AddMember({name='Lok Tar',rank=3,guid='Player-1-0000000D'})
local function boot(name,saved)
 local c=w:Client(name,{saved=saved})
 w:LoadAddon(c,'KeepersWarCommand');w:Login(c);w:Advance(4)
 return c
end
local grom,ash,zug=boot('Grom Warcry'),boot('Ash Ember'),boot('Filibuster Fent')
local now=w.now
local function seed(c,who)
 local d=c.env.KWCDB
 d.pvp=d.pvp or {}
 d.pvp[who]={weekly={},honor={available=true,lifetime=500,lastRead=now,peerReported=true}}
 d.guildRecords.members[who:lower()]={withdrawn=0,groups={{rows={42},rev=now}}}
 table.insert(d.ops,1,{id='c1',author=who,text='[HIGH] Ashenvale | H:A 3:5 | Hold the road',created=now,status='ACTIVE',revision=1})
 d.responses.c1={[who:lower()]='Coming'}
 d.raidTools=d.raidTools or {};d.raidTools.attendance=d.raidTools.attendance or {}
 d.raidTools.attendance['2026-11-20']={[who..'-Forever']={status=3}}
 d.boardDeleteClaims={['B:gone1:'..who:lower()]={at=now,kind='B',id='gone1'}}
end
seed(grom,'Filibuster Fent');seed(ash,'Filibuster Fent')
local function lifetimeFor(c,name)
 for _,r in ipairs(c.env.KWC.PvP.Rankings('lifetime')) do if r.name==name then return r.value end end
end
H.Check('before rename: Filibuster Fent listed with 500 lifetime HKs',lifetimeFor(grom,'Filibuster Fent')==500)
H.Check('identity book recorded the GUID from the live roster',grom.env.KWC.Identity.Record('Player-1-0000000C') and grom.env.KWC.Identity.Record('Player-1-0000000C').name=='Filibuster Fent')

-- Ash is offline while the rename happens.
ash.offline=true
w:Rename('Filibuster Fent','Filibuster Fente')
w:FireAll('GUILD_ROSTER_UPDATE');w:Advance(4)
local K=grom.env.KWC
H.Check('verified rename detected from the live roster GUID',K.Identity.Record('Player-1-0000000C').name=='Filibuster Fente' and K.Identity.Log()[1] and K.Identity.Log()[1].evidence=='live roster GUID')
H.Check('PvP leaderboard shows the new name with full history',lifetimeFor(grom,'Filibuster Fente')==500 and lifetimeFor(grom,'Filibuster Fent')==nil)
H.Check('Guild Records entry moved to the new identity',grom.env.KWCDB.guildRecords.members['filibuster fente']~=nil and grom.env.KWCDB.guildRecords.members['filibuster fent']==nil)
H.Check('CTA authorship follows the character',grom.env.KWCDB.ops[1].author=='Filibuster Fente')
H.Check('CTA response follows the character',grom.env.KWCDB.responses.c1['filibuster fente']=='Coming')
H.Check('raid attendance follows the character (realm kept)',grom.env.KWCDB.raidTools.attendance['2026-11-20']['Filibuster Fente-Forever']~=nil)
H.Check('delete claim follows the author (no resurrection after rename)',grom.env.KWCDB.boardDeleteClaims['B:gone1:filibuster fente']~=nil and grom.env.KWC.Sync.IsBoardDeleted('B','gone1','Filibuster Fente')~=nil)
H.Check('former name kept as a verified alias',K.Identity.Record('Player-1-0000000C').aliases['Filibuster Fent']~=nil)
H.Check('Current() maps the old name to the new one',K.Identity.Current('Filibuster Fent')=='Filibuster Fente')
H.Check('renamed player\'s own client logs back in cleanly',#zug.errors==0,table.concat(zug.errors,' | '))

-- Ash reconnects later and catches up from its own roster view.
ash.offline=false
w:Fire(ash,'GUILD_ROSTER_UPDATE');w:Advance(4)
H.Check('offline guildmate migrates on reconnect',lifetimeFor(ash,'Filibuster Fente')==500 and lifetimeFor(ash,'Filibuster Fent')==nil)

-- Relog persistence: identity and moved data survive /reload; no double migration.
local saved=w:Saved(grom,{'KWCDB'})
w:Drop(grom)
local grom2=boot('Grom Warcry',saved)
H.Check('after /reload the leaderboard still shows the new name',lifetimeFor(grom2,'Filibuster Fente')==500)
H.Check('after /reload no duplicate migration is logged',#grom2.env.KWC.Identity.Log()==1,#grom2.env.KWC.Identity.Log())

-- Pre-2.0 rename: a client that never saw the old GUID/name pairing.
local lok=boot('Lok Tar')
lok.lifetimeHK=80;lok.env.KWC.PvP.RefreshHonor();lok.env.KWC.PvP.RequestGuildHonor(true);w:Advance(6)
lok.env.KWCDB.pvp['Old Lok']={weekly={},honor={available=true,lifetime=77,lastRead=now,peerReported=true}}
ash.env.KWCDB.pvp['Old Lok']={weekly={},honor={available=true,lifetime=77,lastRead=now,peerReported=true}}
w:Fire(ash,'GUILD_ROSTER_UPDATE');w:Advance(4)
H.Check('records are NOT merged on a name guess',ash.env.KWCDB.pvp['Old Lok']~=nil and lifetimeFor(ash,'Old Lok')==nil)
-- The member announces an old name: kept only as a pending claim.
local LK=lok.env.KWC
local claimed=false
for _,cl in ipairs(grom2.env.KWC.Identity.Claims()) do if cl.old=='Old Lok' then claimed=true end end
-- Inject the self-claim exactly as Lok's client would send it.
w:Fire(grom2,'CHAT_MSG_ADDON','KWID1','I|Player-1-0000000D|Old Lok','GUILD','Lok Tar')
for _,cl in ipairs(grom2.env.KWC.Identity.Claims()) do if cl.old=='Old Lok' then claimed=true end end
H.Check('self-claimed old name is held as a pending claim, not merged',claimed and grom2.env.KWCDB.pvp['Old Lok']==nil and LK.Identity.Record('Player-1-0000000D').aliases['Old Lok']==nil)
-- Forged identity: Ash claims Lok's GUID -> rejected.
local before=#grom2.env.KWC.Identity.Claims()
w:Fire(grom2,'CHAT_MSG_ADDON','KWID1','I|Player-1-0000000D|Stolen Name','GUILD','Ash Ember')
H.Check('a member cannot announce another character\'s GUID',#grom2.env.KWC.Identity.Claims()==before)
-- Non-officer link is ignored.
w:Fire(lok,'CHAT_MSG_ADDON','KWID1','L|Player-1-0000000D|Old Lok','GUILD','Ash Ember')
H.Check('a link from a non-officer is ignored',lok.env.KWCDB.pvp['Old Lok']~=nil)
-- Officer approves the link; it syncs to Lok's client which migrates.
local ok,err=grom2.env.KWC.Identity.OfficerLink('Old Lok','Lok Tar')
w:Advance(4)
H.Check('officer link accepted on the officer client',ok,err)
H.Check('officer link syncs: guildmate folds the old record into Lok Tar (no duplicate)',ash.env.KWCDB.pvp['Old Lok']==nil and ash.env.KWCDB.pvp['Lok Tar']~=nil and lifetimeFor(ash,'Old Lok')==nil,tostring(lifetimeFor(ash,'Lok Tar')))
H.Check('renamed player\'s own client folds the old record in (live game stats stay authoritative)',lok.env.KWCDB.pvp['Old Lok']==nil and lok.env.KWCDB.pvp['Lok Tar']~=nil)
H.Check('pending claim cleared after approval',(function() for _,cl in ipairs(grom2.env.KWC.Identity.Claims()) do if cl.old=='Old Lok' then return false end end;return true end)())
-- Officer link refused when the old name belongs to a current member.
local ok2=grom2.env.KWC.Identity.OfficerLink('Ash Ember','Lok Tar')
H.Check('cannot link a name that a current member holds',not ok2)
-- Demotion: the same officer link is refused after rank drops.
w:Member('Grom Warcry').rank=3
local ok3=grom2.env.KWC.Identity.OfficerLink('Another Name','Lok Tar')
H.Check('officer link refused after demotion (live rank)',not ok3)
w:Member('Grom Warcry').rank=1
-- Name reuse: a different character later takes the old name; their data is never moved.
w:AddMember({name='Filibuster Fent',rank=3,guid='Player-1-0000000E'})
grom2.env.KWCDB.pvp['Filibuster Fent']={weekly={},honor={available=true,lifetime=3,lastRead=now,peerReported=true}}
w:Fire(grom2,'GUILD_ROSTER_UPDATE');w:Advance(4)
H.Check('a new character reusing the old name keeps their own record',lifetimeFor(grom2,'Filibuster Fent')==3 and lifetimeFor(grom2,'Filibuster Fente')==500)
-- No Lua errors anywhere.
local errs={}
for _,c in ipairs(w.clients) do for _,e in ipairs(c.errors) do errs[#errs+1]=c.name..': '..e end end
H.Check('no Lua errors on any client',#errs==0,table.concat(errs,' | '):sub(1,600))
os.exit(H.Summary('identity_rename') and 0 or 1)
