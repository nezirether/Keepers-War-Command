-- War Room page: Dashboard. Every tile reads live engine data or shows a
-- useful empty state; every row opens the relevant page.
local K=KWC
local Kit,S,P,W=K.Kit,K.WarRoomSkin,K.WarRoomPages,K.WarRoom2
local OWNER=S.OWNER

local page={id='dashboard',title='Dashboard',subtitle='The state of the war at a glance.',group='ops'}
local tiles,cards={},{}

-- Card with up to n clickable lines (left text, right meta).
local function miniCard(parent,title,n,emptyH,emptyB,openPage,openLabel)
 local c=S.Card(parent,title)
 c.lines={}
 for i=1,n do
  local b=CreateFrame('Button',nil,c.body)
  b:SetHeight(26);b:SetPoint('TOPLEFT',0,-(i-1)*28);b:SetPoint('RIGHT',c.body,'RIGHT',0,0)
  b.hl=Kit.Fill(b,OWNER,'hover','BACKGROUND',0)
  b.dot=b:CreateTexture(nil,'ARTWORK');b.dot:SetSize(6,6);b.dot:SetPoint('LEFT',2,0)
  b.meta=S.Text(b,'small','faint');b.meta:SetPoint('RIGHT',-4,0);b.meta:SetJustifyH('RIGHT')
  b.text=S.Text(b,'body','text');b.text:SetPoint('LEFT',14,0);b.text:SetPoint('RIGHT',b.meta,'LEFT',-10,0)
  local function sizeColumns(self)
   local width=self:GetWidth()
   if width<=0 then return end
   self.meta:SetWidth(math.max(1,math.min(150,math.floor(width*0.28),width-29)))
  end
  b:SetScript('OnSizeChanged',sizeColumns);sizeColumns(b)
  
  b:SetScript('OnEnter',function(self) Kit.Paint(self.hl,OWNER,'hover','fill',1); if GameTooltip and self.fullText then GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:SetText(self.fullText);GameTooltip:AddLine(self.fullMeta or '',1,1,1,true);GameTooltip:Show() end end)
  b:SetScript('OnLeave',function(self) Kit.Paint(self.hl,OWNER,'hover','fill',0);if GameTooltip then GameTooltip:Hide() end end)
  b:SetScript('OnClick',function(self) if self.open then Kit.Safe(self.open) end end)
  c.lines[i]=b
 end
 c.empty=S.Empty(c.body,emptyH,emptyB,300);c.empty:SetPoint('TOPLEFT',0,-2)
 if openPage then c.headerLink=c:HeaderAction(openLabel or 'Open',function() W.Show(openPage) end) end
 function c:Fill(items)
  local count=math.min(#items,#self.lines)
  if self.lineCount~=count then self.lineCount=count;page.countsChanged=true end
  for i,b in ipairs(self.lines) do
   local it=items[i]
   if it then
    b.fullText=it.text;b.fullMeta=it.meta or '';b.text:SetText(b.fullText);b.meta:SetText(b.fullMeta)
    Kit.Paint(b.dot,OWNER,it.tone or 'faint','fill');b.open=it.open;b:Show()
   else b:Hide() end
  end
  self.empty:SetShown(#items==0)
 end
 return c
end

-- World PvP activity: a read-only view over records the engines already keep.
-- Nothing is stored, sent or inferred here. A record without a trustworthy time
-- is left out, and an unknown zone is left blank.
local FEED_LIMIT,FEED_ROW,FEED_GAP,FEED_VISIBLE=25,30,1,7
-- Kill and death engines only record the open world; call and sighting zones are
-- typed by players, and old logs may predate the filter. Never list these.
local EXCLUDED={}
for name in ([[warsong gulch;arathi basin;alterac valley;ragefire chasm;wailing caverns;the deadmines;deadmines;
shadowfang keep;blackfathom deeps;the stockade;stormwind stockade;gnomeregan;razorfen kraul;scarlet monastery;
razorfen downs;uldaman;zul'farrak;maraudon;sunken temple;the temple of atal'hakkar;blackrock depths;blackrock spire;
lower blackrock spire;upper blackrock spire;dire maul;stratholme;scholomance;molten core;onyxia's lair;
blackwing lair;zul'gurub;ruins of ahn'qiraj;temple of ahn'qiraj;ahn'qiraj;naxxramas;the venomous abyss]]):gmatch('[^;]+') do
 EXCLUDED[name:match('^%s*(.-)%s*$')]=true
end
local KINDS={kill={'HONOR KILL','good'},death={'DEATH','danger'},cta={'CALL TO ARMS','accentText'},
 sighting={'SIGHTING','warn'},bounty={'BOUNTY DONE','info'}}

local function known(value)
 if type(value)~='string' then return nil end
 value=K.Clean(value,65):match('^%s*(.-)%s*$')
 if value=='' or value:lower()=='unknown zone' then return nil end
 return value
end
-- A call that arrived without its details still names its zone in the text. Posting
-- strips the "|" separators, so the enemy-count marker also ends the zone.
local function callZone(e)
 local text=tostring(e.text or '')
 local zone=e.details and e.details.zone
 if not zone then
  zone=text:match('^%[%a+%]%s*(.-)%s+|?%s*H:A %d+:%d+') or text:match('^%[%a+%]%s*(.-)%s+[|%-]%s')
 end
 return known(zone)
end
local function named(value) return type(value)=='string' and value~='' end
local function target(b)
 local t=b.details and b.details.target
 if not named(t) then t=tostring(b.text or ''):match('^(.-)%s+[@|%-]%s') or b.text end
 return named(t) and K.Clean(P.Short(t),45) or nil
end

-- Every verified event in the saved records, newest first.
function page.Records()
 local out,seen,now={},{},time()
 -- window: records sharing a key this close together are one event.
 local function add(kind,at,text,zone,open,key,window,count)
  if type(at)~='number' or at<1500000000 or at>now+300 then return end
  if zone and EXCLUDED[zone:lower()] then return end
  if key then
   key=kind..'|'..key:lower()
   for _,other in ipairs(seen[key] or {}) do if math.abs(other-at)<=window then return end end
   seen[key]=seen[key] or {};table.insert(seen[key],at)
  end
  out[#out+1]={kind=kind,at=at,text=text,zone=zone,open=open,order=#out,count=count or 1}
 end
 local function pvp() W.Show('pvp') end
 for _,r in ipairs(KWCDB.worldPvPKills or {}) do
  local count=tonumber(r.count or 1)
  -- A count of zero is a killing blow that earned no honor.
  if named(r.killer) and count and count>0 then
   local victim=named(r.victim) and r.victim or nil
   local text=victim and (P.Short(r.killer)..' slew '..victim) or (P.Short(r.killer)..' scored a kill (victim not identified)')
   if count>1 then text=text..'  x'..count end
   local zone=known(r.zone)
   -- Unnamed kills cannot be told apart, so they are never merged.
   add('kill',Kit.StampEpoch(r.at),text,zone,pvp,victim and (r.killer..'|'..victim..'|'..tostring(zone)..'|'..count),0,count)
  end
 end
 for _,r in ipairs(KWCDB.worldPvPDeaths or {}) do
  if named(r.victim) then
   local said=tostring(r.killer or '')
   local confirmed=said:match('^Killed by: (.+)')
   local suspected=said:match('^Suspected: (.+)')
   local reported=tostring(r.method or ''):find('reported',1,true)
   local text=P.Short(r.victim)..' died'
   if confirmed then text=text..' to '..confirmed..(reported and ' (reported)' or '')
   elseif suspected then text=text..' (suspected: '..suspected..')'
   elseif said:find('^Un') then text=text..' (attacker unidentified)'
   elseif named(said) then text=text..' (reported: '..said..')' end
   add('death',r.epoch or Kit.StampEpoch(r.at),text,known(r.zone),pvp,r.victim,10)
  end
 end
 for _,e in ipairs(KWCDB.ops or {}) do
  -- Call IDs begin with the author's creation time; local "created" can be the
  -- time a copy arrived or was last revised, so it is not used.
  local at=tonumber(tostring(e.id):match('^(%d+)%-%d+$'))
  if e.status~='CANCELLED' and named(e.author) then
   local id=e.id
   add('cta',at,P.Short(e.author)..' called to arms',callZone(e),function() W.Show('cta',{select=id}) end,tostring(id),math.huge)
  end
 end
 for _,b in ipairs(KWCDB.bounties or {}) do
  local who,id=target(b),b.id
  local function open() W.Show('bounties',{select=id}) end
  if who then
   for _,s in ipairs(b.sightings or {}) do
    if named(s.who) then
     add('sighting',s.receivedAt,who..' sighted by '..P.Short(s.who),known(s.zone),open,who..'|'..s.who..'|'..tostring(s.zone),60)
    end
   end
   if b.status=='COMPLETED' then
    -- A relayed copy names the relay, not necessarily whoever completed it.
    local by=not b.relayedBy and named(b.updatedBy) and b.updatedBy
    add('bounty',b.modifiedAt,'Bounty on '..who..' completed'..(by and (' - marked by '..P.Short(by)) or ''),nil,open,tostring(id),math.huge)
   end
  end
 end
 -- Newest first; equal times keep the engines' own newest-first order.
 table.sort(out,function(a,b) if a.at~=b.at then return a.at>b.at end;return a.order<b.order end)
 return out
end
function page.Activity()
 local out=page.Records()
 while #out>FEED_LIMIT do table.remove(out) end
 return out
end

-- Hot Zones: what was recorded per zone in the last hour. It counts reports, not
-- enemies, and says nothing about who is there now.
local HOT_WINDOW,HOT_LIMIT,HOT_ROW,LOG_SIZE=3600,5,26,75
local HOT_FIELD={kill='kills',death='deaths',sighting='sightings',cta='newCalls'}
function page.HotZones()
 local zones,list,now={},{},time()
 for _,it in ipairs(page.Records()) do
  local field=HOT_FIELD[it.kind]
  if field and it.zone and now-it.at<=HOT_WINDOW then
   local key=it.zone:lower()
   local z=zones[key]
   if not z then z={zone=it.zone,kills=0,deaths=0,sightings=0,newCalls=0,calls=0,latest=it.at};zones[key]=z;list[#list+1]=z end
   z[field]=z[field]+(it.kind=='kill' and it.count or 1)
   z.latest=math.max(z.latest,it.at)
  end
 end
 for _,e in ipairs(KWCDB.ops or {}) do
  local zone=(e.status or 'ACTIVE')=='ACTIVE' and callZone(e)
  local z=zone and zones[zone:lower()]
  if z then z.calls=z.calls+1 end
 end
 -- Recorded combat first, then sightings, new calls and recency.
 table.sort(list,function(a,b)
  local x,y=a.kills+a.deaths,b.kills+b.deaths
  if x~=y then return x>y end
  if a.sightings~=b.sightings then return a.sightings>b.sightings end
  if a.newCalls~=b.newCalls then return a.newCalls>b.newCalls end
  if a.latest~=b.latest then return a.latest>b.latest end
  return a.zone:lower()<b.zone:lower()
 end)
 while #list>HOT_LIMIT do table.remove(list) end
 -- A full log whose oldest entry is inside the hour has dropped recent records.
 local clipped=false
 for _,log in ipairs({KWCDB.worldPvPKills or {},KWCDB.worldPvPDeaths or {}}) do
  local last=#log>=LOG_SIZE and log[#log]
  local at=last and (last.epoch or Kit.StampEpoch(last.at))
  if at and now-at<=HOT_WINDOW then clipped=true end
 end
 return list,clipped
end

local HOT_COLUMNS={{'latest','Latest',48},{'sightings','Sightings',64},{'calls','Open calls',70},{'deaths','Deaths',52},{'kills','HKs',40}}
-- Right-aligned number columns; the zone name takes what is left.
local function columns(parent,make)
 local cells,right={},12
 for _,col in ipairs(HOT_COLUMNS) do
  local fs=make();fs:SetPoint('RIGHT',parent,'RIGHT',-right,0);fs:SetWidth(col[3]);fs:SetJustifyH('RIGHT')
  cells[col[1]]=fs;right=right+col[3]+6
 end
 return cells,right
end
local function hotCard(parent)
 local c=S.Card(parent,'PvP Hot Zones - last 60 min')
 c.head=CreateFrame('Frame',nil,c.body);c.head:SetHeight(16);c.head:SetPoint('TOPLEFT');c.head:SetPoint('TOPRIGHT')
 local labels,used=columns(c.head,function() return S.Text(c.head,'small','faint') end)
 for _,col in ipairs(HOT_COLUMNS) do labels[col[1]]:SetText(col[2]) end
 local title=S.Text(c.head,'small','faint');title:SetPoint('LEFT',14,0);title:SetText('Zone')
 c.rows={}
 for i=1,HOT_LIMIT do
  local row=CreateFrame('Button',nil,c.body);row:SetHeight(HOT_ROW)
  row:SetPoint('TOPLEFT',0,-18-(i-1)*(HOT_ROW+1));row:SetPoint('RIGHT',c.body,'RIGHT',0,0)
  row.cells=columns(row,function() return S.Text(row,'body','text') end)
  row.zone=S.Text(row,'body','text');row.zone:SetPoint('LEFT',14,0);row.zone:SetJustifyH('LEFT')
  function row:FitColumns()
   local width=self:GetWidth()
   if width<=0 then width=600 end
   P.StandardRowArt(self,width,HOT_ROW)
   self.zone:SetWidth(math.max(24,width-14-used-8))
  end
  row:HookScript('OnSizeChanged',row.FitColumns)
  row:SetScript('OnClick',function() W.Show('pvp') end)
  Kit.Tooltip(row,function(self) return self.item and self.item.zone end,function(self)
   local z=self.item
   if z then return 'Recorded in the last 60 minutes:\n'..z.kills..' honorable kills\n'..z.deaths..' PvP deaths\n'..
    z.sightings..' bounty sightings\n'..z.newCalls..' new calls\n\n'..z.calls..' calls still open\nPast reports, not confirmed enemy presence.' end
  end)
  c.rows[i]=row
 end
 c.note=S.Text(c.body,'small','faint');c.note:SetPoint('BOTTOMLEFT');c.note:SetPoint('BOTTOMRIGHT');c.note:SetJustifyH('LEFT')
 c.empty=S.Empty(c.body,'No recorded activity in the last hour','Zones appear when the guild records kills, deaths, sightings or calls.',300)
 c.empty:SetPoint('TOPLEFT',0,-2)
 function c:Fill(zones,clipped)
  local shown=math.min(#zones,HOT_LIMIT)
  local rows=math.max(2,shown)
  if self.count~=rows then self.count=rows;page.countsChanged=true end
  for i,row in ipairs(self.rows) do
   local z=zones[i];row.item=z
   if z then
    row.zone:SetText(z.zone)
    for _,col in ipairs(HOT_COLUMNS) do
     local key=col[1]
     row.cells[key]:SetText(key=='latest' and Kit.Age(z.latest) or tostring(z[key]))
    end
    Kit.Paint(row.cells.kills,OWNER,z.kills>0 and 'good' or 'faint','text')
    Kit.Paint(row.cells.deaths,OWNER,z.deaths>0 and 'danger' or 'faint','text')
    row:FitColumns();row:Show()
   else row:Hide() end
  end
  self.head:SetShown(shown>0);self.note:SetShown(shown>0);self.empty:SetShown(shown==0)
  self.note:SetText(clipped and 'A saved log is full: counts may be low.' or 'Past reports, not confirmed enemy presence.')
 end
 function c:Height() return 56+18+(self.count or 2)*(HOT_ROW+1)+18 end
 c:HeaderAction('World PvP',function() W.Show('pvp') end)
 return c
end

local function buildActivity(row)
 row.label=Kit.Text(row,OWNER,'narrow',11,'muted');row.label:SetPoint('LEFT',14,0);row.label:SetWidth(86)
 row.age=S.Text(row,'small','muted');row.age:SetPoint('RIGHT',-14,0);row.age:SetWidth(34);row.age:SetJustifyH('RIGHT')
 row.zone=S.Text(row,'small','faint');row.zone:SetPoint('RIGHT',row.age,'LEFT',-8,0);row.zone:SetJustifyH('RIGHT')
 row.text=S.Text(row,'body','text');row.text:SetPoint('LEFT',106,0);row.text:SetJustifyH('LEFT')
 function row:FitColumns()
  local width=self:GetWidth()
  if width<=0 then width=600 end
  P.StandardRowArt(self,width,FEED_ROW)
  local zone=math.floor(Kit.Clamp(width*0.22,60,170))
  self.zone:SetWidth(zone);self.text:SetWidth(math.max(24,width-106-zone-70))
 end
 row:HookScript('OnSizeChanged',row.FitColumns)
 row:SetScript('OnClick',function(self) if self.item then Kit.Safe(self.item.open) end end)
 Kit.Tooltip(row,function(self) return self.item and self.item.text end,function(self)
  local it=self.item
  if it then return KINDS[it.kind][1]..'\n'..(it.zone or 'Zone not recorded')..'\n'..date('%Y-%m-%d %H:%M',it.at)..
   '  ('..Kit.Age(it.at)..')\nClick to open.' end
 end)
end
local function fillActivity(row,it)
 local kind=KINDS[it.kind]
 row.label:SetText(kind[1]);Kit.Paint(row.label,OWNER,kind[2],'text')
 row.text:SetText(it.text);row.zone:SetText(it.zone or '')
 row.age:SetText(Kit.Age(it.at))
 row:FitColumns()
end
local function activityCard(parent)
 local c=S.Card(parent,'World PvP activity')
 c.list=Kit.List(c.body,FEED_ROW,FEED_GAP,buildActivity,fillActivity);c.list:SetAllPoints(c.body)
 c.empty=S.Empty(c.body,'Quiet out there','Guild kills, deaths, calls to arms and bounty news appear here.',300)
 c.empty:SetPoint('TOPLEFT',0,-2)
 c:HeaderAction('View encounters',function() W.Show('pvp') end)
 function c:Fill(items)
  local rows=math.max(2,math.min(#items,FEED_VISIBLE))
  if self.rows~=rows then self.rows=rows;page.countsChanged=true end
  self.list:SetData(items);self.list:SetShown(#items>0);self.empty:SetShown(#items==0)
 end
 function c:Height() return 56+(self.rows or 2)*(FEED_ROW+FEED_GAP) end
 return c
end
local function last24(records,ts)
 local n,now=0,time()
 for _,r in ipairs(records or {}) do local t=r.epoch or Kit.StampEpoch(r.at);if t and now-t<86400 then n=n+1 end end
 return n
end

local function spoilsItems()
 local state=K.WarSpoils.View()
 local items={}
 if not state then return items end
 local function open() W.Show('raids',{tab='spoils'}) end
 for i=state.count,1,-1 do
  local e=state.events[i]
  if e.kind=='L' then
   local r=state.raiders[e.subject]
   local character=K.Identity.RosterName(e.subject) or r.name
   items[#items+1]={text=P.Short(character)..' - '..e.note,meta=Kit.Age(e.at),tone='accent',open=open}
   if #items==3 then break end
  end
 end
 return items
end

function page.Build(self,host)
 local scroll,c=Kit.Scroll(host);scroll:SetAllPoints(host)
 self.content=c;self.scroll=scroll;self.host=host
 local defs={
  {'cta','Calls to Arms','cta','iconSword'},
  {'bounty','Bounties','bounties','iconScroll'},
  {'pvp','Reports · 24h','pvp','iconSkull'},
  {'lfg','Guild groups','lfg','iconGroup'},
  {'raid','Raids','raids','iconCalendar'},
 }
 for i,d in ipairs(defs) do
  local t=S.Stat(c,d[2],d[4]);t:SetHeight(78);t.page=d[3]
  t:SetScript('OnClick',function(self) W.Show(self.page) end)
  tiles[d[1]]=t;tiles[i]=t
 end
 cards.cta=miniCard(c,'Calls to Arms',4,'No active calls','When the guild needs help in the world, calls appear here.','cta','All calls')
 -- Guild SOS sits in the Calls to Arms header; it becomes "Resolve my SOS" while
 -- this character has an active request.
 local allCalls=cards.cta.headerLink
 local sos=S.Button(cards.cta.titleBar,'Request Backup','danger',function()
  local mine=K.Operations.ActiveSOS()
  if mine then
   local id=mine.id
   -- Confirmed so a double click cannot cancel a request just sent.
   S.Confirm('Resolve your backup request?','Guildmates will see the call as resolved.','Resolve SOS',function()
    K.Operations.ChangeStatus('CTA',id,'RESOLVED');page:Update()
   end)
  else K.Operations.RequestBackup();page:Update() end
 end,118,24)
 sos:SetPoint('RIGHT',allCalls,'LEFT',-8,0);sos:SetFrameLevel(cards.cta.titleBar:GetFrameLevel()+4)
 Kit.Tooltip(sos,function() return K.Operations.ActiveSOS() and 'Resolve my SOS' or 'Request Backup' end,function()
  local mine=K.Operations.ActiveSOS()
  if mine then return 'Close your active backup request.\n'..K.Operations.SOSTimeText(mine)..'. '..(K.Operations.SOSStatusText(mine) or '') end
  return 'Expires after 10 minutes. Sends an urgent Call to Arms to the guild with your current zone. Open world only.'
 end)
 page.sos=sos
 cards.bounty=miniCard(c,'Bounty Board',4,'No open bounties','Enemy sightings and claims appear here.','bounties','The board')
 cards.hot=hotCard(c);page.hot=cards.hot
 cards.activity=activityCard(c);page.activity=cards.activity
 cards.lfg=miniCard(c,'Groups forming',4,'No groups forming','Start a guild group and invite interested members.','lfg','Find a group')
 cards.spoils=miniCard(c,'War Council notices',3,'No recent awards','Recent raid ledger activity shared with the guild.');page.notices=cards.spoils
 cards.spoils:HeaderAction('Ledger',function() W.Show('raids',{tab='spoils'}) end)
 cards.raid=miniCard(c,'Upcoming raids',3,'No raids scheduled','Find a raid and set your signup status.','raids','Raid signups')
 cards.quick=S.Card(c,'Quick Actions');cards.quick.fullWidth=true
 cards.quick.buttons={
  S.Button(cards.quick.body,'New Call','primary',function() W.Show('cta',{compose=true}) end,112,32),
  S.Button(cards.quick.body,'Post Bounty','secondary',function() W.Show('bounties',{compose=true}) end,120,32),
  S.Button(cards.quick.body,'Schedule Raid','secondary',function() W.Show('raids',{compose=true}) end,128,32),
  S.Button(cards.quick.body,'Start a Group','secondary',function() W.Show('lfg',{compose=true}) end,126,32),
  S.Button(cards.quick.body,'Leaderboards','ghost',function() W.Show('leaderboards') end,120,32),
  S.Button(cards.quick.body,'World PvP','ghost',function() W.Show('pvp') end,110,32),
 }
 function cards.quick:LayoutBody(st) st:Actions(self.buttons,0) end
 host:SetScript('OnSizeChanged',function() self:Layout() end)
 -- Ages old activity out while the page is on screen (OnUpdate stops when hidden).
 local since=0
 host:SetScript('OnUpdate',function(_,elapsed)
  since=since+(elapsed or 0)
  if since>=30 then since=0;Kit.Safe(self.Update,self) end
 end)
 -- Kit.Scroll starts with a 10x10 content frame and assigns its real width
 -- when the hidden War Room host receives its final dimensions. Wait for that
 -- measured width before laying out cards; host size notifications can arrive
 -- before the scroll child has been resized.
 if c.HookScript then c:HookScript('OnSizeChanged',function(_,width) if width>=320 then self:Layout() end end) end
 self:Layout()
end
function page.Layout(self)
 local c=self.content;if not c then return end
 local w=c:GetWidth()
 if not w or w<320 then self.layoutPending=true;return end
 if self.layoutBusy then self.layoutPending=true;return end
 self.layoutBusy=true;self.layoutPending=nil
 local gap=10
 local top=K.WinterVeil and K.WinterVeil.Dashboard(c,w) or 0
 self.seasonHeight=top
 local cols=w>=540 and 5 or 3
 local tileHeight=62
 for i,tile in ipairs(tiles) do
  local slot=i-1
  local row=math.floor(slot/cols)
  local count=math.min(cols,#tiles-row*cols)
  local width=math.floor((w-gap*(count-1))/count)
  tile:ClearAllPoints();tile:SetPoint('TOPLEFT',(slot%cols)*(width+gap),-top-row*(tileHeight+gap))
  tile:SetSize(width,tileHeight)
 end
 local half=math.floor((w-gap)/2)
 local y=top+math.ceil(#tiles/cols)*(tileHeight+gap)
 local function put(card,x,yy,cw,h,hasEmptyState)
  card:ClearAllPoints();card:SetPoint('TOPLEFT',x,-yy);card:SetSize(cw,h)
  if hasEmptyState then
   assert(card.empty and card.empty.b,'Dashboard mini-card requires its empty-state component')
   card.empty:SetWidth(cw-28);card.empty.b:SetWidth(cw-28)
  end
 end
 local function pair(left,right)
  local function height(card)
   return 48+math.max(2,card.lineCount or #card.lines)*28
  end
  local h=math.max(height(left),height(right))
  put(left,0,y,half,h,true);put(right,half+gap,y,w-half-gap,h,true)
  y=y+h+gap
 end
 pair(cards.cta,cards.bounty)
 local hot=cards.hot
 put(hot,0,y,w,hot:Height(),true)
 for _,row in ipairs(hot.rows) do row:SetWidth(w-28);row:FitColumns() end
 y=y+hot:Height()+gap
 local activity=cards.activity
 local activityHeight=activity:Height()
 put(activity,0,y,w,activityHeight,true)
 activity.list:SetSize(w-28,activityHeight-54);activity.list:Refresh()
 y=y+activityHeight+gap
 pair(cards.raid,cards.lfg)
 local spoilsHeight=48+math.max(2,cards.spoils.lineCount or #cards.spoils.lines)*28
 put(cards.spoils,0,y,w,spoilsHeight,true)
 y=y+spoilsHeight+gap
 local actionsHeight=P.Flow(cards.quick.buttons,cards.quick.body,w-28,0,8)
 local quickHeight=actionsHeight+60
 put(cards.quick,0,y,w,quickHeight,false)
 c:SetHeight(y+quickHeight+14)
 self.layoutBusy=false
 if self.layoutPending and c:GetWidth()>=320 then self.layoutPending=nil;self:Layout() end
end

function page.Update(self)
 if not self.content then return end
 local stats=K.Operations.Stats()
 tiles.cta:Set(stats.activeCTA,stats.urgent>0 and (stats.urgent..' urgent  -  '..stats.coming..' coming') or (stats.coming..' guildmates coming'),stats.urgent>0 and 'danger' or 'accent')
 local sightings24=0
 for _,b in ipairs(KWCDB.bounties or {}) do for _,s in ipairs(b.sightings or {}) do if s.receivedAt and time()-s.receivedAt<86400 then sightings24=sightings24+1 end end end
 tiles.bounty:Set(stats.activeBounty,sightings24..' sightings today','warn')
 local k,d=last24(KWCDB.worldPvPKills),last24(KWCDB.worldPvPDeaths)
 tiles.pvp:Set(k..' : '..d,'Kill reports : death reports saved in the last 24 hours. A kill report can be a killing blow without honor or cover several kills. Each log keeps 75.',k>=d and 'good' or 'danger')
 local lc,lp=0,0
 if K.GuildLFG and K.GuildLFG.Summary then local ok,a,b=pcall(K.GuildLFG.Summary);if ok then lc,lp=a or 0,b or 0 end end
 tiles.lfg:Set(lc,lp>0 and (lp..' guildmates involved') or 'none open','info')
 local raids=K.RaidSignup and K.RaidSignup.Ordered and K.RaidSignup.Ordered() or {}
 local upcoming=0;for _,e in ipairs(raids) do if not e.cancelled then upcoming=upcoming+1 end end
 tiles.raid:Set(upcoming,upcoming>0 and ('next: '..K.Clean(raids[1].title,22)) or 'none scheduled','accent')
 -- cards
 local items={}
 K.Operations.ExpireSOS()
 for _,e in ipairs(KWCDB.ops or {}) do
  if (e.status or 'ACTIVE')=='ACTIVE' then
   local pr=e.details and e.details.priority or (tostring(e.text):match('^%[(%u+)%]'))
   local id=e.id
   items[#items+1]={text=(e.details and e.details.zone and (e.details.zone..'  -  '..(e.details.objective or ''))) or K.Clean(e.text,80),
    meta=K.Operations.SOSTimeText(e) or Kit.Age(e.created),tone=pr=='URGENT' and 'danger' or pr=='HIGH' and 'warn' or 'accent',open=function() W.Show('cta',{select=id}) end}
  end
 end
 cards.cta:Fill(items)
 local mine=K.Operations.ActiveSOS()
 page.sos.text:SetText(mine and ('Resolve SOS ('..math.ceil(K.Operations.SOSRemaining(mine)/60)..'m)') or 'Request Backup')
 items={}
 for _,b in ipairs(KWCDB.bounties or {}) do
  if (b.status or 'ACTIVE')=='ACTIVE' then
   local s=b.sightings and b.sightings[1];local id=b.id
   items[#items+1]={text=P.Short(b.details and b.details.target or b.text)..(b.details and b.details.reward and b.details.reward~='' and ('  -  '..b.details.reward) or ''),
    meta=s and (s.zone..' '..Kit.Age(s.receivedAt)) or Kit.Age(b.created),tone=s and 'warn' or 'faint',open=function() W.Show('bounties',{select=id}) end}
  end
 end
 cards.bounty:Fill(items)
 cards.hot:Fill(page.HotZones())
 cards.activity:Fill(page.Activity())
 items={}
 local rows=K.GuildLFG and K.GuildLFG.Browse and K.GuildLFG.Browse({}) or {}
 for _,r in ipairs(rows) do
  items[#items+1]={text=r.activity..': '..r.name,meta='needs '..tostring(r.needed),tone='info',open=function() W.Show('lfg') end}
 end
 cards.lfg:Fill(items)
 items={}
 for _,e in ipairs(raids) do
  if not e.cancelled then items[#items+1]={text=K.Clean(e.title,40),meta=K.Clean(e.when,22),tone='accent',open=function() W.Show('raids') end} end
 end
 cards.raid:Fill(items)
 cards.spoils:Fill(spoilsItems())
 -- The season can begin or end while the Dashboard stays open.
 if K.WinterVeil and K.WinterVeil.Active()~=((self.seasonHeight or 0)>0) then
  self.countsChanged=true;if K.WarRoom2.UpdateHeaderArtwork then K.WarRoom2.UpdateHeaderArtwork() end
 end
 if self.countsChanged then self.countsChanged=nil;self:Layout() end
end
W.Register(page)
