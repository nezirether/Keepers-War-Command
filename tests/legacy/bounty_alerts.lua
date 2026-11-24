-- Run from the repository root with Lua 5.1: lua tests/bounty_alerts.lua
-- Headless regression suite for automatic bounty detection reliability.
local noop=function() end
local SECRET=setmetatable({},{__tostring=function() error('secret value was stringified') end,
 __concat=function() error('secret value was concatenated') end,
 __eq=function() error('secret value was compared') end})

local function newSession(opts)
 opts=opts or {}
 local env=setmetatable({},{__index=_G})
 local events,frames={},{}
 local s={env=env,events=events,frames=frames,now=1000,sounds=0,chat={},opened={},
  units={},zone='Hillsbrad Foothills',instance={false,'none'},plates={}}
 env.KWCDB={settings=opts.settings or {},bounties=opts.bounties or {
  {id='B1',status='ACTIVE',details={target='Rival',reward='5g',location='Tarren Mill'},
   sightings={{zone='Alterac Mountains',at='2026-11-15 12:00'}}},
 },deletions=opts.deletions}
 env.KWC={
  On=function(event,fn) events[event]=events[event] or {};table.insert(events[event],fn) end,
  Say=function(m) table.insert(s.chat,m) end,
  GuildScope=function() return 'club-1' end,
  Send=function() error('bounty alerts must not send guild traffic') end,
  UI={OpenBountySighting=function(id,zone) table.insert(s.opened,{id=id,zone=zone});return true end},
  AlertFrameControls={Attach=function()
   return {Initialize=noop,SetUnlocked=noop,SetScale=noop,Reset=noop}
  end},
 }
 env.time=function() return s.now end
 env.wipe=function(t) for k in pairs(t) do t[k]=nil end end
 env.PlaySound=function() s.sounds=s.sounds+1 end
 env.GetRealZoneText=function() return s.zone end
 env.IsInInstance=function() return s.instance[1],s.instance[2] end
 env.GetInstanceInfo=function() return 'Zone',s.instance[2] end
 env.UnitExists=function(u) return s.units[u]~=nil end
 env.UnitIsPlayer=function(u) local d=s.units[u];if not d then return false end;if d.player==nil then return true end;return d.player end
 env.UnitCanAttack=function(_,u) local d=s.units[u];if not d then return false end;if d.enemy==nil then return true end;return d.enemy end
 env.UnitName=function(u)
  if u=='player' then return 'Me' end
  local d=s.units[u];if d then return d.name,d.realm end
 end
 env.UnitIsUnit=function(a,b) return a==b or (b=='player' and s.units[a] and s.units[a].self) or false end
 env.C_NamePlate={GetNamePlates=function() return s.plates end}

 local function region()
  local r={shown=false}
  return setmetatable(r,{__index=function(_,k)
   if k=='SetText' then return function(self,v) self.text=v end end
   if k=='SetShown' then return function(self,v) self.shown=not not v end end
   if k=='Show' then return function(self) self.shown=true end end
   if k=='Hide' then return function(self) self.shown=false end end
   if k=='IsShown' then return function(self) return self.shown end end
   return noop
  end})
 end
 env.CreateFrame=function(kind,name,parent)
  local f={kind=kind,name=name,shown=true,scripts={},text={}}
  setmetatable(f,{__index=function(_,k)
   if k=='SetScript' then return function(self,e,fn) self.scripts[e]=fn end end
   if k=='Show' then return function(self) self.shown=true end end
   if k=='Hide' then return function(self) self.shown=false end end
   if k=='SetShown' then return function(self,v) self.shown=not not v end end
   if k=='IsShown' then return function(self) return self.shown end end
   if k=='SetText' then return function(self,v) self.value=v end end
   if k=='CreateFontString' then return function(self) local r=region();table.insert(self.text,r);return r end end
   if k=='CreateTexture' then return function() return region() end end
   return noop
  end})
  if name then frames[name]=f end
  table.insert(frames,f)
  return f
 end
 setfenv(assert(loadfile('KeepersWarCommand/InstanceAlerts.lua')),env)()
 setfenv(assert(loadfile('KeepersWarCommand/BountyAlerts.lua')),env)()
 s.api=env.KWC.BountyAlerts
 s.banner=frames.KWC_BountyAlertBanner
 s.report=frames.KWC_BountySightingButton
 for _,f in ipairs(frames) do
  -- rawget: the mock's __index returns noop for absent keys such as name.
  if rawget(f,'name')==nil and f.kind=='Frame' and f.scripts.OnUpdate then s.poll=f end
 end
 assert(s.banner and s.report and s.poll,'bounty alert frames were not created')
 function s.fire(event,...) for _,fn in ipairs(events[event] or {}) do fn(...) end end
 function s.location() return s.banner.text[4].text end
 function s.target() return s.banner.text[2].text end
 function s.tick(seconds) s.now=s.now+seconds;s.poll.scripts.OnUpdate(s.poll,1.5) end
 function s.alerts() local n=0;for _,m in ipairs(s.chat) do if m:find('^BOUNTY SPOTTED') or m:find('^TEST FRIENDLY') then n=n+1 end end;return n end
 function s.reset() s.banner:Hide();s.chat={};s.sounds=0 end
 return s
end

-- 1. Target, mouseover and nameplate detection; live location; sound.
do
 local s=newSession()
 s.units.target={name='Rival',realm='OtherRealm'}
 s.fire('PLAYER_TARGET_CHANGED')
 assert(s.banner:IsShown() and s.target()=='Rival-OtherRealm')
 assert(s.location()=='Hillsbrad Foothills','live zone is shown unlabelled')
 assert(s.chat[1]=='BOUNTY SPOTTED: Rival in Hillsbrad Foothills.')
 assert(s.sounds==1 and s.report:IsShown())
 s.report.scripts.OnClick(s.report)
 assert(s.opened[1].id=='B1' and s.opened[1].zone=='Hillsbrad Foothills','Report Sighting is prefilled with the live zone')
 assert(not s.banner:IsShown())

 local m=newSession()
 m.units.mouseover={name='Rival'}
 m.fire('UPDATE_MOUSEOVER_UNIT')
 assert(m.banner:IsShown() and m.alerts()==1)

 local n=newSession()
 n.units.nameplate4={name='Rival'}
 n.fire('NAME_PLATE_UNIT_ADDED','nameplate4')
 assert(n.banner:IsShown() and n.alerts()==1)

 local p=newSession()
 p.units.nameplate7={name='Rival'}
 p.plates={{namePlateUnitToken='nameplate7'}}
 p.tick(2)
 assert(p.banner:IsShown() and p.alerts()==1,'poll scans exposed nameplates')
 local u=newSession()
 u.units.nameplate2={name='Rival'}
 u.plates={{UnitFrame={unit='nameplate2'}}}
 u.tick(2)
 assert(u.alerts()==1,'poll falls back to the plate UnitFrame unit')
 print('PASS: target, mouseover, nameplate event and nameplate poll detection with live zone and sound')
end

-- 2. Continuous visibility suppression and cooldown.
do
 local s=newSession()
 s.units.nameplate1={name='Rival'}
 s.plates={{namePlateUnitToken='nameplate1'}}
 for _=1,200 do s.tick(2) end -- 400 seconds continuously visible
 assert(s.alerts()==1 and s.sounds==1,'a continuously visible target alerts once, got '..s.alerts())
 -- Retargeting the same visible player does not re-alert either.
 s.units.target={name='Rival'}
 s.fire('PLAYER_TARGET_CHANGED')
 assert(s.alerts()==1)
 -- A short gap (below the visibility grace) is still the same episode.
 s.units.target=nil;s.units.nameplate1=nil
 s.tick(5)
 s.units.nameplate1={name='Rival'}
 s.tick(2)
 assert(s.alerts()==1,'brief nameplate flicker must not re-alert')
 -- Leave for longer than the grace and the cooldown: a new episode alerts.
 s.units.nameplate1=nil
 for _=1,50 do s.tick(2) end
 s.units.nameplate1={name='Rival'}
 s.tick(2)
 assert(s.alerts()==2,'a new sighting after cooldown alerts again')

 -- Out of view longer than the grace but within the cooldown: suppressed.
 local c=newSession()
 c.units.target={name='Rival'}
 c.fire('PLAYER_TARGET_CHANGED')
 c.units.target=nil
 c.now=c.now+30
 c.units.target={name='Rival'}
 c.fire('PLAYER_TARGET_CHANGED')
 assert(c.alerts()==1,'cooldown suppresses a quick reappearance')
 c.units.target=nil
 c.now=c.now+90
 c.units.target={name='Rival'}
 c.fire('PLAYER_TARGET_CHANGED')
 assert(c.alerts()==2,'cooldown measured from the last alert, not the last sighting')
 -- Re-enabling clears suppression.
 c.api.SetEnabled(true)
 assert(c.alerts()==3)
 print('PASS: one alert per continuous sighting, flicker tolerance, cooldown, re-enable reset')
end

-- 3. Instance suppression (InstanceAlerts.lua). Automatic bounty alerts appear only
-- in the confirmed open world. The battleground opt-in is retired: the command
-- explains the change and a previously saved value is left untouched.
do
 local s=newSession({settings={bountyAlertsInPvPInstances=true}})
 s.units.target={name='Rival'}
 s.instance={true,'pvp'}
 s.fire('PLAYER_TARGET_CHANGED')
 assert(not s.banner:IsShown() and s.alerts()==0 and s.sounds==0,'battleground suppressed despite a legacy opt-in')
 assert(s.api.Muted()==true and s.api.PvPInstanceAlerts()==false)
 s.api.SetPvPInstanceAlerts(true)
 assert(s.chat[#s.chat]:find('no longer a separate option',1,true),'retired command explains the change')
 s.api.SetPvPInstanceAlerts(false)
 assert(s.env.KWCDB.settings.bountyAlertsInPvPInstances==true,'legacy saved value is untouched')
 s.fire('PLAYER_TARGET_CHANGED')
 assert(s.alerts()==0 and s.sounds==0,'the retired opt-in never enables alerts in instances')
 local before=#s.chat
 s.api.Diagnose()
 local diag
 for i=before+1,#s.chat do if s.chat[i]:find('Bounty diagnostic',1,true) then diag=s.chat[i] end end
 assert(diag and diag:find('instancePolicy=instance',1,true) and diag:find('automaticAllowed=false',1,true),
  'diagnostics report the global policy')
 local open=newSession()
 open.units.target={name='Rival'}
 open.fire('PLAYER_TARGET_CHANGED')
 assert(open.alerts()==1 and open.sounds==1,'confirmed open world alerts')
 assert(open.api.Muted()==false)
 for _,kind in ipairs({'party','raid','scenario'}) do
  local w=newSession()
  w.units.target={name='Rival'}
  w.instance={true,kind}
  w.fire('PLAYER_TARGET_CHANGED')
  assert(w.alerts()==0 and w.sounds==0 and not w.banner:IsShown(),kind..' suppressed')
 end
 local secret=newSession()
 secret.env.issecretvalue=function(v) return v==SECRET end
 secret.env.IsInInstance=function() return SECRET,SECRET end
 secret.units.target={name='Rival'}
 secret.fire('PLAYER_TARGET_CHANGED')
 assert(secret.alerts()==0,'secret instance state suppresses')
 local missing=newSession()
 missing.env.IsInInstance=nil
 missing.units.target={name='Rival'}
 missing.fire('PLAYER_TARGET_CHANGED')
 assert(missing.alerts()==0,'unavailable instance state suppresses')
 print('PASS: bounty alerts only in the confirmed open world; retired battleground opt-in explained and left untouched')
end

-- 4. Live zone versus saved sighting locations.
do
 local s=newSession()
 s.zone=''
 s.units.target={name='Rival'}
 s.fire('PLAYER_TARGET_CHANGED')
 assert(s.location()=='Last sighted: Alterac Mountains','saved sighting is labelled')
 assert(s.chat[1]=='BOUNTY SPOTTED: Rival (current zone unknown; last sighted: Alterac Mountains).')
 s.report.scripts.OnClick(s.report)
 assert(s.opened[1].id=='B1' and s.opened[1].zone==nil,'saved zone is never prefilled as the observed zone')

 local posted=newSession({bounties={{id='B2',status='ACTIVE',details={target='Rival',location='Tarren Mill'}}}})
 posted.zone=nil
 posted.units.target={name='Rival'}
 posted.fire('PLAYER_TARGET_CHANGED')
 assert(posted.location()=='Posted location: Tarren Mill')

 local none=newSession({bounties={{id='B3',status='ACTIVE',details={target='Rival'},sightings={}}}})
 none.env.GetRealZoneText=nil
 none.units.target={name='Rival'}
 none.fire('PLAYER_TARGET_CHANGED')
 assert(none.location()=='Location unavailable' and none.chat[1]=='BOUNTY SPOTTED: Rival (current zone unknown).')

 local live=newSession()
 live.zone='  Arathi Highlands  '
 live.units.target={name='Rival'}
 live.fire('PLAYER_TARGET_CHANGED')
 assert(live.location()=='Arathi Highlands','live zone beats saved sighting')
 print('PASS: live zone, labelled saved sighting and posted location, Report Sighting prefill')
end

-- 5. WoW Forever secret values.
do
 local function secretSession()
  local s=newSession()
  s.env.issecretvalue=function(v) return v==SECRET end
  return s
 end
 local name=secretSession()
 name.units.target={name=SECRET}
 name.fire('PLAYER_TARGET_CHANGED')
 assert(name.alerts()==0 and not name.banner:IsShown(),'secret name never alerts')

 local realm=secretSession()
 realm.units.target={name='Rival',realm=SECRET}
 realm.fire('PLAYER_TARGET_CHANGED')
 assert(realm.alerts()==1 and realm.target()=='Rival','secret realm keeps name detection')

 local hostility=secretSession()
 hostility.env.KWCDB.settings.bountyAlertTest=true
 hostility.units.target={name='Rival',enemy=SECRET}
 hostility.fire('PLAYER_TARGET_CHANGED')
 assert(hostility.alerts()==0,'unknown hostility never alerts, even in test mode')

 local player=secretSession()
 player.units.target={name='Rival',player=SECRET}
 player.fire('PLAYER_TARGET_CHANGED')
 assert(player.alerts()==0)

 local zone=secretSession()
 zone.zone=SECRET
 zone.units.target={name='Rival'}
 zone.fire('PLAYER_TARGET_CHANGED')
 assert(zone.location()=='Last sighted: Alterac Mountains')
 zone.report.scripts.OnClick(zone.report)
 assert(zone.opened[1].zone==nil,'secret zone is not passed to the sighting form')

 local token=secretSession()
 token.units[SECRET]={name='Rival'}
 token.fire('NAME_PLATE_UNIT_ADDED',SECRET)
 token.plates={{namePlateUnitToken=SECRET}}
 token.tick(2)
 assert(token.alerts()==0)

 local throwing=newSession()
 throwing.env.UnitName=function() error('restricted') end
 throwing.units.target={name='Rival'}
 throwing.fire('PLAYER_TARGET_CHANGED')
 throwing.env.UnitName=function() return 'Rival' end
 throwing.env.UnitCanAttack=function() error('restricted') end
 throwing.fire('PLAYER_TARGET_CHANGED')
 assert(throwing.alerts()==0,'API errors are contained')

 local diag=secretSession()
 diag.units.target={name=SECRET}
 diag.api.Diagnose()
 assert(diag.chat[1]:find('target=unavailable',1,true),'diagnostics stay secret-safe')
 print('PASS: secret names, realms, hostility, zones and unit tokens are handled safely')
end

-- 5b. String-typed secret values (regression for the BountyAlerts.lua:70 crash).
-- Vulnerable revisions: ceae4f2 through 646e495 (all report TOC 1.8.0). Fixed in
-- 4e6881f. In those revisions check() passed an unguarded UnitName() result to
-- normalized(), whose type(name)=='string' check let name:lower() run.
-- Assumption: consistent with that crash, this simulation assumes a WoW Forever
-- secret can report type()=='string' and that string-library calls on it fail.
-- This has not been confirmed in the live client. The table-based SECRET above
-- fails type checks and cannot reproduce the crash.
-- Simulation: one real string is reported by issecretvalue(). The 12 functions in
-- `guarded` below are wrapped, including when called as methods such as
-- value:lower(). A wrapper records the operation, then raises an error, only when
-- the secret is its FIRST argument. Each production case asserts that zero
-- operations were recorded, so an unsafe call hidden inside pcall still fails.
-- Not detected: a secret passed as a later argument (string.format('%s',secret),
-- s:find(secret)); other string functions; and '..', '==', '<', '#' or tostring()
-- on the secret, which Lua 5.1 cannot intercept on a plain string.
-- Installation, cases and restoration run protected. Every wrapper that was
-- installed is restored, even after a partial installation or a failed check.
do
 local SECRET_TEXT='\1KWC simulated secret string'
 local guarded={'byte','find','format','gmatch','gsub','len','lower','match','rep','reverse','sub','upper'}
 local original={}
 local forbidden={measuring=false,count=0,ops={}}
 local function resetMeasurement() forbidden.count=0;forbidden.ops={} end
 local function install()
  for _,fname in ipairs(guarded) do
   local fn=string[fname]
   assert(type(fn)=='function','string.'..fname..' is unavailable')
   -- Record the original before replacing it, so cleanup covers partial installs.
   original[fname]=fn
   string[fname]=function(value,...)
    if value==SECRET_TEXT then
     if forbidden.measuring then
      forbidden.count=forbidden.count+1
      forbidden.ops[#forbidden.ops+1]='string.'..fname
     end
     error('string operation on a secret value: string.'..fname,2)
    end
    return fn(value,...)
   end
  end
 end
 local function restore()
  forbidden.measuring=false
  for fname,fn in pairs(original) do string[fname]=fn end
 end
 local function session()
  local s=newSession()
  s.env.issecretvalue=function(v) return v==SECRET_TEXT end
  return s
 end
 -- Run one production case with a fresh measurement. Errors and recorded
 -- operations are both failures; pcall inside production code cannot hide them.
 local function measure(label,fn,...)
  resetMeasurement()
  forbidden.measuring=true
  local ok,err=pcall(fn,...)
  forbidden.measuring=false
  assert(ok and forbidden.count==0,
   label..': '..forbidden.count..' forbidden string operation(s) on the simulated secret ['..
   table.concat(forbidden.ops,', ')..']'..(ok and '' or '; error: '..tostring(err)))
 end
 local function run()
  -- Simulation self-checks run unmeasured and never count toward a case.
  assert(type(SECRET_TEXT)=='string','simulated secret is string-typed')
  assert(not pcall(function() return SECRET_TEXT:lower() end),'simulated secret rejects string methods')
  assert(not pcall(string.match,SECRET_TEXT,'.'),'simulated secret rejects string library calls')
  assert(('Rival'):lower()=='rival','ordinary strings are unaffected')
  assert(forbidden.count==0,'unmeasured self-checks are not recorded')
  -- The recorder must see an operation even when the caller swallows the error.
  resetMeasurement();forbidden.measuring=true
  pcall(function() return SECRET_TEXT:lower() end)
  forbidden.measuring=false
  assert(forbidden.count==1 and forbidden.ops[1]=='string.lower','recorder counts a swallowed operation')
  resetMeasurement()

  local cases={
   {'target',function(s) s.units.target={name=SECRET_TEXT};s.fire('PLAYER_TARGET_CHANGED') end},
   {'mouseover',function(s) s.units.mouseover={name=SECRET_TEXT};s.fire('UPDATE_MOUSEOVER_UNIT') end},
   {'nameplate event',function(s) s.units.nameplate3={name=SECRET_TEXT};s.fire('NAME_PLATE_UNIT_ADDED','nameplate3') end},
   {'nameplate poll',function(s) s.units.nameplate5={name=SECRET_TEXT};s.plates={{namePlateUnitToken='nameplate5'}};s.tick(2) end},
   {'friendly test mode',function(s)
    s.env.KWCDB.settings.bountyAlertTest=true
    s.units.target={name=SECRET_TEXT,enemy=false}
    s.fire('PLAYER_TARGET_CHANGED')
   end},
  }
  for _,case in ipairs(cases) do
   local s=session()
   measure('secret name ('..case[1]..')',case[2],s)
   assert(s.alerts()==0 and s.sounds==0 and not s.banner:IsShown(),'string-typed secret name never alerts ('..case[1]..')')
  end

  local realm=session()
  realm.units.target={name='Rival',realm=SECRET_TEXT}
  measure('secret realm',realm.fire,'PLAYER_TARGET_CHANGED')
  assert(realm.alerts()==1 and realm.target()=='Rival','string-typed secret realm keeps name detection')

  local zone=session()
  zone.zone=SECRET_TEXT
  zone.units.target={name='Rival'}
  measure('secret zone',zone.fire,'PLAYER_TARGET_CHANGED')
  assert(zone.location()=='Last sighted: Alterac Mountains','string-typed secret zone falls back to the labelled saved location')

  local diag=session()
  diag.units.target={name=SECRET_TEXT}
  measure('secret name (diagnostics)',diag.api.Diagnose)
  assert(diag.chat[1] and diag.chat[1]:find('target=unavailable',1,true),'diagnostics report a string-typed secret name as unavailable')
  assert(diag.alerts()==0)
 end
 local ok,err=pcall(function() install();run() end)
 local restored,restoreErr=pcall(restore)
 assert(restored,'string library restore failed: '..tostring(restoreErr))
 for fname,fn in pairs(original) do assert(string[fname]==fn,'string.'..fname..' was not restored') end
 assert(not forbidden.measuring,'measurement is off after the section')
 if not ok then error(err,0) end
 print('PASS: zero forbidden calls across the 12 wrapped string functions, including inside pcall')
end

-- 6. False positives: friendly, NPC, self, completed, deleted, partial names, realms.
do
 local function quiet(label,configure,bounties)
  local s=newSession(bounties and {bounties=bounties} or nil)
  configure(s)
  s.fire('PLAYER_TARGET_CHANGED')
  assert(s.alerts()==0 and not s.banner:IsShown(),label)
 end
 quiet('friendly unit',function(s) s.units.target={name='Rival',enemy=false} end)
 quiet('NPC',function(s) s.units.target={name='Rival',player=false} end)
 quiet('self in test mode',function(s)
  s.env.KWCDB.settings.bountyAlertTest=true
  s.units.target={name='Rival',self=true}
 end)
 quiet('completed bounty',function(s) s.units.target={name='Rival'} end,
  {{id='B1',status='COMPLETED',details={target='Rival'}}})
 quiet('cancelled bounty',function(s) s.units.target={name='Rival'} end,
  {{id='B1',status='CANCELLED',details={target='Rival'}}})
 quiet('legacy free-text bounty',function(s) s.units.target={name='Rival'} end,
  {{id='B1',status='ACTIVE',text='Kill Rival on sight'}})
 quiet('alerts disabled',function(s) s.env.KWCDB.settings.bountyAlerts=false;s.units.target={name='Rival'} end)
 do
  local s=newSession({deletions={['BOUNTY:B1']=1}})
  s.units.target={name='Rival'}
  s.fire('PLAYER_TARGET_CHANGED')
  assert(s.alerts()==0,'tombstoned bounty')
 end
 for _,case in ipairs({{'Ann','Anna'},{'Anna','Ann'},{'Rival','Rivals'},{'Rivalry','Rival'},{'Ri','Rival'}}) do
  quiet('partial '..case[1]..'/'..case[2],function(s) s.units.target={name=case[2]} end,
   {{id='B1',status='ACTIVE',details={target=case[1]}}})
 end
 quiet('different realm',function(s) s.units.target={name='Rival',realm='Stormrage'} end,
  {{id='B1',status='ACTIVE',details={target='Rival-Nightfall'}}})
 quiet('different own realm',function(s)
  s.env.GetRealmName=function() return 'Home Realm' end
  s.units.target={name='Rival'}
 end,{{id='B1',status='ACTIVE',details={target='Rival-Nightfall'}}})

 local m=newSession().api.Matches
 assert(m('Rival','Rival') and m(' rival ','RIVAL'))
 assert(m('Cliveanna Vine','Cliveanna'),'display surname matches')
 assert(m('Rival-Other Realm','Rival','OtherRealm'),'realm spacing is normalized')
 assert(m('Rival-OtherRealm','Rival-OtherRealm'),'combined name-realm unit names match')
 assert(not m('Rival-OtherRealm','Rival-Stormrage'))
 assert(m('Rival','Rival','AnyRealm'),'bounty without a realm still matches any realm')
 assert(m('Rival-Home','Rival'),'same-realm unit without GetRealmName keeps matching')
 assert(not m('','Rival') and not m('Rival',nil) and not m(nil,'Rival'))
 print('PASS: no alerts for friendly, NPC, self, closed, deleted, legacy, partial-name or other-realm targets')
end

-- 7. Existing alert and sound settings; test mode; no sync or storage mutation.
do
 local q={bountySound=true,alertSound=true}
 local s=newSession()
 s.env.KWC.QOL={Enabled=function(k) return q[k]~=false end}
 s.units.target={name='Rival'}
 q.bountySound=false
 s.fire('PLAYER_TARGET_CHANGED')
 assert(s.banner:IsShown() and s.sounds==0,'bounty sound off')
 q.bountySound=true;q.alertSound=false
 s.now=s.now+200;s.fire('PLAYER_TARGET_CHANGED')
 assert(s.alerts()==2 and s.sounds==0,'all alert sounds off')
 q.alertSound=true
 s.now=s.now+200;s.fire('PLAYER_TARGET_CHANGED')
 assert(s.sounds==1)

 local t=newSession()
 t.units.target={name='Rival',enemy=false}
 t.api.SetTestMode(true)
 assert(t.banner:IsShown() and t.banner.text[1].text=='FRIENDLY BOUNTY TEST' and not t.report:IsShown())
 assert(t.chat[2]=='TEST FRIENDLY BOUNTY: Rival in Hillsbrad Foothills.')

 local storage=newSession()
 local before=storage.env.KWCDB.bounties[1]
 local sightings=#before.sightings
 storage.units.target={name='Rival'}
 storage.fire('PLAYER_TARGET_CHANGED')
 assert(storage.env.KWCDB.bounties[1]==before and #before.sightings==sightings,'detection never writes sightings')
 local keys={}
 for k in pairs(storage.env.KWCDB.settings) do keys[#keys+1]=k end
 assert(#keys==0,'detection does not add SavedVariables settings')
 print('PASS: popup and sound settings, friendly test mode, no guild traffic or storage writes')
end

-- 8. Suppression state stays bounded.
do
 local bounties={}
 for i=1,80 do bounties[i]={id='F'..i,status='ACTIVE',details={target='Foe'..i}} end
 local s=newSession({bounties=bounties})
 for i=1,70 do
  s.units.target={name='Foe'..i}
  s.fire('PLAYER_TARGET_CHANGED')
 end
 assert(s.alerts()==64,'at most 64 tracked targets per cooldown window, got '..s.alerts())
 s.now=s.now+120
 s.units.target={name='Foe75'}
 s.fire('PLAYER_TARGET_CHANGED')
 assert(s.alerts()==65,'expired entries are pruned to make room')
 print('PASS: bounded suppression table with pruning')
end

-- 9. Guild change resets suppression; the poll stays idle when nothing can match.
do
 local s=newSession()
 local scope='club-1'
 s.env.KWC.GuildScope=function() return scope end
 s.units.target={name='Rival'}
 s.fire('PLAYER_TARGET_CHANGED')
 assert(s.alerts()==1)
 s.now=s.now+20
 s.fire('PLAYER_TARGET_CHANGED')
 assert(s.alerts()==1,'same guild stays suppressed')
 scope='club-2'
 s.now=s.now+20
 s.fire('PLAYER_TARGET_CHANGED')
 assert(s.alerts()==2,'a guild change starts a fresh suppression window')
 s.env.KWC.GuildScope=function() error('roster unavailable') end
 s.now=s.now+20
 s.fire('PLAYER_TARGET_CHANGED')
 assert(s.alerts()==3,'a failing GuildScope is contained and treated as a scope change')

 local function idle(label,opts,configure)
  local p=newSession(opts)
  local calls=0
  local exists=p.env.UnitExists
  p.env.UnitExists=function(u) calls=calls+1;return exists(u) end
  p.units.nameplate1={name='Rival'}
  p.plates={{namePlateUnitToken='nameplate1'}}
  if configure then configure(p) end
  p.tick(2)
  assert(calls==0 and p.alerts()==0,label..' must skip the unit scan')
 end
 idle('no bounties',{bounties={}})
 idle('only closed bounties',{bounties={{id='B1',status='COMPLETED',details={target='Rival'}}}})
 idle('only legacy free-text bounties',{bounties={{id='B1',status='ACTIVE',text='Kill Rival'}}})
 idle('tombstoned bounty',{deletions={['BOUNTY:B1']=1}})
 idle('alerts disabled',{settings={bountyAlerts=false}})
 idle('battleground',nil,function(p) p.instance={true,'pvp'} end)
 print('PASS: guild-scoped suppression and idle poll when no bounty can match')
end
