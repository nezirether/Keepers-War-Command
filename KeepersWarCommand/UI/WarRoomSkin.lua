-- The War Room visual language (public KWC). All public skins share one structure.
-- Components here are War Room only. The officer Command Table has its own.
local K=KWC
local Kit=K.Kit
local S={};K.WarRoomSkin=S
local OWNER='warroom'
S.OWNER=OWNER
local Themes=K.PublicThemes
S.skins=Themes.entries
local artwork=setmetatable({},{__mode='k'})
local markers=setmetatable({},{__mode='k'})
S.theme={colors=Themes.Get(Themes.default).colors,headingFace='body'}
Kit.RegisterTheme(OWNER,S.theme)
local active,preview=Themes.default,nil

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
 if not art and slot=='crest' and not artEntry(skin,'sigil') then art={'Emblem',1,1} end
 if not art then texture:SetAlpha(0);return end
 local ok,loaded=pcall(texture.SetTexture,texture,Kit.MEDIA..art[1])
 if (not ok or loaded==false) and slot=='crest' then
  ok,loaded=pcall(texture.SetTexture,texture,Kit.MEDIA..'Emblem')
 end
 local tint=art[4] and skin.colors.accent or {1,1,1}
 texture:SetVertexColor(tint[1],tint[2],tint[3])
 crop(texture,art[3],width,height,art[5],art[6])
 texture:SetAlpha(ok and loaded~=false and art[2] or 0)
end

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
 if K.WarRoom2 then K.WarRoom2.Refresh(true) end
end

function S.Current() return Themes.Saved() end
function S.Active() return active end
function S.IsPreviewing() return preview~=nil end
function S.Restore() preview=nil;activate(Themes.Saved()) end
function S.Preview(id)
 id=Themes.Resolve(id)
 if not id then return false end
 preview=id;activate(id);return true
end
function S.CancelPreview() S.Restore() end
function S.Apply(id)
 id=Themes.Resolve(id) or Themes.default
 if not Themes.Save(id) then return false end
 preview=nil;activate(id);return true
end
function S.Reset() return S.Apply(Themes.default) end
function S.Color(role) return S.theme.colors[role] end
function S.Code(role) return Kit.Code(S.theme.colors[role]) end

-- Typography scale (pixel sizes). Body copy is 13-14 for comfortable reading.
S.type={display=24,title=18,section=15,body=13,small=12,kicker=11}
function S.Text(parent,style,role)
 if style=='display' then return Kit.Text(parent,OWNER,'display',S.type.display,role or 'text') end
 if style=='title' then return Kit.Text(parent,OWNER,'body',S.type.title,role or 'text') end
 if style=='section' then return Kit.Text(parent,OWNER,'body',S.type.section,role or 'text') end
 if style=='kicker' then return Kit.Text(parent,OWNER,'narrow',S.type.kicker+1,role or 'faint') end
 if style=='small' then return Kit.Text(parent,OWNER,'body',S.type.small,role or 'muted') end
 if style=='num' then return Kit.Text(parent,OWNER,'narrow',26,role or 'text') end
 return Kit.Text(parent,OWNER,'body',S.type.body,role or 'text')
end
function S.Para(parent,width,role,size) return Kit.Para(parent,OWNER,'body',size or S.type.body,role or 'muted',width) end
-- Kicker labels: uppercase narrow type for section labels.
function S.Kick(fs,text) fs:SetText((text or ''):upper()) end

-- Buttons: filled slab, sentence case, ember underline on hover/primary.
-- variants: primary | secondary | ghost | danger
function S.Button(parent,label,variant,onClick,width,height)
 variant=variant or 'secondary'
 local b=CreateFrame('Button',nil,parent)
 b:SetSize(width or 120,height or 30)
 local fillRole=variant=='primary' and 'accent' or variant=='danger' and 'dangerSoft' or variant=='ghost' and 'base' or 'raised'
 b.bg=Kit.Fill(b,OWNER,fillRole,'BACKGROUND',variant=='ghost' and 0 or nil)
 b.edge=Kit.Rule(b,OWNER,variant=='danger' and 'danger' or 'accent',true,Themes.Get(active).marker or 2)
 markers[b.edge]=true
 b.edge:SetPoint('BOTTOMLEFT');b.edge:SetPoint('BOTTOMRIGHT')
 b.edge:SetShown(false)
 if variant=='secondary' then S.Art(b,'control','BORDER') end
 if variant=='secondary' or variant=='danger' then Kit.Border(b,OWNER,variant=='danger' and 'danger' or 'line',1,variant=='danger' and 0.7 or 1) end
 b.text=Kit.Text(b,OWNER,'body',13,variant=='primary' and 'onAccent' or variant=='danger' and 'danger' or 'text')
 b.text:SetPoint('LEFT',b,'LEFT',6,0);b.text:SetPoint('RIGHT',b,'RIGHT',-6,0)
 b.text:SetJustifyH('CENTER');b.text:SetText(label)
 b.variant=variant
 local function setButtonFill(self,hover)
  local role=self.selected and 'accentSoft' or fillRole
  if hover and self.enabled~=false and variant~='primary' then role='hover' end
  Kit.Paint(self.bg,OWNER,role,'fill',variant=='ghost' and not hover and not self.selected and 0 or nil)
 end
 b:SetScript('OnEnter',function(self)
  if self.enabled~=false then self.edge:Show();setButtonFill(self,true) end
 end)
 b:SetScript('OnLeave',function(self) self.edge:SetShown(self.selected==true);setButtonFill(self,false) end)
 b:SetScript('OnMouseDown',function(self)
  if self.enabled~=false and variant~='primary' and variant~='danger' then Kit.Paint(self.bg,OWNER,'pressed','fill') end
 end)
 b:SetScript('OnMouseUp',function(self) setButtonFill(self,self:IsMouseOver()) end)
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
  self:SetAlpha(enabled and 1 or 0.42)
 end
 Kit.Tooltip(b,function(self) return self.enabled==false and self.reason and 'Unavailable' or self.tip end,function(self) return self.enabled==false and self.reason or self.tipBody end)
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
 f.line=Kit.Rule(f.well,OWNER,'line',true,1);f.line:SetPoint('BOTTOMLEFT');f.line:SetPoint('BOTTOMRIGHT')
 f.edit=Kit.EditBox(f.well,OWNER,'body',13,maxLetters or 80)
 f.edit:SetAllPoints(f.well)
 f.ph=Kit.Text(f.well,OWNER,'body',13,'faint');f.ph:SetPoint('LEFT',8,0);f.ph:SetText(placeholder or '')
 f.err=Kit.Text(f,OWNER,'narrow',12,'danger');f.err:SetPoint('TOPLEFT',f.well,'BOTTOMLEFT',0,-2)
 local function sync() f.ph:SetShown(f.edit:GetText()=='' and not f.edit:HasFocus()) end
 f.edit:SetScript('OnTextChanged',function() sync();f.err:SetText('') end)
 f.edit:SetScript('OnEditFocusGained',function() Kit.Paint(f.line,OWNER,'accent','fill');sync() end)
 f.edit:SetScript('OnEditFocusLost',function() Kit.Paint(f.line,OWNER,'line','fill');sync() end)
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
  s.bg=Kit.Fill(s,OWNER,'raised');S.Art(s,'tab','BORDER')
  s.mark=Kit.Rule(s,OWNER,'accent',true,Themes.Get(active).marker or 2);markers[s.mark]=true;s.mark:SetPoint('BOTTOMLEFT');s.mark:SetPoint('BOTTOMRIGHT')
  s.text=Kit.Text(s,OWNER,'body',12,'muted');s.text:SetPoint('LEFT',s,'LEFT',5,0);s.text:SetPoint('RIGHT',s,'RIGHT',-5,0);s.text:SetJustifyH('CENTER');s.text:SetText(label)
  s.value=value
  s:SetScript('OnClick',function() Kit.Safe(set,value);f:Update() end)
  s:SetScript('OnEnter',function(self) if get()~=self.value then Kit.Paint(self.bg,OWNER,'hover','fill') end end)
  s:SetScript('OnLeave',function(self) f:Update() end)
  f.segs[i]=s
 end
 f:SetWidth(x)
 function f:Update()
  local cur=get()
  for _,s in ipairs(self.segs) do
   local on=s.value==cur
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
 b.track=CreateFrame('Frame',nil,b);b.track:SetSize(34,16);b.track:SetPoint('LEFT',0,0)
 b.trackBg=Kit.Fill(b.track,OWNER,'raised')
 Kit.Border(b.track,OWNER,'line')
 b.knob=b.track:CreateTexture(nil,'ARTWORK');b.knob:SetSize(12,12)
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
  self.knob:ClearAllPoints();self.knob:SetPoint(on and 'RIGHT' or 'LEFT',self.track,on and 'RIGHT' or 'LEFT',on and -2 or 2,0)
  Kit.Paint(self.knob,OWNER,on and 'base' or 'muted','fill')
  Kit.Paint(self.trackBg,OWNER,on and 'accent' or 'raised','fill')
 end
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

-- Card: surface panel with a kicker title and optional header action.
function S.Card(parent,title)
 local c=CreateFrame('Frame',nil,parent)
 Kit.Fill(c,OWNER,'surface');S.Art(c,'panel')
 Kit.Border(c,OWNER,'lineSoft')
 local seam=Kit.Rule(c,OWNER,'line',true,1);seam:SetPoint('TOPLEFT',1,-1);seam:SetPoint('TOPRIGHT',-1,-1)
 local corner=CreateFrame('Frame',nil,c)
 corner:SetSize(19,19);corner:SetPoint('TOPLEFT',c,'TOPLEFT',2,-2)
 corner:EnableMouse(false)
 S.Art(corner,'ornament')
 c.title=S.Text(c,'kicker','accentText');c.title:SetPoint('TOPLEFT',26,-12)
 S.Kick(c.title,title or '')
 c.body=CreateFrame('Frame',nil,c)
 c.body:SetPoint('TOPLEFT',14,-34);c.body:SetPoint('BOTTOMRIGHT',-14,12)
 function c:SetTitle(t) S.Kick(self.title,t) end
 function c:HeaderAction(label,fn,w)
  local b=S.Link(self,label,fn);b:SetPoint('TOPRIGHT',-12,-8);return b
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

-- Stat tile: big number, label, small context line.
function S.Stat(parent,label)
 local t=CreateFrame('Button',nil,parent)
 Kit.Fill(t,OWNER,'surface')
 t.edge=Kit.Rule(t,OWNER,'accent',false,3);t.edge:SetPoint('TOPLEFT');t.edge:SetPoint('BOTTOMLEFT')
 t.num=S.Text(t,'num','text');t.num:SetPoint('TOPLEFT',16,-12)
 t.label=S.Text(t,'kicker','muted');t.label:SetPoint('TOPLEFT',t.num,'BOTTOMLEFT',0,-4);S.Kick(t.label,label)
 t.sub=S.Text(t,'small','faint');t.sub:SetPoint('BOTTOMLEFT',16,10);t.sub:SetPoint('RIGHT',-10,0)
 t:SetScript('OnEnter',function(self) Kit.Paint(self.edge,OWNER,'accentText','fill') end)
 t:SetScript('OnLeave',function(self) Kit.Paint(self.edge,OWNER,self.tone or 'accent','fill') end)
 function t:Set(n,sub,tone)
  self.num:SetText(n==nil and '-' or tostring(n));self.sub:SetText(sub or '')
  self.tone=tone or 'accent';Kit.Paint(self.edge,OWNER,self.tone,'fill')
 end
 return t
end

-- Empty / waiting state: a short headline plus one sentence of guidance.
function S.Empty(parent,headline,body,width)
 local f=CreateFrame('Frame',nil,parent)
 f:SetSize(width or 360,60)
 f.h=S.Text(f,'body','muted');f.h:SetPoint('TOPLEFT',0,0);f.h:SetText(headline)
 f.b=S.Para(f,width or 360,'faint',12);f.b:SetPoint('TOPLEFT',f.h,'BOTTOMLEFT',0,-4);f.b:SetText(body or '')
 function f:Set(h,b) self.h:SetText(h or '');self.b:SetText(b or '') end
 if parent.thumb then
  local function fit(_,w)
   if w>8 then f:SetWidth(w-8);f.b:SetWidth(w-8) end
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
 row.bar=Kit.Rule(row,OWNER,'faint',false,3);row.bar:SetPoint('TOPLEFT');row.bar:SetPoint('BOTTOMLEFT')
 row.title=S.Text(row,'body','text');row.title:SetPoint('TOPLEFT',14,-8);row.title:SetPoint('RIGHT',row,'RIGHT',-120,0)
 row.sub=S.Text(row,'small','muted');row.sub:SetPoint('TOPLEFT',row.title,'BOTTOMLEFT',0,-4);row.sub:SetPoint('RIGHT',row,'RIGHT',-120,0)
 row.meta=S.Text(row,'small','faint');row.meta:SetPoint('TOPRIGHT',-12,-9);row.meta:SetJustifyH('RIGHT')
 row.meta2=S.Text(row,'small','faint');row.meta2:SetPoint('TOPRIGHT',row.meta,'BOTTOMRIGHT',0,-4);row.meta2:SetJustifyH('RIGHT')
 row.meta:SetWidth(102);row.meta2:SetWidth(102)
 row.title:SetJustifyH('LEFT');row.sub:SetJustifyH('LEFT')
 row:SetScript('OnEnter',function(self) if not self.selected then Kit.Paint(self.bg,OWNER,'hover','fill') end end)
 row:SetScript('OnLeave',function(self) Kit.Paint(self.bg,OWNER,self.selected and 'accentSoft' or 'surface','fill') end)
 function row:Select(on) self.selected=on;Kit.Paint(self.bg,OWNER,on and 'accentSoft' or 'surface','fill') end
 listTooltip(row,row.title,{row.sub,row.meta,row.meta2})
 function row:Tone(role) Kit.Paint(self.bar,OWNER,role or 'faint','fill') end
end

-- Compact leaderboard row: rank, name, value, optional bar.
function S.RankBuild(row)
 row.bg=Kit.Fill(row,OWNER,'surface')
 row.rank=S.Text(row,'body','faint');row.rank:SetPoint('LEFT',12,0);row.rank:SetWidth(32)
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
  local textWidth=math.max(24,w-(self.isBoard and 104 or 139+barWidth))
  self.name:ClearAllPoints();self.sub:ClearAllPoints()
  if self.isBoard then
   self.name:SetPoint('TOPLEFT',self,'TOPLEFT',12,-5)
   self.sub:SetPoint('TOPLEFT',self.name,'BOTTOMLEFT',0,-2)
  else
   self.name:SetPoint('LEFT',self.rank,'RIGHT',4,0)
  end
  self.name:SetWidth(textWidth);self.sub:SetWidth(textWidth)
  self.barBg:SetShown(barWidth>0);self.bar:SetShown(barWidth>0)
  self.barBg:SetWidth(math.max(1,barWidth));self.bar:SetWidth(math.max(1,barWidth*(self.ratio or 0)))
 end
 function row:SetScoreLayout(isBoard,ratio)
  self.isBoard=isBoard;self.ratio=Kit.Clamp(ratio or 0,0,1)
  self.rank:SetShown(not isBoard);self.sub:SetShown(isBoard)
  if not isBoard then self.sub:SetText('') end
  self:FitColumns()
 end
 row:HookScript('OnSizeChanged',function(self) self:FitColumns() end)
 row:SetScript('OnEnter',function(self) Kit.Paint(self.bg,OWNER,'hover','fill') end)
 row:SetScript('OnLeave',function(self) Kit.Paint(self.bg,OWNER,'surface','fill') end)
 listTooltip(row,row.name,{row.sub,row.val})
end

function S.Confirm(title,body,label,fn) Kit.Confirm(OWNER,title,body,label,fn) end
S.theme.MakeButton=function(parent,label,variant,fn,w) return S.Button(parent,label,variant,fn,w,30) end
