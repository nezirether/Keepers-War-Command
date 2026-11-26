-- Dashboard World PvP activity feed: filtering, order, deduplication, limits,
-- missing data, empty state, layout and click-through.
local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})
w:AddMember({name='Ash Ember',rank=3,guid='Player-1-0000000A'})
local c=w:Client('Grom Warcry')
w:LoadAddon(c,'KeepersWarCommand');w:Login(c);w:Advance(6)
local K,env=c.env.KWC,c.env
local W=K.WarRoom2
local db=env.KWCDB
W.Show('dashboard')
local page=W.pages.dashboard
local card=page.activity
-- The client raises OnSizeChanged only when a size really changes; the harness
-- always raises it, which would loop the dashboard's pending re-layout.
local setHeight=page.content.SetHeight
page.content.SetHeight=function(self,h) if self.height~=h then setHeight(self,h) end end
local function clean() db.worldPvPKills,db.worldPvPDeaths,db.ops,db.bounties={},{},{},{} end
local function shown() local n=0;for _,r in ipairs(card.list.rows) do if r:IsShown() then n=n+1 end end;return n end
local function size(width)
 W.content:SetSize(width,436);page.host:SetSize(width,436);page.content:SetSize(width,900)
 page:Update();page:Layout()
 for _,r in ipairs(card.list.rows) do r:SetWidth(width-38);r:FitColumns() end
end
clean();size(656)
H.Check('empty feed shows its empty state',#page.Activity()==0 and card.empty:IsShown() and not card.list:IsShown())

local now=env.time()
local function stamp(ago) return env.date('%Y-%m-%d %H:%M',now-ago) end
db.worldPvPKills={
 {killer='Ash Ember',victim='Aurelius',count=1,zone='Hillsbrad Foothills',at=stamp(600)},
 {killer='Ash Ember',victim='Aurelius',count=1,zone='Hillsbrad Foothills',at=stamp(600)},
 {killer='Ash Ember',count=2,zone='Unknown zone',at=stamp(900)},
 {killer='Ash Ember',count=2,zone='Unknown zone',at=stamp(900)},
 {killer='Ash Ember',victim='Lowbie',count=0,zone='Durotar',at=stamp(60),method='Killing blow (no honor)'},
 {killer='Ash Ember',victim='Flagrunner',count=1,zone='Warsong Gulch',at=stamp(60)},
 {killer='Ash Ember',victim='Nowhen',count=1,zone='Durotar'},
 {killer='Ash Ember',victim='Future',count=1,zone='Durotar',at=stamp(-7200)},
}
db.worldPvPDeaths={
 {victim='Grom Warcry',killer='Killed by: Aurelius',zone='Ashenvale',epoch=now-100},
 {victim='Grom Warcry',killer='Killed by: Aurelius',zone='Ashenvale',epoch=now-96},
 {victim='Ash Ember',killer='Suspected: Rogue',zone='Ashenvale',epoch=now-300},
}
db.ops={
 {id=(now-200)..'-1111',author='Grom Warcry',text='[HIGH] Tarren Mill | H:A 3:5 | Hold',created=now,status='ACTIVE'},
 {id=(now-5000)..'-2222',author='Grom Warcry',text='no zone here',created=now,status='RESOLVED'},
 {id=(now-50)..'-3333',author='Grom Warcry',text='[HIGH] Durotar - x',status='CANCELLED'},
 {id='legacy',author='Grom Warcry',text='[HIGH] Durotar - x',created=now,status='ACTIVE'},
}
db.bounties={
 {id='b1',text='Aurelius @ Ashenvale',status='COMPLETED',modifiedAt=now-30,updatedBy='Grom Warcry',
  details={target='Aurelius'},sightings={{who='Ash Ember',zone='Felwood',receivedAt=now-400},{who='Ash Ember',zone='Felwood',receivedAt=now-390},{who='Ash Ember',zone='Felwood'}}},
 {id='b2',text='Relayed - reason',status='COMPLETED',modifiedAt=now-4000,updatedBy='Ash Ember',relayedBy='Ash Ember'},
 {id='b3',text='Untimed',status='COMPLETED'},
 {id='b4',text='Open',status='ACTIVE',modifiedAt=now},
}
size(656)
local feed=page.Activity()
local lines={};for _,it in ipairs(feed) do lines[#lines+1]=it.kind..': '..it.text..' ['..tostring(it.zone)..']' end
local text=table.concat(lines,'\n')
local expected={
 'bounty: Bounty on Aurelius completed - marked by Grom Warcry [nil]',
 'death: Grom Warcry died to Aurelius [Ashenvale]',
 'cta: Grom Warcry called to arms [Tarren Mill]',
 'death: Ash Ember died (suspected: Rogue) [Ashenvale]',
 'sighting: Aurelius sighted by Ash Ember [Felwood]',
 'kill: Ash Ember slew Aurelius [Hillsbrad Foothills]',
 'kill: Ash Ember scored a kill (victim not identified)  x2 [nil]',
 'kill: Ash Ember scored a kill (victim not identified)  x2 [nil]',
 'bounty: Bounty on Relayed completed [nil]',
 'cta: Grom Warcry called to arms [nil]',
}
H.Check('filtering, wording, deduplication and newest-first order',text==table.concat(expected,'\n'),'\n'..text)
H.Check('rows render and the empty state clears',shown()==7 and card.list:IsShown() and not card.empty:IsShown(),shown())
H.Check('relative time shown',card.list.rows[1].age:GetText()=='now' and card.list.rows[2].age:GetText()=='1m')
local savedKills=#db.worldPvPKills
page.Activity();H.Check('building the feed changes no saved data',#db.worldPvPKills==savedKills and #db.bounties==4 and db.activity==nil)

for i=1,60 do table.insert(db.worldPvPKills,1,{killer='Ash Ember',victim='Enemy '..i,count=1,zone='An exceptionally long open world zone name',at=stamp(i*60)}) end
size(656)
H.Check('feed is capped at 25',#page.Activity()==25 and #card.list.data==25)
card.list:GetScript('OnMouseWheel')(card.list,-100)
H.Check('scrolling reaches the 25th entry',card.list.rows[shown()].item==card.list.data[25])
card.list:ScrollTo(1)
for _,width in ipairs({656,936,1456}) do
 size(width)
 local fits=true
 for _,r in ipairs(card.list.rows) do if r:IsShown() and 106+r.text:GetWidth()+r.zone:GetWidth()+56>r:GetWidth() then fits=false end end
 H.Check(width..' columns fit inside the row',fits)
 local _,_,_,_,top=card:GetPoint()
 local _,_,_,_,y2=page.notices:GetPoint();H.Check(width..' notices sit below the feed',-y2>=-top+card:GetHeight(),-y2)
 H.Check(width..' feed spans the dashboard',card:GetWidth()==width)
end
local widgets=#c.allWidgets
for i=1,10 do page:Update() end
H.Check('refreshing creates no widgets',#c.allWidgets==widgets)

-- A kill arriving from a guildmate reaches the visible feed without polling.
clean();size(656)
w:Fire(c,'CHAT_MSG_ADDON','KWC3','2;WORLDKB;Victim;Durotar','GUILD',w.roster[2].name)
w:Advance(3)
H.Check('a no-honor killing blow is not listed',#card.list.data==0)
w:Fire(c,'CHAT_MSG_ADDON','KWC3','2;WORLDKILL;Marked;1;Durotar','GUILD',w.roster[2].name)
w:Advance(3)
H.Check('a received honorable kill appears live',#card.list.data==1 and card.list.data[1].text=='Ash Ember slew Marked',#card.list.data)
card.list.rows[1]:Click()
H.Check('a row opens its page',W.Current().id=='pvp')
H.Check('no Lua errors',#c.errors==0 and not table.concat(c.printed,'\n'):find('Interface error',1,true),c.errors[1] or table.concat(c.printed,'\n'))
os.exit(H.Summary('activity_feed') and 0 or 1)
