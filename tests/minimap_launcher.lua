-- Minimap button: single instance, artwork, tooltip, clicks, drag, minimap
-- resize, reload and reset. Run from the repository root.
local H=dofile('tests/harness/wow.lua')
local function session(settings,rank)
 local w=H.World()
 w:AddMember({name='Grom Warcry',rank=rank or 5,guid='Player-1-0000000B'})
 local c=w:Client('Grom Warcry');local env=c.env
 w:LoadAddon(c,'KeepersWarCommand')
 for k,v in pairs(settings) do env.KWCDB.settings[k]=v end
 local x,y=50,50
 env.GetCursorPosition=function() return x,y end
 env.Minimap.GetCenter=function() return 100,100 end
 env.Minimap.GetEffectiveScale=function() return 0.5 end
 env.Minimap.width,env.Minimap.height=140,160
 w:Login(c);w:Fire(c,'PLAYER_LOGIN');w:Advance(2)
 local buttons={}
 for _,f in ipairs(c.allWidgets) do if f.name=='KWC2_MinimapButton' then buttons[#buttons+1]=f end end
 assert(#buttons==1,'duplicate launcher')
 local toggles={}
 env.KWC.UI.Toggle=function() toggles[#toggles+1]='toggle' end
 env.KWC.UI.Open=function(page) toggles[#toggles+1]=page end
 local tip={}
 env.GameTooltip={SetOwner=function() tip={} end,SetText=function(_,t) tip.title=t end,AddLine=function(_,t) tip[#tip+1]=t end,
  Show=function() tip.shown=true end,Hide=function() tip.shown=false end}
 return {w=w,c=c,env=env,M=env.KWC.Minimap,b=buttons[1],toggles=toggles,tip=function() return tip end,
  cursor=function(a,b) x,y=a,b end,
  at=function() local _,rel,_,px,py=buttons[1]:GetPoint(1);assert(rel==env.Minimap);return px,py end}
end

local s=session({})
local b=s.b
assert(s.M.IsVisible() and b:IsShown() and b:GetWidth()==32)
local artwork;for _,t in ipairs(b.children) do if t.kind=='Texture' and t.texture then artwork=t.texture end end
assert(artwork==s.env.KWC.WarRoomSkin.AssetPath('crestSmallMark'))
assert(io.open('KeepersWarCommand/Media/WarRoomClassic/'..artwork:match('([^\\]+)$')..'.tga','rb'),'artwork ships')
b:GetScript('OnEnter')(b)
assert(s.tip().shown and s.tip().title=='Keepers War Command' and #s.tip()==3 and s.tip()[2]=='Right-click: Settings')
b:GetScript('OnLeave')(b);assert(not s.tip().shown)
b:GetScript('OnClick')(b,'LeftButton');b:GetScript('OnClick')(b,'RightButton')
assert(s.toggles[1]=='toggle' and s.toggles[2]=='settings')
s.cursor(50,100)
b:GetScript('OnDragStart')(b);b:GetScript('OnUpdate')(b);b:GetScript('OnDragStop')(b)
assert(not b:GetScript('OnUpdate'))
local settings=s.env.KWCDB.settings
local px,py=s.at()
assert(math.abs(settings.ui2MinimapAngle-90)<1e-8 and math.abs(px)<1e-8 and math.abs(py-80)<1e-8)
s.env.Minimap.width=200;s.env.Minimap:GetScript('OnSizeChanged')(s.env.Minimap,200,200)
px,py=s.at();assert(math.abs(py-110)<1e-8,'button follows a resized minimap: '..py)
s.M.SetVisible(false);assert(not b:IsShown() and not s.M.IsVisible())
local reloaded=session({ui2MinimapHidden=true,ui2MinimapAngle=90})
assert(not reloaded.M.IsVisible() and not reloaded.b:IsShown())
px,py=reloaded.at();assert(math.abs(py-80)<1e-8)
reloaded.M.SetVisible(true);reloaded.M.Reset()
px,py=reloaded.at()
assert(reloaded.b:IsShown() and reloaded.env.KWCDB.settings.ui2MinimapAngle==nil and px<0 and py<0)
assert(#s.c.errors==0 and #reloaded.c.errors==0,s.c.errors[1] or reloaded.c.errors[1])
print('PASS: minimap singleton, asset, tooltip, clicks, drag, resize, reload and reset')
