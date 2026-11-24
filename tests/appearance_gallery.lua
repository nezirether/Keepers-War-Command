-- Public gallery, appearance persistence, assets and functional isolation.
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
local expected={'trogdor','classic','sleek','horde','alliance','blood-moon'}
local function button(label)
 for _,w in ipairs(c.allWidgets) do
  local text=w.text~='' and w.text or w.title
  if w.kind=='Button' and w:IsVisible() and type(text)=='table' and text:GetText()==label and w:GetScript('OnClick') then
   return w
  end
 end
end
local function click(label)
 local w=button(label)
 if not w then return false end
 w:GetScript('OnClick')(w)
 return true
end
local roleIDs={'base','rail','surface','header','text','muted','accent','line','field','raised','accentSoft'}
local frame=W.Frame()
local width,height=frame:GetSize()
local initialPage=W.Current()
for _,id in ipairs(expected) do
 local skin=T.Get(id)
 local valid=skin~=nil
 for _,role in ipairs(roleIDs) do valid=valid and type(skin.colors[role])=='table' end
 for _,art in pairs(skin.art or {}) do
  local f=io.open('KeepersWarCommand/Media/'..art[1]..'.tga','rb')
  valid=valid and f~=nil
  if f then f:close() end
 end
 H.Check(id..' provides required roles and valid art paths',valid)
end
local appearance=button('Appearance')
H.Check('Appearance section control has its own visible label',
 appearance and appearance.text:IsVisible() and select(2,appearance.text:GetPoint(1))==appearance)
H.Check('Appearance section remains clickable and selected',click('Appearance') and appearance.selected)
local _,titleParent,_,_,titleY=W.pageTitle:GetPoint(1)
local _,subParent,_,_,subY=W.pageSub:GetPoint(1)
H.Check('page title and subtitle are bounded to independent header lanes',
 titleParent==subParent and titleY-W.pageTitle:GetHeight()>=subY and W.pageTitle:GetNumPoints()==2)

local names={trogdor='Trogdor',horde='Horde',alliance='Alliance',['blood-moon']='BloodMoon'}
for id,name in pairs(names) do
 local skin=T.Get(id)
 H.Check(name..' supplies all flagship slots',skin.art.header and skin.art.crest and skin.art.banner
  and skin.art.alert and skin.art.ornament and skin.art.thumbnail)
end
local function search(query)
 for _,widget in ipairs(c.allWidgets) do
  if widget.kind=='EditBox' and widget:IsVisible() then
   local parent=widget:GetParent()
   local field=parent and parent:GetParent()
   if field and field.label and field.label:GetText()=='SEARCH SKINS' then
    widget:SetText(query)
    widget:GetScript('OnTextChanged')(widget)
    return true
   end
  end
 end
 return false
end
assert(search('Sleek'))
local toggle=button('Toggle favorite')
local knownHandler=toggle and toggle:GetScript('OnClick')
H.Check('gallery click previews without changing the saved selection',click('Sleek') and S.Active()=='sleek' and S.Current()=='trogdor')
H.Check('preview keeps the same page, frame, bounds and callback',
 W.Current()==initialPage and W.Frame()==frame and frame:GetWidth()==width and frame:GetHeight()==height and
 toggle and toggle:GetScript('OnClick')==knownHandler)
H.Check('cancel restores the applied appearance',click('Cancel preview') and S.Active()=='trogdor')
H.Check('explicit apply saves Sleek for this character',click('Sleek') and click('Apply preview') and S.Current()=='sleek')
H.Check('favorite is stored and the favorites filter shows it',click('Toggle favorite') and click('Favorites') and button('Sleek')~=nil)
local saved=world:Saved(c,{'KWCDB'})
local other=boot(second,saved)
H.Check('another character does not inherit the explicit character selection',other.env.KWC.WarRoomSkin.Current()=='trogdor')
world:Drop(c);c=boot(first,saved);K=c.env.KWC;W,S=K.WarRoom2,K.WarRoomSkin
W.Show('settings')
H.Check('reload restores selected theme, favorite and recent history',
 S.Active()=='sleek' and K.PublicThemes.Preferences().favorites.sleek and K.PublicThemes.Preferences().recent[1]=='sleek')
H.Check('reset restores the default and updates the visible theme',click('Reset theme') and S.Current()=='trogdor' and S.Active()=='trogdor')
local pages={'dashboard','cta','bounties','pvp','leaderboards','records','lfg','services','raids','alerts','settings'}
for _,id in ipairs(expected) do
 S.Apply(id)
 for _,page in ipairs(pages) do W.Show(page) end
 local message=table.concat(c.printed or {},'\n')
 H.Check(id..' opens all public pages without a UI error',#c.errors==0 and not message:find('Interface error:',1,true))
end
for id,name in pairs(names) do
 S.Apply(id);W.Show('dashboard')
 local media=K.Kit.MEDIA
 local artwork=K.PublicThemes.Get(id).art
 local root=id=='trogdor' and 'Art\\trogdor\\' or nil
 local scene,header,crest=root and root..'dashboard' or name..'Scene',root and root..'header' or name..'Header',root and root..'crest' or name..'Crest'
 local loaded=artwork.banner[1]==scene and artwork.header[1]==header and artwork.crest[1]==crest
  and c.textures[media..scene] and c.textures[media..header] and c.textures[media..crest]
 H.Check(name..' active skin binds dashboard, header and crest assets',loaded)
end
local sample=frame:CreateTexture(nil,'ARTWORK')
sample.SetTexture=function(_,path) return path==K.Kit.MEDIA..'Emblem' end
S.DrawArt(sample,'horde','crest',46,46)
H.Check('missing flagship crest uses the guild emblem fallback',sample:GetAlpha()==1)
S.DrawArt(sample,'horde','header',700,86)
H.Check('missing optional banner leaves the solid header visible',sample:GetAlpha()==0)
W.Show('settings')
local collections,fingerprints={},{}
local count=0
for _,id in ipairs(K.PublicThemes.order) do
 local skin=K.PublicThemes.Get(id)
 collections[skin.collection]=(collections[skin.collection] or 0)+1
 local visual=skin.material..'/'..skin.trim
 assert(not fingerprints[visual],visual..' reused by '..id)
 fingerprints[visual]=true
 count=count+1
end
local registryCount,aliasCount=0,0
for id in pairs(T.entries) do
 registryCount=registryCount+1
 local replacement=T.Resolve(id)
 assert(T.Get(replacement) and not T.retired[replacement])
 if replacement~=id then aliasCount=aliasCount+1 end
end
H.Check('100 definitions, 87 valid aliases, 13 gallery entries',registryCount==100 and aliasCount==87 and count==13)
for _,group in ipairs(T.collections) do assert(collections[group]>0) end
H.Check('only populated collection filters remain',#T.collections==10)
local prefs=K.PublicThemes.Preferences()
prefs.skin='trogdor-inferno'
prefs.favorites={['trogdor-inferno']=true}
prefs.recent={'trogdor-inferno','trogdor','invalid-id','horde'}
S.Restore()
H.Check('legacy selected ID resolves without writing old preference',S.Active()=='trogdor' and prefs.skin=='trogdor-inferno')
assert(search('') and click('Favorites'))
H.Check('inherited favorite appears once and can be disabled',button('Trogdor') and not button('Trogdor Inferno') and click('Toggle favorite') and not button('Trogdor') and prefs.favorites['trogdor-inferno'])
assert(click('Recently used'))
local recent=T.Recent(prefs)
H.Check('recent IDs resolve and deduplicate without changing stored history',#recent==2 and recent[1]=='trogdor' and recent[2]=='horde' and #prefs.recent==4)
assert(click('All themes'))
for old,new in pairs(T.retired) do
 prefs.skin=old;S.Restore();assert(S.Active()==new and prefs.skin==old)
 assert(S.Preview(old) and S.Active()==new)
 S.CancelPreview();assert(S.Current()==new)
 assert(S.Apply(old) and prefs.skin==new)
end
H.Check('all 87 old selections preview, cancel and apply through mapped IDs',true)
prefs.skin=nil
c.env.KWCDB.settings.ui2Skin='graphite'
H.Check('legacy account choice resolves to visible skin',S.Current()=='sleek')
c.env.KWCDB.settings.ui2Skin=nil;S.Reset()
assert(search(''))
H.Check('collection filter shows a known matching skin',click('Warcraft Locations') and search('Dalaran') and button('Dalaran')~=nil)
assert(click('All collections') and search(''))
local netCalls=0
local send=K.Net.Send
K.Net.Send=function(...)
 netCalls=netCalls+1
 return send(...)
end
local before=os.clock()
local guildDB=c.env.KWCDB.guildPartitions
local currentFrame=W.Frame()
local currentPage=W.Current()
local oldWidth,oldHeight=currentFrame:GetSize()
local widgetCount=#c.allWidgets
local allApplied=true
local minimumContrast=100
local function luminance(color)
 local function linear(v) return v<=0.04045 and v/12.92 or ((v+0.055)/1.055)^2.4 end
 return 0.2126*linear(color[1])+0.7152*linear(color[2])+0.0722*linear(color[3])
end
local contrastPairs={{'text','surface'},{'muted','surface'},{'text','accentSoft'},{'accentText','header'},{'onAccent','accent'}}
for _,id in ipairs(K.PublicThemes.order) do
 local skin=K.PublicThemes.Get(id)
 local expectedRoles={'base','header','surface','rail','text','accent','onAccent','line','field','raised','accentSoft'}
 for _,role in ipairs(expectedRoles) do assert(type(skin.colors[role])=='table',id..' missing '..role) end
 for _,pair in ipairs(contrastPairs) do
  local a,b=luminance(skin.colors[pair[1]]),luminance(skin.colors[pair[2]])
  minimumContrast=math.min(minimumContrast,(math.max(a,b)+0.05)/(math.min(a,b)+0.05))
 end
 assert(skin.art.trim and (skin.art.thumbnail or skin.material=='blank'),id..' missing thumbnail')
 for _,art in pairs(skin.art) do
  local file=io.open('KeepersWarCommand/Media/'..art[1]:gsub('\\','/')..'.tga','rb')
  assert(file,art[1]);file:close()
 end
 allApplied=search(skin.label) and click(skin.label) and S.Active()==id and click('Apply preview') and S.Current()==id and allApplied
end
local elapsed=os.clock()-before
K.Net.Send=send
H.Check('all visible skins can be searched, previewed and applied through real gallery controls',allApplied)
H.Check('all catalog switches preserve frame, page, dimensions and guild state',
 W.Frame()==currentFrame and W.Current()==currentPage and
 currentFrame:GetWidth()==oldWidth and currentFrame:GetHeight()==oldHeight and c.env.KWCDB.guildPartitions==guildDB)
H.Check('switching every skin emits zero network sends',netCalls==0)
H.Check('gallery keeps one row pool across all curated switches',#c.allWidgets==widgetCount)
H.Check('critical solid text and control pairs meet 4.5:1 contrast',minimumContrast>=4.5,('%.3f'):format(minimumContrast))
local opened=true
for _,id in ipairs(K.PublicThemes.order) do
 S.Apply(id)
 for _,page in ipairs(pages) do W.Show(page);opened=opened and W.Current().id==page end
end
H.Check('every skin uses the same 11 working public page routes',opened)
H.Check('catalog switching produces no Lua runtime or UI errors',
 #c.errors==0 and not table.concat(c.printed or {},'\n'):find('Interface error:',1,true))
print(('13 search/preview/apply cycles: %.3fs CPU in the headless mock'):format(elapsed))
os.exit(H.Summary('appearance_gallery') and 0 or 1)
