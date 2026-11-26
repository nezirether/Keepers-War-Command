-- Loads public KWC from its TOC into a simulated client, logs in, opens every
-- War Room page in both skins, and checks for Lua errors, legacy assets,
-- recruitment exposure and accidental globals.
package.path='./tests/?.lua;'..package.path
local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Ash Ember',rank=3,guid='Player-1-0000000A'})
w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})
local c=w:Client('Ash Ember')
local ok,err=pcall(w.LoadAddon,w,c,'KeepersWarCommand')
H.Check('KWC loads every TOC file without a Lua error',ok,err)
if not ok then H.Summary('kwc_load');os.exit(1) end
w:Login(c);w:Advance(5)
local K=c.env.KWC
-- The running version must match the manifest. Companion compatibility is a separate
-- contract number, covered by integration_contract.lua.
local manifest=H.ReadToc and select(2,H.ReadToc('KeepersWarCommand/KeepersWarCommand.toc'))
H.Check('version matches the manifest and the build',K.version==manifest.Version and K.build==K.version,tostring(K.version)..' / '..tostring(manifest.Version))
H.Check('no event errors during login',#c.errors==0,table.concat(c.errors,' | '):sub(1,800))
c.errors={}
H.Check('/kt, /kwc, /keepers registered once',c.env.SLASH_KEEPERSWARCOMMAND1=='/kt' and c.env.SLASH_KEEPERSWARCOMMAND2=='/kwc' and c.env.SLASH_KEEPERSWARCOMMAND3=='/keepers' and c.env.SLASH_KEEPERSWARCOMMAND4==nil)
-- No recruitment surface in public KWC.
H.Check('public KWC defines no recruiter service',K.Recruiter==nil)
for _,cmd in ipairs({'recruit','who x','report'}) do c.env.SlashCmdList.KEEPERSWARCOMMAND(cmd) end
H.Check('recruit commands only point to the officer add-on',c.env.C_FriendList and c.whoQuery==nil and (c.chatSent==nil),'who='..tostring(c.whoQuery))
-- A real recipe record is required to exercise the Guild Services resolver.
local serviceDB,_,actor=K.GuildServices.Context()
assert(serviceDB and actor,'profession fixture requires a verified guild')
serviceDB.characters[actor]={professions={Alchemy={rank=300,recipes={{id=12345}},at=c.env.time()}}}
-- Open every page via the slash router, both skins.
local pages={'dashboard','cta','bounties','pvp','leaderboards','records','lfg','services','raids','alerts','settings'}
for _,skin in ipairs({'trogdor','classic'}) do
 c.env.SlashCmdList.KEEPERSWARCOMMAND('skin '..skin)
 for _,p in ipairs(pages) do
  c.printed={}
  c.env.SlashCmdList.KEEPERSWARCOMMAND(p)
  w:Advance(1)
  local bad
  for _,line in ipairs(c.printed) do if line:find('Interface error') then bad=line end end
  H.Check(skin..' page '..p..' opens without error',K.WarRoom2.Current() and K.WarRoom2.Current().id==p and not bad and #c.errors==0,bad or table.concat(c.errors,' | '):sub(1,600))
  c.errors={}
 end
end
local displayed=false
for _,widget in ipairs(c.allWidgets) do
 if type(widget.text)=='string' and widget.text:find('Spell 12345',1,true) then displayed=true end
end
H.Check('shared profession recipe reaches the public list',displayed)
-- Raid tools sub-tabs mount without error.
c.env.SlashCmdList.KEEPERSWARCOMMAND('raids')
for _,tool in ipairs({'Attendance','Roster','Ready Check','Auto-Invite','Combat Tools',"Don't Release",'Notes'}) do
 c.printed={}
 K.UI.Open('Raid Tools: '..tool);w:Advance(0.5)
 local bad;for _,line in ipairs(c.printed) do if line:find('error') then bad=line end end
 H.Check('raid tool '..tool..' mounts',not bad and #c.errors==0,bad or table.concat(c.errors,' | '):sub(1,600))
 c.errors={}
end
-- Toggle closes.
c.env.SlashCmdList.KEEPERSWARCOMMAND('')
H.Check('/kt toggles the War Room closed',not K.WarRoom2.IsShown())
c.env.SlashCmdList.KEEPERSWARCOMMAND('')
H.Check('/kt opens it again',K.WarRoom2.IsShown())
c.env.SlashCmdList.KEEPERSWARCOMMAND('help')
H.Check('/kt help prints command list',#c.printed>5)
-- Legacy-asset fingerprint check: no texture path from 1.x is ever requested.
local legacy
for path in pairs(c.textures) do
 if path:find('Textures\\') or path:find('BountyAlertFrame') or path:find('DeathAlertFrame') or path:find('KillAlertFrame') or path:find('WarRoom\\') or path:find('CommandSteel') then legacy=path end
end
H.Check('no legacy KWC 1.x texture is ever loaded',legacy==nil,legacy)
local missing
for path in pairs(c.textures) do
 local f=path:match('^Interface\\AddOns\\KeepersWarCommand\\(.+)$')
 if f then
  local p='KeepersWarCommand/'..f:gsub('\\','/')
  if not p:match('%.tga$') then p=p..'.tga' end
  local h=io.open(p,'rb');if h then h:close() else missing=p end
 end
end
H.Check('every requested KWC texture exists on disk',missing==nil,missing)
-- Previews of every alert channel.
for key,ch in pairs(K.Toast.channels) do if ch.demo then ch.demo() end end
H.Check('every alert channel previews without error',#c.errors==0,table.concat(c.errors,' | '))
-- Globals created by the add-on (should be only the documented ones).
local allowed={KWC=true,KWCDB=true,SLASH_KEEPERSWARCOMMAND1=true,SLASH_KEEPERSWARCOMMAND2=true,SLASH_KEEPERSWARCOMMAND3=true,
 KeepersRaidTools=true,KeepersRaidToolsDB=true,KeepersRaidToolsAttendanceDB=true,KeepersRaidToolsRosterDB=true,KRTForeverNotesDB=true,LibStub=true,ChatThrottleLib=true,
 -- defined by the harness itself, not the add-on:
 ACCEPT=true,CANCEL=true,NO=true,OKAY=true,YES=true,StaticPopupDialogs=true,MinimalSliderWithSteppersMixin=true}
local extra={}
for k,v in pairs(c.env) do
 if type(k)=='string' and not allowed[k] and k:match('^[%u%l]') and type(v)~='function' and not (type(v)=='table' and (v.kind or v.isFontObject)) and rawget(_G,k)==nil then
  if not ({UISpecialFrames=1,SlashCmdList=1,STANDARD_TEXT_FONT=1,Enum=1,SOUNDKIT=1,UiMapPoint=1})[k] and not k:match('^C_') and not k:match('^ERR_') and not k:match('^COMBATLOG') and k~='_G' then extra[#extra+1]=k end
 end
end
table.sort(extra)
H.Check('no unexpected non-frame globals',#extra==0,table.concat(extra,', '))
os.exit(H.Summary('kwc_load') and 0 or 1)
