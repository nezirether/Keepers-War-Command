-- Public visual themes. Theme entries never own frames or gameplay callbacks.
local K=KWC
local Kit=K.Kit
local T={version=1,entries={},order={},default='trogdor'}
K.PublicThemes=T

local function register(id,label,collection,description,palette,style)
 local colors={}
 for role,value in pairs(palette) do colors[role]=Kit.Hex(value) end
 local fixed={danger='F18986',dangerSoft='512A32',warn='EFC075',good='A2CF8F',
  info='A2C5F3',alliance='91B7FF',horde='F48C89'}
 for role,value in pairs(fixed) do colors[role]=colors[role] or Kit.Hex(value) end
 colors.shadow=Kit.Hex('000000',0.55)
 colors.overlay=Kit.Hex('000000',0.65)
 colors.header=colors.header or colors.surface
 T.entries[id]={id=id,label=label,collection=collection,description=description,colors=colors,
  fonts=style.fonts,art=style.art}
 T.order[#T.order+1]=id
end

register('trogdor','Trogdor','Warcraft','Forged iron, a crimson banner and molten bronze.',
 {base='1A1517',rail='251A1C',surface='2C2224',raised='393032',field='171216',hover='523431',
  line='9E6B4D',lineSoft='59403B',text='FAEDDF',muted='DED0C3',faint='BDACA1',
  accent='EEA56E',accentSoft='63362E',accentText='FFC498',header='382126'},
 {art={header={'ForgeScales',0.65},banner={'Crimson',0.4},rail={'Grain',0.14},panel={'Grain',0.10}}})
register('classic','Classic','Warcraft','Weathered stone, warm brass and textured ledger panels.',
 {base='25241E',rail='29271D',surface='383329',raised='463D2D',field='211D17',hover='565038',
  line='AC905D',lineSoft='66583E',text='FBF1D7',muted='E2D3AE',faint='C5B899',
  accent='F1CE7F',accentSoft='5B492F',accentText='FFE4A2',header='383126'},
 {fonts={display='body'},art={header={'CarvedStone',0.72},banner={'CarvedStone',0.58},rail={'Grain',0.21},panel={'Grain',0.16}}})
register('sleek','Sleek','Minimal','Clean graphite surfaces with a restrained ice-blue selection.',
 {base='151A23',rail='19212D',surface='202A37',raised='2A3646',field='111820',hover='34465A',
  line='5E768E',lineSoft='3B4B60',text='F2F6FE',muted='DAE4F2',faint='B4C3D8',
  accent='97C6FC',accentSoft='304965',accentText='C2E0FF',header='1D2836'},
 {fonts={display='narrow',body='narrow'}})
register('horde','Horde','Warcraft','Black iron and dark leather with a vermilion field standard.',
 {base='191519',rail='221818',surface='2C2221',raised='3C2C29',field='170F11',hover='583138',
  line='9C6458',lineSoft='603B3A',text='F8ECE4',muted='E0CCC2',faint='C1AEA6',
  accent='EF9283',accentSoft='672E32',accentText='FFB4A0',header='471F26'},
 {fonts={display='block'},art={header={'Crimson',0.59},banner={'Crimson',0.58},rail={'Grain',0.24}}})
register('alliance','Alliance','Warcraft','Royal blue heraldry, slate stone and warm gold.',
 {base='182237',rail='213351',surface='263858',raised='31466A',field='111C32',hover='41577E',
  line='A78D57',lineSoft='5A6883',text='F7F3E1',muted='E1E4E7',faint='C2CFDF',
  accent='F1CC83',accentSoft='405B7D',accentText='FFE6AD',header='304972'},
 {fonts={display='body'},art={header={'Grain',0.16},banner={'Grain',0.13},panel={'Grain',0.11}}})
register('blood-moon','Blood Moon','Gothic','Blackened plum metal, crimson bloom and pale gothic type.',
 {base='1A1421',rail='251929',surface='2D2132',raised='3C2B40',field='160F1D',hover='4D2B47',
  line='9A5970',lineSoft='624257',text='FAEAF4',muted='E2C5D8',faint='C7AABD',
  accent='F0A3BA',accentSoft='682D46',accentText='FFC2D7',header='3F2037'},
 {art={header={'BloodEclipse',0.75},banner={'BloodEclipse',0.86}}})

for id, art in pairs(K.ThemeArtwork) do
 for slot, entry in pairs(art) do T.entries[id].art[slot]=entry end
end
T.entries.classic.art.thumbnail={'CarvedStone',0.8}
T.entries.classic.art.ornament={'SharedCorner',0.52,1,true}
T.entries.classic.art.alert={'Grain',0.20}
T.entries.sleek.art={thumbnail={'Grain',0.22},ornament={'SharedCorner',0.23,1,true},alert={'Grain',0.10}}

local function mix(a,b,weight)
 local c={}
 for i=1,3 do c[i]=a[i]*(1-weight)+b[i]*weight end
 c[4]=1
 return c
end

function T.LoadCatalog(collections)
 local original=T.entries
 T.entries={};T.order={};T.collections={}
 for _,collection in ipairs(collections) do
  local group=collection[1]
  T.collections[#T.collections+1]=group
  for _,recipe in ipairs(collection[2]) do
   local name,base,rail,surface,accent,motif,trim,face,desc=unpack(recipe)
   local id=name:lower():gsub('&',''):gsub('[^%w]+','-'):gsub('%-$','')
   assert(not T.entries[id],'Duplicate public theme: '..id)
   local existing=original[id]
   local b,r,s,a=Kit.Hex(base),Kit.Hex(rail),Kit.Hex(surface),Kit.Hex(accent)
   local light=(b[1]*0.2126+b[2]*0.7152+b[3]*0.0722)>0.62
   local text=Kit.Hex(light and '211F24' or 'FFF7EC')
   local palette={
    base=b,rail=r,surface=s,header=mix(r,s,0.52),text=text,
    muted=mix(text,s,0.18),faint=mix(text,s,0.32),accent=a,
    accentText=mix(a,text,0.22),accentSoft=mix(s,a,0.15),
    field=mix(b,text,0.04),raised=mix(s,text,0.08),hover=mix(s,a,0.20),
    line=mix(s,a,0.66),lineSoft=mix(s,text,0.26),
    danger=Kit.Hex(light and '872936' or 'F18986'),dangerSoft=Kit.Hex(light and 'F1C9CC' or '512A32'),
    warn=Kit.Hex(light and '714B18' or 'EFC075'),good=Kit.Hex(light and '32603A' or 'A2CF8F'),
    info=Kit.Hex(light and '305482' or 'A2C5F3'),alliance=Kit.Hex(light and '233F91' or '91B7FF'),
    horde=Kit.Hex(light and '862C35' or 'F48C89'),shadow=Kit.Hex('000000',0.55),overlay=Kit.Hex('000000',0.65),
   }
   local skin=existing or {colors=palette,fonts={display=face},art={}}
   skin.id,skin.label,skin.collection,skin.description=id,name,group,desc
   skin.art=skin.art or {}
   local material='Themes\\M_'..motif
   local edge='Themes\\T_'..trim
   if motif~='blank' then
    skin.art.material={material,skin.art.crest and 0.13 or 0.62,nil,true}
    skin.art.railMark={material,0.31,nil,true}
    skin.art.panel=skin.art.panel or {material,0.06,nil,true}
    skin.art.thumbnail=skin.art.thumbnail or {material,0.81,nil,true}
    skin.art.alert=skin.art.alert or {material,0.15,nil,true}
   end
   skin.art.trim={edge,0.9,nil,true}
   skin.art.seal={edge,0.60,nil,true}
   if motif~='blank' and not skin.art.crest then
    skin.art.sigil={material,0.79,nil,true}
   end
   local tailored=trim=='forged' or trim=='brackets' or trim=='crown' or trim=='monolith'
   skin.art.control={edge,tailored and 0.31 or 0.17,nil,true}
   skin.art.tab={edge,tailored and 0.30 or 0.13,nil,true}
   skin.material,skin.trim=motif,trim
   skin.marker=(trim=='forged' or trim=='monolith') and 4 or (trim=='edge' or trim=='inset') and 1 or 2
   skin.colors.pressed=mix(skin.colors.hover or palette.hover,skin.colors.accent,0.12)
   skin.colors.onAccent=mix(skin.colors.accent,Kit.Hex(light and 'FFFFFF' or '16121A'),0.94)
   local production=K.ProductionThemeArtwork and K.ProductionThemeArtwork[id]
   if production then
    for slot,entry in pairs(production) do skin.art[slot]=entry end
    skin.art.sigil=nil
    skin.art.seal={production.trim[1],0.35}
    skin.art.control={production.trim[1],0.22}
    skin.art.tab={production.trim[1],0.18}
    skin.art.panel={production.material[1],0.06}
    skin.art.railMark={production.material[1],0.23}
   end
   T.entries[id]=skin
   T.order[#T.order+1]=id
  end
 end
end

function T.Get(id) return T.entries[id] end

-- Only appearance is character-scoped. The prior account-wide selection is a
-- migration fallback for each character until an explicit selection is saved.
function T.Preferences(create)
 local settings=KWCDB and KWCDB.settings
 local guid=UnitGUID and UnitGUID('player')
 if not settings or type(guid)~='string' or (issecretvalue and issecretvalue(guid)) or guid=='' then return end
 local characters=settings.ui2Appearance
 if create and type(characters)~='table' then characters={};settings.ui2Appearance=characters end
 if type(characters)~='table' then return end
 local profile=characters[guid]
 if create and type(profile)~='table' then profile={favorites={},recent={}};characters[guid]=profile end
 return type(profile)=='table' and profile or nil
end

function T.Saved()
 local profile=T.Preferences()
 local settings=KWCDB and KWCDB.settings
 local id=profile and profile.skin or settings and settings.ui2Skin
 return T.Resolve(id) or T.default
end

-- Project historical preferences onto the visible catalog. Reads never rewrite saved choices.
function T.Resolve(id)
 if T.entries[id] then return T.retired[id] or id end
end

function T.Recent(profile)
 local recent,seen={},{}
 for _,old in ipairs(profile and profile.recent or {}) do
  local id=T.Resolve(old)
  if id and not seen[id] then
   recent[#recent+1]=id
   seen[id]=true
  end
 end
 return recent
end

function T.IsFavorite(id,profile)
 local favorites=profile and profile.favorites
 if not favorites then return false end
 if favorites[id]~=nil then return favorites[id] end
 for old,enabled in pairs(favorites) do
  if enabled and T.retired[old]==id then return true end
 end
 return false
end

function T.Save(id)
 id=T.Resolve(id)
 local profile=T.Preferences(true)
 if not profile or not T.Get(id) then return false end
 profile.skin=id
 local recent={id}
 for _,old in ipairs(profile.recent or {}) do
  if old~=id and #recent<6 and T.Get(old) then recent[#recent+1]=old end
 end
 profile.recent=recent
 return true
end

function T.ToggleFavorite(id)
 id=T.Resolve(id)
 local profile=T.Preferences(true)
 if not profile or not T.Get(id) then return false end
 profile.favorites=profile.favorites or {}
 profile.favorites[id]=not T.IsFavorite(id,profile)
 return true
end
