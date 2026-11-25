-- KWC 2.0 public interface: The War Room.
-- Structure: left rail (brand + grouped navigation + officer launch), top status
-- strip (page title, guild/sync/instance chips), and a content host where pages
-- are built lazily and refreshed in place (no full rebuild per sync message).
local K=KWC
local Kit,S=K.Kit,K.WarRoomSkin
local OWNER=S.OWNER
local W={pages={},order={},groups={},PrivatePageSupported=true};K.WarRoom2=W

W.GROUPS={
 {id='ops',label='War Room'},
 {id='guild',label='Guild'},
 {id='records',label='Honors'},
 {id='system',label='Advanced'},
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
local navRows,navContent={},nil
local function pageAllowed(page)
 if not page or not page.CanShow then return page~=nil end
 local ok,allowed=pcall(page.CanShow);return ok and allowed==true
end
local RAIL_W,STRIP_H=212,72
local NAV_ORDER={dashboard=1,bounties=2,cta=3,leaderboards=4,pvp=5,raids=6,lfg=7,
 ['officer-command']=8,records=9,services=10,alerts=11,settings=12}
local CLASSIC_ICON={dashboard='iconShield',bounties='iconScroll',cta='iconSword',leaderboards='iconTrophy',
 pvp='iconSkull',raids='iconCalendar',lfg='iconGroup',['officer-command']='iconCrown',records='iconFlag',
 services='iconAnvil',alerts='iconFlag',settings='iconGear'}
local V3_NAV_ICON={dashboard='navDashboard',bounties='navBounty',cta='navCta',leaderboards='navLeaderboards',
 raids='navRaid',['officer-command']='navWarCouncil',services='navServices',alerts='navAlerts',settings='navSettings'}
local V3_PAGE_HEADER={dashboard='headerDashboard',bounties='headerBounty',cta='headerCta',
 leaderboards='headerLeaderboards',settings='headerSettings',['officer-command']='headerWarCouncil'}

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
 local scale=math.min(requested,sw/900,sh/560)
 frame:SetScale(scale)
 local maxW=Kit.Clamp(sw/scale,900,1700)
 local maxH=Kit.Clamp(sh/scale,560,1100)
 if frame.SetResizeBounds then frame:SetResizeBounds(900,560,maxW,maxH)
 elseif frame.SetMaxResize then frame:SetMaxResize(maxW,maxH) end
 frame:SetSize(Kit.Clamp(frame:GetWidth(),900,maxW),Kit.Clamp(frame:GetHeight(),560,maxH))
end

local function restoreGeometry()
 local g=settings().ui2Window
 frame:ClearAllPoints()
 frame:SetSize(Kit.Clamp(g and g.w or 1180,900,1700),Kit.Clamp(g and g.h or 760,560,1100))
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
 local edge=Kit.Rule(rail,OWNER,'lineSoft',false,1);edge:SetPoint('TOPRIGHT');edge:SetPoint('BOTTOMRIGHT')
 -- brand block
 local crest=CreateFrame('Frame',nil,rail)
 crest:SetSize(46,46);crest:SetPoint('TOPLEFT',rail,'TOPLEFT',16,-16);crest:EnableMouse(false)
 local heraldry=S.ThemedTexture(crest,'crestBanner',44,'ARTWORK');heraldry:SetPoint('CENTER')
 local guild=S.Text(rail,'kicker','accentText')
 guild:SetPoint('TOPLEFT',rail,'TOPLEFT',70,-19);guild:SetPoint('RIGHT',rail,'RIGHT',-8,0)
 guild:SetText('KEEPERS OF TROGDOR')
 local title=Kit.Text(rail,OWNER,'display',21,'text')
 title:SetPoint('TOPLEFT',rail,'TOPLEFT',70,-34);title:SetPoint('RIGHT',rail,'RIGHT',-8,0);title:SetText('War Room')
 local nav
 navScroll,nav=Kit.Scroll(rail);navContent=nav
 navScroll:SetPoint('TOPLEFT',0,-72);navScroll:SetPoint('BOTTOMRIGHT',0,32)
 local divider=Kit.Rule(rail,OWNER,'lineSoft',true,1)
 divider:SetPoint('TOPLEFT',12,-65);divider:SetPoint('TOPRIGHT',-12,-65)
 local y=0
 for _,group in ipairs(W.GROUPS) do
  local items={}
  for _,p in ipairs(W.order) do if p.group==group.id then items[#items+1]=p end end
  table.sort(items,function(a,b) return (NAV_ORDER[a.id] or 100)<(NAV_ORDER[b.id] or 100) end)
  if #items>0 then
   local label=S.Text(nav,'kicker','accentText');label:SetPoint('TOPLEFT',18,y-11);label:SetText(group.label:upper())
   navRows[#navRows+1]={frame=label,header=true,group=group.id}
   y=y-26
   for _,p in ipairs(items) do
    local b=CreateFrame('Button',nil,nav)
    b:SetPoint('TOPLEFT',8,y);b:SetPoint('RIGHT',nav,'RIGHT',-12,0);b:SetHeight(31)
    b.contentTop=-y
    b.bg=Kit.Fill(b,OWNER,'rail')
    b.bar=Kit.Rule(b,OWNER,'accent',false,3);b.bar:SetPoint('TOPLEFT');b.bar:SetPoint('BOTTOMLEFT');b.bar:Hide()
    b.iconKey=V3_NAV_ICON[p.id] or CLASSIC_ICON[p.id] or 'iconFlag'
    b.icon=S.ThemedTexture(b,b.iconKey,20,'ARTWORK',2);b.icon:SetPoint('LEFT',8,0)
    b.text=S.Text(b,'body','muted');b.text:SetPoint('LEFT',b.icon,'RIGHT',8,0);b.text:SetPoint('RIGHT',b,'RIGHT',-34,0);b.text:SetText(p.id=='records' and 'Guild Records' or p.title);b.text:SetJustifyH('LEFT')
    Kit.Tooltip(b,p.title,p.subtitle)
    b.badge=Kit.Text(b,OWNER,'narrow',13,'accentText');b.badge:SetPoint('RIGHT',-10,0)
    b.page=p
    b:SetScript('OnClick',function(self) W.Show(self.page.id) end)
    b.classicSlice=S.SliceAsset(b,'navSelected',8,256,'BORDER',2,nil,16)
    b.hovered=false
    b:SetScript('OnEnter',function(self)
     self.hovered=true;if current~=self.page then Kit.Paint(self.bg,OWNER,'hover','fill') end
     self.classicSlice:SetAsset(current==self.page and 'navSelected' or 'navHover')
    end)
    b:SetScript('OnLeave',function(self)
     self.hovered=false;Kit.Paint(self.bg,OWNER,current==self.page and 'accentSoft' or 'rail','fill')
     self.classicSlice:SetAsset(current==self.page and 'navSelected' or nil)
    end)
    navButtons[#navButtons+1]=b
    navRows[#navRows+1]={frame=b,page=p,group=group.id}
    y=y-33
   end
  end
 end
 nav:SetHeight(-y+5)
 -- officer launch (separate experience, never a War Room page)
 local off=CreateFrame('Button',nil,rail)
 off:SetPoint('BOTTOMLEFT',10,46);off:SetPoint('BOTTOMRIGHT',-10,46);off:SetHeight(44)
 off.bg=Kit.Fill(off,OWNER,'dangerSoft')
 Kit.Border(off,OWNER,'danger',1,0.6)
 off.t=S.Text(off,'body','text');off.t:SetPoint('TOPLEFT',12,-8);off.t:SetPoint('RIGHT',off,'RIGHT',-10,0);off.t:SetText('War Council')
 off.s=S.Text(off,'small','muted');off.s:SetPoint('TOPLEFT',off.t,'BOTTOMLEFT',0,-2);off.s:SetPoint('RIGHT',off,'RIGHT',-10,0);off.s:SetText('Private officer workspace')
 off:SetScript('OnClick',function() if officerAvailable() then Kit.Safe(K.Officer.Open) end end)
 W.officerButton=off
 local foot=S.Text(rail,'small','muted');foot:SetPoint('BOTTOMLEFT',16,18)
 foot:SetText('/kt help')
end

local function buildStrip()
 strip=CreateFrame('Frame',nil,frame)
 strip:SetPoint('TOPLEFT',frame,'TOPLEFT',RAIL_W,0)
 strip:SetPoint('TOPRIGHT',frame,'TOPRIGHT',0,0)
 strip:SetHeight(STRIP_H)
 S.Art(strip,'panel','BACKGROUND')
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
 W.pageSub=line('small','muted',40,16)
 local function updateHeraldryStrip()
  local key=current and V3_PAGE_HEADER[current.id]
  local use=key and S.AssetPath(key) and strip:GetWidth()>=590
  if use then
   W.v3Heraldry:SetAsset(key);W.v3Heraldry:ClearAllPoints();W.v3Heraldry:SetAspectHeight(strip:GetHeight());W.v3Heraldry:SetPoint('LEFT',strip,'LEFT',0,0);W.v3Heraldry:SetShown(true)
   W.headerTextInset=112
  else
   W.v3Heraldry:SetShown(false);W.headerTextInset=24
  end
  if W.pageGroup then
   W.pageGroup:SetShown(not use)
   local parchment=use and key=='headerBounty'
   Kit.Paint(W.pageGroup,OWNER,parchment and 'paperText' or 'accentText','text')
   Kit.Paint(W.pageTitle,OWNER,parchment and 'paperText' or 'text','text')
   Kit.Paint(W.pageSub,OWNER,parchment and 'paperText' or 'muted','text')
   for _,text in ipairs({W.pageGroup,W.pageTitle,W.pageSub}) do
    local offset=text==W.pageGroup and 4 or text==W.pageTitle and (use and 10 or 17) or (use and 35 or 44)
    text:ClearAllPoints();text:SetPoint('TOPLEFT',strip,'TOPLEFT',W.headerTextInset,-offset)
    text:SetWidth(use and 355 or math.max(40,strip:GetWidth()-W.headerTextInset-58))
   end
  end
 end
 W.UpdateHeaderArtwork=updateHeraldryStrip
 W.v3Heraldry=S.AssetOverlay(strip,'headerDashboard','BACKGROUND',3)
 strip:HookScript('OnSizeChanged',updateHeraldryStrip)
 S.OnThemeChange(strip,updateHeraldryStrip)
 local seam=Kit.Rule(strip,OWNER,'accentSoft',true,2);seam:SetPoint('TOPLEFT');seam:SetPoint('TOPRIGHT')
 local close=CreateFrame('Button',nil,strip);close:SetSize(32,32);close:SetPoint('TOPRIGHT',-12,-14)
 S.ControlIcon(close,'Close')
 close:SetScript('OnClick',function() frame:Hide() end)
 Kit.Tooltip(close,'Close the War Room','Esc also closes it. /kt opens it again.')
end

local function updateNav()
 if W.UpdateHeaderArtwork then W.UpdateHeaderArtwork() end
 local groups={}
 for _,row in ipairs(navRows) do if row.page and pageAllowed(row.page) then groups[row.group]=true end end
 local y=0
 for _,row in ipairs(navRows) do
  local visible=row.header and groups[row.group] or (row.page and pageAllowed(row.page))
  row.frame:SetShown(visible and true or false)
  if visible then
   row.frame:ClearAllPoints()
   if row.header then row.frame:SetPoint('TOPLEFT',18,y-10);y=y-23
   else row.frame:SetPoint('TOPLEFT',8,y);row.frame:SetPoint('RIGHT',navContent,'RIGHT',-8,0);row.frame.contentTop=-y;y=y-28 end
  end
 end
 if navContent then navContent:SetHeight(-y+5) end
 for _,b in ipairs(navButtons) do
  local on=current==b.page
  b.classicSlice:SetAsset(on and 'navSelected' or b.hovered and 'navHover' or nil)
  b.bar:SetShown(on)
  Kit.Paint(b.bg,OWNER,on and 'accentSoft' or 'rail','fill')
  Kit.Paint(b.text,OWNER,on and 'text' or 'muted','text')
  if b.icon.SetVertexColor then b.icon:SetVertexColor(on and 1 or 0.82,on and 0.88 or 0.82,on and 0.68 or 0.82) end
  local n=b.page.Badge and select(2,pcall(b.page.Badge))
  b.badge:SetText(type(n)=='number' and n>0 and (n>99 and '99+' or tostring(n)) or '')
 end
 if W.officerButton then
  local visible=not W.pages['officer-command'] and officerAvailable() and true or false
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
 if frame.SetResizeBounds then frame:SetResizeBounds(900,560,1700,1100)
 elseif frame.SetMinResize then frame:SetMinResize(900,560);if frame.SetMaxResize then frame:SetMaxResize(1700,1100) end end
 frame:RegisterEvent('DISPLAY_SIZE_CHANGED')
 frame:RegisterEvent('UI_SCALE_CHANGED')
 frame:SetScript('OnEvent',function() W.FitWindow() end)
 local shadow=frame:CreateTexture(nil,'BACKGROUND',nil,-3);shadow:SetPoint('TOPLEFT',-6,6);shadow:SetPoint('BOTTOMRIGHT',6,-6)
 Kit.Paint(shadow,OWNER,'shadow','fill')
 Kit.Fill(frame,OWNER,'base');S.Art(frame,'material','BACKGROUND')
 local frameBorder=Kit.Border(frame,OWNER,'line',2,0.95)
 S.FrameChrome(frame,frameBorder,'window')
 tinsert(UISpecialFrames,'KWC2_WarRoom')
 buildRail();buildStrip()
 content=CreateFrame('Frame',nil,frame)
 content:SetPoint('TOPLEFT',RAIL_W+22,-STRIP_H-14);content:SetPoint('BOTTOMRIGHT',-18,18)
 W.content=content
 -- resize grip
 local grip=CreateFrame('Button',nil,frame);grip:SetSize(16,16);grip:SetPoint('BOTTOMRIGHT',-3,3)
 S.ControlIcon(grip,'ResizeGrip')
 grip:SetScript('OnMouseDown',function() frame:StartSizing('BOTTOMRIGHT') end)
 grip:SetScript('OnMouseUp',function() frame:StopMovingOrSizing();W.FitWindow();saveGeometry();W.Refresh(true) end)
 frame:SetScript('OnShow',function() updateNav();if K.Sync and K.Sync.OnWindowOpened then Kit.Safe(K.Sync.OnWindowOpened) end end)
 frame:SetScript('OnHide',function() saveGeometry() end)
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
 if not pageAllowed(page) then page=W.pages.dashboard end
 if current and current~=page and current.host then current.host:Hide() end
 current=page
 if not page._built then
  local host=CreateFrame('Frame',nil,content);host:SetAllPoints(content)
  page.host=host
  local ok=Kit.Safe(page.Build,page,host)
  if not ok then
   -- A failed build can leave only some page fields initialized. Never run
   -- OnShow, Layout, or Update on that partial page; sync refreshes wait for
   -- the successful-build flag below.
   host:Hide();page.host=nil
   current=nil
   if frame:IsShown() then frame:Hide() end
   return false
  end
  page._built=true
 end
 page.host:Show()
 if page.Layout then Kit.Safe(page.Layout,page) end
 if W.UpdateHeaderArtwork then W.UpdateHeaderArtwork() end
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
 updateNav()
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
 if frame and frame:IsShown() and current then
  if not pageAllowed(current) then W.Show('dashboard');return end
  if current._built and current.Update then Kit.Safe(current.Update,current) end
  updateNav()
 end
end)
function W.Refresh(now)
 dirty=true
 if now then since=1 end
end
