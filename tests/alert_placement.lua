-- Alert placement and the production death/bounty alert behaviour, through the
-- real add-on. Ported from the 1.x banner suite: the engine scenarios keep their
-- original assertions; placement now exercises the War Room toast channels.
-- Run from the repository root with Lua 5.1 or LuaJIT.
local H=dofile('tests/harness/wow.lua')
local function near(actual,expected,label)
 assert(math.abs(actual-expected)<1e-6,('%s: expected %g, got %g'):format(label,expected,actual))
end
local NAMES={'Player One','Rival Mate','One Mate','Two Mate','Three Mate','Four Mate','Five Mate','Six Mate',
 'Victim Realm','ScoutFriend Mate','Peer Mate','Guildmate Mate'}
local function newSession(settings)
 local w=H.World()
 -- Short sender names used by the scenarios resolve to roster members.
 for i,name in ipairs({'Player','One','Two','Three','Four','Five','Six','Victim','ScoutFriend','Peer','Guildmate'}) do
  w:AddMember({name=name,rank=3,guid=('Player-1-%08X'):format(i)})
 end
 local c=w:Client('Player')
 local env=c.env
 local clock=env.time;env.time=function(...) return math.floor(clock(...)) end
 local sounds,enemy=0,true
 w:LoadAddon(c,'KeepersWarCommand')
 local K=env.KWC
 for k,v in pairs(settings) do env.KWCDB.settings[k]=v end
 w:Login(c);w:Advance(20)
 env.UnitExists=function() return true end
 env.UnitIsPlayer=function() return true end
 env.UnitIsUnit=function(a,b) return a==b end
 env.UnitCanAttack=function() return enemy end
 env.UnitName=function(unit) if unit=='player' then return 'Player' end;return 'Rival','OtherRealm' end
 env.PlaySound=function() sounds=sounds+1 end
 local events={}
 for event,list in pairs(K.listeners) do events[event]=list end
 local session={env=env,world=w,client=c,K=K,events=events,alerts={}}
 for _,spec in ipairs({{api=K.WorldPvPDeaths,key='worldPvPDeath'},{api=K.BountyAlerts,key='bountyAlert'}}) do
  local ch=K.Toast.channels[spec.key]
  spec.channel,spec.frame=ch,ch.frame
  session.alerts[#session.alerts+1]=spec
 end
 function session.setEnemy(value) enemy=value end
 function session.soundCount() return sounds end
 -- Death announcements this client printed to chat.
 function session.messages()
  local out={}
  for _,line in ipairs(c.printed) do if line:find('WORLD PVP:',1,true) then out[#out+1]=line end end
  return out
 end
 -- Scenario times are offsets from a fixed point after login; full epochs pass through.
 function session.setTime(value) w.now=value>1e8 and value or 1795000100+value end
 function session.fire(event,...) w:Fire(c,event,...) end
 function session.display(alert)
  w.now=w.now+100
  if alert.key=='bountyAlert' then session.fire('PLAYER_TARGET_CHANGED')
  else session.fire('CHAT_MSG_ADDON','KWC3','2;WORLDDEATH;Rival;Hillsbrad','GUILD','Guildmate');w:Advance(0.75) end
 end
 return session
end

-- Placement: unlock, drag, save, reload, reset and bounded scale.
for _,scale in ipairs({0.5,1,1.5,2}) do
 local s=newSession({worldPvPDeathScale=scale,bountyAlertScale=scale})
 for i,alert in ipairs(s.alerts) do
  local ch,frame=alert.channel,alert.frame
  local other=s.alerts[3-i]
  local key=alert.key..'Position'
  local otherSaved=s.env.KWCDB.settings[other.key..'Position']
  ch:Initialize();near(frame:GetScale(),scale,'scale from SavedVariables')
  local moved=0
  frame.StartMoving=function() moved=moved+1 end
  frame.StopMovingOrSizing=function() end
  frame:GetScript('OnDragStart')(frame)
  assert(moved==0,'a locked alert must not move')
  ch:SetUnlocked(true)
  assert(frame:IsShown() and frame.hint:IsShown())
  frame:GetScript('OnDragStart')(frame);assert(moved==1)
  frame:ClearAllPoints();frame:SetPoint('TOPLEFT',s.env.UIParent,'TOPLEFT',100+i,-50-i)
  frame:GetScript('OnDragStop')(frame)
  local saved=s.env.KWCDB.settings[key]
  assert(saved.point=='TOPLEFT' and saved.x==100+i and saved.y==-50-i)
  assert(s.env.KWCDB.settings[other.key..'Position']==otherSaved)
  -- Automatic alerts never replace the card being positioned.
  assert(ch:Present({title='automatic'},true)==false)
  ch:SetScale(5);near(ch:Scale(),2,'upper bound');ch:SetScale(0.1);near(ch:Scale(),0.5,'lower bound');ch:SetScale(scale)
  assert(s.env.KWCDB.settings[key]==saved)
  ch:SetUnlocked(false);assert(not frame:IsShown() and not frame.hint:IsShown())
 end
 local restored={}
 for k,v in pairs(s.env.KWCDB.settings) do restored[k]=type(v)=='table' and H.DeepCopy(v) or v end
 local reload=newSession(restored)
 for i,alert in ipairs(reload.alerts) do
  alert.channel:Initialize()
  local point,_,_,x,y=alert.frame:GetPoint(1)
  assert(point=='TOPLEFT' and x==100+i and y==-50-i,'position after reload')
  near(alert.frame:GetScale(),scale,'scale after reload')
  alert.channel:Reset()
  assert(reload.env.KWCDB.settings[alert.key..'Position']==nil and alert.frame:GetPoint(1)=='TOP')
 end
 assert(#s.client.errors==0 and #reload.client.errors==0,s.client.errors[1] or reload.client.errors[1])
 print('PASS: both alert lifecycles at scale '..scale)
end

-- Bounty alert content, location fallback, duration, close and proximity.
local legacy={bountyAlertScale=0.75,bountyAlertPosition={nx=0.6,ny=0.6},
 worldPvPDeathDuration=12,bountySound=false,alertSound=false,guildmateAlerts=true,guildmateSound=true}
local session=newSession(legacy)
local env=session.env
local v=env.KWCDB.settings
local bounty,death=session.alerts[2],session.alerts[1]
env.KWCDB.bounties={{id='b1',status='ACTIVE',details={target='Rival',reward='5g'},sightings={{zone='Last Sighting'}}}}
env.GetRealZoneText=nil
assert(v.bountyAlertDuration==nil and bounty.api.GetDuration()==7)
bounty.channel:Initialize();near(bounty.frame:GetScale(),0.75,'legacy bounty scale')
assert(v.bountyAlertPosition.nx==0.6 and v.worldPvPDeathDuration==12 and v.bountySound==false)
assert(v.guildmateAlerts and v.guildmateSound and not env.KWC.GuildmateAlerts)
for _,event in ipairs({'PLAYER_TARGET_CHANGED','UPDATE_MOUSEOVER_UNIT'}) do
 assert(session.events[event] and #session.events[event]>=1,event)
end
session.setEnemy(false)
session.display(bounty)
assert(not bounty.frame:IsShown())
bounty.api.SetTestMode(true);session.display(bounty)
assert(bounty.frame:IsShown() and bounty.frame.kicker:GetText()=='FRIENDLY BOUNTY TEST')
bounty.frame:Hide();bounty.api.SetTestMode(false)
session.setEnemy(true)
session.display(bounty)
assert(bounty.frame.title:GetText()=='Rival-OtherRealm')
assert(bounty.frame.detail:GetText()=='Reward: 5g' and bounty.frame.meta:GetText()=='Last sighted: Last Sighting',bounty.frame.meta:GetText())
bounty.frame:Hide()
env.GetRealZoneText=function() return 'Current Zone' end
session.display(bounty)
assert(bounty.frame.meta:GetText()=='Current Zone')
bounty.api.SetDuration(3)
bounty.frame:GetScript('OnUpdate')(bounty.frame,2);assert(bounty.frame:IsShown())
bounty.frame:GetScript('OnUpdate')(bounty.frame,1.1)
assert(not bounty.frame:IsShown() and v.bountyAlertDuration==3)
bounty.api.Demo();bounty.frame.close:Click();assert(not bounty.frame:IsShown())
bounty.api.SetEnabled(false);bounty.frame:Hide();session.display(bounty)
assert(not bounty.frame:IsShown() and v.worldPvPDeathAlerts==nil)
local history=#(env.KWCDB.worldPvPDeaths or {})
death.api.Demo()
assert(death.frame:IsShown() and #(env.KWCDB.worldPvPDeaths or {})==history,'a preview records nothing')
assert(#session.client.errors==0,session.client.errors[1])
print('PASS: legacy settings, full bounty name, reward, location fallback, duration, close and proximity removal')

local smartSettings={}
local battle=newSession(smartSettings)
battle.setTime(900)
local api=battle.alerts[1].api
local banner=battle.alerts[1].frame
local function report(at,who)
 battle.setTime(at)
 battle.fire('CHAT_MSG_ADDON','KWC3','2;WORLDDEATH;Rival;Hillsbrad','GUILD',who)
 battle.world:Advance(0.75)
 battle.setTime(at)
end
local defaults=api.GetBattleSettings()
assert(defaults.threshold==5 and defaults.window==60 and defaults.quiet==90)
api.SetBattleSettings({threshold=2,window=15,quiet=30})
report(1000,'One')
assert(banner:IsShown())
banner:Hide()
report(1005,'ONE')
assert(not banner:IsShown() and #battle.messages()==1 and api.GetBattleStatus().unique==1,#battle.messages())
report(1015,'Two')
assert(api.GetBattleStatus().active and api.GetBattleStatus().unique==2)
assert(not banner:IsShown() and #battle.messages()==2)
report(1030,'Three')
assert(api.GetBattleStatus().quietRemaining==30)
report(1035,'Three')
assert(api.GetBattleStatus().quietRemaining==25 and #battle.messages()==3)
battle.env.KWCDB.bounties={{id='b1',status='ACTIVE',details={target='Rival',reward='5g'}}}
battle.fire('PLAYER_TARGET_CHANGED')
assert(battle.alerts[2].frame:IsShown(),'bounty alerts are independent of Smart Mode')
-- Visible alerts share a presentation queue; clear it before the next death.
battle.alerts[2].frame:Hide();battle.world:Advance(10)
battle.setTime(1060)
assert(not api.GetBattleStatus().active)
report(1061,'Four')
-- Four death lines: the bounty notice between them is not a death announcement.
assert(banner:IsShown() and #battle.messages()==4)
banner:Hide()
report(1077,'Five')
assert(banner:IsShown() and not api.GetBattleStatus().active and api.GetBattleStatus().unique==1)
report(1080,'Six')
assert(api.GetBattleStatus().active and api.GetBattleStatus().unique==2)
api.SetSmart(false)
assert(not api.GetBattleStatus().active)
report(1082,'Victim')
assert(banner:IsShown() and not api.GetBattleStatus().active)
api.SetBattleSettings({threshold=200,window=0,quiet='bad'})
local persisted=H.DeepCopy(battle.env.KWCDB.settings)
local restored=newSession(persisted).alerts[1].api.GetBattleSettings()
assert(restored.threshold==20 and restored.window==15 and restored.quiet==90)
api.ResetBattleSettings()
assert(battle.env.KWCDB.settings.worldPvPDeathSmart and api.GetBattleSettings().threshold==5)
print('PASS: Smart Mode limits, inclusive window, deduplication, rolling expiry, independent chat and bounty, persistence')

local life=newSession({})
life.env.UnitIsDeadOrGhost=function() return true end
life.env.KWC.Send=function() end
life.env.KWC.EventEvidence.Send=function() end
life.alerts[1].api.Report('Rival')
assert(#life.env.KWCDB.worldPvPDeaths==1)
life.setTime(life.world.now+30)
life.alerts[1].api.Report('Rival')
assert(#life.env.KWCDB.worldPvPDeaths==1)
life.env.UnitIsDeadOrGhost=function() return false end
life.fire('PLAYER_UNGHOST')
life.env.UnitIsDeadOrGhost=function() return true end
life.alerts[1].api.Report('Rival')
assert(#life.env.KWCDB.worldPvPDeaths==2)
print('PASS: local death reports deduplicate until resurrection')

local artwork=newSession({})
local deathBanner=artwork.alerts[1].frame
local selected
artwork.env.KWC.UI.OpenBountyForName=function(name) selected=name end
artwork.display(artwork.alerts[1])
assert(deathBanner.title:GetText()=='Guildmate was slain')
assert(deathBanner.detail:GetText()=='Reported attacker: Rival' and deathBanner.meta:GetText()=='Hillsbrad')
local bountyAction=deathBanner.actions[1]
assert(bountyAction:IsShown() and bountyAction.text:GetText()=='Post bounty')
bountyAction:Click()
assert(selected=='Rival')
artwork.setTime(artwork.world.now+100)
artwork.fire('CHAT_MSG_ADDON','KWC3','2;WORLDDEATH;Suspected: Scout;Arathi','GUILD','ScoutFriend')
artwork.world:Advance(0.75)
assert(deathBanner.detail:GetText()=='Suspected attacker: Scout' and deathBanner.meta:GetText()=='Arathi')
assert(deathBanner.actions[1].text:GetText()~='Post bounty','a suspicion offers no bounty')

-- Actual production death handlers; forbidden APIs are intentionally absent.
local function deathSession()
 local s=newSession({})
 s.sent={}
 s.env.UnitIsDeadOrGhost=function() return true end
 s.env.GetRealZoneText=function() return 'Hillsbrad Foothills' end
 local send=s.env.KWC.Send
 s.env.KWC.Send=function(kind,payload) if kind=='WORLDDEATH' then table.insert(s.sent,{kind,payload}) end;return send(kind,payload) end
 s.env.C_DeathRecap={GetRecapEvents=function() return s.recap end}
 s.env.C_Timer=nil
 s.api=s.alerts[1].api
 s.banner=s.alerts[1].frame
 s.base=s.env.time()
 return s
end
-- Recap times are relative to the session clock (1000 stands for "now").
local current
local function hit(name,stamp,flags,event)
 return {sourceName=name,sourceGUID='Player-123',sourceFlags=flags or 0x540,
  timestamp=current.base+((stamp or 1000)-1000),amount=100,event=event or 'SWING_DAMAGE'}
end
local confirmed=deathSession()
current=confirmed
confirmed.recap={hit('Enemy-Realm'),hit('Other-Realm')}
confirmed.fire('PLAYER_DEAD')
assert(#confirmed.sent==1 and confirmed.sent[1][1]=='WORLDDEATH')
assert(confirmed.banner.detail:GetText()=='Killed by: Enemy-Realm')
assert(confirmed.sent[1][2]=='Killed by: Enemy-Realm;Hillsbrad Foothills')
confirmed.fire('PLAYER_DEAD')
assert(#confirmed.sent==1)
local receiving=deathSession()
current=receiving
receiving.fire('CHAT_MSG_ADDON','KWC3','2;WORLDDEATH;'..confirmed.sent[1][2],'GUILD','Victim');receiving.world:Advance(0.75)
assert(receiving.banner.detail:GetText()=='Killed by: Enemy-Realm')
receiving.fire('CHAT_MSG_ADDON','KWC3','2;WORLDDEATH;'..confirmed.sent[1][2],'GUILD','Victim');receiving.world:Advance(0.75)
assert(#receiving.env.KWCDB.worldPvPDeaths==1)
assert(#receiving.env.KWCDB.bounties==0) -- no automatic bounty creation
confirmed.banner:Hide();confirmed.world:Advance(10)
current=confirmed;confirmed.base=confirmed.env.time()
confirmed.env.UnitIsDeadOrGhost=function() return false end
confirmed.setTime(confirmed.base+1);confirmed.fire('PLAYER_UNGHOST')
confirmed.env.UnitIsDeadOrGhost=function() return true end
confirmed.recap={hit('Dot-Realm',1001,nil,'SPELL_PERIODIC_DAMAGE')}
confirmed.fire('PLAYER_DEAD')
assert(#confirmed.sent==2 and confirmed.banner.detail:GetText()=='Killed by: Dot-Realm')
for _,flags in ipairs({0x240,0,0x510}) do
 local s=deathSession();current=s
 s.recap={hit('NPC',1000,flags),hit('Enemy-Realm')}
 s.fire('PLAYER_DEAD')
 assert(#s.sent==0,'NPC/environment/friendly finishing damage must not report PvP')
end
for _,flags in ipairs({0x1140,0x2140}) do
 local s=deathSession();current=s
 s.recap={hit('Pet',1000,flags),hit('Other-Realm')}
 s.fire('PLAYER_DEAD')
 assert(#s.sent==1 and s.banner.detail:GetText()=='Attacker unidentified')
end
local suspected=deathSession()
current=suspected
suspected.recap={hit(nil),hit('Recent-Realm')}
suspected.fire('PLAYER_DEAD')
-- A name carried by the same attacker GUID identifies the attacker.
assert(suspected.banner.detail:GetText()=='Killed by: Recent-Realm')
-- A name from a different attacker is never borrowed for the finishing blow.
local other=deathSession();current=other
local nameless,named=hit(nil),hit('Bystander-Realm');named.sourceGUID='Player-999'
other.recap={nameless,named};other.fire('PLAYER_DEAD')
assert(#other.sent==1 and other.banner.detail:GetText()=='Attacker unidentified')
local unknown=deathSession()
current=unknown
unknown.recap={hit(nil)}
unknown.fire('PLAYER_DEAD')
assert(unknown.banner.detail:GetText()=='Attacker unidentified')
for _,recap in ipairs({function() return {} end,function() return {hit('Old',900)} end,function() return {hit('Future',1100)} end,function() return {hit('NPC',1000,0,'ENVIRONMENTAL_DAMAGE')} end}) do
 local s=deathSession();current=s;s.recap=recap();s.fire('PLAYER_DEAD');assert(#s.sent==0)
end
local absent=deathSession()
current=absent
absent.env.C_DeathRecap=nil;absent.fire('PLAYER_DEAD');assert(#absent.sent==0)
absent.api.Report('Manual');assert(#absent.sent==1,'Manual fallback remains available')
local restricted=deathSession()
current=restricted
restricted.env.C_DeathRecap.GetRecapEvents=function() error('restricted') end
restricted.fire('PLAYER_DEAD');assert(#restricted.sent==0)
local bg=deathSession()
current=bg
bg.client.instance='pvp'
bg.recap={hit('Enemy')};bg.fire('PLAYER_DEAD');assert(#bg.sent==0)
local async=deathSession()
current=async
local timers={}
-- Keep only the death recap attempts (0.3s then 0.7s); other modules schedule too.
async.env.C_Timer={After=function(delay,fn) if delay==0.3 or delay==0.7 then timers[#timers+1]=fn end end}
async.fire('PLAYER_DEAD');async.fire('PLAYER_DEAD')
assert(#timers==1)
table.remove(timers,1)();assert(#timers==1 and #async.sent==0)
async.recap={hit('Delayed')}
table.remove(timers,1)();assert(#async.sent==1)
local cancelled=deathSession()
current=cancelled
-- Keep only the death recap attempts (0.3s then 0.7s); other modules schedule too.
cancelled.env.C_Timer={After=function(delay,fn) if delay==0.3 or delay==0.7 then timers[#timers+1]=fn end end}
cancelled.fire('PLAYER_DEAD')
cancelled.env.UnitIsDeadOrGhost=function() return false end
cancelled.fire('PLAYER_UNGHOST')
cancelled.recap={hit('Stale')};table.remove(timers,1)();assert(#cancelled.sent==0)
local reloaded=deathSession()
current=reloaded
reloaded.setTime(reloaded.base+100);reloaded.env.UnitIsDeadOrGhost=function() return false end
reloaded.fire('PLAYER_ALIVE');reloaded.recap={hit('Old')};reloaded.fire('PLAYER_DEAD')
assert(#reloaded.sent==0)
local secret=deathSession()
current=secret
secret.env.issecretvalue=function(v) return v=='SECRET' end
secret.recap={hit('SECRET')};secret.fire('PLAYER_DEAD')
assert(secret.banner.detail:GetText()=='Attacker unidentified')
assert(not confirmed.events.COMBAT_LOG_EVENT_UNFILTERED and not confirmed.events.COMBAT_LOG_EVENT)
print('PASS: death recap evidence, confidence, DoT, pets, NPC/environment, retries, reset, wire compatibility, no auto bounty')

local invalid=deathSession()
current=invalid
invalid.recap={hit('Enemy',1000,nil,'SPELL_HEAL')}
invalid.fire('PLAYER_DEAD');assert(#invalid.sent==0)
local enriched=deathSession()
current=enriched
-- The attacker is the targeted unit; the player keeps a different identity.
enriched.env.UnitGUID=function(unit) return unit=='player' and 'Player-1-00000001' or unit=='target' and 'Player-123' or nil end
enriched.env.UnitClass=function() return 'Rogue' end
enriched.env.UnitFactionGroup=function(unit) return unit=='player' and 'Horde' or 'Alliance' end
enriched.recap={hit('Real-Realm')};enriched.fire('PLAYER_DEAD')
local evidence=enriched.env.KWCDB.worldPvPDeaths[1].evidence
assert(evidence.name=='Real-Realm' and evidence.class=='Rogue' and evidence.faction=='Alliance')
local malformed=deathSession()
current=malformed
malformed.recap={hit('Bad;Name')};malformed.fire('PLAYER_DEAD')
assert(malformed.banner.detail:GetText()=='Attacker unidentified')
malformed.fire('CHAT_MSG_ADDON','KWC3','2;WORLDDEATH;|cBad;Zone','GUILD','Peer');malformed.world:Advance(0.75)
assert(#malformed.env.KWCDB.worldPvPDeaths==1)
local bounded=deathSession();current=bounded;bounded.recap={}
for i=1,50 do bounded.recap[i]=hit('Enemy'..i) end
bounded.fire('PLAYER_DEAD');assert(#bounded.api.recentDamage==32 and #bounded.sent==1)
print('PASS: malformed names/messages, non-damage events, GUID-matched metadata, bounded history')
