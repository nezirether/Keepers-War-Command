-- KWC 2.0 slash commands: the single registration point for /kt, /kwc and /keepers.
-- The officer add-on never registers these slashes; it attaches to K.Officer and
-- is reached through "/kt command". No recruitment command exists in public KWC.
local K=KWC
K.Officer=K.Officer or {}
local C={};K.Commands=C

local HELP={
 {'/kt','Open or close the War Room'},
 {'/kt <page>','dashboard, cta, bounties, pvp, leaderboards, records, lfg, services, raids, alerts, settings'},
 {'/kt command','Officer Command Table (requires KeepersWarCommand_Command and War Council rank)'},
 {'/kt cta <text>','Post a quick Call to Arms'},
 {'/kt bounty <name>','Open the bounty composer (/kt bounty addtarget uses your target)'},
 {'/kt sync','Request a manual guild sync'},
 {'/kt autosync on|off','Automatic guild sync'},
 {'/kt skin <id>','Switch War Room skin'},
 {'/kt scale 75-135','War Room window scale'},
 {'/kt minimap show|hide|reset','Minimap button'},
 {'/kt alerts','Alert settings and previews'},
 {'/kt deathalert | killalert | bountyalert ...','Alert channel controls (test, on/off, unlock/lock, reset, scale)'},
 {'/kt deathreport <name>','Report your own open-world death attacker while dead'},
 {'/kt instancestatus','Explain the current automatic-alert policy'},
 {'/kt guilddebug | syncdiag | pvpdiag | net','Diagnostics'},
 {'/kt addons','Check which guildmates run KWC'},
}
function C.Help()
 K.Say('War Command '..tostring(K.version)..' commands:')
 for _,h in ipairs(HELP) do print('  |cffe0733a'..h[1]..'|r  '..h[2]) end
end

local PAGES={dashboard='dashboard',home='dashboard',cta='cta',ctas='cta',bounties='bounties',board='bounties',
 pvp='pvp',worldpvp='pvp',leaderboards='leaderboards',lb='leaderboards',records='records',deaths='records',
 lfg='lfg',services='services',professions='services',raids='raids',raid='raids',alerts='alerts',settings='settings',options='settings'}

local function alertChannel(A,arg,label)
 local a=(arg or ''):lower()
 if not A then return end
 if a=='on' then A.SetEnabled(true) elseif a=='off' then A.SetEnabled(false)
 elseif a=='test' then A.Demo() elseif a=='status' and A.Status then A.Status()
 elseif a=='unlock' then A.SetUnlocked(true) elseif a=='lock' then A.SetUnlocked(false)
 elseif a=='reset' and A.ResetPosition then A.ResetPosition()
 elseif a:match('^scale%s+%d+') and A.SetScale then A.SetScale((tonumber(a:match('%d+')) or 100)/100)
 elseif a=='debug on' and A.SetDebug then A.SetDebug(true) elseif a=='debug off' and A.SetDebug then A.SetDebug(false)
 elseif a=='sound on' and A.SetSound then A.SetSound(true) elseif a=='sound off' and A.SetSound then A.SetSound(false)
 elseif a=='broadcast on' and A.SetBroadcast then A.SetBroadcast(true) elseif a=='broadcast off' and A.SetBroadcast then A.SetBroadcast(false)
 elseif a=='broadcast on' then KWCDB.settings.worldPvPDeathBroadcast=true;K.Say('Death broadcasting ON')
 elseif a=='broadcast off' then KWCDB.settings.worldPvPDeathBroadcast=false;K.Say('Death broadcasting OFF')
 else K.Say('/kt '..label..' on|off | test | status | unlock|lock | reset | scale 50-200 | sound on|off') end
end

function C.Run(input)
 if K.RefreshGuildScope then K.RefreshGuildScope() end
 local cmd,arg=tostring(input or ''):match('^(%S*)%s*(.-)%s*$');cmd=(cmd or ''):lower();arg=arg or ''
 if cmd=='' then K.UI.Toggle() return end
 if PAGES[cmd] then K.UI.Open(PAGES[cmd]) return end
 if cmd=='help' or cmd=='?' then C.Help()
 elseif cmd=='command' or cmd=='officer' or cmd=='council' then
  if K.Officer.Open then K.Officer.Open() else K.Say('The officer Command Table needs KeepersWarCommand_Command (War Council and Warchief only).') end
 elseif cmd=='recruit' or cmd=='who' or cmd=='report' then
  if K.Officer.Open then K.Officer.Open('recruit') else K.Say('Recruitment is part of the officer add-on only.') end
 elseif cmd=='cta' then
  if arg=='' then K.UI.Open('cta',{compose=true}) else K.Operations.CreateCTA(arg) end
 elseif cmd=='bounty' then
  if arg:lower()=='addtarget' then K.UI.OpenBountyForUnit('target')
  elseif arg=='' then K.UI.Open('bounties',{compose=true}) else K.UI.OpenBountyForName(arg) end
 elseif cmd=='sync' then if K.Sync and K.Sync.RequestAll then K.Sync.RequestAll(false) end
 elseif cmd=='autosync' then
  if arg:lower()=='on' then K.Sync.SetAutoSync(true) elseif arg:lower()=='off' then K.Sync.SetAutoSync(false)
  else K.Say('Auto Guild Sync: '..(K.Sync.AutoSyncEnabled() and 'ON' or 'OFF')..'. /kt autosync on|off') end
 elseif cmd=='skin' then
  local s=K.PublicThemes.Resolve(arg:lower());if not s then K.Say('Available skins: '..table.concat(K.PublicThemes.order,', '));return end
  if K.WarRoomSkin.Apply(s) then K.Say('War Room skin: '..s) else K.Say('Character appearance is unavailable until login completes.') end
 elseif cmd=='scale' then
  local n=tonumber(arg);if not n then K.Say('War Room scale '..math.floor(K.UI.GetScale()*100+0.5)..'%. /kt scale 75-135') else K.UI.SetScale(n/100) end
 elseif cmd=='minimap' then
  local M=K.Minimap
  if arg=='hide' then M.SetVisible(false) elseif arg=='show' then M.SetVisible(true) elseif arg=='reset' then M.Reset() else K.Say('/kt minimap show|hide|reset') end
 elseif cmd=='alerts' then K.UI.Open('alerts')
 elseif cmd=='deathalert' then alertChannel(K.WorldPvPDeaths,arg,'deathalert')
 elseif cmd=='killalert' then alertChannel(K.WorldPvPKills,arg,'killalert')
 elseif cmd=='bountyalert' then
  local a=arg:lower()
  if a=='test on' then K.BountyAlerts.SetTestMode(true) elseif a=='test off' then K.BountyAlerts.SetTestMode(false)
  elseif a=='diag' then K.BountyAlerts.Diagnose()
  else alertChannel(K.BountyAlerts,arg,'bountyalert') end
 elseif cmd=='alerttest' then K.BountyAlerts.Demo()
 elseif cmd=='deathreport' then K.WorldPvPDeaths.Report(arg)
 elseif cmd=='deathhistory' then K.UI.Open('records')
 elseif cmd=='instancestatus' then K.Say(K.InstanceStatusLine())
 elseif cmd=='deathledger' then
  if K.DeathLedger and K.DeathLedger.Summary then K.Say(K.DeathLedger.Summary());K.Say('Last ledger decision: '..K.DeathLedger.LastDecision());if K.DeathLedgerSync then K.Say(K.DeathLedgerSync.Diagnostics()) end end
 elseif cmd=='guilddebug' then K.GuildDebug()
 elseif cmd=='lfgdebug' then K.GuildLFG.Debug(arg)
 elseif cmd=='net' then local q,ok,fail,drop=K.Net.Status();K.Say('Network queued: '..q..' | sent: '..ok..' | send errors: '..fail..' | dropped: '..drop)
 elseif cmd=='syncdiag' then
  local d=K.Sync.BoardDiagnostics()
  for _,kind in ipairs({'CTA','Bounty'}) do local x=d[kind];K.Say(kind..' sync: sent='..x.sent..' received='..x.received..' applied='..x.applied..' rejected='..x.rejected) end
  if K.RaidSignup and K.RaidSignup.Diagnostics then local x=K.RaidSignup.Diagnostics();K.Say('Raid sign-up sync: sent='..x.sent..' received='..x.received..' applied='..x.applied..' rejected='..x.rejected..' requests='..x.requests) end
 elseif cmd=='pvpdiag' then
  local x=K.PvP.Diagnostics()
  K.Say('PvP sync: sent='..x.sent..' received='..x.received..' rejected='..x.rejected..' pending='..x.pending..' last='..tostring(x.lastPeer or 'none')..' ('..tostring(x.lastReason)..')')
 elseif cmd=='honor' then K.PvP.RefreshHonor();K.Say('Honor statistics refreshed (if available).')
 elseif cmd=='autoscout' then
  if arg:lower()=='on' then K.AutoScout.SetEnabled(true) elseif arg:lower()=='off' then K.AutoScout.SetEnabled(false) else K.Say('Auto Scout: '..(K.AutoScout.Status() and 'ON' or 'OFF')..'. '..K.AutoScout.Info()) end
 elseif cmd=='active' then local kind=arg:lower():match('^%s*(%S+)');K.Operations.ListActive((kind=='bounty' or kind=='bounties') and 'BOUNTY' or 'CTA',false)
 elseif cmd=='guildreport' then local kind=arg:lower():match('^%s*(%S+)');K.Operations.ListActive((kind=='bounty' or kind=='bounties') and 'BOUNTY' or 'CTA',true)
 elseif cmd=='chatcheck' then K.Operations.GuildChatDiagnostics()
 elseif cmd=='scan' then K.Roster.Scan()
 elseif cmd=='integrations' then K.Companions.Report()
 elseif cmd=='addons' then K.UI.Open('settings',{section='addons'});if K.AddonChecker then K.AddonChecker.Request() end
 else K.Say('Unknown command "'..cmd..'". /kt help lists commands.') end
end

SLASH_KEEPERSWARCOMMAND1='/kt';SLASH_KEEPERSWARCOMMAND2='/kwc';SLASH_KEEPERSWARCOMMAND3='/keepers'
SlashCmdList.KEEPERSWARCOMMAND=function(s) K.Kit.Safe(C.Run,s) end
