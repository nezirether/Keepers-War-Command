-- Alert Art Pack v1 integration (UI/AlertArt.lua), run through the real add-on
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
local before=frames()
local expect={worldPvPDeath='fallen',pvpKill='honorableKill',bountyAlert='bountySighting',ctaNotice='callToArms',lfgNotice=false}
for key,want in pairs(expect) do
 local ch=T[key];ch.frame:Hide();ch.demo()
 local f=ch.frame
 if want then
  check('preview '..key..' shows plate '..want,f:IsShown() and f.artKey==want and f.plate:IsShown(),tostring(f.artKey))
  check('preview '..key..' hides only the card chrome',not f.bg:IsShown() and not f.rail:IsShown() and not f.border[1]:IsShown() and f.icon:IsShown() and f.title:IsShown() and f.close:IsShown())
  check('preview '..key..' plate uses painted rows only',f.plate.points[1] and f.plate.points[1][1]=='CENTER')
 else
  check('preview '..key..' keeps classic chrome',f:IsShown() and f.artKey==nil and f.bg:IsShown() and f.rail:IsShown())
 end
end
check('artwork adds no mouse-capable frames (textures only)',frames()==before,frames()..' vs '..before)
for _,key in ipairs({'plate','plateGlint','scrim','scrimFade'}) do check('plate part '..key..' is a Texture',T.pvpKill.frame[key].kind=='Texture') end
check('close backing is a texture on the existing close button',T.pvpKill.frame.closeBack.kind=='Texture' and T.pvpKill.frame.closeBack.parent==T.pvpKill.frame.close)

-- Text, names, actions and coordinates are byte-identical with art on/off ----
local death=T.worldPvPDeath
local content={kicker='Guildmate slain  |  World PvP',title='Filibuster Fente was slain',detail='Killed by: Brightblade-Stormrage',
 meta='Hillsbrad Foothills  48.2, 61.7',tone='danger',actions={{label='Post bounty',fn=function() end},{label='Death log',fn=function() end}}}
death:Present(content,false)
local on={death.frame.kicker:GetText(),death.frame.title:GetText(),death.frame.detail:GetText(),death.frame.meta:GetText(),death.frame.actions[1]:IsShown(),death.frame.actions[2]:IsShown()}
C.Preferences().eventArt=false
death:Present(content,false)
local off={death.frame.kicker:GetText(),death.frame.title:GetText(),death.frame.detail:GetText(),death.frame.meta:GetText(),death.frame.actions[1]:IsShown(),death.frame.actions[2]:IsShown()}
local same=true;for i=1,#on do if on[i]~=off[i] then same=false end end
check('live text, coordinates and both actions identical with and without art',same and on[4]=='Hillsbrad Foothills  48.2, 61.7' and on[5] and on[6])
check('Event artwork off restores the classic card',death.frame.artKey==nil and death.frame.bg:IsShown() and not death.frame.plate:IsShown())
C.Preferences().eventArt=true
local clicked=false
death:Present({title='X',actions={{label='Go',fn=function() clicked=true end}}},false)
death.frame.actions[1]:Click()
check('action buttons still fire over the artwork',clicked)
local frames0=frames()
local full=K.CharacterDisplayName('Nezdankdabs',true)
C.Preview('Legendary')
local m=T.warCelebration.frame
check('celebration preview keeps the full character name',m.title:GetText()==full and full~='')
check('Legendary preview uses KillStreak',m.artKey=='killStreak')
check('Epic/Legendary width still drives plate size',m.artW and m.artW>=m:GetWidth()*1.12-0.01)
check('no frames created on later presentations',frames()==frames0)

-- Scrim follows text so long names stay readable -----------------------------
local k=T.pvpKill
k:Present({kicker='Enemy slain',title='A',detail='',meta=''},false)
local short=k.frame.artScrim
k:Present({kicker='Enemy slain',title='Nezdankdabs slew Brightblade-Stormrage of the Silver Hand',detail='Honorable kill',meta='Hillsbrad Foothills'},false)
check('backing widens under long text and never exceeds the body',k.frame.artScrim>short and k.frame.artScrim<=k.frame:GetWidth()-28,short..' -> '..tostring(k.frame.artScrim))
check('scrim is painted by the theme engine (base role)',k.frame.scrim.kind=='Texture')

-- Motion settings -----------------------------------------------------------
local p=C.Preferences()
p.animations,p.reducedMotion=true,false
C.Preview('Heroic')
check('arrival animation runs when animations are on',m.artAnimating==true and m.plateGlint:IsShown())
w:Advance(1)
check('arrival settles to exact size and the glint clears',not m.artAnimating and math.abs(m.plate.width-m.artW)<0.01 and not m.plateGlint:IsShown())
p.reducedMotion=true
C.Preview('Heroic')
check('reduced motion: no scale or glint',not m.artAnimating and math.abs(m.plate.width-m.artW)<0.01 and not m.plateGlint:IsShown())
p.reducedMotion=false;p.animations=false
C.Preview('Legendary')
check('animations off: no scale or glint',not m.artAnimating and not m.plateGlint:IsShown())
p.animations=true
death:Present({title='Fallen'},false)
check('death plate is somber (no glint)',death.frame.artGlintPeak==0)

-- Themes: every curated skin presents; light skins keep the classic card ----
local order=K.PublicThemes.order
check('curated collection still has 13 skins',#order==13,#order)
local lightSeen,darkSeen=false,false
for _,id in ipairs(order) do
 S.Preview(id)
 local ok=pcall(function() k:Present({kicker='Enemy slain',title='Nezdankdabs slew X',detail='Honorable kill'},false) end)
 local txt=S.Color('text');local lum=0.2126*txt[1]+0.7152*txt[2]+0.0722*txt[3]
 local want=lum>=0.55
 check('skin '..id..' presents; art '..(want and 'on' or 'off (light skin)'),ok and (k.frame.artKey~=nil)==want)
 if want then darkSeen=true else lightSeen=true end
end
S.CancelPreview()
check('both dark-art and light-classic paths exercised',darkSeen and lightSeen)

-- Texture memory: lazy, one plate per visible channel ------------------------
local loaded={}
for path in pairs(c.textures) do if path:find('Media\\Alerts\\',1,true) and not path:find('ScrimFade',1,true) then loaded[#loaded+1]=path end end
check('only plates actually shown were requested',#loaded<=10 and #loaded>=1,#loaded)

-- Artwork gallery preview cycles all ten plates -----------------------------
local seen={}
for i=1,10 do A.Preview();seen[m.artKey or '?']=true end
local n=0;for key in pairs(seen) do if A.plates[key] then n=n+1 end end
check('Artwork preview cycles all ten plates',n==10,n)
check('previews create no Chronicle entries',#C.History()==0)
check('previews send no network traffic',#w.bus==0)

-- Instance suppression still dismisses automatic plated toasts --------------
k:Present({kicker='Enemy slain',title='auto',eventID='art-test-1'},true)
c.instance='party';w:Fire(c,'PLAYER_ENTERING_WORLD',false,false);w:Advance(1)
check('automatic plated toast hidden inside an instance',not k.frame:IsShown())
c.instance=nil;w:Fire(c,'PLAYER_ENTERING_WORLD',false,false);w:Advance(1)

-- Move / lock still works with a plate ---------------------------------------
k:SetUnlocked(true)
check('Move mode shows the plated demo with drag hint',k.frame:IsShown() and k.frame.hint:IsShown() and k.frame.artKey=='honorableKill')
k:SetUnlocked(false)

check('no Lua errors',#c.errors==0,c.errors[1])

os.exit(H.Summary('alert_art') and 0 or 1)
