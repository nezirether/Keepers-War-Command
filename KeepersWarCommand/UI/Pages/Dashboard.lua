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
 if openPage then c:HeaderAction(openLabel or 'Open',function() W.Show(openPage) end) end
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

local function pvpFeed()
 local items={}
 for _,r in ipairs(KWCDB.worldPvPKills or {}) do
  items[#items+1]={at=Kit.StampEpoch(r.at) or 0,text=P.Short(r.killer)..(r.victim and (' slew '..r.victim) or ' scored a kill'),meta=r.zone,tone='good'}
 end
 for _,r in ipairs(KWCDB.worldPvPDeaths or {}) do
  local who=tostring(r.killer or ''):match('^Killed by: (.+)') or tostring(r.killer or ''):match('^Suspected: (.+)')
  items[#items+1]={at=r.epoch or Kit.StampEpoch(r.at) or 0,text=P.Short(r.victim)..' died'..(who and (' to '..who) or ''),meta=r.zone,tone='danger'}
 end
 table.sort(items,function(a,b) return a.at>b.at end)
 for _,it in ipairs(items) do it.meta=Kit.Age(it.at)..'  '..tostring(it.meta or '');it.open=function() W.Show('pvp') end end
 return items
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
  {'pvp','PvP · 24h','pvp','iconSkull'},
  {'lfg','Guild groups','lfg','iconGroup'},
  {'raid','Raids','raids','iconCalendar'},
 }
 for i,d in ipairs(defs) do
  local t=S.Stat(c,d[2],d[4]);t:SetHeight(78);t.page=d[3]
  t:SetScript('OnClick',function(self) W.Show(self.page) end)
  tiles[d[1]]=t;tiles[i]=t
 end
 cards.cta=miniCard(c,'Calls to Arms',4,'No active calls','When the guild needs help in the world, calls appear here.','cta','All calls')
 cards.bounty=miniCard(c,'Bounty Board',4,'No open bounties','Enemy sightings and claims appear here.','bounties','The board')
 cards.pvp=miniCard(c,'World PvP',6,'Quiet out there','Recent guild kills and guildmate deaths.','pvp','View encounters')
 cards.lfg=miniCard(c,'Groups forming',4,'No groups forming','Start a guild group and invite interested members.','lfg','Find a group')
 cards.spoils=miniCard(c,'War Council notices',3,'No recent awards','Recent raid ledger activity shared with the guild.')
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
 local cols=w>=540 and 5 or 3
 local tileHeight=62
 for i,tile in ipairs(tiles) do
  local slot=i-1
  local row=math.floor(slot/cols)
  local count=math.min(cols,#tiles-row*cols)
  local width=math.floor((w-gap*(count-1))/count)
  tile:ClearAllPoints();tile:SetPoint('TOPLEFT',(slot%cols)*(width+gap),-row*(tileHeight+gap))
  tile:SetSize(width,tileHeight)
 end
 local half=math.floor((w-gap)/2)
 local y=math.ceil(#tiles/cols)*(tileHeight+gap)
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
 pair(cards.raid,cards.lfg)
 pair(cards.pvp,cards.spoils)
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
 tiles.pvp:Set(k..' : '..d,'guild kills : guild deaths',k>=d and 'good' or 'danger')
 local lc,lp=0,0
 if K.GuildLFG and K.GuildLFG.Summary then local ok,a,b=pcall(K.GuildLFG.Summary);if ok then lc,lp=a or 0,b or 0 end end
 tiles.lfg:Set(lc,lp>0 and (lp..' guildmates involved') or 'none open','info')
 local raids=K.RaidSignup and K.RaidSignup.Ordered and K.RaidSignup.Ordered() or {}
 local upcoming=0;for _,e in ipairs(raids) do if not e.cancelled then upcoming=upcoming+1 end end
 tiles.raid:Set(upcoming,upcoming>0 and ('next: '..K.Clean(raids[1].title,22)) or 'none scheduled','accent')
 -- cards
 local items={}
 for _,e in ipairs(KWCDB.ops or {}) do
  if (e.status or 'ACTIVE')=='ACTIVE' then
   local pr=e.details and e.details.priority or (tostring(e.text):match('^%[(%u+)%]'))
   local id=e.id
   items[#items+1]={text=(e.details and e.details.zone and (e.details.zone..'  -  '..(e.details.objective or ''))) or K.Clean(e.text,80),
    meta=Kit.Age(e.created),tone=pr=='URGENT' and 'danger' or pr=='HIGH' and 'warn' or 'accent',open=function() W.Show('cta',{select=id}) end}
  end
 end
 cards.cta:Fill(items)
 items={}
 for _,b in ipairs(KWCDB.bounties or {}) do
  if (b.status or 'ACTIVE')=='ACTIVE' then
   local s=b.sightings and b.sightings[1];local id=b.id
   items[#items+1]={text=P.Short(b.details and b.details.target or b.text)..(b.details and b.details.reward and b.details.reward~='' and ('  -  '..b.details.reward) or ''),
    meta=s and (s.zone..' '..Kit.Age(s.receivedAt)) or Kit.Age(b.created),tone=s and 'warn' or 'faint',open=function() W.Show('bounties',{select=id}) end}
  end
 end
 cards.bounty:Fill(items)
 cards.pvp:Fill(pvpFeed())
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
 if self.countsChanged then self.countsChanged=nil;self:Layout() end
end
W.Register(page)
