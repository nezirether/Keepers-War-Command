local F=CreateFrame('Frame')
KWC={version='1.5.0-dev.15',listeners={}};local K=KWC
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
 local ok,result=pcall(C_ChatInfo.SendAddonMessage,'KWC3',msg,'GUILD');return ok and result~=false
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
 if event=='ADDON_LOADED' then if ...=='KeepersWarCommand' then K.Init() end;return end
 for _,fn in ipairs(K.listeners[event] or {}) do local ok,err=pcall(fn,...);if not ok then K.Say(event..' error: '..tostring(err)) end end
end)
SLASH_KEEPERSWARCOMMAND1='/kt';SLASH_KEEPERSWARCOMMAND2='/keepers'
SlashCmdList.KEEPERSWARCOMMAND=function(s)
 local cmd,arg=tostring(s or ''):match('^(%S*)%s*(.-)%s*$');cmd=(cmd or ''):lower()
 if cmd=='autoscout' then
  if arg:lower()=='on' then K.AutoScout.SetEnabled(true) elseif arg:lower()=='off' then K.AutoScout.SetEnabled(false) else K.Say('Auto Scout: '..(K.AutoScout.Status() and 'ON' or 'OFF')..'. /kt autoscout on/off. '..K.AutoScout.Info()) end
 elseif cmd=='chatcheck' then K.Operations.GuildChatDiagnostics()
 elseif cmd=='scale' then
  if arg=='' then K.Say('Window scale: '..math.floor(K.UI.GetScale()*100+0.5)..'%. Use /kt scale 75-135')
  else local n=tonumber(arg);if not n then K.Say('Use /kt scale 75-135 (example: /kt scale 90)') else K.UI.SetScale(n/100) end end
 elseif cmd=='bountyalert' then
  if arg:lower()=='test on' then K.BountyAlerts.SetTestMode(true) elseif arg:lower()=='test off' then K.BountyAlerts.SetTestMode(false) elseif arg:lower()=='on' then K.BountyAlerts.SetEnabled(true) elseif arg:lower()=='off' then K.BountyAlerts.SetEnabled(false) else K.Say('Bounty spotting alerts: '..(K.BountyAlerts.Status() and 'ON' or 'OFF')..'. Use /kt bountyalert on/off or /kt bountyalert test on/off') end
 elseif cmd=='bountydiag' then
  if K.BountyAlerts and K.BountyAlerts.Diagnose then K.BountyAlerts.Diagnose() end
 elseif cmd=='alerttest' then
  if K.BountyAlerts and K.BountyAlerts.Demo then K.BountyAlerts.Demo() end
  if K.GuildmateAlerts and K.GuildmateAlerts.Demo then K.GuildmateAlerts.Demo() end
  K.Say('Showing both test banners. These do not confirm detection. Roster entries: '..tostring(KWCDB and KWCDB.roster and (function() local n=0;for _ in pairs(KWCDB.roster) do n=n+1 end;return n end)() or 0))
 elseif cmd=='guildalert' then
  if arg:lower()=='on' then K.GuildmateAlerts.SetEnabled(true) elseif arg:lower()=='off' then K.GuildmateAlerts.SetEnabled(false) else K.Say('Guildmate nearby alerts: '..(K.GuildmateAlerts.Status() and 'ON' or 'OFF')..'. Use /kt guildalert on/off') end
 elseif cmd=='deathalert' then
  if arg:lower()=='on' then K.WorldPvPDeaths.SetEnabled(true) elseif arg:lower()=='off' then K.WorldPvPDeaths.SetEnabled(false) elseif arg:lower()=='test' then K.WorldPvPDeaths.Demo() elseif arg:lower()=='sound on' then KWCDB.settings.worldPvPDeathSound=true;K.Say('World PvP death sound ON') elseif arg:lower()=='sound off' then KWCDB.settings.worldPvPDeathSound=false;K.Say('World PvP death sound OFF') elseif arg:lower()=='broadcast on' then KWCDB.settings.worldPvPDeathBroadcast=true;K.Say('Death broadcasting ON') elseif arg:lower()=='broadcast off' then KWCDB.settings.worldPvPDeathBroadcast=false;K.Say('Death broadcasting OFF') else K.Say('/kt deathalert on/off | test | sound on/off | broadcast on/off') end
 elseif cmd=='deathreport' then K.WorldPvPDeaths.Report(arg)
 elseif cmd=='deathhistory' then K.UI.Toggle('World PvP Deaths')
 elseif cmd=='achievements' then K.UI.Toggle('Achievements')
 elseif cmd=='alerts' then K.UI.Toggle('Alert Settings')
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
 elseif cmd=='pvpdiag' then
  local x=K.PvP.Diagnostics()
  K.Say('PvP sync: sent='..x.sent..' received='..x.received..' rejected='..x.rejected..' pending='..x.pending..' last='..tostring(x.lastPeer or 'none')..' ('..tostring(x.lastReason)..')')
 elseif cmd=='honor' then K.PvP.RefreshHonor();K.Say('Honor statistics refreshed (if available).')
 elseif cmd=='scan' then K.Roster.Scan()
 elseif cmd=='integrations' then K.Companions.Report()
 elseif cmd=='help' then K.Say('/kt | /kt scale 75-135 | /kt bountyalert on/off | /kt bountyalert test on/off | /kt guildalert on/off | /kt alerttest | /kt addons | /kt recruit | /kt who 10-20 | /kt cta zone - objective | /kt bounty addtarget | /kt bounty target - reason | /kt scan | /kt report | /kt integrations')
 else K.UI.Toggle() end
end
