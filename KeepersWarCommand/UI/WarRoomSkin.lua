-- The War Room visual language (public KWC). All public skins share one structure.
-- Components here are shared by the public War Room and integrated officer page.
local K=KWC
local Kit=K.Kit
local S={};K.WarRoomSkin=S
local OWNER='warroom'
S.OWNER=OWNER
local Themes=K.PublicThemes
S.skins=Themes.entries
local artwork=setmetatable({},{__mode='k'})
local markers=setmetatable({},{__mode='k'})
local skinWidgets=setmetatable({},{__mode='k'})
S.theme={colors=Themes.Get(Themes.default).colors,headingFace='body'}
Kit.RegisterTheme(OWNER,S.theme)
local active=Themes.default

local function artEntry(skin,slot)
 return skin and skin.art and skin.art[slot]
end

local function crop(texture,aspect,width,height,x,y)
 if not aspect or not width or not height or width<=0 or height<=0 then
  texture:SetTexCoord(0,1,0,1)
  return
 end
 local ratio=width/height
 if ratio>aspect then
  local span=aspect/ratio
  local top=Kit.Clamp((y or 0.5)-span/2,0,1-span)
  texture:SetTexCoord(0,1,top,top+span)
 else
  local span=ratio/aspect
  local left=Kit.Clamp((x or 0.5)-span/2,0,1-span)
  texture:SetTexCoord(left,left+span,0,1)
 end
end

function S.DrawArt(texture,id,slot,width,height)
 local skin=Themes.Get(id)
 local art=artEntry(skin,slot)
 if not art then texture:SetAlpha(0);return end
 local ok,loaded=pcall(texture.SetTexture,texture,Kit.MEDIA..art[1])
 local tint=art[4] and skin.colors.accent or {1,1,1}
 texture:SetVertexColor(tint[1],tint[2],tint[3])
 if texture.SetHorizTile then texture:SetHorizTile(art[7]==true) end
 if texture.SetVertTile then texture:SetVertTile(art[8]==true) end
 crop(texture,art[3],width,height,art[5],art[6])
 texture:SetAlpha(ok and loaded~=false and art[2] or 0)
end

local function registerSkinWidget(frame,callback)
 local callbacks=skinWidgets[frame]
 if not callbacks then callbacks={};skinWidgets[frame]=callbacks end
 callbacks[#callbacks+1]=callback
 callback()
end

function S.AssetPath(key)
 local skin=Themes.Get(active);local file=skin and skin.assets and skin.assets[key]
 return file and (Kit.MEDIA..'WarRoomClassic\\'..file) or nil
end

function S.AssetAspect(key)
 local skin=Themes.Get(active)
 return skin and skin.assetAspect and skin.assetAspect[key]
end

local function applyAssetUV(texture,key)
 local skin=Themes.Get(active);local uv=skin and skin.assetUV and skin.assetUV[key]
 if uv then texture:SetTexCoord(uv[1],uv[2],uv[3],uv[4])
 else texture:SetTexCoord(0,1,0,1) end
end

function S.ThemedTexture(parent,key,size,layer,subLevel)
 local texture=parent:CreateTexture(nil,layer or 'ARTWORK',nil,subLevel or 1)
 if size then texture:SetSize(size*(S.AssetAspect(key) or 1),size) end
 registerSkinWidget(parent,function()
  local path=S.AssetPath(key)
  if path then
   if size then texture:SetSize(size*(S.AssetAspect(key) or 1),size) end
   texture:SetTexture(path);applyAssetUV(texture,key);texture:SetAlpha(1);texture:Show()
  else texture:SetAlpha(0);texture:Hide() end
 end)
 return texture
end

function S.OnThemeChange(parent,callback)
 registerSkinWidget(parent,callback)
end

-- Three-slice production textures keep metallic end caps undistorted while
-- allowing their centers to fit real live text controls at any width.
function S.SliceAsset(frame,key,capPixels,totalPixels,layer,subLevel,height,sourceCapPixels)
 local textures={}
 for i=1,3 do textures[i]=frame:CreateTexture(nil,layer or 'BORDER',nil,subLevel or 2) end
 textures[1]:SetPoint('TOPLEFT',frame,'TOPLEFT',0,0);textures[1]:SetWidth(capPixels)
 textures[3]:SetPoint('TOPRIGHT',frame,'TOPRIGHT',0,0);textures[3]:SetWidth(capPixels)
 if height then
  textures[1]:SetHeight(height);textures[3]:SetHeight(height)
  textures[2]:SetPoint('TOPLEFT',textures[1],'TOPRIGHT',0,0);textures[2]:SetPoint('TOPRIGHT',textures[3],'TOPLEFT',0,0);textures[2]:SetHeight(height)
 else
  textures[1]:SetPoint('BOTTOMLEFT',frame,'BOTTOMLEFT',0,0)
  textures[3]:SetPoint('BOTTOMRIGHT',frame,'BOTTOMRIGHT',0,0)
  textures[2]:SetPoint('TOPLEFT',textures[1],'TOPRIGHT',0,0);textures[2]:SetPoint('BOTTOMRIGHT',textures[3],'BOTTOMLEFT',0,0)
 end
 local sourceCap=sourceCapPixels or capPixels
 local partUV={{0,sourceCap/totalPixels},{sourceCap/totalPixels,(totalPixels-sourceCap)/totalPixels},{(totalPixels-sourceCap)/totalPixels,1}}
 for i,t in ipairs(textures)do t:SetTexCoord(partUV[i][1],partUV[i][2],0,1)end
 local slice={textures=textures,key=key,alpha=1}
 function slice:SetAsset(assetKey)
  self.key=assetKey
  local path=S.AssetPath(self.key)
  if path then
   for _,texture in ipairs(self.textures)do texture:SetTexture(path);texture:SetAlpha(self.alpha);texture:Show()end
  else for _,texture in ipairs(self.textures)do texture:Hide()end end
 end
 function slice:SetAlpha(alpha)
  self.alpha=alpha
  for _,texture in ipairs(self.textures)do texture:SetAlpha(alpha)end
 end
 function slice:Hide()for _,texture in ipairs(self.textures)do texture:Hide()end end
 function slice:Show()self:SetAsset(self.key)end
 registerSkinWidget(frame,function()slice:SetAsset(slice.key)end)
 return slice
end

function S.AssetOverlay(parent,key,layer,subLevel)
 local texture=parent:CreateTexture(nil,layer or 'BACKGROUND',nil,subLevel or 1)
 local region={texture=texture,key=key,visible=false,alpha=1}
 function region:Refresh()
  local path=S.AssetPath(self.key)
  if path and self.visible then texture:SetTexture(path);applyAssetUV(texture,self.key);texture:SetAlpha(self.alpha);texture:Show()
  else texture:Hide() end
 end
 function region:SetAsset(value) self.key=value;self:Refresh() end
 function region:SetShown(value) self.visible=value and true or false;self:Refresh() end
 function region:SetAlpha(value) self.alpha=value;self:Refresh() end
 function region:SetAllPoints(...) texture:SetAllPoints(...);return self end
 function region:SetPoint(...) texture:SetPoint(...);return self end
 function region:SetSize(...) texture:SetSize(...);return self end
 function region:ClearAllPoints() texture:ClearAllPoints();return self end
 function region:SetAspectHeight(height)
  texture:SetSize(height*(S.AssetAspect(self.key) or 1),height);return self
 end
 registerSkinWidget(parent,function()region:Refresh()end)
 return region
end

local function applyFrameChrome(frame,flatEdges,kind)
 frame._warRoomChrome=frame._warRoomChrome or CreateFrame('Frame',nil,frame)
 local chrome=frame._warRoomChrome
 chrome:SetAllPoints(frame);chrome:SetFrameLevel(frame:GetFrameLevel()+20);chrome:EnableMouse(false)
 local spec=kind=='window' and {edge=5,corner=34} or kind=='stat' and {edge=2,corner=9} or {edge=3,corner=17}
 chrome._warRoomChromeTextures=chrome._warRoomChromeTextures or {}
 local t=chrome._warRoomChromeTextures
 if #t==0 then
  for i=1,8 do t[i]=chrome:CreateTexture(nil,'OVERLAY',nil,7) end
  t[1]:SetPoint('TOPLEFT',chrome,'TOPLEFT',spec.corner,0);t[1]:SetPoint('TOPRIGHT',chrome,'TOPRIGHT',-spec.corner,0);t[1]:SetHeight(spec.edge)
  t[2]:SetPoint('BOTTOMLEFT',chrome,'BOTTOMLEFT',spec.corner,0);t[2]:SetPoint('BOTTOMRIGHT',chrome,'BOTTOMRIGHT',-spec.corner,0);t[2]:SetHeight(spec.edge)
  t[3]:SetPoint('TOPLEFT',chrome,'TOPLEFT',0,-spec.corner);t[3]:SetPoint('BOTTOMLEFT',chrome,'BOTTOMLEFT',0,spec.corner);t[3]:SetWidth(spec.edge)
  t[4]:SetPoint('TOPRIGHT',chrome,'TOPRIGHT',0,-spec.corner);t[4]:SetPoint('BOTTOMRIGHT',chrome,'BOTTOMRIGHT',0,spec.corner);t[4]:SetWidth(spec.edge)
  for i=5,8 do t[i]:SetSize(spec.corner,spec.corner)end
  t[5]:SetPoint('TOPLEFT',chrome,'TOPLEFT',0,0);t[6]:SetPoint('TOPRIGHT',chrome,'TOPRIGHT',0,0)
  t[7]:SetPoint('BOTTOMLEFT',chrome,'BOTTOMLEFT',0,0);t[8]:SetPoint('BOTTOMRIGHT',chrome,'BOTTOMRIGHT',0,0)
 end
 local keys={'frameEdgeHorizontal','frameEdgeHorizontal','frameEdgeVertical','frameEdgeVertical',
  'frameCornerTL','frameCornerTR','frameCornerBL','frameCornerBR'}
 local function refresh()
  local skin=Themes.Get(active);local assets=skin and skin.assets
  local enabled=assets~=nil
  for i,texture in ipairs(t)do
   local file=enabled and assets[keys[i]]
   if file then texture:SetTexture(Kit.MEDIA..'WarRoomClassic\\'..file);texture:SetAlpha(1);texture:Show()
   else texture:Hide()end
  end
  for _,edge in ipairs(flatEdges or {})do edge:SetAlpha(enabled and 0 or 0.85)end
 end
 registerSkinWidget(frame,refresh)
 return chrome
end
S.FrameChrome=applyFrameChrome

local function paintArt(texture,spec)
 S.DrawArt(texture,active,spec.slot,spec.owner:GetWidth(),spec.owner:GetHeight())
end

function S.Art(frame,slot,layer)
 local texture=frame:CreateTexture(nil,layer or 'BORDER',nil,1)
 texture:SetAllPoints(frame)
 local spec={owner=frame,slot=slot}
 artwork[texture]=spec
 if slot=='banner' or slot=='crest' or slot=='ornament' then
  frame:HookScript('OnSizeChanged',function()
   local art=artEntry(Themes.Get(active),slot)
   if art then crop(texture,art[3],frame:GetWidth(),frame:GetHeight(),art[5],art[6]) end
  end)
 end
 paintArt(texture,spec)
 return texture
end

local function activate(id)
 active=id
 local skin=Themes.Get(id)
 S.theme.colors,S.theme.fonts=skin.colors,skin.fonts
 Kit.Repaint(OWNER)
 for texture,spec in pairs(artwork) do paintArt(texture,spec) end
 for texture in pairs(markers) do texture:SetHeight(skin.marker or 2) end
 for frame,callbacks in pairs(skinWidgets)do
  for _,callback in ipairs(callbacks)do callback()end
 end
 if K.WarRoom2 then K.WarRoom2.Refresh(true) end
end

function S.Current() return Themes.Saved() end
function S.Active() return active end
function S.Restore() activate(Themes.Saved()) end
function S.Color(role) return S.theme.colors[role] end
function S.Code(role) return Kit.Code(S.theme.colors[role]) end

-- Typography scale (pixel sizes). Body copy is 13-14 for comfortable reading.
S.type={display=24,title=21,section=16,body=13,small=12,kicker=11}
function S.Text(parent,style,role)
 if style=='display' then return Kit.Text(parent,OWNER,'display',S.type.display,role or 'text') end
 if style=='title' then return Kit.Text(parent,OWNER,'display',S.type.title,role or 'text') end
 if style=='section' then return Kit.Text(parent,OWNER,'display',S.type.section,role or 'text') end
 if style=='kicker' then return Kit.Text(parent,OWNER,'narrow',S.type.kicker+1,role or 'faint') end
 if style=='small' then return Kit.Text(parent,OWNER,'body',S.type.small,role or 'muted') end
 if style=='num' then return Kit.Text(parent,OWNER,'narrow',26,role or 'text') end
 return Kit.Text(parent,OWNER,'body',S.type.body,role or 'text')
end
function S.Para(parent,width,role,size) return Kit.Para(parent,OWNER,'body',size or S.type.body,role or 'muted',width) end
-- Kicker labels: uppercase narrow type for section labels.
function S.Kick(fs,text) fs:SetText((text or ''):upper()) end

-- Square V4 artwork follows the native Button state machine.
function S.ControlIcon(button,name)
 local base=Kit.MEDIA..'WarRoomClassic\\'..name..'_'
 button:SetNormalTexture(base..'Normal')
 button:SetPushedTexture(base..'Pressed')
 button:SetHighlightTexture(base..'Hover','BLEND')
end

-- Buttons: crimson primary, quiet bronze secondary, and action-colored responses.
-- variants: primary | secondary | ghost | danger | success | warning
function S.Button(parent,label,variant,onClick,width,height,navTab)
 variant=variant or 'secondary'
 local b=CreateFrame('Button',nil,parent)
 b:SetSize(width or 120,height or 30)
 local fillRole=variant=='primary' and 'primary' or variant=='danger' and 'dangerSoft' or variant=='warning' and 'warnSoft' or variant=='success' and 'goodSoft' or variant=='ghost' and 'base' or 'raised'
 local edgeRole=variant=='danger' and 'danger' or variant=='warning' and 'warn' or variant=='success' and 'good' or 'accent'
 b.bg=Kit.Fill(b,OWNER,fillRole,'BACKGROUND',variant=='ghost' and 0 or nil)
 b.edge=Kit.Rule(b,OWNER,edgeRole,true,Themes.Get(active).marker or 2)
 markers[b.edge]=true
 b.edge:SetPoint('BOTTOMLEFT');b.edge:SetPoint('BOTTOMRIGHT')
 b.edge:SetShown(false)
 -- Navigation labels render on an independent, non-interactive foreground frame.
 local labelParent=b
 if navTab then
  labelParent=CreateFrame('Frame',nil,b)
  labelParent:SetAllPoints(b);labelParent:SetFrameLevel(b:GetFrameLevel()+2)
  labelParent:EnableMouse(false)
 end
 b.text=Kit.Text(labelParent,OWNER,'body',13,(variant=='primary' or variant=='danger' or variant=='warning' or variant=='success') and 'onAccent' or 'text')
 b.text:SetPoint('TOPLEFT',b,'TOPLEFT',6,-2);b.text:SetPoint('BOTTOMRIGHT',b,'BOTTOMRIGHT',-6,2)
 b.text:SetDrawLayer('OVERLAY',7);b.text:SetJustifyV('MIDDLE')
 b.text:SetJustifyH('CENTER');b.text:SetText(label)
 b.variant=variant
 local function setButtonFill(self,hover)
  local disabled=self.enabled==false
  local role=disabled and 'raised' or self.selected and (navTab and 'selected' or 'accentSoft') or fillRole
  if hover and self.enabled~=false and variant~='primary' and variant~='danger' and variant~='warning' and variant~='success' and not (navTab and self.selected) then role='hover' end
  Kit.Paint(self.bg,OWNER,role,'fill',variant=='ghost' and not hover and not self.selected and 0 or nil)
  if self.classicSlice then
   local prefix=variant=='primary' and 'primary' or variant=='danger' and 'danger' or variant=='success' and 'accept' or variant=='warning' and 'caution' or 'secondary'
   local suffix=disabled and 'Disabled' or self.pressed and 'Pressed' or hover and 'Hover' or 'Normal'
   if navTab then prefix='tab';suffix=self.selected and 'Selected' or 'Normal' end
   self.classicSlice:SetAsset(prefix..suffix)
   self.classicSlice:SetAlpha(variant=='ghost' and not hover and not self.selected and not disabled and 0.55 or 1)
  end
  local textRole=disabled and 'muted' or (variant=='primary' or variant=='danger' or variant=='warning' or variant=='success' or (navTab and self.selected)) and 'onAccent' or 'text'
  Kit.Paint(self.text,OWNER,textRole,'text',1)
  self.text:Show()
 end
 b:SetScript('OnEnter',function(self)
  if self.enabled~=false then self.edge:Show();setButtonFill(self,true) end
 end)
 b:SetScript('OnLeave',function(self) self.edge:SetShown(self.selected==true and self.enabled~=false);setButtonFill(self,false) end)
 b.classicSlice=S.SliceAsset(b,navTab and 'tabNormal' or (variant=='primary' and 'primaryNormal' or variant=='danger' and 'dangerNormal' or variant=='success' and 'acceptNormal' or variant=='warning' and 'cautionNormal' or 'secondaryNormal'),8,256,'BORDER',2,nil,16)
 b:SetScript('OnMouseDown',function(self)
  if self.enabled~=false then self.pressed=true;setButtonFill(self,self:IsMouseOver()) end
 end)
 b:SetScript('OnMouseUp',function(self) self.pressed=nil;setButtonFill(self,self:IsMouseOver()) end)
 b:SetScript('OnClick',function(self) if self.enabled~=false and onClick then Kit.Safe(onClick,self) end end)
 function b:SetSelected(selected)
  self.selected=selected and true or nil
  self.edge:SetShown(self.selected==true);setButtonFill(self,false)
 end
 function b:SetLabel(t) self.text:SetText(t) end
 -- Disabled buttons stay visible and explain why (no dead buttons).
 function b:SetEnabledState(enabled,reason)
  self.enabled=enabled and true or false
  self.reason=reason
  -- Muted palette roles and the explanatory tooltip communicate disabled state
  -- without fading the label below readable contrast.
  self:SetAlpha(1)
  self.edge:SetShown(self.enabled and self.selected==true)
  setButtonFill(self,false)
 end
 Kit.Tooltip(b,function(self) return self.enabled==false and self.reason and 'Unavailable' or self.tip or self.text:GetText() end,function(self) return self.enabled==false and self.reason or self.tipBody end)
 return b
end

-- Field: label above a flat input well; inline validation text below.
function S.Field(parent,label,width,maxLetters,placeholder)
 local f=CreateFrame('Frame',nil,parent)
 f:SetSize(width,52)
 f.label=S.Text(f,'kicker','muted');f.label:SetPoint('TOPLEFT',0,0);S.Kick(f.label,label)
 f.well=CreateFrame('Frame',nil,f)
 f.well:SetPoint('TOPLEFT',0,-16);f.well:SetPoint('TOPRIGHT',0,-16);f.well:SetHeight(28)
 Kit.Fill(f.well,OWNER,'field')
 f.classicInput=S.SliceAsset(f.well,'inputNormal',8,256,'BORDER',2,nil,16)
 f.line=Kit.Rule(f.well,OWNER,'line',true,1);f.line:SetPoint('BOTTOMLEFT');f.line:SetPoint('BOTTOMRIGHT')
 f.edit=Kit.EditBox(f.well,OWNER,'body',13,maxLetters or 80)
 f.edit:SetAllPoints(f.well)
 f.ph=Kit.Text(f.well,OWNER,'body',13,'faint');f.ph:SetPoint('LEFT',8,0);f.ph:SetText(placeholder or '')
 f.err=Kit.Text(f,OWNER,'narrow',12,'danger');f.err:SetPoint('TOPLEFT',f.well,'BOTTOMLEFT',0,-2)
 local function sync() f.ph:SetShown(f.edit:GetText()=='' and not f.edit:HasFocus()) end
 f.edit:SetScript('OnTextChanged',function() sync();f.err:SetText('') end)
 f.edit:SetScript('OnEditFocusGained',function() f.classicInput:SetAsset('inputFocus');Kit.Paint(f.line,OWNER,'accent','fill');sync() end)
 f.edit:SetScript('OnEditFocusLost',function() f.classicInput:SetAsset('inputNormal');Kit.Paint(f.line,OWNER,'line','fill');sync() end)
 f.edit:SetScript('OnTabPressed',function(self) if f.next then f.next.edit:SetFocus() end end)
 function f:Get() return (self.edit:GetText() or ''):match('^%s*(.-)%s*$') end
 function f:Set(v) self.edit:SetText(v==nil and '' or tostring(v));sync() end
 function f:Error(t) self.err:SetText(t or '');if t then Kit.Paint(self.line,OWNER,'danger','fill') end end
 return f
end

-- Segmented control: a row of flat segments; the active one carries ember.
function S.Segmented(parent,options,get,set,segWidth)
 local f=CreateFrame('Frame',nil,parent)
 f:SetHeight(28)
 f.segs={}
 local x=0
 for i,opt in ipairs(options) do
  local value,label=opt[1],opt[2] or opt[1]
  local s=CreateFrame('Button',nil,f)
  local w=segWidth or math.max(70,#label*8+24)
  s:SetSize(w,28);s:SetPoint('LEFT',x,0);x=x+w+2
  s.bg=Kit.Fill(s,OWNER,'raised')
  s.classicSlice=S.SliceAsset(s,'tabNormal',8,256,'BORDER',2,nil,16)
  s.mark=Kit.Rule(s,OWNER,'accent',true,Themes.Get(active).marker or 2);markers[s.mark]=true;s.mark:SetPoint('BOTTOMLEFT');s.mark:SetPoint('BOTTOMRIGHT')
  s.text=Kit.Text(s,OWNER,'body',12,'muted');s.text:SetPoint('LEFT',s,'LEFT',5,0);s.text:SetPoint('RIGHT',s,'RIGHT',-5,0);s.text:SetJustifyH('CENTER');s.text:SetText(label)
  s.value=value
  Kit.Tooltip(s,label)
  s:SetScript('OnClick',function() Kit.Safe(set,value);f:Update() end)
  s:SetScript('OnEnter',function(self) self.hovered=true;f:Update() end)
  s:SetScript('OnLeave',function(self) self.hovered=nil;self.pressed=nil;f:Update() end)
  s:SetScript('OnMouseDown',function(self) self.pressed=true;f:Update() end)
  s:SetScript('OnMouseUp',function(self) self.pressed=nil;f:Update() end)
  f.segs[i]=s
 end
 f:SetWidth(x)
 function f:Update()
  local cur=get()
  for _,s in ipairs(self.segs) do
   local on=s.value==cur
   s.classicSlice:SetAsset((on or s.pressed) and 'tabSelected' or s.hovered and 'navHover' or 'tabNormal')
   s.mark:SetShown(on)
   Kit.Paint(s.text,OWNER,on and 'text' or 'muted','text')
   Kit.Paint(s.bg,OWNER,on and 'accentSoft' or 'raised','fill')
  end
 end
 f:Update()
 return f
end

-- Switch: a small track with a knob; label to the right.
function S.Switch(parent,label,get,set,width,hint)
 local b=CreateFrame('Button',nil,parent)
 b:SetSize(width or 300,26)
 b.track=b:CreateTexture(nil,'ARTWORK');b.track:SetSize(21,21);b.track:SetPoint('LEFT',1,0)
 b.text=S.Text(b,'body','text');b.text:SetPoint('LEFT',b.track,'RIGHT',10,0);b.text:SetText(label)
 b.text:SetPoint('RIGHT',b,'RIGHT',0,0)
 b.text:SetJustifyH('LEFT')
 if b.text.SetWordWrap then b.text:SetWordWrap(true) end
 function b:FitHeight(width)
  self.text:SetWidth(math.max(1,width-44))
  self:SetHeight(math.max(26,(self.text:GetStringHeight() or 16)+8))
 end
 function b:Update()
  local on=get() and true or false
  local prefix=on and 'CheckBox_Checked_' or 'CheckBox_'
  self.track:SetTexture(Kit.MEDIA..'WarRoomClassic\\'..prefix..(self:IsMouseOver() and 'Hover' or 'Normal'))
 end
 b:SetScript('OnEnter',function(self) self:Update() end)
 b:SetScript('OnLeave',function(self) self:Update() end)
 b:SetScript('OnClick',function(self) Kit.Safe(set,not get());self:Update() end)
 if hint then Kit.Tooltip(b,label,hint) end
 b:Update()
 return b
end

-- Status chip: small rounded-feeling pill (rectangle with tinted fill + dot).
function S.Chip(parent)
 local c=CreateFrame('Frame',nil,parent)
 c:SetHeight(22)
 c.bg=Kit.Fill(c,OWNER,'raised')
 c.dot=c:CreateTexture(nil,'ARTWORK');c.dot:SetSize(6,6);c.dot:SetPoint('LEFT',8,0)
 c.text=Kit.Text(c,OWNER,'narrow',13,'muted');c.text:SetPoint('LEFT',c.dot,'RIGHT',6,0)
 function c:Set(text,tone)
  self.text:SetText(text or '')
  Kit.Paint(self.dot,OWNER,tone or 'faint','fill')
  self:SetWidth(math.max(40,(self.text:GetStringWidth() or 40)+28))
 end
 return c
end

-- Parchment header strip keeps section hierarchy legible over iron panels.
function S.SectionHeader(parent,label,width)
 local h=CreateFrame('Frame',nil,parent);h:SetSize(width or 300,26)
 Kit.Fill(h,OWNER,'paper')
 Kit.Border(h,OWNER,'line',1,0.9)
 h.classicPaper=S.SliceAsset(h,'parchmentHeader',8,512,'BACKGROUND',2,nil,16)
 h.mark=Kit.Rule(h,OWNER,'primary',false,4);h.mark:SetPoint('TOPLEFT');h.mark:SetPoint('BOTTOMLEFT')
 registerSkinWidget(h,function() h.mark:SetShown(not (Themes.Get(active) and Themes.Get(active).assets)) end)
 h.text=Kit.Text(h,OWNER,'display',16,'paperText');h.text:SetPoint('LEFT',12,0);h.text:SetPoint('RIGHT',-8,0)
 h.text:SetText(label or '')
 function h:SetLabel(value) self.text:SetText(value or '') end
 return h
end

-- Card: surface panel with a parchment title and optional header action.
function S.Card(parent,title)
 local c=CreateFrame('Frame',nil,parent)
 Kit.Fill(c,OWNER,'surface');S.Art(c,'panel')
 local border=Kit.Border(c,OWNER,'lineSoft',1,0.9)
 S.FrameChrome(c,border,'panel')
 c.titleBar=CreateFrame('Frame',nil,c);c.titleBar:SetPoint('TOPLEFT',1,-1);c.titleBar:SetPoint('TOPRIGHT',-1,-1);c.titleBar:SetHeight(32)
 c.titleHeader=S.SectionHeader(c.titleBar,title or '',c.titleBar:GetWidth())
 c.titleHeader:SetAllPoints(c.titleBar)
 c.title=c.titleHeader.text
 c.body=CreateFrame('Frame',nil,c)
 c.body:SetPoint('TOPLEFT',14,-42);c.body:SetPoint('BOTTOMRIGHT',-14,12)
 function c:SetTitle(t) self.titleHeader:SetLabel(t) end
 function c:HeaderAction(label,fn,w)
  local b=S.Link(self.titleBar,label,fn);b:SetPoint('RIGHT',self.titleBar,'RIGHT',-10,0)
  Kit.Paint(b.text,OWNER,'paperText','text');Kit.Paint(b.u,OWNER,'paperText','fill')
  return b
 end
 return c
end

-- Text link button (ember text, underline on hover).
function S.Link(parent,label,fn)
 local b=CreateFrame('Button',nil,parent)
 b.text=Kit.Text(b,OWNER,'body',12,'accentText');b.text:SetPoint('RIGHT');b.text:SetText(label)
 b:SetSize((b.text:GetStringWidth() or 60)+14,20);b.autosize=true
 b.u=Kit.Rule(b,OWNER,'accentText',true,1);b.u:SetPoint('BOTTOMLEFT',b.text,'BOTTOMLEFT',0,-1);b.u:SetPoint('BOTTOMRIGHT',b.text,'BOTTOMRIGHT',0,-1);b.u:Hide()
 b:SetScript('OnEnter',function(self) self.u:Show() end)
 b:SetScript('OnLeave',function(self) self.u:Hide() end)
 b:SetScript('OnClick',function() if fn then Kit.Safe(fn) end end)
 function b:SetLabel(t) self.text:SetText(t);self:SetWidth((self.text:GetStringWidth() or 60)+14) end
 return b
end

-- Compact summary buttons keep the count and label visible at the smallest width.
function S.Stat(parent,label,icon)
 local t=CreateFrame('Button',nil,parent)
 S.Art(t,'panel','BACKGROUND')
 S.FrameChrome(t,nil,'stat')
 t.icon=S.ThemedTexture(t,icon,20,'ARTWORK');t.icon:SetPoint('TOPLEFT',10,-9)
 t.num=Kit.Text(t,OWNER,'body',19,'text');t.num:SetPoint('LEFT',t.icon,'RIGHT',5,0)
 t.label=S.Text(t,'small','muted');t.label:SetPoint('BOTTOMLEFT',10,9);t.label:SetText(label)
 Kit.Tooltip(t,label,function() return t.detail end)
 function t:Set(n,sub,tone)
  self.num:SetText(tostring(n or 0));self.detail=sub
  Kit.Paint(self.num,OWNER,tone=='danger' and 'danger' or 'text','text')
 end
 return t
end

-- Empty / waiting state: a short headline plus one sentence of guidance.
function S.Empty(parent,headline,body,width,art)
 local f=CreateFrame('Frame',nil,parent)
 f:SetSize(width or 360,60)
 local inset=art and 46 or 0
 if art then
  local mark=f:CreateTexture(nil,'ARTWORK');mark:SetSize(36,36);mark:SetPoint('TOPLEFT',2,-2)
  mark:SetTexture(Kit.MEDIA..'WarRoomClassic\\'..art)
 end
 f.h=S.Text(f,'body','muted');f.h:SetPoint('TOPLEFT',inset,0);f.h:SetText(headline)
 f.b=S.Para(f,width or 360,'faint',12);f.b:SetPoint('TOPLEFT',f.h,'BOTTOMLEFT',0,-4);f.b:SetText(body or '')
 function f:Set(h,b) self.h:SetText(h or '');self.b:SetText(b or '') end
 if parent.thumb then
  local function fit(_,w)
   if w>8 then f:SetWidth(w-8);f.b:SetWidth(math.max(1,w-8-inset)) end
  end
  parent:HookScript('OnSizeChanged',fit);fit(parent,parent:GetWidth())
 end
 return f
end

-- List text independently truncates in each column. Hover restores the full record.
local function listTooltip(row,heading,description)
 Kit.Tooltip(row,function(self)
  if self.item then return self.tooltipName or heading:GetText() end
 end,function(self)
  if not self.item then return end
  local parts={}
  for _,label in ipairs(description) do
   local text=label:GetText()
   if text and text~='' then parts[#parts+1]=text end
  end
  return table.concat(parts,'\n')
 end)
end

-- List row "card": used by most War Room lists. Two lines + right meta + tone bar.
function S.RowBuild(row)
 row.bg=Kit.Fill(row,OWNER,'surface')
 row.classicAlternate=S.AssetOverlay(row,'rowAlternate','BACKGROUND',1);row.classicAlternate:SetAllPoints(row)
 row.classicHover=S.AssetOverlay(row,'rowHover','BACKGROUND',2);row.classicHover:SetAllPoints(row)
 row.classicSelected=S.AssetOverlay(row,'rowSelected','BACKGROUND',3);row.classicSelected:SetAllPoints(row)
 row.bar=Kit.Rule(row,OWNER,'faint',false,3);row.bar:SetPoint('TOPLEFT');row.bar:SetPoint('BOTTOMLEFT')
 row.title=S.Text(row,'body','text');row.title:SetPoint('TOPLEFT',14,-8);row.title:SetPoint('RIGHT',row,'RIGHT',-120,0)
 row.sub=S.Text(row,'small','muted');row.sub:SetPoint('TOPLEFT',row.title,'BOTTOMLEFT',0,-4);row.sub:SetPoint('RIGHT',row,'RIGHT',-120,0)
 row.meta=S.Text(row,'small','faint');row.meta:SetPoint('TOPRIGHT',-12,-9);row.meta:SetJustifyH('RIGHT')
 row.meta2=S.Text(row,'small','faint');row.meta2:SetPoint('TOPRIGHT',row.meta,'BOTTOMRIGHT',0,-4);row.meta2:SetJustifyH('RIGHT')
 row.meta:SetWidth(102);row.meta2:SetWidth(102)
 local function fit(self)
  local w=self:GetWidth()
  if w<=0 then return end
  local meta=self.metaWidth or math.min(102,math.max(48,math.floor(w*0.30)))
  local left=self.iconWell and 48 or 14
  self.meta:SetWidth(meta);self.meta2:SetWidth(meta)
  if self.iconWell then
   self.title:ClearAllPoints();self.sub:ClearAllPoints()
   self.title:SetPoint('TOPLEFT',self,'TOPLEFT',left,-8)
   self.sub:SetPoint('TOPLEFT',self.title,'BOTTOMLEFT',0,-4)
   self.title:SetPoint('RIGHT',self,'RIGHT',-meta-18,0)
   self.sub:SetPoint('RIGHT',self,'RIGHT',-meta-18,0)
   return
  end
  self.title:SetPoint('LEFT',self,'LEFT',left,0);self.title:SetPoint('RIGHT',self,'RIGHT',-meta-18,0)
  self.sub:SetPoint('LEFT',self,'LEFT',left,0);self.sub:SetPoint('RIGHT',self,'RIGHT',-meta-18,0)
 end
 row:HookScript('OnSizeChanged',fit);fit(row)
 row.LayoutText=fit
 row.title:SetJustifyH('LEFT');row.sub:SetJustifyH('LEFT')
 function row:UpdateClassicStyle(index)
  self.classicAlternate:SetShown(not self.selected and not self.hovered and index and index%2==0)
  self.classicHover:SetShown(not self.selected and self.hovered)
  self.classicSelected:SetShown(self.selected)
 end
 row:SetScript('OnEnter',function(self) self.hovered=true;self:UpdateClassicStyle(self.index);if not self.selected then Kit.Paint(self.bg,OWNER,'hover','fill') end end)
 row:SetScript('OnLeave',function(self) self.hovered=nil;self:UpdateClassicStyle(self.index);Kit.Paint(self.bg,OWNER,self.selected and 'accentSoft' or 'surface','fill') end)
 function row:Select(on) self.selected=on;self:UpdateClassicStyle(self.index);Kit.Paint(self.bg,OWNER,on and 'accentSoft' or 'surface','fill') end
 listTooltip(row,row.title,{row.sub,row.meta,row.meta2})
 function row:Tone(role) Kit.Paint(self.bar,OWNER,role or 'faint','fill') end
end

-- Optional native-game icon for rows that benefit from a quick visual cue.
-- The shared builder creates it lazily so ordinary lists keep their frame cost.
function S.RowIcon(row,icon)
 if not row.iconWell then
  row.iconWell=CreateFrame('Frame',nil,row);row.iconWell:SetSize(30,30);row.iconWell:SetPoint('LEFT',8,0)
  Kit.Fill(row.iconWell,OWNER,'raised');Kit.Border(row.iconWell,OWNER,'lineSoft',1,0.8)
  row.icon=row.iconWell:CreateTexture(nil,'ARTWORK');row.icon:SetPoint('TOPLEFT',3,-3);row.icon:SetPoint('BOTTOMRIGHT',-3,3)
 end
 row.icon:SetTexture(icon)
 row.iconWell:Show()
 if row.LayoutText then row:LayoutText() end
end

-- Compact leaderboard row: rank, name, value, optional bar.
function S.RankBuild(row)
 row.bg=Kit.Fill(row,OWNER,'surface')
 row.classicAlternate=S.AssetOverlay(row,'rowAlternate','BACKGROUND',1);row.classicAlternate:SetAllPoints(row)
 row.classicHover=S.AssetOverlay(row,'rowHover','BACKGROUND',2);row.classicHover:SetAllPoints(row)
 row.rankWreath=S.ThemedTexture(row,'rankGold',24,'ARTWORK',2);row.rankWreath:SetPoint('LEFT',row,'LEFT',8,0);row.rankWreath:Hide()
 row.rank=S.Text(row,'body','faint');row.rank:SetPoint('LEFT',12,0);row.rank:SetWidth(32)
 row.warlordInsignia=S.AssetOverlay(row,'warlord01','ARTWORK',6)
 row.name=S.Text(row,'body','text');row.name:SetJustifyH('LEFT')
 row.sub=S.Text(row,'small','muted');row.sub:SetJustifyH('LEFT')
 row.val=Kit.Text(row,OWNER,'narrow',16,'text');row.val:SetPoint('RIGHT',-12,0);row.val:SetJustifyH('RIGHT');row.val:SetWidth(68)
 row.barBg=row:CreateTexture(nil,'ARTWORK');row.barBg:SetPoint('RIGHT',row.val,'LEFT',-9,0);row.barBg:SetHeight(4)
 Kit.Paint(row.barBg,OWNER,'raised','fill')
 row.bar=row:CreateTexture(nil,'OVERLAY');row.bar:SetPoint('LEFT',row.barBg,'LEFT');row.bar:SetHeight(4)
 Kit.Paint(row.bar,OWNER,'accent','fill')
 function row:FitColumns()
  local w=self:GetWidth()
  if w<=0 then w=270 end
  local barWidth=self.isBoard and 0 or math.min(90,math.max(0,w-285))
  local valueWidth=math.min(68,math.max(42,math.floor(w*0.24)))
  self.val:SetWidth(valueWidth)
  local textWidth=math.max(24,w-(self.isBoard and valueWidth+36 or valueWidth+71+barWidth))
  self.name:ClearAllPoints();self.sub:ClearAllPoints()
  if self.isBoard then
   self.name:SetPoint('TOPLEFT',self,'TOPLEFT',12,-5)
   self.sub:SetPoint('TOPLEFT',self.name,'BOTTOMLEFT',0,-2)
  else
   self.name:SetPoint('TOPLEFT',self,'TOPLEFT',52,-5)
   self.sub:SetPoint('TOPLEFT',self.name,'BOTTOMLEFT',0,-2)
  end
  self.name:SetWidth(textWidth);self.sub:SetWidth(textWidth)
  self.barBg:SetShown(barWidth>0);self.bar:SetShown(barWidth>0)
  self.barBg:SetWidth(math.max(1,barWidth));self.bar:SetWidth(math.max(1,barWidth*(self.ratio or 0)))
 end
 function row:SetScoreLayout(isBoard,ratio,subtitle)
  self.isBoard=isBoard;self.ratio=Kit.Clamp(ratio or 0,0,1)
  self.rank:SetShown(not isBoard);self.sub:SetShown(isBoard or (subtitle and subtitle~=''))
  if isBoard then self.sub:SetText(self.sub:GetText() or '') else self.sub:SetText(subtitle or '') end
  self:FitColumns()
 end
 function row:SetRankWreath(rank)
  local key=rank==1 and 'rankGold' or rank==2 and 'rankSilver' or rank==3 and 'rankBronze'
  if key and S.AssetPath(key) then
   self.rankWreath:SetTexture(S.AssetPath(key));self.rankWreath:Show()
  else self.rankWreath:Hide() end
 end
 function row:SetWarlordInsignia(rank)
  local key=rank and rank>=1 and rank<=5 and ('warlord%02d'):format(rank)
  if key and S.AssetPath(key) then
   self.warlordInsignia:SetAsset(key);self.warlordInsignia:SetAspectHeight(27);self.warlordInsignia:ClearAllPoints()
   self.warlordInsignia:SetPoint('LEFT',self,'LEFT',4,0);self.warlordInsignia:SetShown(true)
   self.rank:ClearAllPoints();self.rank:SetPoint('LEFT',self,'LEFT',31,0);self.rank:SetWidth(22)
  else
   self.warlordInsignia:SetShown(false)
   self.rank:ClearAllPoints();self.rank:SetPoint('LEFT',self,'LEFT',12,0);self.rank:SetWidth(32)
  end
 end
 row:HookScript('OnSizeChanged',function(self) self:FitColumns() end)
 function row:UpdateClassicStyle(index)
  self.classicAlternate:SetShown(not self.hovered and index and index%2==0)
  self.classicHover:SetShown(self.hovered)
 end
 row:SetScript('OnEnter',function(self) self.hovered=true;self:UpdateClassicStyle(self.index);Kit.Paint(self.bg,OWNER,'hover','fill') end)
 row:SetScript('OnLeave',function(self) self.hovered=nil;self:UpdateClassicStyle(self.index);Kit.Paint(self.bg,OWNER,'surface','fill') end)
 listTooltip(row,row.name,{row.sub,row.val})
end

function S.Confirm(title,body,label,fn) Kit.Confirm(OWNER,title,body,label,fn) end
S.theme.MakeButton=function(parent,label,variant,fn,w) return S.Button(parent,label,variant,fn,w,30) end
