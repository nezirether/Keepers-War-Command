-- Winter Veil seasonal layer: dates, switch, restoration, placement at the
-- smallest and larger window sizes, scaling, mouse and timer safety, artwork.
local H=dofile('tests/harness/wow.lua')
local function at(year,month,day,hour) return os.time({year=year,month=month,day=day,hour=hour or 12}) end
local function boot(now,mutate,saved)
 local w=H.World({now=now})
 w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})
 local c=w:Client('Grom Warcry',{saved=saved});if mutate then mutate(c) end
 w:LoadAddon(c,'KeepersWarCommand');c.env.UIParent:SetSize(1920,1080);w:Login(c);w:Advance(8)
 return w,c,c.env.KWC
end
local function winter(c)
 local out={}
 for _,o in ipairs(c.allWidgets) do
  if o.kind=='Texture' and type(o.texture)=='string' and o.texture:find('WinterVeil',1,true) then out[o.texture:match('([^\\]+)$')]=o end
 end
 return out
end
local function visible(o) while o do if not o:IsShown() then return false end;o=o.parent end;return true end
local function shownArt(c) local n={};for name,o in pairs(winter(c)) do if visible(o) then n[#n+1]=name end end;table.sort(n);return table.concat(n,',') end
local ALL='FestiveTrogdor,FrostCornerLeft,FrostCornerRight,HeaderGarland,WinterVeilEmblem'
-- The harness does not resolve anchors, so give the Dashboard its in-game width.
local function dashboard(w,K,width,height)
 local W=K.WarRoom2;W.Show('dashboard');w:Advance(1)
 -- The harness does not restore saved geometry; size the window as ui_layout does.
 W.Frame():SetSize(width or 1180,height or 760);W.FitWindow();W.UpdateHeaderArtwork()
 local content=W.pages.dashboard.content
 if not content.gameLike then
  -- The client raises OnSizeChanged only when a size changes; the harness always does.
  local set=content.SetHeight;content.gameLike=true
  content.SetHeight=function(self,h) if h~=self.height then set(self,h) end end
 end
 content.width=W.Frame():GetWidth()-262;W.pages.dashboard:Layout();w:Advance(1)
end

for _,case in ipairs({{'November 25 2026',at(2026,11,25,23),false},{'November 26 2026',at(2026,11,26,0),true},{'December 25 2026',at(2026,12,25),true},
 {'January 1 2027',at(2027,1,1),true},{'January 2 2027',at(2027,1,2,23),true},{'January 3 2027',at(2027,1,3,0),false},{'December 2027',at(2027,12,25),false}}) do
 local w,c,K=boot(case[2]);K.WarRoom2.Show('dashboard');w:Advance(1)
 H.Check((case[3] and 'decorated on ' or 'classic on ')..case[1],K.WinterVeil.Active()==case[3] and (shownArt(c)~='')==case[3] and #c.errors==0,shownArt(c)..' '..table.concat(c.errors,'|'))
end

-- Date source
local w,c,K=boot(at(2026,12,25),function(c) c.env.C_DateAndTime=nil end)
H.Check('falls back to the computer date without a game calendar',K.WinterVeil.Today()==20261225)
c.env.C_DateAndTime={GetCurrentCalendarTime=function() error('unavailable') end}
H.Check('falls back when the game calendar errors',K.WinterVeil.Today()==20261225)
c.env.C_DateAndTime={GetCurrentCalendarTime=function() return {year=25,month=1,monthDay=1} end}
H.Check('ignores an implausible calendar year',K.WinterVeil.Today()==20261225)
c.env.C_DateAndTime={GetCurrentCalendarTime=function() return {year=2027,month=1,monthDay=3} end}
H.Check('prefers the game calendar over the computer date',K.WinterVeil.Today()==20270103 and not K.WinterVeil.Active())

-- Expiry while the Dashboard stays open
w,c,K=boot(at(2027,1,2,23));local W=K.WarRoom2;dashboard(w,K);w:Advance(2)
local dash=W.pages.dashboard
H.Check('open on January 2 at the default size: all five textures show',shownArt(c)==ALL,shownArt(c))
w.now=at(2027,1,3,0)+30;w:Advance(40)
H.Check('January 3 returns to War Room Classic while open',shownArt(c)=='' and dash.seasonHeight==0,shownArt(c))

-- Switch, restoration and no side effects
local function classic(c)
 local out={}
 for i,o in ipairs(c.allWidgets) do
  if o.kind=='Texture' and type(o.texture)=='string' and not o.texture:find('WinterVeil',1,true) then out[#out+1]=i..o.texture..tostring(o:IsShown()) end
 end
 return table.concat(out,';')
end
local function geometry(K)
 local W=K.WarRoom2
 return table.concat({W.pageTitle:GetWidth(),W.pageSub:GetWidth(),W.pages.dashboard.seasonHeight,W.pages.dashboard.content:GetHeight(),W.Frame():GetWidth(),W.Frame():GetHeight()},',')
end
local _,base,BK=boot(at(2026,12,10),nil,{KWCDB={settings={winterVeil=false}}})
local basew=_;dashboard(basew,BK)
w,c,K=boot(at(2026,12,10));W=K.WarRoom2;dashboard(w,K);w:Advance(2)
H.Check('a saved off switch keeps War Room Classic',shownArt(base)=='' and not BK.WinterVeil.Active())
H.Check('decorations are on by default in season',K.WinterVeil.Active() and shownArt(c)~='')
local sent=0
local send=c.env.C_ChatInfo.SendAddonMessage
c.env.C_ChatInfo.SendAddonMessage=function(...) sent=sent+1;return send(...) end
local onGeometry=geometry(K)
K.WinterVeil.SetEnabled(false)
H.Check('switching off hides every seasonal texture',shownArt(c)=='' and K.WinterVeil.Active()==false,shownArt(c))
H.Check('switching off restores the classic layout and artwork',geometry(K)==geometry(BK),geometry(K)..' vs '..geometry(BK))
K.WinterVeil.SetEnabled(true)
H.Check('switching on restores the decorations',shownArt(c)~='' and geometry(K)==onGeometry,geometry(K)..' vs '..onGeometry)
H.Check('the switch sends nothing',sent==0,sent)
H.Check('War Room Classic textures are never replaced',(function() local before=classic(c);K.WinterVeil.SetEnabled(false);K.WinterVeil.SetEnabled(true);return classic(c)==before end)())
W.Show('settings');w:Advance(1)
local switch=W.pages.settings.a.winter
H.Check('Settings has one Winter Veil switch',switch~=nil)
switch.scripts.OnClick(switch);w:Advance(1)
H.Check('the Settings switch turns decorations off',c.env.KWCDB.settings.winterVeil==false and shownArt(c)=='')
switch.scripts.OnClick(switch);w:Advance(1)
H.Check('and on again',c.env.KWCDB.settings.winterVeil==true and shownArt(c)~='')

-- Mouse and animation safety
local inert=true
for _,o in pairs(winter(c)) do
 local f=o.parent
 if o.scripts.OnUpdate or o.scripts.OnClick or o.scripts.OnEnter then inert=false end
 if f and f~=W.Frame() then for _,script in ipairs({'OnUpdate','OnClick','OnEnter','OnMouseDown','OnEvent'}) do if f.scripts[script] and winter(c).FestiveTrogdor.parent~=f then inert=false end end end
end
H.Check('decorative frames have no input or timer scripts',inert)
local source=assert(io.open('KeepersWarCommand/UI/WinterVeil.lua','rb')):read('*a')
local clean=true
for _,word in ipairs({'OnUpdate','C_Timer','PlaySound','SendAddonMessage','K.Net','EnableMouse(true)','RegisterEvent','SetScript','Animation'}) do if source:find(word,1,true) then clean=false;print('found '..word) end end
H.Check('no timers, sounds, scripts or network use in the seasonal file',clean)

-- Placement across window sizes and scales
local pages={'dashboard','cta','bounties','pvp','leaderboards','records','lfg','services','raids','alerts','settings'}
for _,case in ipairs({{900,560,1},{900,560,0.75},{1040,640,1},{1180,760,1},{1180,760,1.35},{1700,1000,1}}) do
 local width,height,scale=unpack(case)
 w,c,K=boot(at(2026,12,10),nil,{KWCDB={settings={ui2Scale=scale,ui2Window={point='CENTER',x=0,y=0,w=width,h=height}}}})
 W=K.WarRoom2
 local problems={}
 dashboard(w,K,width,height)
 if W.Frame():GetWidth()~=width or W.Frame():GetHeight()~=height then problems[#problems+1]='window resized to '..W.Frame():GetWidth() end
 for _,id in ipairs(pages) do
  W.Show(id);w:Advance(0.5)

  local banner=winter(c).FestiveTrogdor
  if banner and visible(banner) then
   local left=W.Frame():GetWidth()-212-52-banner:GetWidth()
   local point,_,_,_,x=W.pageTitle:GetPoint()
   if left<430 or banner:GetHeight()>64 or banner:GetHeight()<44 or x+W.pageTitle:GetWidth()>left-8+0.1 then problems[#problems+1]=id..' banner '..left end
  end
 end
 dashboard(w,K,width,height)
 local dash=W.pages.dashboard
 local emblem,garland=winter(c).WinterVeilEmblem,winter(c).HeaderGarland
 local card=emblem.parent
 if card:GetHeight()~=84 or card:GetWidth()~=dash.content:GetWidth() then problems[#problems+1]='card size '..card:GetWidth() end
 if garland:IsShown() and card:GetWidth()-8-garland:GetWidth()<128+300 then problems[#problems+1]='garland crowds greeting '..garland:GetWidth() end
 if garland:IsShown() and garland:GetHeight()>card:GetHeight()-20 then problems[#problems+1]='garland too tall' end
 for _,o in ipairs(c.allWidgets) do
  if o.parent==dash.content and o~=card and o.kind~='Texture' and o:IsShown() then
   local point,_,_,_,y=o:GetPoint()
   if point=='TOPLEFT' and y and -y<card:GetHeight() then problems[#problems+1]='overlap at '..y end
  end
 end
 local frame=W.Frame()
 H.Check(('%dx%d at %d%%: window unchanged, banner %s, garland %s, no overlap'):format(width,height,scale*100,(winter(c).FestiveTrogdor and winter(c).FestiveTrogdor:IsShown()) and 'shown' or 'hidden',garland:IsShown() and 'shown' or 'hidden'),
  #problems==0 and #c.errors==0 and frame:GetWidth()==width and frame:GetHeight()==height,table.concat(problems,'; ')..table.concat(c.errors,'|'))
end

-- Header rules with page artwork showing, at the strip widths of real windows
w,c,K=boot(at(2026,12,10));K.WarRoom2.Show('dashboard');w:Advance(1)
local strip=K.WarRoom2.pageTitle.parent
local function header(heraldry,width) local edge=K.WinterVeil.Header(strip,heraldry,width);local b=winter(c).FestiveTrogdor;return edge,b and b:IsShown(),b end
local edge,shown=header(true,688)
H.Check('smallest window: banner hidden rather than cover the page artwork',edge==nil and not shown)
edge,shown=header(false,688)
H.Check('smallest window: banner stays hidden on every page',edge==nil and not shown)
edge,shown=header(false,720)
H.Check('slightly wider: banner fits beside the Guild Hall tabs',shown and edge>=430,edge)
for _,width in ipairs({888,968,1148,1488}) do
 local e,s,b=header(true,width)
 H.Check('strip '..width..': banner clear of artwork and close button',s and e>=596 and b:GetHeight()<=64 and b:GetHeight()>=44 and e+b:GetWidth()<=width-52+0.1,tostring(e)..' '..tostring(b and b:GetHeight()))
end

-- Artwork files
local files=0
for _,name in ipairs({'FestiveTrogdor','HeaderGarland','FrostCornerLeft','FrostCornerRight','WinterVeilEmblem'}) do
 local f=io.open('KeepersWarCommand/Media/WinterVeil/'..name..'.tga','rb')
 if f then
  local head=f:read(18);f:close()
  local width,height=head:byte(13)+256*head:byte(14),head:byte(15)+256*head:byte(16)
  local function power(v) while v%2==0 do v=v/2 end;return v==1 end
  if head:byte(3)==2 and head:byte(17)==32 and head:byte(18)%16==8 and power(width) and power(height) then files=files+1 end
 end
end
H.Check('five 32-bit power-of-two textures ship with the add-on',files==5,files)
os.exit(H.Summary('winter_veil') and 0 or 1)
