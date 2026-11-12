local F=CreateFrame('Frame')
KWC={version='1.6.0-dev.56',listeners={}};local K=KWC
function K.Say(s) print('|cffffb54d[Keepers]|r '..tostring(s)) end
function K.Clean(s,n) return tostring(s or ''):gsub('[\r\n|]',' '):sub(1,n or 180) end
function K.Now() return date('%Y-%m-%d %H:%M') end
function K.On(event,fn)
 local ok,err=pcall(F.RegisterEvent,F,event)
 if not ok then K.Say('Event unavailable: '..tostring(event));return false end
 K.listeners[event]=K.listeners[event] or {};table.insert(K.listeners[event],fn)
 return true
end
function K.Log(cat,msg) if not KWCDB then return end;local t=KWCDB.history;table.insert(t,1,{time=K.Now(),category=cat,text=K.Clean(msg,230)});while #t>350 do table.remove(t) end end
function K.IsOfficer() if not IsInGuild() then return false end;local _,_,rank=GetGuildInfo('player');return type(rank)=='number' and rank<=1 end
function K.IsMember(sender) if type(sender)~='string' then return false end;local n=sender:lower();local short=n:match('^[^-]+');return KWCDB and KWCDB.roster and (KWCDB.roster[n] or KWCDB.roster[short])~=nil end
function K.IsSenderOfficer(sender) if type(sender)~='string' or not KWCDB or not KWCDB.roster then return false end;local n=sender:lower();local r=KWCDB.roster[n] or KWCDB.roster[n:match('^[^-]+')];return r and type(r.rankIndex)=='number' and r.rankIndex<=1 and r.scannedAt and time()-r.scannedAt<=180 end
function K.RosterRecord(name)
 local short=tostring(name or ''):lower():match('^[^-]+')
 if not short or not KWCDB or not KWCDB.roster then return nil end
 return KWCDB.roster[tostring(name):lower()] or KWCDB.roster[short]
end
function K.IsGuildWarchief(name)
 local r=K.RosterRecord(name)
 if r then return r.rankIndex==0 end
 local me=UnitName and UnitName('player')
 if me and tostring(me):lower()==tostring(name):lower() then
  local _,_,rank=GetGuildInfo('player');return rank==0
 end
 return false
end
function K.CommandIsOffline(name)
 local r=K.RosterRecord(name)
 -- Unknown roster state must NEVER trigger succession.
 return r and r.online==false and (r.offlineScans or 0)>=2
end
function K.Send(kind,payload)
 if not IsInGuild() or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
 local msg='2;'..K.Clean(kind,18)..';'..K.Clean(payload,210)
 return K.Net.Send('KWC3',msg,'GUILD')
end
function K.Init()
 KWCDB=KWCDB or {};local d=KWCDB
 for _,key in ipairs({'history','roster','ops','bounties','pvp','settings','recruiter','responses','scoutReports','afterAction'}) do d[key]=d[key] or {} end
 -- DEV6 migration: start all automatic guild data and scouting features ON,
 -- including clients that disabled them in earlier development builds.
 -- Apply only once; subsequent user OFF choices remain respected.
 if not d.settings.dev6AutoDefaultsApplied then
  d.settings.autoScout=true
  d.settings.autoGuildSync=true
  d.settings.dev6AutoDefaultsApplied=true
 end
 if d.settings.autoScout==nil then d.settings.autoScout=true end
 if d.settings.autoGuildSync==nil then d.settings.autoGuildSync=true end
 d.settings.alerts=(d.settings.alerts~=false)
 d.settings.pitch=d.settings.pitch or 'Keepers of Trogdor is recruiting! World PvP, dungeons, and a relaxed crew. Interested?'
 if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix,'KWC3');pcall(C_ChatInfo.RegisterAddonMessagePrefix,'KWC4');pcall(C_ChatInfo.RegisterAddonMessagePrefix,'KWCS1') end
 K.Say('War Command '..K.version..' loaded. /kt to open.')
 if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
 if K.PvP and K.PvP.RefreshHonor then K.PvP.RefreshHonor() end
end
F:RegisterEvent('ADDON_LOADED')
F:SetScript('OnEvent',function(_,event,...)
 if event=='ADDON_LOADED' and ...=='KeepersWarCommand' then K.Init() end
 for _,fn in ipairs(K.listeners[event] or {}) do local ok,err=pcall(fn,...);if not ok then K.Say(event..' error: '..tostring(err)) end end
end)
SLASH_KEEPERSWARCOMMAND1='/kt';SLASH_KEEPERSWARCOMMAND2='/keepers'
SlashCmdList.KEEPERSWARCOMMAND=function(s)
 local cmd,arg=tostring(s or ''):match('^(%S*)%s*(.-)%s*$');cmd=(cmd or ''):lower()
 if cmd=='net' then local q,ok,fail,drop=K.Net.Status();K.Say('Network queued: '..q..' | sent: '..ok..' | send errors: '..fail..' | dropped: '..drop)
 elseif cmd=='autoscout' then
  if arg:lower()=='on' then K.AutoScout.SetEnabled(true) elseif arg:lower()=='off' then K.AutoScout.SetEnabled(false) else K.Say('Auto Scout: '..(K.AutoScout.Status() and 'ON' or 'OFF')..'. /kt autoscout on/off. '..K.AutoScout.Info()) end
 elseif cmd=='chatcheck' then K.Operations.GuildChatDiagnostics()
 elseif cmd=='scale' then
  if arg=='' then K.Say('Window scale: '..math.floor(K.UI.GetScale()*100+0.5)..'%. Use /kt scale 75-135')
  else local n=tonumber(arg);if not n then K.Say('Use /kt scale 75-135 (example: /kt scale 90)') else K.UI.SetScale(n/100) end end
 elseif cmd=='bountyalert' then
  local option=arg:lower()
  if option=='test on' then K.BountyAlerts.SetTestMode(true)
  elseif option=='test off' then K.BountyAlerts.SetTestMode(false)
  elseif option=='on' then K.BountyAlerts.SetEnabled(true)
  elseif option=='off' then K.BountyAlerts.SetEnabled(false)
  elseif option=='unlock' then K.BountyAlerts.SetUnlocked(true)
  elseif option=='lock' then K.BountyAlerts.SetUnlocked(false)
  elseif option=='test' then K.BountyAlerts.Demo()
  elseif option=='reset' then K.BountyAlerts.ResetPosition()
  elseif option:match('^scale%s+[%d%.]+$') then K.BountyAlerts.SetScale((tonumber(option:match('[%d%.]+')) or 100)/100)
  else K.Say('/kt bountyalert on/off | test | unlock/lock | reset | scale 50-200 | test on/off') end
 elseif cmd=='bountydiag' then
  if K.BountyAlerts and K.BountyAlerts.Diagnose then K.BountyAlerts.Diagnose() end
 elseif cmd=='alerttest' then
  if K.BountyAlerts and K.BountyAlerts.Demo then K.BountyAlerts.Demo() end
  K.Say('Showing the bounty test. Use /kt deathalert test to preview the death alert.')
 elseif cmd=='deathalert' then
  if arg:lower()=='on' then K.WorldPvPDeaths.SetEnabled(true) elseif arg:lower()=='off' then K.WorldPvPDeaths.SetEnabled(false) elseif arg:lower()=='test' then K.WorldPvPDeaths.Demo() elseif arg:lower()=='status' then K.WorldPvPDeaths.Status() elseif arg:lower()=='debug on' then K.WorldPvPDeaths.SetDebug(true);K.Say('Death alert diagnostics ON') elseif arg:lower()=='debug off' then K.WorldPvPDeaths.SetDebug(false);K.Say('Death alert diagnostics OFF') elseif arg:lower()=='unlock' then K.WorldPvPDeaths.SetUnlocked(true) elseif arg:lower()=='lock' then K.WorldPvPDeaths.SetUnlocked(false) elseif arg:lower()=='reset' then K.WorldPvPDeaths.ResetPosition() elseif arg:lower():match('^scale %d+') then K.WorldPvPDeaths.SetScale((tonumber(arg:match('%d+')) or 100)/100) elseif arg:lower()=='sound on' then KWCDB.settings.worldPvPDeathSound=true;K.Say('World PvP death sound ON') elseif arg:lower()=='sound off' then KWCDB.settings.worldPvPDeathSound=false;K.Say('World PvP death sound OFF') elseif arg:lower()=='broadcast on' then KWCDB.settings.worldPvPDeathBroadcast=true;K.Say('Death broadcasting ON') elseif arg:lower()=='broadcast off' then KWCDB.settings.worldPvPDeathBroadcast=false;K.Say('Death broadcasting OFF') else K.Say('/kt deathalert on/off | test | status | debug on/off | unlock/lock | reset | scale 50-200 | sound on/off | broadcast on/off') end
 elseif cmd=='deathreport' then K.WorldPvPDeaths.Report(arg)
 elseif cmd=='deathhistory' then K.UI.Toggle('World PvP Deaths')
 elseif cmd=='achievements' then K.UI.Toggle('Achievements')
 elseif cmd=='alerts' then K.UI.Toggle('Alerts')
 elseif cmd=='raid' then if K.RaidCommand then K.RaidCommand.Toggle() end
 elseif cmd=='warroom' then K.UI.Toggle('War Room')
 elseif cmd=='scout' then K.UI.Toggle('Scout Network')
 elseif cmd=='aar' then K.UI.Toggle('After Action')
 elseif cmd=='ctahere' then K.UI.Toggle('CTA Entry')
 elseif cmd=='addons' then K.UI.Toggle('Addon Checker');if K.AddonChecker then K.AddonChecker.Request() end
 elseif cmd=='recruit' then K.UI.Toggle('Recruitment')
 elseif cmd=='who' then K.Recruiter.Search(arg)
 elseif cmd=='active' then
  local kind=arg:lower():match('^%s*(%S+)')
  K.Operations.ListActive((kind=='bounty' or kind=='bounties') and 'BOUNTY' or 'CTA',false)
 elseif cmd=='guildreport' then
  local kind=arg:lower():match('^%s*(%S+)')
  K.Operations.ListActive((kind=='bounty' or kind=='bounties') and 'BOUNTY' or 'CTA',true)
 elseif cmd=='cta' then K.Operations.CreateCTA(arg)
 elseif cmd=='bounty' then
  if arg:lower()=='addtarget' then K.UI.OpenBountyForUnit('target') else K.Operations.AddBounty(arg) end
 elseif cmd=='report' then K.Recruiter.Report()
 elseif cmd=='sync' then if K.Sync and K.Sync.RequestAll then K.Sync.RequestAll(false) end
 elseif cmd=='autosync' then
  if arg:lower()=='on' then K.Sync.SetAutoSync(true) elseif arg:lower()=='off' then K.Sync.SetAutoSync(false) else K.Say('Auto Guild Sync: '..(K.Sync.AutoSyncEnabled() and 'ON' or 'OFF')..'. Use /kt autosync on/off.') end
 elseif cmd=='syncdiag' then
  if K.Sync and K.Sync.BoardDiagnostics then
   local d=K.Sync.BoardDiagnostics()
   for _,kind in ipairs({'CTA','Bounty'}) do
    local x=d[kind];K.Say(kind..' sync: sent='..x.sent..' received='..x.received..' applied='..x.applied..' rejected='..x.rejected)
   end
  end
  if K.RaidSignup and K.RaidSignup.Diagnostics then
   local x=K.RaidSignup.Diagnostics()
   K.Say('Raid sign-up sync: sent='..x.sent..' received='..x.received..' applied='..x.applied..' rejected='..x.rejected..' requests='..x.requests)
  end
  K.Say('Counters are since /reload. Received is not the same as applied. Use /kt pvpdiag for honor.')
 elseif cmd=='pvpdiag' then
  local x=K.PvP.Diagnostics()
  K.Say('PvP sync: sent='..x.sent..' received='..x.received..' rejected='..x.rejected..' pending='..x.pending..' last='..tostring(x.lastPeer or 'none')..' ('..tostring(x.lastReason)..')')
 elseif cmd=='honor' then K.PvP.RefreshHonor();K.Say('Honor statistics refreshed (if available).')
 elseif cmd=='scan' then K.Roster.Scan()
 elseif cmd=='integrations' then K.Companions.Report()
 elseif cmd=='help' then K.Say('/kt | /kt scale 75-135 | /kt bountyalert on/off | /kt bountyalert test on/off | /kt alerts | /kt alerttest | /kt addons | /kt recruit | /kt who 10-20 | /kt cta zone - objective | /kt bounty addtarget | /kt bounty target - reason | /kt scan | /kt report | /kt integrations')
 else K.UI.Toggle() end
end
