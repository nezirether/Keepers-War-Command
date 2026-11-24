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
   self.meta:SetWidth(math.max(1,math.min(150,math.floor(width*0.40),width-29)))
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
 self.content=c
 local banner=CreateFrame('Frame',nil,c)
 banner:SetHeight(108)
 Kit.Fill(banner,OWNER,'accentSoft');Kit.Border(banner,OWNER,'line')
 local scene=CreateFrame('Frame',nil,banner)
 scene:SetPoint('TOPLEFT',banner,'TOP',-42,0);scene:SetPoint('BOTTOMRIGHT',banner,'BOTTOMRIGHT')
 scene:EnableMouse(false);scene:SetFrameLevel(banner:GetFrameLevel())
 S.Art(scene,'banner','BACKGROUND');S.Art(scene,'material','BORDER')
 local trim=CreateFrame('Frame',nil,banner)
 trim:SetPoint('BOTTOMLEFT');trim:SetPoint('BOTTOMRIGHT');trim:SetHeight(8)
 trim:EnableMouse(false);S.Art(trim,'trim','BORDER')
 local stripe=Kit.Rule(banner,OWNER,'accent',false,3);stripe:SetPoint('TOPLEFT');stripe:SetPoint('BOTTOMLEFT')
 local emblem=banner:CreateTexture(nil,'ARTWORK');emblem:SetTexture(Kit.MEDIA..'Emblem')
 emblem:SetSize(50,50);emblem:SetPoint('LEFT',20,0)
 local kicker=S.Text(banner,'kicker','accentText');kicker:SetText('KEEPERS OF TROGDOR')
 kicker:SetPoint('TOPLEFT',emblem,'TOPRIGHT',16,8)
 local heading=S.Text(banner,'display','text');heading:SetText('Guild Operations')
 heading:SetPoint('TOPLEFT',kicker,'BOTTOMLEFT',0,-5)
 self.brief=S.Text(banner,'small','text');self.brief:SetPoint('TOPLEFT',heading,'BOTTOMLEFT',0,-4)
 self.brief:SetPoint('RIGHT',banner,'RIGHT',-298,0)
 local map=S.Button(banner,'PvP activity','secondary',function() W.Show('pvp') end,110,30)
 map:SetPoint('RIGHT',-16,0)
 map:SetFrameLevel(scene:GetFrameLevel()+1)
 local calls=S.Button(banner,'Calls to Arms','primary',function() W.Show('cta') end,120,30)
 calls:SetPoint('RIGHT',map,'LEFT',-10,0);calls:SetFrameLevel(scene:GetFrameLevel()+1)
 banner:SetPoint('TOPLEFT');banner:SetPoint('TOPRIGHT')
 local defs={
  {'cta','Calls to arms','cta'},{'bounty','Active bounties','bounties'},{'pvp','World PvP 24h','pvp'},
  {'lfg','Guild groups','lfg'},{'raid','Raid sign-ups','raids'},{'sync','Guild sync','settings'},
 }
 for i,d in ipairs(defs) do
  local t=S.Stat(c,d[2]);t:SetHeight(92);t.page=d[3]
  t:SetScript('OnClick',function(self) W.Show(self.page) end)
  tiles[d[1]]=t;tiles[i]=t
 end
 cards.cta=miniCard(c,'Calls to arms',4,'No active calls','When the guild needs bodies in the world, calls appear here.','cta','All calls')
 cards.bounty=miniCard(c,'Bounty board',4,'No open bounties','Post one on an enemy who keeps camping your guildmates.','bounties','Board')
 cards.pvp=miniCard(c,'World PvP feed',6,'Quiet out there','Guild kills and guildmate deaths in the open world show up here.','pvp','World PvP')
 cards.lfg=miniCard(c,'Guild groups',4,'No groups forming','Start one from Guild LFG; guildmates in level range are notified.','lfg','Guild LFG')
 cards.spoils=miniCard(c,'WarSpoils awards',3,'No contested awards recorded','Registered raiders and their recent transactions are under Raid Operations.')
 cards.spoils:HeaderAction('Ledger',function() W.Show('raids',{tab='spoils'}) end)
 cards.raid=miniCard(c,'Raid operations',3,'No raids scheduled','War Council schedules raids; sign-ups sync to every member.','raids','Raids')
 host:SetScript('OnSizeChanged',function() self:Layout() end)
 self:Layout()
end
function page.Layout(self)
 local c=self.content;if not c then return end
 local w=self.host:GetWidth();if w<=0 then w=676 end
 local gap=14
 local cols=w>=1042 and 6 or 3
 local tw=math.floor((w-gap*(cols-1))/cols)
 local tileY=122
 for i,tile in ipairs(tiles) do
  local slot=i-1
  tile:ClearAllPoints()
  tile:SetPoint('TOPLEFT',(slot%cols)*(tw+gap),-(tileY+math.floor(slot/cols)*(92+gap)))
  tile:SetWidth(tw)
 end
 local half=math.floor((w-gap)/2)
 local y=tileY+math.ceil(6/cols)*(92+gap)
 local function put(card,x,yy,cw,h)
  card:ClearAllPoints();card:SetPoint('TOPLEFT',x,-yy);card:SetSize(cw,h)
  card.empty:SetWidth(cw-28);card.empty.b:SetWidth(cw-28)
 end
 put(cards.cta,0,y,half,166);put(cards.bounty,half+gap,y,half,166)
 y=y+166+gap
 put(cards.pvp,0,y,half,222);put(cards.lfg,half+gap,y,half,118)
 put(cards.raid,half+gap,y+118+gap,half,128)
 local bottom=y+118+gap+128+gap
 put(cards.spoils,0,bottom,w,128)
 c:SetHeight(bottom+138)
end

function page.Update(self)
 if not self.content then return end
 local stats=K.Operations.Stats()
 self.brief:SetText(('%d active calls  /  %d open bounties'):format(stats.activeCTA,stats.activeBounty))
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
 local h=K.Sync and K.Sync.Health and K.Sync.Health() or {}
 local peers=0;for _ in pairs(h.peers or {}) do peers=peers+1 end
 local last=tonumber(h.lastReceived) or 0
 tiles.sync:Set(peers,last>0 and ('peers  -  last update '..Kit.Age(last)) or 'peers heard since /reload',last>0 and time()-last<900 and 'good' or 'faint')
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
end
W.Register(page)
