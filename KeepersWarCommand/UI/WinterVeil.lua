-- Winter Veil 2026: temporary, static War Room decorations. Active by game date
-- from November 26, 2026 through January 2, 2027 unless switched off in Settings.
-- Presentation only: no timers, no network traffic, no mouse input. War Room
-- Classic artwork is never replaced, so hiding these textures restores it.
local K=KWC
local Kit,S=K.Kit,K.WarRoomSkin
local OWNER=S.OWNER
local V={FIRST=20261126,LAST=20270102};K.WinterVeil=V
local DIR=Kit.MEDIA..'WinterVeil\\'
-- file, visible area of the canvas, width / height of that area
local ART={
 banner={'FestiveTrogdor',{3/1024,1019/1024,23/256,238/256},1016/215},
 garland={'HeaderGarland',{28/1024,1000/1024,0,116/128},972/116},
 cornerLeft={'FrostCornerLeft',{0,1,0,1},1},
 cornerRight={'FrostCornerRight',{0,1,0,1},1},
 emblem={'WinterVeilEmblem',{0,1,84/512,428/512},512/344},
}
local CARD_HEIGHT=84
local corners,banner,card

local function readable(value) return not issecretvalue or not issecretvalue(value) end
local function dayNumber(year,month,day)
 for _,v in ipairs({year,month,day}) do
  if not readable(v) or type(v)~='number' or v%1~=0 then return end
 end
 if year<2020 or month<1 or month>12 or day<1 or day>31 then return end
 return year*10000+month*100+day
end
-- The game calendar first; the computer's date if the client cannot supply it.
function V.Today()
 if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
  local ok,now=pcall(C_DateAndTime.GetCurrentCalendarTime)
  if ok and readable(now) and type(now)=='table' then
   local today=dayNumber(now.year,now.month,now.monthDay)
   if today then return today end
  end
 end
 local ok,now=pcall(date,'*t')
 if ok and type(now)=='table' then return dayNumber(now.year,now.month,now.day) end
end
function V.InSeason()
 local today=V.Today()
 return today~=nil and today>=V.FIRST and today<=V.LAST
end
function V.Enabled() return not (KWCDB and KWCDB.settings and KWCDB.settings.winterVeil==false) end
function V.Active() return V.Enabled() and V.InSeason() end

local function texture(parent,key,layer,subLevel)
 local art=ART[key]
 local t=parent:CreateTexture(nil,layer or 'ARTWORK',nil,subLevel or 1)
 t:SetTexture(DIR..art[1]);t:SetTexCoord(art[2][1],art[2][2],art[2][3],art[2][4])
 return t
end
local function sized(t,key,height) t:SetSize(math.floor(height*ART[key][3]+0.5),height) end

-- Frosted lantern brackets that hug the outside of the window's top corners.
function V.Window(window)
 local on=V.Active()
 if on and not corners then
  corners=CreateFrame('Frame',nil,window)
  corners:SetAllPoints(window);corners:SetFrameLevel(window:GetFrameLevel()+25);corners:EnableMouse(false)
  local left=texture(corners,'cornerLeft','OVERLAY');left:SetSize(84,84);left:SetPoint('TOPLEFT',corners,'TOPLEFT',-26,18)
  local right=texture(corners,'cornerRight','OVERLAY');right:SetSize(84,84);right:SetPoint('TOPRIGHT',corners,'TOPRIGHT',28,18)
  corners.left,corners.right=left,right
 end
 if corners then corners:SetShown(on) end
end

-- Festive banner at the right of the header, only where it cannot cover the page
-- artwork, title or tabs. heraldry: the header is showing its own page artwork.
-- Returns the left edge of the banner so the title text can stop before it.
function V.Header(strip,heraldry,width)
 local on=V.Active()
 local limit=heraldry and 596 or 430
 local height=math.min(64,math.floor((width-52-limit)/ART.banner[3]))
 if not on or height<44 then
  if banner then banner:Hide() end
  return
 end
 if not banner then banner=texture(strip,'banner','ARTWORK',3);banner:SetPoint('RIGHT',strip,'RIGHT',-52,0) end
 sized(banner,'banner',height);banner:Show()
 return width-52-math.floor(height*ART.banner[3]+0.5)
end

-- Greeting row at the top of the Dashboard. Returns the height it occupies.
function V.Dashboard(parent,width)
 if not V.Active() then
  if card then card:Hide() end
  return 0
 end
 if not card then
  card=CreateFrame('Frame',nil,parent);card:EnableMouse(false)
  Kit.Fill(card,OWNER,'surface');Kit.Border(card,OWNER,'lineSoft',1,0.9)
  card.emblem=texture(card,'emblem','ARTWORK',2);sized(card.emblem,'emblem',72);card.emblem:SetPoint('LEFT',card,'LEFT',10,0)
  card.greeting=Kit.Text(card,OWNER,'display',20,'text')
  card.greeting:SetPoint('TOPLEFT',card,'TOPLEFT',128,-22);card.greeting:SetText('Happy Winter Veil, Keepers!')
  card.flavor=S.Text(card,'small','accentText')
  card.flavor:SetPoint('TOPLEFT',card,'TOPLEFT',128,-50);card.flavor:SetText('Burninating through the snow.')
  card.garland=texture(card,'garland','ARTWORK',1)
  card.garland:SetPoint('TOPRIGHT',card,'TOPRIGHT',-8,-1)
 end
 card:ClearAllPoints();card:SetPoint('TOPLEFT',parent,'TOPLEFT',0,0);card:SetSize(width,CARD_HEIGHT)
 local textRight=width-12
 -- The garland hangs from the card's top edge when there is room beside the text.
 local garland=math.min(300,width-440)
 if garland>=160 then
  card.garland:SetSize(garland,math.floor(garland/ART.garland[3]+0.5));card.garland:Show()
  textRight=width-garland-16
 else card.garland:Hide() end
 card.greeting:SetWidth(math.max(1,textRight-128));card.flavor:SetWidth(math.max(1,textRight-128))
 card:Show()
 return CARD_HEIGHT+10
end

function V.SetEnabled(enabled)
 if not KWCDB or not KWCDB.settings then return end
 KWCDB.settings.winterVeil=enabled and true or false
 local W=K.WarRoom2
 if W.UpdateHeaderArtwork then W.UpdateHeaderArtwork() end
 local dashboard=W.pages.dashboard
 if dashboard and dashboard._built then Kit.Safe(dashboard.Layout,dashboard) end
 W.Refresh(true)
end
