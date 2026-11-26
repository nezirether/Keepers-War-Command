-- Public appearance: War Room Classic is the only theme (the 13-design gallery
-- was retired in 2.0.3). Persistence, assets, contrast, routes and isolation.
local H=dofile('tests/harness/wow.lua')
local world=H.World()
local first,second='Grom Warcry','Ash Ember'
world:AddMember({name=first,rank=1,guid='Player-1-0000000B'})
world:AddMember({name=second,rank=3,guid='Player-1-0000000A'})
local function boot(name,saved)
 local c=world:Client(name,{saved=saved})
 world:LoadAddon(c,'KeepersWarCommand');world:Login(c);world:Advance(6)
 return c
end
local c=boot(first)
local K=c.env.KWC
local W,T,S=K.WarRoom2,K.PublicThemes,K.WarRoomSkin
W.Show('settings')
H.Check('exactly one theme, and it is the default',#T.order==1 and T.order[1]==T.default and S.Current()==T.default and S.Active()==T.default)
local skin=T.Get()
local roles=true
for _,role in ipairs({'base','rail','surface','header','text','muted','accent','line','field','raised','accentSoft','onAccent'}) do roles=roles and type(skin.colors[role])=='table' end
H.Check('theme provides the required colour roles',roles)
local missing={}
for key,file in pairs(skin.assets) do
 local f=io.open('KeepersWarCommand/Media/WarRoomClassic/'..file..'.tga','rb')
 if f then f:close() else missing[#missing+1]=key..'='..file end
end
H.Check('every theme asset file ships',#missing==0,table.concat(missing,', '))
local _,titleParent,_,_,titleY=W.pageTitle:GetPoint(1)
local _,subParent,_,_,subY=W.pageSub:GetPoint(1)
H.Check('page title and subtitle occupy separate header lanes',
 titleParent==subParent and titleY-W.pageTitle:GetHeight()>=subY and W.pageTitle:GetWidth()>0 and W.pageSub:GetWidth()>0)

local function luminance(color)
 local function linear(v) return v<=0.04045 and v/12.92 or ((v+0.055)/1.055)^2.4 end
 return 0.2126*linear(color[1])+0.7152*linear(color[2])+0.0722*linear(color[3])
end
-- On-accent text is drawn only on button and selected-tab fills, never on the
-- bare accent colour, so those fills are what must be readable.
local minimum,worst=100,''
for _,pair in ipairs({{'text','surface'},{'muted','surface'},{'text','accentSoft'},{'accentText','header'},{'onAccent','primary'},{'onAccent','selected'},{'onAccent','dangerSoft'},{'onAccent','warnSoft'},{'onAccent','goodSoft'},{'paperText','paper'}}) do
 local a,b=luminance(skin.colors[pair[1]]),luminance(skin.colors[pair[2]])
 local ratio=(math.max(a,b)+0.05)/(math.min(a,b)+0.05)
 if ratio<minimum then minimum,worst=ratio,pair[1]..' on '..pair[2] end
end
H.Check('critical solid text and control pairs meet 4.5:1 contrast',minimum>=4.5,('%.3f %s'):format(minimum,worst))

local pages={'dashboard','cta','bounties','pvp','leaderboards','records','lfg','services','raids','alerts','settings'}
local opened=true
for _,page in ipairs(pages) do W.Show(page);opened=opened and W.Current().id==page end
H.Check('all 11 public page routes open',opened)
local frame,current,widgets=W.Frame(),W.Current(),#c.allWidgets
local w1,h1=frame:GetSize()
local netCalls,send=0,K.Net.Send
K.Net.Send=function(...) netCalls=netCalls+1;return send(...) end
for i=1,10 do S.Restore() end
K.Net.Send=send
H.Check('reapplying the theme preserves frame, page and size',W.Frame()==frame and W.Current()==current and frame:GetWidth()==w1 and frame:GetHeight()==h1)
H.Check('reapplying the theme creates no widgets and sends nothing',#c.allWidgets==widgets and netCalls==0,#c.allWidgets-widgets)

-- Old saved selections, account-wide and per character, migrate on reload.
local settings=c.env.KWCDB.settings
settings.ui2Skin='sleek';settings.ui2Appearance={['Grom Warcry']={skin='trogdor-inferno',favorites={horde=true}}}
settings.ui2Scale=1.1
local saved=world:Saved(c,{'KWCDB'});world:Drop(c);c=boot(first,saved);K=c.env.KWC
settings=c.env.KWCDB.settings
H.Check('legacy account choice resolves to the theme',K.WarRoomSkin.Current()==K.PublicThemes.default and settings.ui2Skin==K.PublicThemes.default)
H.Check('legacy character choice migrates and unrelated preferences survive',
 settings.ui2Appearance['Grom Warcry'].skin==K.PublicThemes.default and settings.ui2Appearance['Grom Warcry'].favorites.horde==true and settings.ui2Scale==1.1)
local other=boot(second)
H.Check('another character starts on the theme',other.env.KWC.WarRoomSkin.Current()==other.env.KWC.PublicThemes.default)
H.Check('no Lua runtime or UI errors',#c.errors==0 and #other.errors==0 and not table.concat(c.printed or {},'\n'):find('Interface error:',1,true),c.errors[1])
os.exit(H.Summary('appearance_gallery') and 0 or 1)
