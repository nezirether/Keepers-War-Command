local function session(settings)
 local buttons,events,toggles={}, {}, {}
 local x,y=50,50
 local tooltip={}
 function tooltip:SetOwner(owner) self.owner=owner;self.lines={} end
 function tooltip:IsOwned(owner) return self.owner==owner end
 function tooltip:SetText(title) self.title=title end
 function tooltip:AddLine(line) self.lines[#self.lines+1]=line end
 function tooltip:Show() self.shown=true end
 function tooltip:Hide() self.shown=false;self.owner=nil end
 local minimap={
  width=140,height=160,
  GetWidth=function(self) return self.width end,GetHeight=function(self) return self.height end,
  GetCenter=function() return 100,100 end,GetEffectiveScale=function() return 0.5 end,
  GetFrameLevel=function() return 2 end,
  HookScript=function(self,event,fn) self[event]=fn end,
 }
 local env=setmetatable({
  Minimap=minimap,GameTooltip=tooltip,KWCDB={settings=settings},
  GetCursorPosition=function() return x,y end,
  KWC={version="1.6.1",On=function(event,fn) events[event]=fn end,
   UI={Toggle=function(page) toggles[#toggles+1]=page or "toggle" end}},
 },{__index=_G})
 env.CreateFrame=function(kind,name,parent)
  assert(kind=="Button" and name=="KWCMinimapLauncher" and parent==minimap)
  local b={scripts={}}
  function b:SetSize(w,h) assert(w==30 and h==30) end
  function b:SetFrameLevel(level) assert(level>minimap:GetFrameLevel()) end
  function b:SetNormalTexture(path) self.texture=path end
  function b:SetHighlightTexture() end
  function b:RegisterForClicks(left,right) assert(left=="LeftButtonUp" and right=="RightButtonUp") end
  function b:RegisterForDrag(mouse) assert(mouse=="LeftButton") end
  function b:SetScript(event,fn) self.scripts[event]=fn end
  function b:ClearAllPoints() self.x,self.y=nil,nil end
  function b:SetPoint(_,relative,_,anchorX,anchorY)
   assert(relative==minimap)
   self.x,self.y=anchorX,anchorY
  end
  function b:SetShown(value)
   self.shown=value
   if not value then self.scripts.OnHide(self) end
  end
  buttons[#buttons+1]=b
  return b
 end
 setfenv(assert(loadfile("KeepersWarCommand/MinimapLauncher.lua")),env)()
 events.PLAYER_LOGIN()
 events.PLAYER_ENTERING_WORLD()
 events.PLAYER_LOGIN()
 assert(#buttons==1,"duplicate launcher")
 return env.KWC.MinimapLauncher,buttons[1],toggles,tooltip,minimap,function(nextX,nextY) x,y=nextX,nextY end
end

local settings={}
local launcher,b,toggles,tip,minimap,cursor=session(settings)
assert(launcher.IsVisible() and b.shown)
assert(b.texture:match("Textures\\TrogdorMinimap%.tga$"))
b.scripts.OnEnter(b)
assert(tip.shown and tip.title=="Keepers War Command 1.6.1" and #tip.lines==3)
b.scripts.OnMouseDown(b)
b.scripts.OnClick(b,"LeftButton")
b.scripts.OnMouseDown(b)
b.scripts.OnClick(b,"RightButton")
assert(toggles[1]=="toggle" and toggles[2]=="Settings")
cursor(50,100)
b.scripts.OnDragStart(b)
b.scripts.OnUpdate(b)
b.scripts.OnDragStop(b)
b.scripts.OnClick(b,"LeftButton")
assert(#toggles==2 and not tip.shown and not b.scripts.OnUpdate)
assert(settings.minimapAngle==90 and math.abs(b.x)<1e-8 and b.y==84)
minimap.height=200;minimap.OnSizeChanged(minimap)
assert(b.y==104)
launcher.SetVisible(false)
assert(not b.shown)
local reloaded,newButton=session(settings)
assert(not reloaded.IsVisible() and not newButton.shown and newButton.y==84)
reloaded.SetVisible(true)
reloaded.ResetPosition()
assert(newButton.shown and settings.minimapAngle==nil and newButton.x<0 and newButton.y<0)
print("PASS: minimap singleton, asset, tooltip, clicks, drag, resize, reload and reset")
