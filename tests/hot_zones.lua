-- Dashboard PvP Hot Zones: aggregation, expiry, filtering, empty state, order,
-- layout, tooltips and the 24-hour tile label.
local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})
w:AddMember({name='Ash Ember',rank=3,guid='Player-1-0000000A'})
local c=w:Client('Grom Warcry')
w:LoadAddon(c,'KeepersWarCommand');w:Login(c);w:Advance(6)
local K,env=c.env.KWC,c.env
local W=K.WarRoom2
local db=env.KWCDB
local tip={}
env.GameTooltip={SetOwner=function() tip={} end,SetText=function(_,t) tip[#tip+1]=t end,AddLine=function(_,t) tip[#tip+1]=t end,Show=function() end,Hide=function() end}
W.Show('dashboard')
local page=W.pages.dashboard
-- The client raises OnSizeChanged only for real size changes; the harness always
-- does, which would loop the dashboard's pending re-layout.
local setHeight=page.content.SetHeight
page.content.SetHeight=function(self,h) if self.height~=h then setHeight(self,h) end end
local hot=page.hot
local function clean() db.worldPvPKills,db.worldPvPDeaths,db.ops,db.bounties={},{},{},{} end
local function size(width)
 W.content:SetSize(width,436);page.host:SetSize(width,436);page.content:SetSize(width,1400);page:Update();page:Layout()
end
local function shown() local n=0;for _,r in ipairs(hot.rows) do if r:IsShown() then n=n+1 end end;return n end
clean();size(656)
H.Check('empty state',#page.HotZones()==0 and shown()==0 and hot.empty:IsShown() and not hot.head:IsShown() and not hot.note:IsShown())

local now=env.time()
local function stamp(ago) return env.date('%Y-%m-%d %H:%M',now-ago) end
local function kill(zone,ago,victim,count) table.insert(db.worldPvPKills,{killer='Ash Ember',victim=victim,count=count or 1,zone=zone,at=stamp(ago)}) end
local function death(zone,ago,victim) table.insert(db.worldPvPDeaths,{victim=victim or 'Grom Warcry',killer='Unidentified Alliance attacker',zone=zone,epoch=now-ago}) end
kill('Hillsbrad Foothills',300,'A');kill('Hillsbrad Foothills',300,'A')            -- duplicate
kill('hillsbrad foothills ',600,nil,3);death('Hillsbrad Foothills',120);death('Hillsbrad Foothills',116) -- repeat report
kill('Hillsbrad Foothills',7200,'Old')                                           -- expired
kill('Ashenvale',200,'B');death('Ashenvale',900,'Ash Ember')
kill('Warsong Gulch',60,'BG');death('Scarlet Monastery',60);kill('Unknown zone',60,'U');death(nil,60,'Nobody')
kill('Durotar',60,'KB',0)                                                        -- no honor
for i,zone in ipairs({'Felwood','Desolace','Feralas','Tanaris'}) do kill(zone,1000+i*60,'C'..i) end
db.ops={
 {id=(now-100000)..'-1111',author='Grom Warcry',text='[HIGH] Ashenvale | H:A 1:1 | old but open',status='ACTIVE'},
 {id=(now-400)..'-2222',author='Grom Warcry',text='[HIGH] Ashenvale | H:A 1:1 | new',status='ACTIVE'},
 {id=(now-500)..'-3333',author='Grom Warcry',text='[HIGH] Ashenvale | H:A 1:1 | done',status='RESOLVED'},
 {id=(now-100000)..'-4444',author='Grom Warcry',text='[HIGH] Winterspring | H:A 1:1 | stale only',status='ACTIVE'},
 {id=(now-30)..'-5555',author='Grom Warcry',text='[HIGH] The Deadmines | H:A 1:1 | instance',status='ACTIVE'},
}
db.bounties={{id='b1',text='Rogue',status='ACTIVE',details={target='Rogue'},sightings={
 {who='Ash Ember',zone='Hillsbrad Foothills',receivedAt=now-30},{who='Ash Ember',zone='Hillsbrad Foothills',receivedAt=now-40},
 {who='Ash Ember',zone='Stranglethorn Vale',receivedAt=now-5000},{who='Ash Ember',zone='Molten Core',receivedAt=now-5}}}}
size(656)
local zones,clipped=page.HotZones()
local names={};for _,z in ipairs(zones) do names[#names+1]=z.zone end
H.Check('top five ranked by recorded combat',table.concat(names,',')=='Hillsbrad Foothills,Ashenvale,Felwood,Desolace,Feralas',table.concat(names,','))
local h,a=zones[1],zones[2]
H.Check('counts, case folding and duplicate removal',h.kills==4 and h.deaths==1 and h.sightings==1 and h.calls==0,('%d %d %d'):format(h.kills,h.deaths,h.sightings))
H.Check('open calls include old ones, not resolved ones',a.calls==2 and a.newCalls==2 and a.kills==1 and a.deaths==1,a.calls)
H.Check('latest activity age',h.latest==now-30 and hot.rows[1].cells.latest:GetText()=='now' and not clipped)
H.Check('instances, battlegrounds and stale-only zones are excluded',(function()
 for _,it in ipairs(page.Records()) do if it.zone=='Warsong Gulch' or it.zone=='Scarlet Monastery' or it.zone=='Molten Core' or it.zone=='The Deadmines' then return false end end
 for _,z in ipairs(zones) do if z.zone=='Winterspring' or z.zone=='Stranglethorn Vale' or z.zone=='Durotar' then return false end end
 return true
end)())
H.Check('rows render',shown()==5 and hot.rows[1].zone:GetText()=='Hillsbrad Foothills' and hot.rows[1].cells.kills:GetText()=='4' and not hot.empty:IsShown())
hot.rows[1]:GetScript('OnEnter')(hot.rows[1])
H.Check('zone tooltip explains the counts',tip[1]=='Hillsbrad Foothills' and tip[2]:find('not confirmed enemy presence',1,true))
local row=page.activity.list.rows[1];row:GetScript('OnEnter')(row)
H.Check('feed tooltip carries the full entry',tip[1]==row.item.text and tip[2]:find('Click to open',1,true))
-- Reliable records beyond the 25 shown in the feed still count.
clean();for i=1,40 do kill('Ashenvale',60+i*30,'E'..i) end;size(656)
H.Check('aggregation is not limited to the feed',page.HotZones()[1].kills==40 and #page.activity.list.data==25)
clean();for i=1,75 do kill('Ashenvale',60+i,'F'..i) end;size(656)
H.Check('a full log is disclosed',select(2,page.HotZones()) and hot.note:GetText():find('may be low',1,true))
clean();kill('Ashenvale',3500,'Edge');death('Felwood',3590);size(656)
H.Check('activity inside the hour shows',#page.HotZones()==2)
local update=page.host:GetScript('OnUpdate')
w.now=w.now+200;update(page.host,10)
H.Check('no refresh before 30 seconds',shown()==2)
update(page.host,25)
H.Check('old activity ages out with no new event',shown()==0 and hot.empty:IsShown())
H.Check('feed keeps history after zones expire',#page.activity.list.data==2)

clean()
for i=1,5 do death('An exceptionally long open world zone name number '..i,i*60) end
for _,width in ipairs({656,936,1456}) do
 size(width)
 local function top(card) local _,_,_,_,y=card:GetPoint();return -y end
 local raid
 for _,f in ipairs(c.allWidgets) do if rawget(f,'titleHeader') and tostring(f.title:GetText()):upper()=='UPCOMING RAIDS' then raid=f end end
 H.Check(width..' hot zones, feed, then raids without overlap',raid and top(hot)+hot:GetHeight()<=top(page.activity)
  and top(page.activity)+page.activity:GetHeight()<=top(raid) and top(page.notices)>=top(raid)+raid:GetHeight())
 local fits=true
 for _,r in ipairs(hot.rows) do
  local zx=14+r.zone:GetWidth()
  local _,_,_,x=r.cells.kills:GetPoint()
  if zx>r:GetWidth()+x-r.cells.kills:GetWidth() then fits=false end
 end
 H.Check(width..' zone names stay clear of the columns',fits and hot:GetWidth()==width)
end
local label=false
for _,f in ipairs(c.allWidgets) do if f.kind=='FontString' and f:GetText()=='Reports · 24h' then label=true end end
H.Check('24-hour tile is labelled as reports',label)
local widgets=#c.allWidgets;for i=1,10 do page:Update() end
H.Check('refreshing creates no widgets',#c.allWidgets==widgets)
H.Check('no Lua errors',#c.errors==0 and not table.concat(c.printed,'\n'):find('Interface error',1,true),c.errors[1] or table.concat(c.printed,'\n'))
os.exit(H.Summary('hot_zones') and 0 or 1)
