-- KWCC officer add-on: load, UI, authorization (fail closed), recruitment rules,
-- officer-only sync, demotion, guild change and stale roster handling.
local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})   -- War Council
w:AddMember({name='Thrall Doomhammer',rank=0,guid='Player-1-0000000F'}) -- Warchief
w:AddMember({name='Ash Ember',rank=3,guid='Player-1-0000000A'})      -- member
local function boot(name,withKWCC)
 local c=w:Client(name)
 w:LoadAddon(c,'KeepersWarCommand')
 if withKWCC then w:LoadAddon(c,'KeepersWarCommand_Command') end
 w:Login(c);w:Advance(5)
 return c
end
local grom=boot('Grom Warcry',true)
local thrall=boot('Thrall Doomhammer',true)
local ash=boot('Ash Ember',true)        -- a member who installed KWCC anyway
local pub=boot('Ash Ember',false)       -- a member with public KWC only (separate client view)
local function errs(c) return table.concat(c.errors,' | '):sub(1,500) end
H.Check('KWCC loads with KWC (dependency satisfied) without errors',#grom.errors==0 and grom.env.KWCC~=nil,errs(grom))
H.Check('KWCC does not register any slash command',grom.env.SLASH_KEEPERSWARCOMMAND_COMMAND1==nil and grom.env.SLASH_KWCC1==nil and grom.env.SLASH_KEEPERSWARCOMMAND1=='/kt')
H.Check('public KWC alone has no recruiter or officer service',pub.env.KWC.Recruiter==nil and pub.env.KWCC==nil and pub.env.KWC.Officer.Open==nil)
pub.env.SlashCmdList.KEEPERSWARCOMMAND('command')
H.Check('/kt command without KWCC explains it needs the officer add-on',(pub.printed[#pub.printed] or ''):find('KeepersWarCommand_Command')~=nil)
-- Authorization
local okG=grom.env.KWCC.Auth.Status()
local okT=thrall.env.KWCC.Auth.Status()
local okA,why=ash.env.KWCC.Auth.Status()
H.Check('War Council is authorized',okG)
H.Check('Warchief is authorized',okT)
H.Check('ordinary member is denied even with KWCC installed',not okA,why)
-- /kt command opens the Command Table (distinct frame), not a War Room page
grom.env.SlashCmdList.KEEPERSWARCOMMAND('command');w:Advance(1)
local ct=grom.env.KWCC_CommandTable
H.Check('/kt command opens the separate Command Table frame',ct and ct:IsShown() and not (grom.env.KWC2_WarRoom and grom.env.KWC2_WarRoom:IsShown()))
for _,m in ipairs({'recruit','contacts','dnc','identity','boards','audit'}) do
 grom.printed={}
 grom.env.KWCC.UI.Open(m);w:Advance(0.5)
 local bad;for _,l in ipairs(grom.printed) do if l:find('Interface error') then bad=l end end
 H.Check('Command Table mode '..m..' renders without error',not bad and #grom.errors==0,bad or errs(grom))
 grom.errors={}
end
-- Member sees only the lock screen.
ash.env.KWCC.UI.Open('recruit');w:Advance(0.5)
H.Check('member opening the Command Table gets the lock screen (no officer data drawn)',ash.env.KWCC_CommandTable:IsShown() and ash.env.KWCC.UI.IsLocked())
-- Recruitment: WHO search, whisper rules.
grom.whoResults={{fullName='Fresh Recruit',level=24,classStr='Shaman',area='Barrens'},{fullName='Guilded Guy',level=24,fullGuildName='Other Guild'},
 {fullName='Spam Hater',level=24},{fullName='Recent Contact',level=24}}
local GK=grom.env.KWCC
GK.Store.AddDNC('Spam Hater',w.now,'Grom Warcry','asked not to be contacted')
GK.Store.RecordContact('Recent Contact',w.now-3600,'Thrall Doomhammer','whispered')
GK.Recruiter.Search('20-30');w:Fire(grom,'WHO_LIST_UPDATE');w:Advance(1)
local names={};for _,c in ipairs(GK.Recruiter.results) do names[#names+1]=c.name end
H.Check('WHO results exclude guilded, do-not-contact and recently contacted players',#names==1 and names[1]=='Fresh Recruit',table.concat(names,','))
H.Check('hidden counts are reported',GK.Recruiter.hidden.dnc==1 and GK.Recruiter.hidden.cooldown==1 and GK.Recruiter.hidden.guilded==1)
GK.Recruiter.Select('Fresh Recruit')
H.Check('whisper is sent on explicit action and starts the cooldown',GK.Recruiter.Whisper() and grom.chatSent and #grom.chatSent==1 and GK.Store.Cooldown('Fresh Recruit')>0)
H.Check('second whisper inside 72h is refused',not GK.Recruiter.Whisper() and #grom.chatSent==1)
-- Officer sync: contact reaches Thrall (officer) by whisper; never GUILD.
w:Advance(4)
local TK=thrall.env.KWCC
H.Check('contact syncs to the other officer (72h cooldown is guild-wide)',TK.Store.Cooldown('Fresh Recruit')>0)
H.Check('member client never received officer contact data',ash.env.KWCC.Store.Guild()==nil or ash.env.KWCC.Store.Cooldown('Fresh Recruit')==0)
-- DNC sync
GK.Recruiter.DoNotContact('Rude Person','harassment');w:Advance(4)
H.Check('Do Not Contact syncs to officers',TK.Store.IsDNC('Rude Person'))
H.Check('Do Not Contact never reaches members',not ash.env.KWCC.Store.IsDNC('Rude Person'))
-- Forged officer packet from a member is rejected.
local before=TK.OfficerSync.stats.rejected
w:Fire(thrall,'CHAT_MSG_ADDON','KWCC1','D|Innocent Player|'..w.now..'|Ash Ember|forged','WHISPER','Ash Ember')
H.Check('officer packet from a member is rejected',not TK.Store.IsDNC('Innocent Player') and TK.OfficerSync.stats.rejected==before+1)
-- Officer data sent on GUILD (wrong channel) is rejected even from an officer.
w:Fire(thrall,'CHAT_MSG_ADDON','KWCC1','D|Guild Leak|'..w.now..'|Grom Warcry|x','GUILD','Grom Warcry')
H.Check('officer packet on GUILD channel is rejected',not TK.Store.IsDNC('Guild Leak'))
-- Demotion: Grom drops to member; next action is denied and incoming data refused.
w:Member('Grom Warcry').rank=4
w:FireAll('GUILD_ROSTER_UPDATE');w:Advance(3)
local okAfter=grom.env.KWCC.Auth.Status()
H.Check('demoted officer is denied immediately (live rank)',not okAfter)
H.Check('demoted officer cannot whisper candidates',not GK.Recruiter.Whisper())
w:Fire(grom,'CHAT_MSG_ADDON','KWCC1','D|After Demotion|'..w.now..'|Thrall Doomhammer|x','WHISPER','Thrall Doomhammer')
H.Check('demoted officer\'s client refuses restricted data',not GK.Store.IsDNC('After Demotion'))
grom.env.KWCC.UI.Open('recruit');w:Advance(0.5)
H.Check('Command Table shows the lock screen after demotion',grom.env.KWCC.UI.IsLocked())
H.Check('authorized officer does not see the lock screen',(function() thrall.env.KWCC.UI.Open('recruit');return not thrall.env.KWCC.UI.IsLocked() end)())
w:Member('Grom Warcry').rank=1;w:FireAll('GUILD_ROSTER_UPDATE');w:Advance(3)
-- Stale roster fails closed.
TK.Auth._SetRosterAge(TK.Auth.ROSTER_MAX_AGE+5)
local okStale,staleWhy=TK.Auth.Status()
H.Check('stale roster fails closed',not okStale and tostring(staleWhy):find('stale')~=nil,staleWhy)
w:Fire(thrall,'GUILD_ROSTER_UPDATE');w:Advance(1)
H.Check('fresh roster restores access',(TK.Auth.Status()))
-- Guild change: leaving the guild locks and partitions data.
thrall.inGuild=false;w:Fire(thrall,'PLAYER_GUILD_UPDATE');w:Advance(1)
H.Check('leaving the guild locks the Command Table',not (TK.Auth.Status()) and TK.Store.Guild()==nil)
thrall.inGuild=true
thrall.guildID=999;w:Fire(thrall,'PLAYER_GUILD_UPDATE');w:Fire(thrall,'GUILD_ROSTER_UPDATE');w:Advance(2)
H.Check('a different guild never sees the previous guild\'s officer data',not TK.Store.IsDNC('Rude Person'))
thrall.guildID=nil;w:Fire(thrall,'PLAYER_GUILD_UPDATE');w:Fire(thrall,'GUILD_ROSTER_UPDATE');w:Advance(2)
H.Check('returning to the guild restores its officer data',TK.Store.IsDNC('Rude Person'))
-- Invite is prepared, never sent silently.
GK.Recruiter.results={{name='Invitee Person',status='discovered'}};GK.Store.PutCandidate(GK.Recruiter.results[1]);GK.Recruiter.Select('Invitee Person')
local cmd=GK.Recruiter.PrepareInvite()
H.Check('guild invite is prepared as /ginvite, not sent',cmd=='/ginvite Invitee Person' and grom.invited==nil)
-- No Lua errors anywhere.
local all={}
for _,c in ipairs(w.clients) do for _,e in ipairs(c.errors) do all[#all+1]=c.name..': '..e end end
H.Check('no Lua errors on any client',#all==0,table.concat(all,' | '):sub(1,600))
os.exit(H.Summary('kwcc_security') and 0 or 1)
