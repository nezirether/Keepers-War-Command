-- 2.0 alert behavior through the real engine + toast path (simulated):
-- guildmate deaths, guild kills, bounty sightings, dedupe, Smart Mode, instance
-- suppression (including loading screens), toggles, previews and own-death coords.
local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Ash Ember',rank=3,guid='Player-1-0000000A'})
for i=1,8 do w:AddMember({name='Grunt '..string.char(64+i)..'son',rank=3,guid=('Player-1-%08X'):format(100+i)}) end
local c=w:Client('Ash Ember');w:LoadAddon(c,'KeepersWarCommand');w:Login(c);w:Advance(6)
local K=c.env.KWC
local T=K.Toast.channels
local function death(from,killer,zone) w:Fire(c,'CHAT_MSG_ADDON','KWC3','2;WORLDDEATH;'..killer..';'..(zone or 'Hillsbrad Foothills'),'GUILD',from);w:Advance(0.6) end
death('Grunt Ason','Killed by: Evil Rogue')
H.Check('guildmate death shows a popup',T.worldPvPDeath.frame:IsShown())
H.Check('popup names victim and confirmed killer',(T.worldPvPDeath.frame.title:GetText() or ''):find('Grunt Ason')~=nil and (T.worldPvPDeath.frame.detail:GetText() or ''):find('Killed by: Evil Rogue')~=nil)
H.Check('death recorded in the history log',#(c.env.KWCDB.worldPvPDeaths or {})==1)
T.worldPvPDeath.frame:Hide()
death('Grunt Ason','Killed by: Evil Rogue')
H.Check('repeat report from the same victim within 12s is deduped',not T.worldPvPDeath.frame:IsShown() and #c.env.KWCDB.worldPvPDeaths==1)
death('Grunt Bson','Suspected: Shady Mage')
H.Check('suspected attacker is labelled as suspected, not confirmed',(T.worldPvPDeath.frame.detail:GetText() or ''):find('Suspected attacker')~=nil)
-- Smart Mode: many unique deaths in the window -> quiet period.
T.worldPvPDeath.frame:Hide()
for i=3,8 do death('Grunt '..string.char(64+i)..'son','Killed by: Raider') end
local status=K.WorldPvPDeaths.GetBattleStatus()
H.Check('Smart Mode enters a quiet period during a big fight',status.active==true)
T.worldPvPDeath.frame:Hide()
death('Grunt Hson','Killed by: Raider')
H.Check('Smart Mode suppresses further popups but still records deaths',not T.worldPvPDeath.frame:IsShown() and #c.env.KWCDB.worldPvPDeaths>=8)
w:Advance(200)
-- Instance suppression and loading screens.
c.instance='pvp';w:Fire(c,'PLAYER_ENTERING_WORLD',false,false);w:Advance(1)
death('Grunt Gson','Killed by: Someone')
H.Check('no death popup inside a battleground',not T.worldPvPDeath.frame:IsShown())
c.instance=nil;w:Fire(c,'PLAYER_LEAVING_WORLD')
H.Check('loading screen keeps alerts suppressed',K.InstanceAlerts.Allowed()==false)
w:Fire(c,'PLAYER_ENTERING_WORLD',false,false);w:Advance(1)
H.Check('alerts resume after open world is confirmed',K.InstanceAlerts.Allowed()==true)
-- Toggle off: chat/records continue, popup does not.
K.WorldPvPDeaths.SetEnabled(false);T.worldPvPDeath.frame:Hide()
death('Grunt Fson','Killed by: Another')
H.Check('popup toggle off suppresses the popup',not T.worldPvPDeath.frame:IsShown())
K.WorldPvPDeaths.SetEnabled(true)
-- Guild kill from a peer.
w:Fire(c,'CHAT_MSG_ADDON','KWC3','2;WORLDKILL;Alliance Mage;1;Ashenvale','GUILD','Grunt Ason');w:Advance(0.6)
H.Check('guild kill shows an enemy-slain popup',T.pvpKill.frame:IsShown() and (T.pvpKill.frame.title:GetText() or ''):find('Alliance Mage')~=nil,T.pvpKill.frame.title:GetText())
T.pvpKill:Hide() -- A queued sighting is presented after the active channel closes.
-- Bounty target spotted on target (open world).
K.Operations.AddBounty('Evil Rogue - camping',{target='Evil Rogue',location='',reason='camping',reward='25g'})
c.target={name='Evil Rogue',guid='Player-2-0000BEEF',faction='Alliance'}
w:Fire(c,'PLAYER_TARGET_CHANGED');w:Advance(2)
H.Check('bounty target on screen raises a bounty popup',T.bountyAlert.frame:IsShown() and (T.bountyAlert.frame.title:GetText() or '')=='Evil Rogue',T.bountyAlert.frame.title:GetText())
H.Check('bounty popup offers Report sighting',T.bountyAlert.frame.actions[1]:IsShown())
T.bountyAlert.frame:Hide();w:Advance(3)
H.Check('same target staying visible is not re-alerted',not T.bountyAlert.frame:IsShown())
c.target=nil
-- Previews always work, also in instances; Move/Lock toggles placement.
c.instance='raid';w:Fire(c,'PLAYER_ENTERING_WORLD',false,false);w:Advance(1)
for key,ch in pairs({death=T.worldPvPDeath,kill=T.pvpKill,bounty=T.bountyAlert,cta=T.ctaNotice,lfg=T.lfgNotice}) do
 ch.frame:Hide();ch.demo()
 H.Check('preview works in an instance: '..key,ch.frame:IsShown())
end
T.pvpKill:SetUnlocked(true)
H.Check('Move unlocks a channel and keeps it visible',T.pvpKill:Unlocked() and T.pvpKill.frame:IsShown())
T.pvpKill:SetUnlocked(false)
H.Check('Lock hides the placement preview',not T.pvpKill.frame:IsShown())
-- Instance transition dismisses automatic popups (previews unaffected).
c.instance=nil;w:Fire(c,'PLAYER_ENTERING_WORLD',false,false);w:Advance(1)
T.worldPvPDeath.frame:Hide();w:Advance(15)
death('Grunt Cson','Killed by: Late One')
H.Check('fresh open-world death shows again after returning',T.worldPvPDeath.frame:IsShown())
-- Own death coordinates (local only) power Drop Pin / Copy Coordinates.
c.mapID,c.mapX,c.mapY=1424,0.54,0.61
c.recap={{timestamp=w.now,amount=500,overkill=10,sourceName='Real Killer',sourceGUID='Player-2-00001234',sourceFlags=0x40+0x400,event='SPELL_DAMAGE'}}
c.dead=true;w:Fire(c,'PLAYER_DEAD');w:Advance(3)
local rec=c.env.KWCDB.worldPvPDeaths[1]
H.Check('own open-world death is recorded with coordinates',rec and rec.victim=='Ash Ember' and rec.map==1424 and math.abs((rec.x or 0)-0.54)<1e-6,rec and tostring(rec.victim))
H.Check('own death attributed from the public death recap',rec and tostring(rec.killer):find('Real Killer')~=nil,rec and rec.killer)
T.worldPvPDeath:Hide();w:Advance(1)
local pin,copy=false,false
K.Geo.DropPin=function(map,x,y) pin=map==1424 and x==rec.x and y==rec.y;return pin end
K.Kit.CopyBox=function(_,_,text) copy=text:find('54.0, 61.0',1,true)~=nil end
T.worldPvPDeath.frame.actions[3]:Click();T.worldPvPDeath.frame.actions[4]:Click()
H.Check('own death popup exposes pin and copy coordinates actions',pin and copy and T.worldPvPDeath.frame.meta:GetText():find('54.0, 61.0',1,true))
c.dead=false
local errs=table.concat(c.errors,' | ')
H.Check('no Lua errors',#c.errors==0,errs:sub(1,500))
os.exit(H.Summary('alerts') and 0 or 1)
