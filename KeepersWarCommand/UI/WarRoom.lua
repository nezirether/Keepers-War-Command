-- KWC 2.0 public interface: The War Room.
-- Structure: left rail (brand + grouped navigation + officer launch), top status
-- strip (page title, guild/sync/instance chips), and a content host where pages
-- are built lazily and refreshed in place (no full rebuild per sync message).
local K=KWC
local Kit,S=K.Kit,K.WarRoomSkin
local OWNER=S.OWNER
local W={pages={},order={},groups={}};K.WarRoom2=W

W.GROUPS={
 {id='ops',label='Operations'},
 {id='guild',label='Guild'},
 {id='records',label='Records'},
 {id='system',label='System'},
}
-- page={id,title,subtitle,group,Build(page,host),Update(page),Badge()->n,OnShow(page,arg)}
function W.Register(page)
 for _,group in ipairs(W.GROUPS) do if page.group==group.id then page.groupLabel=group.label;break end end
 W.pages[page.id]=page
 W.order[#W.order+1]=page
 return page
end

local frame,rail,strip,content,current
local navButtons={}
local navScroll
local RAIL_W,STRIP_H=198,86

local function settings() return KWCDB and KWCDB.settings or {} end

local function saveGeometry()
 if not frame or not KWCDB then return end
 local point,_,rel,x,y=frame:GetPoint(1)
 KWCDB.settings.ui2Window={point=point,rel=rel,x=x,y=y,w=frame:GetWidth(),h=frame:GetHeight()}
end
local function availableSize()
 local sw,sh=UIParent:GetWidth(),UIParent:GetHeight()
 return math.max(1,sw-32),math.max(1,sh-48)
end

function W.FitWindow()
 if not frame then return end
 local sw,sh=availableSize()
 local requested=Kit.Clamp(settings().ui2Scale or 1,0.75,1.35)
 local scale=math.min(requested,sw/920,sh/580)
 frame:SetScale(scale)
 local maxW=Kit.Clamp(sw/scale,920,1700)
 local maxH=Kit.Clamp(sh/scale,580,1100)
 if frame.SetResizeBounds then frame:SetResizeBounds(920,580,maxW,maxH)
 elseif frame.SetMaxResize then frame:SetMaxResize(maxW,maxH) end
 frame:SetSize(Kit.Clamp(frame:GetWidth(),920,maxW),Kit.Clamp(frame:GetHeight(),580,maxH))
end

local function restoreGeometry()
 local g=settings().ui2Window
 frame:ClearAllPoints()
 frame:SetSize(Kit.Clamp(g and g.w or 1100,920,1700),Kit.Clamp(g and g.h or 700,580,1100))
 W.FitWindow()
 if g and g.point and type(g.x)=='number' then frame:SetPoint(g.point,UIParent,g.rel or g.point,g.x,g.y)
 else frame:SetPoint('CENTER',UIParent,'CENTER',0,20) end
end

-- Officer launch: visible only when the officer add-on is loaded and the live
-- roster says this character is War Council or Warchief. The officer add-on
-- performs its own fail-closed authorization when opened.
local function officerAvailable()
 return K.Officer and type(K.Officer.Open)=='function' and K.IsOfficer and K.IsOfficer()
end

local function buildRail()
 rail=CreateFrame('Frame',nil,frame)
 rail:SetPoint('TOPLEFT');rail:SetPoint('BOTTOMLEFT');rail:SetWidth(RAIL_W)
 Kit.Fill(rail,OWNER,'rail');S.Art(rail,'rail')
 local mark=CreateFrame('Frame',nil,rail)
 mark:SetHeight(52);mark:SetPoint('BOTTOMLEFT',rail,'BOTTOMLEFT',0,0)
 mark:SetPoint('BOTTOMRIGHT',rail,'BOTTOMRIGHT',0,0)
 mark:EnableMouse(false);S.Art(mark,'railMark')
 local edge=Kit.Rule(rail,OWNER,'lineSoft',false,1);edge:SetPoint('TOPRIGHT');edge:SetPoint('BOTTOMRIGHT')
 -- brand block
 local crest=CreateFrame('Frame',nil,rail)
 crest:SetSize(46,46);crest:SetPoint('TOPLEFT',rail,'TOPLEFT',16,-16);crest:EnableMouse(false)
 S.Art(crest,'crest','ARTWORK')
 local sigil=CreateFrame('Frame',nil,crest)
 sigil:SetPoint('TOPLEFT',crest,'TOPLEFT',8,-8);sigil:SetPoint('BOTTOMRIGHT',crest,'BOTTOMRIGHT',-8,8)
 sigil:EnableMouse(false);S.Art(sigil,'sigil','OVERLAY')
 S.Art(crest,'seal','BORDER')
 local guild=S.Text(rail,'kicker','accentText')
 guild:SetPoint('TOPLEFT',rail,'TOPLEFT',70,-19);guild:SetPoint('RIGHT',rail,'RIGHT',-8,0)
 guild:SetText('KEEPERS OF TROGDOR')
 local title=Kit.Text(rail,OWNER,'display',21,'text')
 title:SetPoint('TOPLEFT',rail,'TOPLEFT',70,-34);title:SetPoint('RIGHT',rail,'RIGHT',-8,0);title:SetText('War Room')
 local nav
 navScroll,nav=Kit.Scroll(rail)
 navScroll:SetPoint('TOPLEFT',0,-72);navScroll:SetPoint('BOTTOMRIGHT',0,32)
 local divider=Kit.Rule(rail,OWNER,'lineSoft',true,1)
 divider:SetPoint('TOPLEFT',12,-65);divider:SetPoint('TOPRIGHT',-12,-65)
 local y=0
 for _,group in ipairs(W.GROUPS) do
  local items={}
  for _,p in ipairs(W.order) do if p.group==group.id then items[#items+1]=p end end
  if #items>0 then
   local label=S.Text(nav,'kicker','faint');label:SetPoint('TOPLEFT',18,y-10);label:SetText(group.label:upper())
   y=y-23
   for _,p in ipairs(items) do
    local b=CreateFrame('Button',nil,nav)
    b:SetPoint('TOPLEFT',8,y);b:SetPoint('RIGHT',nav,'RIGHT',-8,0);b:SetHeight(27)
    b.contentTop=-y
    b.bg=Kit.Fill(b,OWNER,'rail')
    b.bar=Kit.Rule(b,OWNER,'accent',false,3);b.bar:SetPoint('TOPLEFT');b.bar:SetPoint('BOTTOMLEFT');b.bar:Hide()
    b.text=S.Text(b,'body','muted');b.text:SetPoint('LEFT',14,0);b.text:SetPoint('RIGHT',b,'RIGHT',-32,0);b.text:SetText(p.title);b.text:SetJustifyH('LEFT')
    b.badge=Kit.Text(b,OWNER,'narrow',13,'accentText');b.badge:SetPoint('RIGHT',-10,0)
    b.page=p
    Kit.Tooltip(b,p.title)
    b:SetScript('OnClick',function(self) W.Show(self.page.id) end)
    b:SetScript('OnEnter',function(self) if current~=self.page then Kit.Paint(self.bg,OWNER,'hover','fill') end end)
    b:SetScript('OnLeave',function(self) Kit.Paint(self.bg,OWNER,current==self.page and 'accentSoft' or 'rail','fill') end)
    navButtons[#navButtons+1]=b
    y=y-28
   end
  end
 end
 nav:SetHeight(-y+5)
 -- officer launch (separate experience, never a War Room page)
 local off=CreateFrame('Button',nil,rail)
 off:SetPoint('BOTTOMLEFT',10,46);off:SetPoint('BOTTOMRIGHT',-10,46);off:SetHeight(44)
 off.bg=Kit.Fill(off,OWNER,'dangerSoft')
 Kit.Border(off,OWNER,'danger',1,0.6)
 off.t=S.Text(off,'body','text');off.t:SetPoint('TOPLEFT',12,-8);off.t:SetText('Command Table')
 off.s=S.Text(off,'small','muted');off.s:SetPoint('TOPLEFT',off.t,'BOTTOMLEFT',0,-2);off.s:SetText('Officer console (KWCC)')
 off:SetScript('OnClick',function() if officerAvailable() then Kit.Safe(K.Officer.Open) end end)
 W.officerButton=off
 local foot=S.Text(rail,'small','faint');foot:SetPoint('BOTTOMLEFT',16,18)
 foot:SetText('v'..tostring(K.version)..'   /kt help')
end

local chips={}
local function buildStrip()
 strip=CreateFrame('Frame',nil,frame)
 strip:SetPoint('TOPLEFT',frame,'TOPLEFT',RAIL_W,0)
 strip:SetPoint('TOPRIGHT',frame,'TOPRIGHT',0,0)
 strip:SetHeight(STRIP_H)
 Kit.Fill(strip,OWNER,'header');S.Art(strip,'header')
 local material=CreateFrame('Frame',nil,strip)
 material:SetPoint('TOPLEFT',strip,'TOP',-10,0);material:SetPoint('BOTTOMRIGHT',strip,'BOTTOMRIGHT',-1,1)
 material:SetFrameLevel(strip:GetFrameLevel());material:EnableMouse(false)
 S.Art(material,'material')
 local trim=CreateFrame('Frame',nil,strip)
 trim:SetHeight(18);trim:SetFrameLevel(strip:GetFrameLevel());trim:EnableMouse(false)
 trim:SetPoint('BOTTOMLEFT',strip,'BOTTOMLEFT',0,0)
 trim:SetPoint('BOTTOMRIGHT',strip,'BOTTOMRIGHT',0,0)
 S.Art(trim,'trim','BORDER')
 local rule=Kit.Rule(strip,OWNER,'lineSoft',true,1);rule:SetPoint('BOTTOMLEFT');rule:SetPoint('BOTTOMRIGHT')
 strip:EnableMouse(true);strip:RegisterForDrag('LeftButton')
 strip:SetScript('OnDragStart',function() frame:StartMoving() end)
 strip:SetScript('OnDragStop',function() frame:StopMovingOrSizing();saveGeometry() end)
 local function line(style,role,offset,height)
  local text=S.Text(strip,style,role)
  text:SetPoint('TOPLEFT',strip,'TOPLEFT',24,-offset)
  text:SetPoint('TOPRIGHT',strip,'TOPRIGHT',-58,-offset)
  text:SetHeight(height)
  return text
 end
 W.pageGroup=line('kicker','accentText',4,13)
 W.pageTitle=line('display','text',17,27)
 W.pageSub=line('small','muted',44,13)
 local seam=Kit.Rule(strip,OWNER,'accentSoft',true,2);seam:SetPoint('TOPLEFT');seam:SetPoint('TOPRIGHT')
 local close=CreateFrame('Button',nil,strip);close:SetSize(32,32);close:SetPoint('TOPRIGHT',-12,-14)
 close.t=Kit.Text(close,OWNER,'narrow',20,'faint');close.t:SetPoint('CENTER',close,'CENTER',0,0);close.t:SetText('x')
 close:SetScript('OnClick',function() frame:Hide() end)
 close:SetScript('OnEnter',function(self) Kit.Paint(self.t,OWNER,'text','text') end)
 close:SetScript('OnLeave',function(self) Kit.Paint(self.t,OWNER,'faint','text') end)
 Kit.Tooltip(close,'Close the War Room','Esc also closes it. /kt opens it again.')
 local anchor
 for _,id in ipairs({'guild','sync','instance'}) do
  local c=S.Chip(strip)
  if anchor then c:SetPoint('LEFT',anchor,'RIGHT',8,0)
  else c:SetPoint('BOTTOMLEFT',24,8) end
  chips[id]=c;anchor=c
 end
 Kit.Tooltip(chips.sync,'Guild sync',function() return W.syncDetail end)
 Kit.Tooltip(chips.instance,'Alert policy',function() return W.instanceDetail end)
 Kit.Tooltip(chips.guild,'Guild identity',function() return W.guildDetail end)
end

local function updateChips()
 local state=K.GuildReadiness and K.GuildReadiness() or 'Unavailable'
 local gname=IsInGuild and IsInGuild() and GetGuildInfo and GetGuildInfo('player')
 if issecretvalue and issecretvalue(gname) then gname=nil end
 chips.guild:Set(gname and K.Clean(gname,32) or 'No guild',state=='Ready' and 'good' or 'warn')
 W.guildDetail=state..(state=='Ready' and '. Guild data is partitioned to this guild only.' or '. Guild features wait until identity and roster are verified.')
 local h=K.Sync and K.Sync.Health and K.Sync.Health()
 local q=K.Net and K.Net.Status and K.Net.Status()
 local label,tone='Sync idle','faint'
 W.syncDetail=nil
 if type(h)=='table' then
  local peers=0;for _ in pairs(h.peers or {}) do peers=peers+1 end
  local last=tonumber(h.lastReceived) or 0
  if last>0 and time()-last<900 then label,tone='Synced '..Kit.Age(last),'good'
  elseif (h.sent or 0)>0 or (h.requests or 0)>0 then label,tone='Waiting for peers','info' end
  W.syncDetail=('Received %d, applied %d, rejected %d from %d peers since /reload.'):format(h.received or 0,h.applied or 0,h.rejected or 0,peers)
 end
 local recovery,received=K.Sync.RecoveryStatus()
 if recovery=='Recovery in progress' or recovery=='Recovery data received' then label,tone=recovery,'info' end
 if q and q>0 then label,tone='Sending '..q,'info' end
 if K.Sync and K.Sync.AutoSyncEnabled and not K.Sync.AutoSyncEnabled() then label,tone='Auto sync off','warn' end
 chips.sync:Set(label,tone)
 W.syncDetail=(W.syncDetail and (W.syncDetail..'\n') or '')..recovery..' ('..received..' verified recovery envelopes in this request). Queue: '..tostring(q or 0)..'. Use Settings > Diagnostics for details.'
 local P=K.InstanceAlerts
 local allowed=P and P.Allowed and P.Allowed()
 local st=P and P.State and P.State() or 'unknown'
 if allowed then chips.instance:Set('Open world','good');W.instanceDetail='Automatic alerts are active.'
 else chips.instance:Set(st=='loading' and 'Loading' or 'Alerts paused','warn');W.instanceDetail='Automatic alerts are suppressed in raids, dungeons, battlegrounds and uncertain or loading states. Previews still work.' end
end

local function updateNav()
 for _,b in ipairs(navButtons) do
  local on=current==b.page
  b.bar:SetShown(on)
  Kit.Paint(b.bg,OWNER,on and 'accentSoft' or 'rail','fill')
  Kit.Paint(b.text,OWNER,on and 'text' or 'muted','text')
  local n=b.page.Badge and select(2,pcall(b.page.Badge))
  b.badge:SetText(type(n)=='number' and n>0 and (n>99 and '99+' or tostring(n)) or '')
 end
 if W.officerButton then
  local visible=officerAvailable() and true or false
  if visible~=W.officerButton:IsShown() then W.officerButton:SetShown(visible) end
  local bottom=visible and 96 or 32
  if navScroll.footer~=bottom then
   navScroll.footer=bottom
   navScroll:SetPoint('BOTTOMRIGHT',rail,'BOTTOMRIGHT',0,bottom)
  end
 end
end

local function build()
 if frame then return end
 frame=CreateFrame('Frame','KWC2_WarRoom',UIParent)
 frame:SetFrameStrata('HIGH');frame:SetToplevel(true);frame:SetClampedToScreen(true)
 frame:SetMovable(true);frame:SetResizable(true);frame:EnableMouse(true)
 if frame.SetResizeBounds then frame:SetResizeBounds(920,580,1700,1100)
 elseif frame.SetMinResize then frame:SetMinResize(920,580);if frame.SetMaxResize then frame:SetMaxResize(1700,1100) end end
 frame:RegisterEvent('DISPLAY_SIZE_CHANGED')
 frame:RegisterEvent('UI_SCALE_CHANGED')
 frame:SetScript('OnEvent',function() W.FitWindow() end)
 local shadow=frame:CreateTexture(nil,'BACKGROUND',nil,-3);shadow:SetPoint('TOPLEFT',-6,6);shadow:SetPoint('BOTTOMRIGHT',6,-6)
 Kit.Paint(shadow,OWNER,'shadow','fill')
 Kit.Fill(frame,OWNER,'base')
 Kit.Border(frame,OWNER,'line')
 tinsert(UISpecialFrames,'KWC2_WarRoom')
 buildRail();buildStrip()
 content=CreateFrame('Frame',nil,frame)
 content:SetPoint('TOPLEFT',RAIL_W+24,-STRIP_H-18);content:SetPoint('BOTTOMRIGHT',-22,20)
 W.content=content
 -- resize grip
 local grip=CreateFrame('Button',nil,frame);grip:SetSize(16,16);grip:SetPoint('BOTTOMRIGHT',-3,3)
 for i=1,2 do local r=Kit.Rule(grip,OWNER,'faint',true,1);r:SetWidth(i*6);r:SetPoint('BOTTOMRIGHT',0,(i-1)*4) end
 grip:SetScript('OnMouseDown',function() frame:StartSizing('BOTTOMRIGHT') end)
 grip:SetScript('OnMouseUp',function() frame:StopMovingOrSizing();W.FitWindow();saveGeometry();W.Refresh(true) end)
 frame:SetScript('OnShow',function() updateChips();updateNav();if K.Sync and K.Sync.OnWindowOpened then Kit.Safe(K.Sync.OnWindowOpened) end end)
 frame:SetScript('OnHide',function() saveGeometry();if S.IsPreviewing() then S.CancelPreview() end end)
 frame:Hide()
 restoreGeometry()
 S.Restore()
end
W.Build=build

function W.Frame() return frame end
function W.IsShown() return frame and frame:IsShown() end
function W.Current() return current end

function W.Show(id,arg)
 build()
 local page=W.pages[id] or W.pages.dashboard
 if current and current~=page and current.host then current.host:Hide() end
 current=page
 if not page.host then
  page.host=CreateFrame('Frame',nil,content);page.host:SetAllPoints(content)
  Kit.Safe(page.Build,page,page.host)
 end
 page.host:Show()
 if page.Layout then Kit.Safe(page.Layout,page) end
 W.pageGroup:SetText((page.groupLabel or page.group):upper())
 W.pageTitle:SetText(page.title);W.pageSub:SetText(page.subtitle or '')
 frame:Show()
 if page.OnShow then Kit.Safe(page.OnShow,page,arg) end
 for _,button in ipairs(navButtons) do
  if button.page==page then
   local top=navScroll:GetVerticalScroll() or 0
   local height=navScroll:GetHeight() or 0
   if height>0 and (button.contentTop<top or button.contentTop+27>top+height) then
    navScroll:SetVerticalScroll(Kit.Clamp(button.contentTop-12,0,navScroll:GetVerticalScrollRange() or 0))
   end
   break
  end
 end
 if page.Update then Kit.Safe(page.Update,page) end
 updateNav();updateChips()
 if KWCDB then KWCDB.settings.ui2LastPage=page.id end
end
function W.Toggle(id,arg)
 build()
 if frame:IsShown() and (not id or (current and current.id==id)) then frame:Hide();return end
 W.Show(id or (KWCDB and KWCDB.settings.ui2LastPage) or 'dashboard',arg)
end

-- Coalesced refresh: sync traffic can call Refresh many times per second; the
-- visible page updates at most four times a second and only while shown.
local dirty,ticker=false,CreateFrame('Frame')
local since=0
ticker:SetScript('OnUpdate',function(_,dt)
 since=since+dt
 if not dirty or since<0.25 then return end
 since=0;dirty=false
 if frame and frame:IsShown() and current and current.Update then Kit.Safe(current.Update,current);updateNav();updateChips() end
end)
function W.Refresh(now)
 dirty=true
 if now then since=1 end
end
