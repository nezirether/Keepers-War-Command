-- Historical game death rankings and Guild Records with separate recorded event details.
-- Clicking a member opens their death log with Drop Pin / Copy Coordinates,
-- enabled only for entries that carry real coordinates.
local K=KWC
local Kit,S,P,W=K.Kit,K.WarRoomSkin,K.WarRoomPages,K.WarRoom2
local OWNER=S.OWNER

local page={id='records',title='Deaths & Guild Records',subtitle='Historical game statistics with separate recorded event details.',group='records'}
local state={tab='lifetime',category=1,member=nil,query=''}
local list,side,head,note,catSeg
local TABS={
 bg={'Battleground deaths','From the game\'s Statistics, shared by members who enabled Guild Records sharing.'},
 lifetime={'Lifetime Deaths','Total deaths recorded by WoW Forever, including battlegrounds, PvE and environmental deaths.'},
 nonBG={'Non-Battleground Deaths','WoW Forever lifetime total minus battleground map deaths. Includes PvE and environmental deaths.'},
 halls={'Guild Records','Statistics boards from members who share Guild Records. Values are lifetime game Statistics.'},
}

local function rows()
 local out={}
 local data
 if state.tab=='lifetime' or state.tab=='nonBG' then data=K.GuildRecords.DeathRankings(state.tab)
 elseif state.tab=='bg' then data=K.GuildRecords.DeathRankings('battleground')
 else
  local cat=K.GuildRecords.categories[state.category]
  for i,board in ipairs(cat and cat.boards or {}) do
   local r=K.GuildRecords.Rankings(state.category,i)
   local leader=r[1]
   out[#out+1]={board=true,name=board[2],sub=board[3],value=leader and leader.value,leaderName=leader and (leader.display or leader.name),count=#r}
  end
  return out
 end
 local tracked={}
 for _,r in ipairs(data or {}) do if r.value~=nil or r.self then tracked[#tracked+1]=r end end
 table.sort(tracked,function(a,b) if a.value~=b.value then return (a.value or -1)>(b.value or -1) end;return tostring(a.display or a.name)<tostring(b.display or b.name) end)
 local top=tracked[1] and tracked[1].value or 0
 for i,r in ipairs(tracked) do
  local n=r.display or r.name
  if P.Matches(n,state.query) then out[#out+1]={rank=i,name=n,key=r.name,value=r.value,top=top,self=r.self} end
 end
 return out
end
local function fill(row,r)
 row.tooltipName=r.name
 if r.board then
  row.rank:SetText('')
  row.name:SetText(r.name)
  row.sub:SetText(r.sub..(r.leaderName and (' · '..r.leaderName) or ''))
  row.val:SetText(r.value and tostring(r.value) or 'No data')
  row:SetScoreLayout(true)
  return
 end
 row.rank:SetText('#'..r.rank);Kit.Paint(row.rank,OWNER,r.rank<=3 and 'accentText' or 'faint','text')
 row.name:SetText(P.Short(r.name)..(r.self and S.Code('accentText')..'  (you)|r' or ''))
 row.val:SetText(r.value==nil and 'Unavailable' or tostring(r.value))
 row:SetScoreLayout(false,r.value and r.top>0 and r.value/r.top or 0)
 Kit.Paint(row.bar,OWNER,'danger','fill')
end

-- Member death log drawer.
local function deathsFor(name)
 local out={}
 local b=P.Lower(P.Short(name))
 for _,r in ipairs(KWCDB.worldPvPDeaths or {}) do
  if P.Lower(P.Short(r.victim))==b then out[#out+1]=r end
 end
 return out
end
local function renderSide()
 local st=side.stack;st:Reset()
 for _,k in ipairs({'head','historical','summary','entries','pin','copy','pinNote','empty'}) do side[k]:Hide() end
 if not state.member then st:Place(side.empty,50);return end
 local d=deathsFor(state.member)
 side.head:Set('Death log',P.Short(state.member));st:Place(side.head,nil,12)
 if state.tab=='lifetime' or state.tab=='bg' or state.tab=='nonBG' then
  local values=K.GuildRecords.DeathBreakdown(state.member)
  local function label(n) return n==nil and 'Unavailable' or tostring(n) end
  side.historical:Set(table.concat({
   'Lifetime Deaths: '..label(values.total),
   'Battleground Deaths: '..label(values.bg),
   'Non-Battleground Deaths: '..label(values.nonBG),
   'Deaths from other players: '..label(values.pvp),
   'Raid and dungeon deaths: '..label(values.instance),
  },'\n'))
  st:Place(side.historical,nil,12)
 end
 local own=K.DeathLedger.Get and K.DeathLedger.Get()
 side.summary:Set(#d..' world PvP deaths recorded on this client'..(own and K.PvP.PlayerName and P.Lower(P.Short(K.PvP.PlayerName()))==P.Lower(P.Short(state.member)) and ('\nYour ledger: '..(own.openWorld or 0)..' open-world, '..(own.instanced or 0)..' instanced') or ''))
 st:Place(side.summary,nil,12)
 local lines={}
 side.coord=nil
 for i,r in ipairs(d) do
  if i>8 then break end
  local ev=tostring(r.killer or '')
  local who=ev:match('^Killed by: (.+)') and ('killed by '..ev:match('^Killed by: (.+)')) or ev:match('^Suspected: (.+)') and ('suspected: '..ev:match('^Suspected: (.+)')) or 'attacker unidentified'
  local c=r.x and r.y and K.Geo.Format(r.x,r.y)
  if c and not side.coord then side.coord=r end
  lines[#lines+1]=tostring(r.zone)..(c and (' ('..c..')') or '')..'\n'..S.Code('faint')..who..'  -  '..tostring(r.at)..'|r'
 end
 side.entries:Set(#lines>0 and table.concat(lines,'\n') or S.Code('faint')..'No world PvP deaths recorded for this member on this client.|r');st:Place(side.entries,nil,14)
 local has=side.coord~=nil
 side.pin:SetEnabledState(has and K.Geo.CanDropPin(),has and 'Map pins are unavailable on this client.' or 'No coordinates recorded for these deaths.')
 side.copy:SetEnabledState(has,'No coordinates recorded for these deaths.')
 st:Place(side.pin,30,6);st:Place(side.copy,30,8)
 side.pinNote:SetText(has and 'Uses the most recent death with coordinates.' or 'Coordinates are recorded only for your own deaths, on your own client. Guildmates\' death reports carry zone only (1.8.2-compatible protocol).')
 st:Place(side.pinNote,nil,6)
end

function page.Build(self,host)
 local left,right=P.Split(host,350)
 local bar=P.Toolbar(left,{search=function(t) state.query=t;if list then list:ScrollTo(1) end;self:Update() end,searchHint='Find a guildmate',searchWidth=180,
  segments={{'lifetime','Lifetime'},{'bg','Battlegrounds'},{'nonBG','Non-BG'},{'halls','Guild Records'}},get=function() return state.tab end,
  set=function(v)
   state.tab=v;state.member=nil
   if v~='halls' then
    K.GuildRecords.Sample()
    state.member=K.LocalGuildMember() or UnitName('player')
   end
   if list then list:ScrollTo(1) end
   self:Update()
  end,segWidth=96})
 self.bar=bar
 head=S.Text(left,'section','text');head:SetPoint('TOPLEFT',bar,'BOTTOMLEFT',0,-18)
 note=S.Para(left,300,'faint',12);note:SetPoint('TOPLEFT',head,'BOTTOMLEFT',0,-4);note:SetPoint('RIGHT',left,'RIGHT',-4,0)
 local opts={};for i,c in ipairs(K.GuildRecords.categories) do opts[#opts+1]={i,c.name} end
 catSeg=S.Segmented(left,opts,function() return state.category end,function(v) state.category=v;self:Update() end,150)
 catSeg:SetPoint('TOPLEFT',note,'BOTTOMLEFT',0,-10)
 local function fit(_,width)
  if width>0 then
   note:SetWidth(math.max(1,width-4))
   P.SegmentWidth(catSeg,width)
  end
 end
 left:HookScript('OnSizeChanged',fit)
 fit(left,left:GetWidth()>0 and left:GetWidth() or 300)
 list=Kit.List(left,34,3,function(row) S.RankBuild(row);row:SetScript('OnClick',function(r) if not r.item.board then state.member=r.item.key or r.item.name;renderSide() end end) end,fill)
 P.ListHeading(left,list,note,'Records')
 Kit.Paint(list.thumb,OWNER,'line','fill')
 list.empty=S.Empty(list,'No counts shared yet','Members appear once their client reports. Turn on sharing in Settings > Sharing to include yours.',460)
 list.empty:SetPoint('TOPLEFT',4,-6)
 local _,c=P.DrawerBody(right)
 side={stack=P.Stack(c,300)}
 side.head=P.DrawerHead(c,300)
 side.historical=P.Section(c,'WoW Forever Statistics',300)
 side.summary=P.Section(c,'KWC recorded history',300)
 side.entries=P.Section(c,'Recent world PvP deaths',300)
 side.pin=S.Button(c,'Drop map pin','primary',function()
  local r=side.coord;if r and K.Geo.DropPin(r.map,r.x,r.y) then K.Say('Map pin placed at '..K.Geo.Format(r.x,r.y)..' in '..tostring(r.zone)..'.') else K.Say('Could not place a map pin here.') end
 end,150,30);side.pin.keepWidth=true
 side.copy=S.Button(c,'Copy coordinates','secondary',function()
  local r=side.coord;if r then Kit.CopyBox(OWNER,'Death location: '..tostring(r.zone),tostring(r.zone)..' '..K.Geo.Format(r.x,r.y)) end
 end,150,30);side.copy.keepWidth=true
 side.pinNote=S.Para(c,300,'faint',12)
 side.empty=S.Empty(c,'Select a guildmate','Their recorded world PvP deaths and locations show here.',300)
end
function page.Update(self)
 if not list then return end
 self.bar.seg:Update();catSeg:Update()
 catSeg:SetShown(state.tab=='halls')
 list.header:SetAnchor(state.tab=='halls' and catSeg or note)
 head:SetText(TABS[state.tab][1]);note:SetText(TABS[state.tab][2])
 list:SetData(rows())
 renderSide()
end
W.Register(page)
