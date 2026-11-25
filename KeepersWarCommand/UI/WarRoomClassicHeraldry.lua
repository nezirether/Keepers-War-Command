-- V3 heraldry asset map. Values are textures selected from the supplied manifest;
-- presentation-only metadata, scoped to War Room Classic.
local K=KWC
local classic=K.PublicThemes.Get('war-room-classic')
assert(classic and classic.assets,'War Room Classic V2 theme must load before V3 artwork.')
local artwork={
 crestBanner={file='Crest_Banner',uv={0.0078125, 0.9921875, 0.015625, 0.984375},aspect=1.0161},
 crestSmallMark={file='Crest_SmallMark',uv={0.01953125, 0.98046875, 0.0078125, 0.9921875},aspect=0.9762},
 bountyStandard={file='Bounty_Standard',uv={0.01953125, 0.98046875, 0.0078125, 0.9921875},aspect=0.9762},
 bountyEpic={file='Bounty_Epic',uv={0.0234375, 0.97265625, 0.0078125, 0.9921875},aspect=0.9643},
 bountyLegendary={file='Bounty_Legendary',uv={0.0625, 0.93359375, 0.0078125, 0.9921875},aspect=0.8849},
 warlord01={file='Warlord_01',uv={0.078125, 0.9140625, 0.015625, 0.984375},aspect=0.8629},
 warlord02={file='Warlord_02',uv={0.046875, 0.9453125, 0.015625, 0.984375},aspect=0.9274},
 warlord03={file='Warlord_03',uv={0.0546875, 0.9375, 0.015625, 0.984375},aspect=0.9113},
 warlord04={file='Warlord_04',uv={0.015625, 0.984375, 0.015625, 0.9765625},aspect=1.0081},
 warlord05={file='Warlord_05',uv={0.078125, 0.9140625, 0.015625, 0.984375},aspect=0.8629},
 headerDashboard={file='Header_Dashboard',uv={0.00390625, 0.99609375, 0.015625, 0.984375},aspect=8.1935},
 headerBounty={file='Header_Bounty',uv={0.001953125, 0.998046875, 0.0234375, 0.9765625},aspect=8.3607},
 headerCta={file='Header_CTA',uv={0.001953125, 0.998046875, 0.015625, 0.984375},aspect=8.2258},
 headerLeaderboards={file='Header_Leaderboards',uv={0.001953125, 0.998046875, 0.015625, 0.984375},aspect=8.2258},
 headerSettings={file='Header_Settings',uv={0.001953125, 0.998046875, 0.015625, 0.984375},aspect=8.2258},
 headerWarCouncil={file='Header_WarCouncil',uv={0.00390625, 0.99609375, 0.015625, 0.984375},aspect=8.1935},
 alertPvPKill={file='Alert_PvPKill',uv={0.00390625, 0.99609375, 0.125, 0.87109375},aspect=2.6597},
 alertDeath={file='Alert_Death',uv={0.00390625, 0.99609375, 0.13671875, 0.86328125},aspect=2.7312},
 alertBounty={file='Alert_Bounty',uv={0.00390625, 0.99609375, 0.109375, 0.88671875},aspect=2.5528},
 alertCta={file='Alert_CTA',uv={0.00390625, 0.99609375, 0.12109375, 0.87890625},aspect=2.6186},
 alertLFG={file='Alert_LFG',uv={0.00390625, 0.99609375, 0.1484375, 0.84765625},aspect=2.838},
 navDashboard={file='Nav_Dashboard',uv={0.109375, 0.890625, 0.03125, 0.96875},aspect=0.8333},
 navBounty={file='Nav_Bounty',uv={0.03125, 0.96875, 0.046875, 0.953125},aspect=1.0345},
 navCta={file='Nav_CTA',uv={0.0625, 0.921875, 0.03125, 0.96875},aspect=0.9167},
 navWarCouncil={file='Nav_WarCouncil',uv={0.078125, 0.90625, 0.03125, 0.96875},aspect=0.8833},
 navSync={file='Nav_Sync',uv={0.03125, 0.953125, 0.03125, 0.96875},aspect=0.9833},
 navRecruitment={file='Nav_Recruitment',uv={0.078125, 0.90625, 0.03125, 0.96875},aspect=0.8833},
 navServices={file='Nav_Services',uv={0.078125, 0.921875, 0.03125, 0.96875},aspect=0.9},
 navOperations={file='Nav_Operations',uv={0.046875, 0.953125, 0.03125, 0.96875},aspect=0.9667},
 navSettings={file='Nav_Settings',uv={0.03125, 0.96875, 0.03125, 0.96875},aspect=1},
 navLeaderboards={file='Nav_Leaderboards',uv={0.03125, 0.96875, 0.03125, 0.96875},aspect=1},
 navAlerts={file='Nav_Alerts',uv={0.09375, 0.90625, 0.03125, 0.96875},aspect=0.8667},
 navRaid={file='Nav_Raid',uv={0.03125, 0.953125, 0.03125, 0.96875},aspect=0.9833},
}
classic.assetUV=classic.assetUV or {}
classic.assetAspect=classic.assetAspect or {}
for key,entry in pairs(artwork) do
 classic.assets[key]=entry.file
 classic.assetUV[key]=entry.uv
 classic.assetAspect[key]=entry.aspect
end
