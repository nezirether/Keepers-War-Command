-- World PvP flagship leaderboard: sorting, Warlord recognition, tabs, empty and
-- populated boards, geometry, frame reuse and texture packaging.
local H=dofile('tests/harness/wow.lua')
local w=H.World()
local viewer='Grom Warcry'
w:AddMember({name=viewer,rank=1,guid='Player-1-0000000B'})
local long='Bartholomew Emberwardenstormcaller'
local names={'Ash Ember',long,'Cinder Vale','Dorn Hollow','Ember Reach','Flint Marsh','Gale Thorne','Hearth Oakes','Iron Wick','Juniper Sol'}
for i,name in ipairs(names) do w:AddMember({name=name,rank=3,guid=('Player-1-%08X'):format(200+i)}) end
local c=w:Client(viewer)
w:LoadAddon(c,'KeepersWarCommand');w:Login(c);w:Advance(6)
local K=c.env.KWC
local W=K.WarRoom2
local page=W.pages.leaderboards

local function find(list,name) for _,row in ipairs(list.rows) do if row:IsShown() and row.item.name==name then return row end end end
local function shown(list) local n=0;for _,row in ipairs(list.rows) do if row:IsShown() then n=n+1 end end;return n end
local function texture(t) return (t:GetTexture() or ''):match('([^\\]+)$') end
local function frames() local n=0;for _ in ipairs(c.allWidgets) do n=n+1 end;return n end
-- The harness cannot resolve opposing anchors, so give the page its real size.
local function size(width,height)
 W.content:SetSize(width,height);page.host:SetSize(width,height)
 page:Update()
 page.hero:SetWidth(width);page.tabs:SetWidth(width)
 page.bar:SetWidth(width);page.bar:Layout(width)
 local listH=height-36-6-page.hero:GetHeight()-8-page.bar:GetHeight()-10-29-6
 for _,list in pairs(page.boards) do
  list:SetSize(width,listH);list.heading:SetWidth(width)
  for _,row in ipairs(list.rows) do row:SetWidth(width-10) end
 end
 page:Update()
 return listH
end

W.Show('leaderboards')
H.Check('page opens without errors',W.Current()==page and #c.errors==0,c.errors[1])
H.Check('World PvP is the default board',page.boards.world:IsShown() and not page.boards.battleground:IsShown() and not page.boards.lifetime:IsShown())
size(656,436)
local world=page.boards.world
H.Check('nobody is a Warlord before any score is shared',(function()
 for _,row in ipairs(world.rows) do if row:IsShown() and (row.designated or row.emblem:IsShown()) then return false end end
 return true
end)())

-- Scores arrive through the real public protocol handler.
local scores={['Ash Ember']=1234567,[long]=9000,['Cinder Vale']=800,['Dorn Hollow']=700,['Ember Reach']=600,['Flint Marsh']=500,['Gale Thorne']=0}
local now=c.env.time()
for name,value in pairs(scores) do
 w:Fire(c,'CHAT_MSG_ADDON','KWC3',('2;HKAREA;%d;%d;%d;%d'):format(value,now,2000-math.floor(value/1000),now),'GUILD',name)
 w:Fire(c,'CHAT_MSG_ADDON','KWC3','2;HONOR;'..(5000000-value),'GUILD',name)
end
page:Update()
local data=world.data
H.Check('world board sorts by world HKs',data[1].name=='Ash Ember' and data[2].name==long and data[3].name=='Cinder Vale' and data[6].name=='Flint Marsh' and data[7].name=='Gale Thorne')
H.Check('all five leaders are visible at the minimum window',shown(world)>=5,shown(world))
local expect={{'Row_Legendary','Emblem_Legendary'},{'Row_Epic','Emblem_Epic'},{'Row_Epic','Emblem_Epic'},{'Row_Elite','Emblem_Elite'},{'Row_Elite','Emblem_Elite'}}
for i=1,5 do
 local row=world.rows[i]
 H.Check('rank '..i..' tier art and Warlord designation',
  texture(row.art[1])==expect[i][1] and texture(row.art[3])==expect[i][1] and row.emblem:IsShown() and texture(row.emblem)==expect[i][2]
  and row.sub:GetText():find('WARLORD OF TROGDOR',1,true) and row.rank:GetText()=='#'..i)
end
H.Check('large totals are grouped',world.rows[1].val:GetText()=='1,234,567',world.rows[1].val:GetText())
size(656,700)
local sixth=find(world,'Flint Marsh')
H.Check('rank 6 uses the standard row with no recognition',sixth and texture(sixth.art[1])=='Row_Standard' and not sixth.emblem:IsShown() and not sixth.sub:IsShown())
local waiting=find(world,'Hearth Oakes')
H.Check('members without data show Awaiting Stats, unranked',waiting and waiting.rank:GetText()=='-' and waiting.val:GetText()=='Awaiting Stats')

-- Search keeps true ranks, and pooled rows drop previous recognition.
local function search(text) page.bar.search:SetText(text);page.bar.search:GetScript('OnTextChanged')(page.bar.search) end
search('flint')
H.Check('search keeps the global rank',shown(world)==1 and world.rows[1].rank:GetText()=='#6')
H.Check('reused row clears Warlord art',texture(world.rows[1].art[1])=='Row_Standard' and not world.rows[1].emblem:IsShown() and not world.rows[1].designated)
search('nobody at all')
H.Check('empty search result explains itself',shown(world)==0 and world.empty:IsShown() and world.empty.h:GetText():find('No guildmate matches',1,true))
search('')
H.Check('search clears back to the full board',shown(world)>=5 and not world.empty:IsShown())

-- Stale scores are marked without losing rank.
local at=c.env.KWCDB.pvp
w.now=w.now+90000;page:Update()
H.Check('stale Warlord keeps designation and says stale',world.rows[1].sub:GetText():find('STALE',1,true) and world.rows[1].designated)
w.now=w.now-90000;page:Update()
H.Check('stale marker clears when data is fresh',not world.rows[1].sub:GetText():find('STALE',1,true))

-- Tabs.
local function tab(value) for _,b in ipairs(page.tabs.segs) do if b.value==value then return b end end end
local function selected() local out={};for _,b in ipairs(page.tabs.segs) do if b.state=='Tab_Selected' then out[#out+1]=b.value end end;return table.concat(out,',') end
for _,value in ipairs({'battleground','lifetime','world','lifetime','battleground'}) do
 tab(value):Click()
 local only=true
 for id,list in pairs(page.boards) do if list:IsShown()~=(id==value) or list.heading:IsShown()~=(id==value) then only=false end end
 H.Check('tab '..value..' shows exactly its board and highlight',only and selected()==value,selected())
 size(656,436)
 H.Check(value..' showcase art only on World PvP',page.hero.art:IsShown()==(value=='world') and page.hero.crest:IsShown()==(value~='world') and page.hero.title:IsShown()==(value~='world'))
end
local other=tab('lifetime')
other:GetScript('OnEnter')(other);H.Check('hover art applies to an unselected tab',other.state=='Tab_Hover')
other:GetScript('OnLeave')(other);H.Check('hover art clears',other.state=='Tab_Inactive')
for _,id in ipairs({'battleground','lifetime'}) do
 tab(id):Click();size(656,436)
 local list=page.boards[id]
 local plain=shown(list)>=7
 for _,row in ipairs(list.rows) do
  if row.emblem or row.art or row.designated or row.name:GetText():find('Warlord',1,true) then plain=false end
 end
 H.Check(id..' is a plain ranking table',plain,shown(list))
end
H.Check('battleground sorting uses its own statistic',page.boards.battleground.data[1].name=='Cinder Vale' and page.boards.battleground.data[1].value==2000 and page.boards.battleground.data[7].name=='Ash Ember' and page.boards.battleground.data[7].value==766)
tab('lifetime'):Click()
H.Check('lifetime sorting uses lifetime totals',page.boards.lifetime.data[1].name=='Gale Thorne' and page.boards.lifetime.data[1].value==5000000)

-- Geometry across the supported window range.
tab('world'):Click()
for _,case in ipairs({{656,436,'WorldPvP_Header'},{936,636,'Warlords_Banner'},{1456,976,'Warlords_Banner'}}) do
 local width,height,art=case[1],case[2],case[3]
 local listH=size(width,height)
 local label=width..'x'..height
 H.Check(label..' hero art choice and aspect',texture(page.hero.art)==art and math.abs(page.hero.art:GetWidth()/page.hero.art:GetHeight()-5)<0.01 and page.hero.art:GetWidth()<=width)
 H.Check(label..' room for the five Warlords',listH>=5*44+4*2,listH)
 local tabsRight=0
 for _,b in ipairs(page.tabs.segs) do local p={b:GetPoint()};tabsRight=math.max(tabsRight,p[4]+b:GetWidth()) end
 H.Check(label..' tabs fit',tabsRight<=width)
 local fits=true
 for _,row in ipairs(world.rows) do if row:IsShown() then
  local rw=row:GetWidth()
  if 98+row.name:GetWidth()+row.val:GetWidth()+18>rw then fits=false end
  if row.art[1]:GetWidth()+row.art[3]:GetWidth()>=rw then fits=false end
  -- end caps keep their source proportions
  if math.abs(row.art[1]:GetWidth()-48*44/64)>0.01 then fits=false end
 end end
 H.Check(label..' names, values and row art stay inside the row',fits)
end

-- Scrolling and frame reuse.
size(656,436)
local before=frames()
world:GetScript('OnMouseWheel')(world,-1)
H.Check('wheel scrolls past the leaders',world.offset>0 and world.rows[1].item.name==world.data[world.offset+1].name)
world:ScrollTo(1)
for i=1,10 do tab('lifetime'):Click();tab('world'):Click();world:GetScript('OnMouseWheel')(world,-1);world:GetScript('OnMouseWheel')(world,1) end
page:Update()
H.Check('repeated tab switching and scrolling creates no widgets',frames()==before,frames()-before)
H.Check('no Lua errors',#c.errors==0 and not table.concat(c.printed,'\n'):find('Interface error',1,true),c.errors[1])

-- Packaging: every referenced texture ships, and every shipped texture is used.
local dir='KeepersWarCommand/Media/WarRoomClassic/WorldPvP/'
local source=assert(io.open('KeepersWarCommand/UI/Pages/Leaderboards.lua')):read('*a')
local used={}
for path in pairs(c.textures) do local name=path:match('WorldPvP\\([%w_]+)$');if name then used[name]=true end end
for name in source:gmatch("'([%a]+_[%a_]+)'") do if name:find('^Row_') or name:find('^Tab_') or name:find('^Icon_') or name:find('^Emblem_') or name:find('^KWC_') or name:find('^WorldPvP_') or name:find('^Warlords_') then used[name]=true end end
local count=0
for name in pairs(used) do
 count=count+1
 local file=io.open(dir..name..'.tga','rb')
 local head=file and file:read(18)
 if file then file:close() end
 H.Check('texture '..name..' exists as 32-bit uncompressed TGA',head and head:byte(3)==2 and head:byte(17)==32)
 if head then
  local width,height=head:byte(13)+256*head:byte(14),head:byte(15)+256*head:byte(16)
  local function pow2(n) while n>1 and n%2==0 do n=n/2 end;return n==1 end
  H.Check('texture '..name..' has power-of-two dimensions',pow2(width) and pow2(height))
 end
end
H.Check('all 17 shipped textures are referenced',count==17,count)
os.exit(H.Summary('world_pvp_board') and 0 or 1)
