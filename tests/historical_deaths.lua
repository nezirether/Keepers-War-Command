-- Native Interface 16001 fixture captured in Forever: 166 total, 51 BG, 115 non-BG.
local H=dofile('tests/harness/wow.lua')
local w=H.World()
local first,second='Ash Ember','Grom Warcry'
w:AddMember({name=first,rank=3,guid='Player-1-0000000A'})
w:AddMember({name=second,rank=1,guid='Player-1-0000000B'})
local ids={[122]={60},[124]={57,59,56,64182,593},[125]={321},[21]={1501},[153]={59,1496}}
local figures={[60]='166',[57]='--',[59]='7',[56]='39',[64182]='5',[593]='9',[321]='3',[1501]='104',[1496]='12'}
local function boot(name,saved,stats)
 local c=w:Client(name,{saved=saved})
 c.env.GetStatisticsCategoryList=function() return {122,124,125,21,153} end
 c.env.GetCategoryNumAchievements=function(category) return #(ids[category] or {}) end
 c.env.GetStatistic=function(category,index)
  assert(index~=nil,'Forever statistics require category and index')
  local id=ids[category][index]
  return stats[id],false,id
 end
 w:LoadAddon(c,'KeepersWarCommand');w:Login(c)
 return c
end
local a,b=boot(first,nil,figures),boot(second,nil,{})
local A,B=a.env.KWC,b.env.KWC
local count=A.GuildRecords.DeathStatistics()
H.Check('old character starts with zero KWC deaths and 166 historical deaths',A.DeathLedger.Get().openWorld==0 and count.total==166)
H.Check('four distinct map totals produce 51 and 115, excluding boss counts',count.bg==51 and count.nonBG==115)
H.Check('PvP and instanced lifetime figures are independently read',count.pvp==104 and count.instance==3)
local function value(k,view,name)
 for _,row in ipairs(k.GuildRecords.DeathRankings(view)) do
  if row.display==name or row.name==name:lower() then return row.value end
 end
end
H.Check('lifetime and non-BG rankings immediately use native data',value(A,'lifetime',first)==166 and value(A,'nonBG',first)==115)
local function viewTab(key)
 A.WarRoom2.Show('records')
 for _,widget in ipairs(a.allWidgets) do
  if widget.kind=='Button' and widget.value==key and widget:IsVisible() then
   local click=widget:GetScript('OnClick')
   if click then click(widget);return true end
  end
 end
 return false
end
local function shows(label)
 for _,widget in ipairs(a.allWidgets) do
  if widget.kind=='FontString' and widget.text==label and widget:IsVisible() then return true end
 end
 return false
end
A.WarRoom2.Show('records')
local bar=A.WarRoom2.Current().bar
bar:SetWidth(300)
local point,relative,relativePoint=bar.seg:GetPoint()
H.Check('wrapped Records tabs have an explicit top-left parent anchor',
 point=='TOPLEFT' and relative==bar and relativePoint=='TOPLEFT' and bar.seg:GetHeight()>28)
H.Check('clicking Lifetime visibly displays 166',viewTab('lifetime') and shows('Lifetime Deaths') and shows('166'))
H.Check('clicking Non-BG visibly displays 115',viewTab('nonBG') and shows('Non-Battleground Deaths') and shows('115'))
H.Check('clicking Battlegrounds visibly displays 51',viewTab('bg') and shows('51'))
H.Check('open-world history does not display the 166 historical total',not viewTab('open'))
-- Exercise one populated Records data set and search across every sign-off skin.
local oldRankings=A.GuildRecords.DeathRankings
A.GuildRecords.DeathRankings=function(tab)
 if tab=='lifetime' then
  return {{name='longname',display='Emberwarden-LongRealmName',value=166,self=true},
   {name='other',display='Emberblade-AnotherRealm',value=145}}
 end
 return oldRankings(tab)
end
-- War Room Classic is the only appearance.
for _,id in ipairs(A.PublicThemes.order) do
 for _,size in ipairs({{920,580,308},{1280,720,668}}) do
  local W=A.WarRoom2
  W.Frame():SetSize(size[1],size[2]);bar:SetWidth(size[3])
  assert(viewTab('lifetime'))
  bar.search:SetText('Ember')
  bar.search:GetScript('OnTextChanged')(bar.search)
  A.WarRoomSkin.Restore()
  local row
  for _,widget in ipairs(a.allWidgets) do
   if widget.item and widget.item.key=='longname' and widget:IsVisible() then row=widget;break end
  end
  if row then
   row:SetWidth(size[3])
   row:GetScript('OnEnter')(row)
  end
  local visibleTabs=0
  for _,button in ipairs(bar.seg.segs) do
   if button:IsVisible() and button:GetScript('OnClick') then visibleTabs=visibleTabs+1 end
  end
  H.Check(id..' populated Records at '..size[1]..' preserves search, four tabs, score lane and full hover name',
   W.Current().bar==bar and bar.search:GetText()=='Ember' and visibleTabs==4 and
   row and row.val:GetText()=='166' and row.val:GetWidth()==68 and
   a.env.GameTooltip:GetText()=='Emberwarden-LongRealmName')
 end
end
A.WarRoomSkin.Restore()
A.GuildRecords.DeathRankings=oldRankings
bar.search:SetText('');bar.search:GetScript('OnTextChanged')(bar.search)
w:Advance(10)
H.Check('guild peer receives the authoritative totals',value(B,'lifetime',first)==166 and value(B,'nonBG',first)==115 and value(B,'battleground',first)==51)
local _,_,actor=A.GuildReadiness()
local row=B.GuildRecords.DeathBreakdown(actor)
H.Check('peer receives independent PvP and instance breakdown',row.pvp==104 and row.instance==3)

-- Force an old cached slot to move and verify native IDs, not offsets, decide the score.
ids[124]={593,64182,56,59,57}
figures[60]='169'
figures[56]='40'
a.env.KWCDB.worldPvPDeaths={{victim=first,zone='Orgrimmar',at=a.env.time()}}
A.GuildRecords.Sample();A.GuildRecords.Sample();w:Advance(15)
H.Check('updated server value replaces rather than increments stored value',value(A,'lifetime',first)==169 and value(B,'nonBG',first)==117)
figures[64182]=nil
A.GuildRecords.Sample();w:Advance(15)
H.Check('missing native map value leaves total readable and derived totals unavailable',value(A,'lifetime',first)==169 and value(A,'nonBG',first)==nil and value(B,'nonBG',first)==nil)
H.Check('unknown native value has a visible unavailable state',viewTab('nonBG') and shows('Unavailable'))

local saved=w:Saved(a,{'KWCDB'})
w:Drop(a)
figures[64182]='5'
a=boot(first,saved,figures);A=a.env.KWC;w:Advance(20)
H.Check('reload restores history and reads the current server value',value(A,'nonBG',first)==117 and #a.env.KWCDB.worldPvPDeaths==1)
w:Rename(first,'Ash Rekindled')
w:FireAll('GUILD_ROSTER_UPDATE');w:Advance(10)
H.Check('verified GUID rename moves guild statistics to the new name',value(B,'nonBG','Ash Rekindled')==117 and value(B,'nonBG',first)==nil)
A.GuildRecords.SetSharing(false);w:Advance(15)
H.Check('withdrawal removes peer results but does not hide the local historical figure',value(B,'lifetime','Ash Rekindled')==nil and value(A,'lifetime','Ash Rekindled')==169)
H.Check('no Lua errors',#a.errors==0 and #b.errors==0,table.concat(a.errors,'|')..table.concat(b.errors,'|'))
os.exit(H.Summary('historical_deaths') and 0 or 1)
