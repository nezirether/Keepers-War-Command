-- Alert artwork. War Room Classic (the only theme) draws its own channel plates,
-- so the older Alert Art Pack plates stand down; its mapping and assets remain.
-- Run through the real add-on
-- files in TOC order inside the simulated client. Presentation-only checks:
-- mapping, live text/button preservation, mouse safety, theme policy, motion
-- settings, texture loading and asset integrity. Simulated: no in-game capture.
local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Nezdankdabs',rank=3,guid='Player-1-0000000A'})
w:AddMember({name='Filibuster Fente',rank=3,guid='Player-1-0000000B'})
local c=w:Client('Nezdankdabs');w:LoadAddon(c,'KeepersWarCommand');w:Login(c);w:Advance(6)
local K=c.env.KWC
local A,T,S,C=K.AlertArt,K.Toast.channels,K.WarRoomSkin,K.Celebrations
local check=H.Check

-- Registry and assets -------------------------------------------------------
check('AlertArt module loaded and hooked into Toast',A~=nil and K.Toast.Decorate==A.Apply)
check('ten plates registered in a fixed order',#A.order==10)
local function tgaHeader(path)
 local f=io.open(path,'rb');if not f then return nil end
 local h=f:read(18);local size=f:seek('end');f:close()
 local function u16(i) return h:byte(i)+h:byte(i+1)*256 end
 return {type=h:byte(3),w=u16(13),h=u16(15),bits=h:byte(17),desc=h:byte(18),size=size}
end
local total=0
for _,key in ipairs(A.order) do
 local plate=A.plates[key]
 local t=tgaHeader('KeepersWarCommand/Media/'..plate.file:gsub('\\','/')..'.tga')
 check('asset '..key..' is a 512x256 uncompressed 32-bit bottom-left TGA',t and t.type==2 and t.w==512 and t.h==256 and t.bits==32 and t.desc==8,t and (t.w..'x'..t.h))
 total=total+(t and t.size or 0)
 check('plate '..key..' has a panel centre within the safe band',plate.cy>=0.44 and plate.cy<=0.56)
end
check('scrim fade texture present',tgaHeader('KeepersWarCommand/Media/Alerts/ScrimFade.tga')~=nil)
check('alert plates stay under 5.5 MiB on disk',total<5.5*1048576,total)
local toc=io.open('KeepersWarCommand/KeepersWarCommand.toc'):read('*a')
check('TOC loads AlertArt after Celebrations',(toc:find('UI/Celebrations.lua',1,true) or 1e9)<(toc:find('UI/AlertArt.lua',1,true) or 0))

-- Event mapping -------------------------------------------------------------
local R=A.Resolve
check('honorable kill -> HonorableKill',R('pvpKill',{kicker='Enemy slain'})=='honorableKill')
check('own killing blow -> KillingBlow',R('pvpKill',{level='Heroic',evidence='Reported own killing blow'})=='killingBlow')
check('guildmate death -> Fallen',R('worldPvPDeath',{})=='fallen')
check('bounty sighting -> BountySighting',R('bountyAlert',{})=='bountySighting')
check('new Call to Arms -> CallToArms',R('ctaNotice',{})=='callToArms')
check('Guild LFG keeps the classic card',R('lfgNotice',{})==nil)
check('streak celebration -> KillStreak',R('warCelebration',{category='streaks'})=='killStreak')
check('personal milestone -> Commendation',R('warCelebration',{category='milestones'})=='commendation')
check('bounty completed -> BountyClaimed',R('warCelebration',{category='bounties'})=='bountyClaimed')
check('CTA outcome (own or guild) -> CTAVictory',R('warCelebration',{category='cta'})=='ctaVictory' and R('warCelebration',{category='guild'})=='ctaVictory')
check('level previews: Standard/Heroic/Legendary',R('warCelebration',{level='Standard'})=='commendation' and R('warCelebration',{level='Heroic'})=='ctaVictory' and R('warCelebration',{level='Legendary'})=='killStreak')
check('explicit content.art wins; false opts out; unknown ignored',R('pvpKill',{art='bountyPosted'})=='bountyPosted' and R('pvpKill',{art=false})==nil and R('pvpKill',{art='nope'})==nil)
check('unknown channels get no plate',R('someFutureChannel',{})==nil)

-- Live presentation on every existing channel ------------------------------
local function frames() local n=0;for _,x in ipairs(c.allWidgets) do if x.kind~='Texture' and x.kind~='FontString' then n=n+1 end end;return n end
local function plateStrips(f,key)
 local path,n=S.AssetPath(key),0
 for _,x in ipairs(c.allWidgets) do if x.kind=='Texture' and x.parent==f and x:GetTexture()==path then n=n+1 end end
 return n
end
local classicPlate={worldPvPDeath='alertDeath',pvpKill='alertPvPKill',bountyAlert='alertBounty',ctaNotice='alertCta',lfgNotice='alertLFG'}
local before=frames()
for key,plate in pairs(classicPlate) do
 local ch=T[key];ch.frame:Hide();ch.demo()
 local f=ch.frame
 check('preview '..key..' shows the War Room Classic plate',f:IsShown() and plateStrips(f,plate)==3,plateStrips(f,plate))
 check('preview '..key..' keeps live text and close control',f.title:GetText()~='' and f.title:IsShown() and f.close:IsShown())
 check('preview '..key..' adds no second art layer',f.artKey==nil and f.plate==nil)
 local info=tgaHeader('KeepersWarCommand/Media/WarRoomClassic/'..S.AssetPath(plate):match('([^\\]+)$')..'.tga')
 check('plate '..plate..' is a 32-bit power-of-two TGA',info and info.type==2 and info.bits==32 and info.w%2==0 and info.h%2==0)
end
check('presentation adds no frames',frames()==before,frames()..' vs '..before)

-- Text, names, actions and coordinates do not depend on the artwork setting --
local death=T.worldPvPDeath
local content={kicker='Guildmate slain  |  World PvP',title='Filibuster Fente was slain',detail='Killed by: Brightblade-Stormrage',
 meta='Hillsbrad Foothills  48.2, 61.7',tone='danger',actions={{label='Post bounty',fn=function() end},{label='Death log',fn=function() end}}}
death:Present(content,false)
local on={death.frame.kicker:GetText(),death.frame.title:GetText(),death.frame.detail:GetText(),death.frame.meta:GetText(),death.frame.actions[1]:IsShown(),death.frame.actions[2]:IsShown()}
C.Preferences().eventArt=false
death:Present(content,false)
local off={death.frame.kicker:GetText(),death.frame.title:GetText(),death.frame.detail:GetText(),death.frame.meta:GetText(),death.frame.actions[1]:IsShown(),death.frame.actions[2]:IsShown()}
local same=true;for i=1,#on do if on[i]~=off[i] then same=false end end
check('live text, coordinates and both actions identical with the setting on or off',same and on[4]=='Hillsbrad Foothills  48.2, 61.7' and on[5] and on[6])
C.Preferences().eventArt=true
local clicked=false
death:Present({title='X',actions={{label='Go',fn=function() clicked=true end}}},false)
death.frame.actions[1]:Click()
check('action buttons still fire over the artwork',clicked)
local frames0=frames()
local full=K.CharacterDisplayName('Nezdankdabs',true)
C.Preview('Legendary')
-- Each celebration level has its own channel.
local m=assert(T.warCelebrationLegendary,'legendary channel').frame
check('celebration preview keeps the full character name',m.title:GetText()==full and full~='')
check('no frames created on later presentations',frames()==frames0)

-- Motion settings -----------------------------------------------------------
local p=C.Preferences()
local kill=T.pvpKill
local function alphaAfter(step)
 kill:Present({kicker='Enemy slain',title='Motion'},false)
 kill.frame:GetScript('OnUpdate')(kill.frame,step)
 return kill.frame:GetAlpha()
end
p.animations,p.reducedMotion=true,false
check('arrival fades in when animations are on',alphaAfter(0.04)<1)
p.reducedMotion=true
check('reduced motion: shown at full strength',alphaAfter(0.04)==1)
p.reducedMotion=false;p.animations=false
check('animations off: shown at full strength',alphaAfter(0.04)==1)
p.animations=true

-- Theme ----------------------------------------------------------------------
check('one theme is offered',#K.PublicThemes.order==1)
check('the older plates stand down under the themed alerts',A.Enabled()==false)

-- Only the classic plates are loaded ------------------------------------------
local loaded=0
for path in pairs(c.textures) do if path:find('Media\\Alerts\\',1,true) then loaded=loaded+1 end end
check('no unused older plate is loaded',loaded==0,loaded)

-- Artwork gallery preview cycles all ten labels -------------------------------
local seen={}
local levels={T.warCelebration,T.warCelebrationHeroic,T.warCelebrationLegendary}
for i=1,10 do
 for _,ch in ipairs(levels) do ch.frame:Hide() end
 A.Preview();w:Advance(1)
 for _,ch in ipairs(levels) do if ch.frame:IsShown() then seen[ch.frame.kicker:GetText():match('(%d+)/10') or '?']=true end end
end
local n=0;for i=1,10 do if seen[tostring(i)] then n=n+1 end end
check('Artwork preview cycles all ten entries',n==10,n)
check('previews create no Chronicle entries',#C.History()==0)
check('previews send no network traffic',#w.bus==0)

-- Instance suppression still dismisses automatic toasts -----------------------
local k=T.pvpKill
k:Present({kicker='Enemy slain',title='auto',eventID='art-test-1'},true)
check('automatic toast appears in the open world',k.frame:IsShown())
c.instance='party';w:Fire(c,'PLAYER_ENTERING_WORLD',false,false);w:Advance(1)
check('automatic toast hidden inside an instance',not k.frame:IsShown())
c.instance=nil;w:Fire(c,'PLAYER_ENTERING_WORLD',false,false);w:Advance(1)

-- Move / lock -----------------------------------------------------------------
k:SetUnlocked(true)
check('Move mode shows the demo with a drag hint',k.frame:IsShown() and k.frame.hint:IsShown())
k:SetUnlocked(false)

check('no Lua errors',#c.errors==0,c.errors[1])

os.exit(H.Summary('alert_art') and 0 or 1)
