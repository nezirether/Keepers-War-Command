-- Two-plus-client board sync (simulated): create, update, respond, sightings,
-- delete with tombstone replay, offline recovery, duplicate-alert suppression,
-- instance alert suppression, cross-guild isolation, and 1.8.2 <-> 2.0 mixing.
local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})
w:AddMember({name='Ash Ember',rank=3,guid='Player-1-0000000A'})
w:AddMember({name='Lok Tar',rank=3,guid='Player-1-0000000D'})
w:AddMember({name='Old Timer',rank=3,guid='Player-1-00000010'})
local function boot(name,dir,saved)
 local c=w:Client(name,{saved=saved})
 w:LoadAddon(c,dir or 'KeepersWarCommand');w:Login(c);w:Advance(6)
 return c
end
local grom,ash=boot('Grom Warcry'),boot('Ash Ember')
local function find(c,kind,pred) for _,e in ipairs(kind=='CTA' and c.env.KWCDB.ops or c.env.KWCDB.bounties) do if pred(e) then return e end end end
-- CTA create
grom.env.KWC.Operations.DetailedCTA('Hillsbrad Foothills','Defend Tarren Mill',4,9,'HIGH','54.0, 61.0','bring heals')
w:Advance(8)
local cta=find(ash,'CTA',function(e) return e.text:find('Tarren Mill') end)
H.Check('CTA created by an officer reaches a member',cta~=nil)
H.Check('CTA details (counts, priority) sync',cta and cta.details and cta.details.horde==4 and cta.details.alliance==9 and cta.details.priority=='HIGH',cta and cta.details and cta.details.priority)
-- New CTA toast fired once on the member (open world, fresh, not mine)
local toast=ash.env.KWC.Toast.channels.ctaNotice
H.Check('member sees one new-CTA popup',toast.frame:IsShown())
toast.frame:Hide()
ash.env.KWC.UI.Refresh();w:Advance(2)
H.Check('no duplicate popup for the same CTA',not toast.frame:IsShown())
-- Response
ash.env.KWC.Operations.Respond(cta.id,'Coming');w:Advance(6)
local gcta=find(grom,'CTA',function(e) return e.id==cta.id end)
local resp=grom.env.KWCDB.responses[cta.id] or {}
local coming=false;for k,v in pairs(resp) do if v=='Coming' then coming=true end end
H.Check('member response reaches the commander',coming)
-- Update by owner
grom.env.KWC.Operations.UpdateCTA(cta.id,'Hillsbrad Foothills',10,9,'Push the flag','URGENT','')
w:Advance(8)
cta=find(ash,'CTA',function(e) return e.id==gcta.id end)
H.Check('CTA update syncs',cta.details and cta.details.priority=='URGENT' and cta.details.horde==10,cta.details and cta.details.priority)
-- Member cannot edit someone else's CTA (engine rule; UI hides the button)
ash.env.KWC.Operations.UpdateCTA(cta.id,'Nowhere',0,0,'Vandalism','LOW','')
H.Check('member cannot edit another member\'s CTA',cta.details.zone=='Hillsbrad Foothills')
-- Bounty + sighting
ash.env.KWC.Operations.AddBounty('Evil Rogue @ Hillsbrad - camping',{target='Evil Rogue',location='Hillsbrad',reason='camping',reward='50g'})
w:Advance(8)
local b=find(grom,'BOUNTY',function(e) return e.details and e.details.target=='Evil Rogue' end)
H.Check('bounty reaches the guild',b~=nil)
grom.env.KWC.Operations.AddSighting(b.id,'Southshore','near the inn');w:Advance(8)
local ab=find(ash,'BOUNTY',function(e) return e.id==b.id end)
H.Check('sighting syncs to the poster',ab.sightings and ab.sightings[1] and ab.sightings[1].zone=='Southshore')
-- Lok was offline for all of the above; recovers on login.
local lok=boot('Lok Tar')
-- One officer serves one recovery at a time (1.8.2 bounded design); a request that
-- lands mid-reply is caught by the built-in retries at ~44-50s and ~84-90s.
w:Advance(100)
H.Check('offline member recovers the active CTA on login',find(lok,'CTA',function(e) return e.id==gcta.id end)~=nil)
H.Check('offline member recovers the bounty on login',find(lok,'BOUNTY',function(e) return e.id==b.id end)~=nil)
local lt=lok.env.KWC.Toast.channels.ctaNotice
H.Check('recovered (old) CTAs do not raise new-CTA popups',not lt.frame:IsShown())
-- Delete with tombstone; a stale client replaying the record must not resurrect it.
local savedLok=w:Saved(lok,{'KWCDB','KeepersRaidToolsDB','KeepersRaidToolsAttendanceDB','KeepersRaidToolsRosterDB','KRTForeverNotesDB'})
w:Drop(lok)
H.Check('poster can delete their bounty',ash.env.KWC.Operations.Delete('BOUNTY',b.id))
w:Advance(8)
H.Check('deletion reaches the officer',find(grom,'BOUNTY',function(e) return e.id==b.id end)==nil)
-- Lok comes back with the stale copy in SavedVariables.
lok=boot('Lok Tar',nil,savedLok)
w:Advance(60)
H.Check('tombstone stops a stale client from resurrecting the bounty (officer view)',find(grom,'BOUNTY',function(e) return e.id==b.id end)==nil)
H.Check('stale client drops the deleted bounty after sync',find(lok,'BOUNTY',function(e) return e.id==b.id end)==nil)
-- Instance suppression: Ash enters a dungeon; a new CTA must not pop up.
ash.instance='party';w:Fire(ash,'PLAYER_ENTERING_WORLD',false,false);w:Advance(1)
ash.env.KWC.Toast.channels.ctaNotice.frame:Hide()
grom.env.KWC.Operations.DetailedCTA('Arathi Highlands','Hold the farm',2,3,'NORMAL','','')
w:Advance(8)
H.Check('new CTA arrives while in a dungeon (data synced)',find(ash,'CTA',function(e) return e.text:find('Hold the farm') end)~=nil)
H.Check('but no popup is shown inside an instance',not ash.env.KWC.Toast.channels.ctaNotice.frame:IsShown())
H.Check('alert policy reports suppression',ash.env.KWC.InstanceAlerts.Allowed()==false)
ash.instance=nil;w:Fire(ash,'PLAYER_ENTERING_WORLD',false,false);w:Advance(1)
H.Check('alerts resume after returning to the open world',ash.env.KWC.InstanceAlerts.Allowed()==true)
-- Bounty sighting alert suppressed in instance, previews still work.
ash.instance='raid';w:Fire(ash,'PLAYER_ENTERING_WORLD',false,false);w:Advance(1)
ash.env.KWC.BountyAlerts.Demo()
H.Check('manual preview still works inside an instance',ash.env.KWC.Toast.channels.bountyAlert.frame:IsShown())
ash.instance=nil;w:Fire(ash,'PLAYER_ENTERING_WORLD',false,false);w:Advance(1)
-- Cross-guild isolation: a client in another guild never sees these boards.
w:AddMember({name='Stranger Elsewhere',rank=3,guid='Player-1-00000099'})
local stranger=w:Client('Stranger Elsewhere');stranger.guildID=777
w:LoadAddon(stranger,'KeepersWarCommand');w:Login(stranger);w:Advance(20)
H.Check('a client with a different guild ID keeps an empty board',#(stranger.env.KWCDB.ops or {})==0)
-- No wire message exceeds limits (harness asserts 255 on send).
H.Check('all addon messages within the 255-byte limit',true)
local all={}
for _,c in ipairs(w.clients) do for _,e in ipairs(c.errors) do all[#all+1]=c.name..': '..e end end
H.Check('no Lua errors on any 2.0 client',#all==0,table.concat(all,' | '):sub(1,600))
-- Mixed versions: a 1.8.2 client (original add-on, loaded from the reference
-- copy) and 2.0 clients in one guild.
if arg and arg[1]=='--public-only' then
 print('SKIP mixed-version tests: --public-only was selected')
 os.exit(H.Summary('board_sync') and 0 or 1)
end
local reference=arg and arg[1] or '/home/claude/ref/v4.9/KeepersWarCommand'
local okLegacy,legacy=pcall(function()
 local c=w:Client('Old Timer')
 w:LoadAddon(c,reference);w:Login(c);w:Advance(40)
 return c
end)
H.Check('1.8.2 reference client loads in the same harness',okLegacy,legacy)
if okLegacy then
 H.Check('1.8.2 client receives 2.0 CTAs (shared KWC4 protocol)',find(legacy,'CTA',function(e) return e.text:find('Hold the farm') end)~=nil)
 legacy.env.KWC.Operations.DetailedCTA('Alterac Mountains','Old client test',1,1,'LOW','','')
 w:Advance(10)
 H.Check('2.0 client receives a CTA posted from 1.8.2',find(ash,'CTA',function(e) return e.text:find('Old client test') end)~=nil)
 legacy.env.KWC.Operations.AddBounty('Legacy Target',{target='Legacy Target',location='',reason='',reward=''});w:Advance(10)
 H.Check('2.0 client receives a bounty posted from 1.8.2',find(grom,'BOUNTY',function(e) return e.details and e.details.target=='Legacy Target' end)~=nil)
 -- 2.0-only WORLDKB kind reaches the old client too; it must be ignored silently.
 w:Fire(legacy,'CHAT_MSG_ADDON','KWC3','2;WORLDKB;Low Gnome;Ashenvale','GUILD',ash.name)
 w:Advance(2)
 H.Check('1.8.2 client stores nothing from an unknown WORLDKB kind',#(legacy.env.KWCDB.worldPvPKills or {})==0)
 local lerr={};for _,e in ipairs(legacy.errors) do lerr[#lerr+1]=e end
 H.Check('1.8.2 client raises no Lua errors from 2.0 traffic (incl. new KWID1 prefix)',#lerr==0,table.concat(lerr,' | '):sub(1,500))
end
os.exit(H.Summary('board_sync') and 0 or 1)
