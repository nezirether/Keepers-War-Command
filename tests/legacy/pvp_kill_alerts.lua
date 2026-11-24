-- V4.8 Guild PvP Kill alerts. Run from the repository root with Lua 5.1/LuaJIT.
-- Two simulated clients: a killer whose addon detects its own honorable kill
-- and broadcasts WORLDKILL, and a guildmate whose addon shows the alert.
local noop=function() end
local function object(extra)
 local o=extra or {}
 o.shown=o.shown==nil and true or o.shown
 o.texts=o.texts or {}
 return setmetatable(o,{__index=function(t,k)
  if k=='Show' then return function(self) self.shown=true end end
  if k=='Hide' then return function(self) self.shown=false end end
  if k=='IsShown' then return function(self) return self.shown end end
  if k=='SetShown' then return function(self,v) self.shown=not not v end end
  if k=='SetText' then return function(self,v) self.text=v end end
  if k=='GetText' then return function(self) return self.text end end
  if k=='SetScript' then return function(self,e,f) self['on'..e]=f end end
  if k=='GetWidth' then return function() return 800 end end
  if k=='GetHeight' then return function() return 320 end end
  if k=='GetEffectiveScale' then return function() return 1 end end
  if k=='GetScale' then return function() return 1 end end
  if k=='GetFrameLevel' then return function() return 1 end end
  if k=='CreateFontString' then return function(self) local f=object({shown=true});self.texts[#self.texts+1]=f;return f end end
  if k=='CreateTexture' then return function(self) local t=object();local list=rawget(self,'tex') or {};rawset(self,'tex',list);list[#list+1]=t;t.SetTexture=function(s,p) s.path=p end;return t end end
  return noop
 end})
end

local function newClient(name)
 local env=setmetatable({},{__index=_G})
 local events,timers,said,sent={}, {}, {}, {}
 local c={env=env,events=events,said=said,sent=sent,timers=timers,frames={}}
 c.now=1000;c.session=5;c.lifetime=100;c.allowed=true;c.combat=false;c.sounds=0;c.zone='Ashenvale'
 env.UIParent=object({GetWidth=function() return 1920 end,GetHeight=function() return 1080 end})
 env.KWCDB={settings={}}
 env.KWC={
  On=function(e,f) events[e]=events[e] or {};table.insert(events[e],f) end,
  IsMember=function(sender) return sender~='Stranger-Realm' end,
  Say=function(m) said[#said+1]=m end,
  Now=function() return c.now end,
  Clean=function(s,n) s=tostring(s or ''):gsub('[|\r\n]','');return s:sub(1,n or 255) end,
  GuildScope=function() return c.scope or '42' end,
  Send=function(kind,payload) sent[#sent+1]=kind..';'..payload;if c.route then c.route(kind,payload) end;return true end,
  InstanceAlerts={Allowed=function() return c.allowed end,Token=function() return c.allowed end,OnSuppressed=noop},
 }
 env.time=function() return c.now end
 env.IsInGuild=function() return true end
 env.UnitName=function(unit) if unit=='player' then return name,nil end;return c.unitNames and c.unitNames[unit] end
 env.GetRealmName=function() return 'Realm' end
 env.UnitExists=function(u) return c.unitNames and c.unitNames[u]~=nil end
 env.UnitIsPlayer=function() return true end
 env.UnitIsUnit=function(a,b) return a==b end
 env.UnitIsEnemy=function() return true end
 env.UnitAffectingCombat=function() return c.combat end
 env.GetRealZoneText=function() return c.zone end
 env.GetPVPSessionStats=function() if c.session==nil then error('unreadable') end;return c.session,0 end
 env.GetPVPLifetimeStats=function() if c.lifetime==nil then error('unreadable') end;return c.lifetime,0,0 end
 env.PlaySound=function() c.sounds=c.sounds+1 end
 env.COMBATLOG_HONORGAIN='%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)'
 env.C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
 env.CreateFrame=function(kind,fname,parent)
  local f=object({shown=true,kind=kind})
  if fname then c.frames[fname]=f end
  return f
 end
 for _,file in ipairs({'AlertFrameControls','WorldPvPKills'}) do
  setfenv(assert(loadfile('KeepersWarCommand/'..file..'.lua')),env)()
 end
 c.api=env.KWC.WorldPvPKills
 c.banner=c.frames.KWC_WorldPvPKillBanner
 assert(c.banner,'kill banner created')
 c.banner.shown=false
 function c.fire(e,...) for _,f in ipairs(events[e] or {}) do f(...) end end
 function c.flush() while #timers>0 do table.remove(timers,1)() end end
 function c.lines() local out={};for _,t in ipairs(c.banner.texts) do if t.text then out[#out+1]=t.text end end;return table.concat(out,' | ') end
 function c.reset() for i=#said,1,-1 do said[i]=nil end;for i=#sent,1,-1 do sent[i]=nil end;c.sounds=0;c.banner.shown=false end
 return c
end

local killer=newClient('Nez')
local mate=newClient('Pal')
killer.route=function(kind,payload) mate.fire('CHAT_MSG_ADDON','KWC3','2;'..kind..';'..payload,'GUILD','Nez-Realm') end
-- Login baseline, then let the 10 s settle window pass.
killer.fire('PLAYER_LOGIN');mate.fire('PLAYER_LOGIN')
killer.now=killer.now+30;mate.now=mate.now+30

-- 1. A named kill: honor chat names the victim, the HK count rises by one.
killer.fire('CHAT_MSG_COMBAT_HONOR_GAIN','Bob dies, honorable kill Rank: Private (Estimated Honor Points: 12)')
killer.session=6
killer.fire('PLAYER_PVP_KILLS_CHANGED','player')
killer.flush()
assert(#killer.sent==1 and killer.sent[1]=='WORLDKILL;Bob;1;Ashenvale','named kill broadcast: '..tostring(killer.sent[1]))
assert(killer.banner.shown and killer.lines():find('Nez slew Bob',1,true),'killer sees own alert: '..killer.lines())
assert(mate.banner.shown,'guildmate popup shown')
assert(mate.lines():find('ENEMY SLAIN',1,true) and mate.lines():find('Nez slew Bob',1,true) and mate.lines():find('Ashenvale',1,true),mate.lines())
assert(mate.said[1]=='WORLD PVP: Nez slew Bob in Ashenvale.','guildmate chat: '..tostring(mate.said[1]))
assert(mate.sounds==1 and killer.sounds==1,'sound on both clients')
assert(mate.env.KWCDB.worldPvPKills[1].victim=='Bob','kill recorded')
print('PASS: a named open-world kill is broadcast and shown to guildmates with chat, popup and sound')

-- 2. Counter-only kill (no readable victim) says so instead of guessing.
killer.reset();mate.reset();killer.now=killer.now+20;mate.now=mate.now+20
killer.session=7;killer.fire('PLAYER_PVP_KILLS_CHANGED','player');killer.flush()
assert(killer.sent[1]=='WORLDKILL;-;1;Ashenvale',tostring(killer.sent[1]))
assert(mate.lines():find('Nez scored a kill',1,true) and mate.lines():find('victim not identified',1,true),mate.lines())
print('PASS: an unnamed honorable kill is reported without inventing a victim')

-- 3. The event unit names the victim when readable.
killer.reset();mate.reset();killer.now=killer.now+20;mate.now=mate.now+20
killer.unitNames={nameplate3='Carl'}
killer.session=8;killer.fire('PLAYER_PVP_KILLS_CHANGED','nameplate3');killer.flush()
assert(killer.sent[1]=='WORLDKILL;Carl;1;Ashenvale',tostring(killer.sent[1]))
killer.unitNames=nil
print('PASS: PLAYER_PVP_KILLS_CHANGED unit names the victim when readable')

-- 4. Several kills in one burst become one report with a count.
killer.reset();mate.reset();killer.now=killer.now+20;mate.now=mate.now+20
killer.fire('CHAT_MSG_COMBAT_HONOR_GAIN','Dan dies, honorable kill Rank: Scout (Estimated Honor Points: 9)')
killer.fire('CHAT_MSG_COMBAT_HONOR_GAIN','Eve dies, honorable kill Rank: Scout (Estimated Honor Points: 9)')
killer.session=10;killer.fire('PLAYER_PVP_KILLS_CHANGED','player');killer.fire('PLAYER_PVP_KILLS_CHANGED','player');killer.flush()
assert(#killer.sent==1 and killer.sent[1]=='WORLDKILL;Dan;2;Ashenvale',tostring(killer.sent[1]))
assert(mate.lines():find('2 honorable kills',1,true),mate.lines())
print('PASS: a burst of kills is batched into one report')

-- 5. Not reported: instance, broadcast off, catch-up jump, settle window, no new HK.
local function attempt(setup,label)
 killer.reset();mate.reset();killer.now=killer.now+20;mate.now=mate.now+20
 setup()
 killer.session=killer.session+1;killer.fire('PLAYER_PVP_KILLS_CHANGED','player');killer.flush()
 assert(#killer.sent==0 and not mate.banner.shown,label)
end
attempt(function() killer.allowed=false end,'instance kill not reported');killer.allowed=true
attempt(function() killer.env.KWCDB.settings.pvpKillBroadcast=false end,'broadcast off');killer.env.KWCDB.settings.pvpKillBroadcast=nil
attempt(function() killer.session=killer.session+20 end,'catch-up jump ignored')
attempt(function() killer.fire('PLAYER_ENTERING_WORLD') end,'settle window after zoning')
killer.now=killer.now+30
killer.reset();killer.fire('PLAYER_PVP_KILLS_CHANGED','player');killer.flush()
assert(#killer.sent==0,'signal without a new HK sends nothing')
print('PASS: instance, broadcast-off, catch-up, zoning and no-change cases send nothing')

-- 6. Lifetime count is used when session stats are unreadable.
killer.reset();mate.reset();killer.now=killer.now+20;mate.now=mate.now+20
killer.session=nil;killer.fire('PLAYER_PVP_KILLS_CHANGED','player');killer.flush() -- rebase on lifetime
killer.lifetime=killer.lifetime+1;killer.fire('PLAYER_PVP_KILLS_CHANGED','player');killer.flush()
assert(killer.sent[1]=='WORLDKILL;-;1;Ashenvale' and killer.api.lastSource=='lifetime HKs',tostring(killer.sent[1]))
killer.session=20
print('PASS: lifetime HKs are the fallback count source')

-- 7. Receiver settings: popup off keeps chat; chat off; hide in combat; sound off.
local function receive(payload,sender)
 mate.reset();mate.now=mate.now+10
 mate.fire('CHAT_MSG_ADDON','KWC3','2;WORLDKILL;'..payload,'GUILD',sender or 'Nez-Realm')
end
local s=mate.env.KWCDB.settings
mate.api.SetSmart(false) -- isolate per-setting checks from Smart Mode (tested in 8)
mate.api.SetEnabled(false);receive('Fay;1;Duskwood')
assert(not mate.banner.shown and mate.said[1]=='WORLD PVP: Nez slew Fay in Duskwood.','popup off keeps chat')
mate.api.SetEnabled(true);mate.api.SetChat(false);receive('Gus;1;Duskwood')
assert(mate.banner.shown and #mate.said==0,'chat off keeps popup')
mate.api.SetChat(true);mate.api.SetCombatSuppression(true);mate.combat=true;receive('Hal;1;Duskwood')
assert(not mate.banner.shown,'hidden in combat')
mate.combat=false;mate.api.SetCombatSuppression(false);mate.api.SetSound(false);receive('Ivy;1;Duskwood')
assert(mate.banner.shown and mate.sounds==0,'sound off')
mate.api.SetSound(true)
mate.api.SetDuration(12);assert(s.pvpKillDuration==12)
mate.api.SetDuration(99);assert(s.pvpKillDuration==30)
assert(type(mate.api.SetScale)=='function' and type(mate.api.ResetPosition)=='function' and type(mate.api.SetUnlocked)=='function')
print('PASS: popup, chat, combat, sound and duration settings behave like the death alert')

-- 8. Smart Mode suppresses popups during heavy guild PvP, chat continues.
mate.now=mate.now+400;mate.api.SetSmart(true)
mate.api.SetBattleSettings({threshold=3,window=60,quiet=90})
local shownCount=0
for i,v in ipairs({'Jo','Ki','Lu','Mo'}) do
 receive(v..';1;Duskwood','Nez-Realm')
 if mate.banner.shown then shownCount=shownCount+1 end
end
assert(shownCount==2,'popups suppressed from the threshold onward: '..shownCount)
assert(mate.api.GetBattleStatus().active,'quiet period active')
mate.api.SetSmart(false);receive('Ned;1;Duskwood')
assert(mate.banner.shown,'Smart Mode off shows again')
mate.api.ResetBattleSettings()
assert(s.pvpKillThreshold==5 and s.pvpKillWindow==60 and s.pvpKillQuiet==90 and s.pvpKillSmart==true)
print('PASS: Smart Mode thresholds, quiet period and reset')

-- 9. Validation: malformed, non-member, self, duplicate and instance-suppressed messages.
mate.api.SetSmart(false)
for _,bad in ipairs({'Bob|cff;1;Zone','Bob;0;Zone','Bob;11;Zone','Bob;1','Bob;x;Zone',string.rep('a',60)..';1;Zone'}) do
 receive(bad);assert(not mate.banner.shown and #mate.said==0,'rejected: '..bad)
end
receive('Bob;1;Zone','Stranger-Realm');assert(not mate.banner.shown,'non-member rejected')
receive('Bob;1;Zone','Pal-Realm');assert(not mate.banner.shown,'own echo ignored')
mate.reset();mate.fire('CHAT_MSG_ADDON','KWC3','2;WORLDKILL;Zed;1;Zone','GUILD','Nez-Realm')
assert(mate.banner.shown)
mate.banner.shown=false;mate.fire('CHAT_MSG_ADDON','KWC3','2;WORLDKILL;Zed;1;Zone','GUILD','Nez-Realm')
assert(not mate.banner.shown,'duplicate within 4s ignored')
mate.allowed=false;receive('Quinn;1;Zone');assert(not mate.banner.shown and #mate.said==0,'receiver in an instance shows nothing')
mate.allowed=true
mate.fire('CHAT_MSG_ADDON','KWC3','2;WORLDKILL;Bob;1;Zone','PARTY','Nez-Realm')
print('PASS: malformed, non-member, self, duplicate, wrong-channel and instance cases are rejected')

-- 10. Test preview sends nothing.
killer.reset();killer.api.Demo()
assert(killer.banner.shown and #killer.sent==0 and killer.sounds==1,'preview is local only')
print('PASS: Test Alert is a local preview and sends no guild message')

-- V4.9 regressions -------------------------------------------------------------
-- 11. Session-to-lifetime source switch never reports one kill twice.
do
 local k=newClient('Ari');local sent=0
 k.route=function() sent=sent+1 end
 k.fire('PLAYER_LOGIN');k.now=k.now+30
 k.session=k.session+1;k.fire('PLAYER_PVP_KILLS_CHANGED','player');k.flush()
 assert(sent==1,'first kill reported once')
 -- Session stats become unreadable while the lagging lifetime total catches up.
 k.now=k.now+5;k.session=nil;k.lifetime=k.lifetime+1
 k.fire('PLAYER_PVP_KILLS_CHANGED','player');k.flush()
 assert(sent==1,'lifetime catch-up after a session-counted kill is not a second kill')
 -- From then on lifetime is the established source and new kills still report.
 k.now=k.now+5;k.lifetime=k.lifetime+1;k.fire('PLAYER_PVP_KILLS_CHANGED','player');k.flush()
 assert(sent==2 and k.api.lastSource=='lifetime HKs','lifetime source works once re-established')
 print('PASS: switching HK count sources never double counts a kill')
end
-- 12. Daily session reset: a lower session count still reports the new kill.
do
 local k=newClient('Bo');local got
 k.route=function(_,payload) got=payload end
 k.session=9;k.fire('PLAYER_LOGIN');k.now=k.now+30
 k.session=k.session+1;k.fire('PLAYER_PVP_KILLS_CHANGED','player');k.flush()
 assert(got=='-;1;Ashenvale','kill after daily reset reported: '..tostring(got))
 print('PASS: a kill right after the daily session reset is reported once')
end
-- 13. A battleground kill's victim name is never attached to a later open-world kill.
do
 local k=newClient('Cy');local got,sent={},0
 k.route=function(_,payload) sent=sent+1;got[#got+1]=payload end
 k.fire('PLAYER_LOGIN');k.now=k.now+30
 k.allowed=false
 k.fire('CHAT_MSG_COMBAT_HONOR_GAIN','Zed dies, honorable kill Rank: Scout (Estimated Honor Points: 9)')
 k.session=k.session+1;k.fire('PLAYER_PVP_KILLS_CHANGED','player');k.flush()
 assert(sent==0,'battleground kill not broadcast')
 k.allowed=true;k.fire('PLAYER_ENTERING_WORLD');k.now=k.now+12
 k.session=k.session+1;k.fire('PLAYER_PVP_KILLS_CHANGED','player');k.flush()
 assert(sent==1 and got[1]=='-;1;Ashenvale','outdoor kill is not named after the battleground victim: '..tostring(got[1]))
 print('PASS: battleground kills are not broadcast and their names never leak into outdoor alerts')
end
-- 14. Kill alerts and receiver alerts in instances: nothing on either side.
do
 local a,b=newClient('Dee'),newClient('Eli')
 a.route=function(kind,payload) b.fire('CHAT_MSG_ADDON','KWC3','2;'..kind..';'..payload,'GUILD','Dee-Realm') end
 a.fire('PLAYER_LOGIN');a.now=a.now+30
 b.allowed=false
 a.session=a.session+1;a.fire('PLAYER_PVP_KILLS_CHANGED','player');a.flush()
 assert(#a.sent==1 and not b.banner.shown and #b.said==0 and b.sounds==0,'receiver in a battleground gets no popup, chat or sound')
 -- Same report delivered twice (e.g. a relay or re-send): one alert only.
 b.allowed=true;b.reset()
 b.fire('CHAT_MSG_ADDON','KWC3','2;WORLDKILL;Fin;1;Barrens','GUILD','Dee-Realm')
 b.fire('CHAT_MSG_ADDON','KWC3','2;WORLDKILL;Fin;1;Barrens','GUILD','Dee-Realm')
 assert(#b.said==1 and b.sounds==1,'duplicate delivery shows one alert')
 print('PASS: no kill alert inside instances; duplicate deliveries alert once')
end
