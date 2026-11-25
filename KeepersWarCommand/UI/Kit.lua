-- KWC 2.0 UI Kit: non-visual primitives shared by the public War Room and the
-- officer Command Table. Visual identity (colors, buttons, rows, chrome) lives in
-- each interface's own skin module; this file only provides mechanics:
-- fonts with fallback, solid fills, 1px rules, text measurement, scroll lists,
-- edit boxes, safe callbacks and a skin-aware paint registry.
-- No legacy KWC 1.x frame, texture or layout is referenced here.
local K=KWC
local Kit={};K.Kit=Kit

Kit.MEDIA='Interface\\AddOns\\KeepersWarCommand\\Media\\'
Kit.FONTS={
 body='Fonts\\FRIZQT__.TTF',
 narrow='Fonts\\ARIALN.TTF',
 display='Fonts\\MORPHEUS.TTF',
 block='Fonts\\SKURRI.TTF',
}
local FALLBACK=STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF'

-- Applies a font; falls back to the client's standard font if a file is missing.
function Kit.SetFont(fs,face,size,flags)
 local path=Kit.FONTS[face] or face or FALLBACK
 local ok,applied=pcall(fs.SetFont,fs,path,size,flags or '')
 if not ok or applied==false or not fs:GetFont() then pcall(fs.SetFont,fs,FALLBACK,size,flags or '') end
end

-- Color helpers. Colors are {r,g,b[,a]} in 0-1.
function Kit.Hex(hex,a)
 hex=hex:gsub('#','')
 return {tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255,a or 1}
end
function Kit.Code(c) return string.format('|cff%02x%02x%02x',math.floor(c[1]*255+0.5),math.floor(c[2]*255+0.5),math.floor(c[3]*255+0.5)) end

-- Paint registry: every themed texture/fontstring remembers its role so a skin
-- switch recolors existing frames without rebuilding them. Weak keys let
-- discarded widgets be collected.
local painted=setmetatable({},{__mode='k'})
local themes={}
function Kit.RegisterTheme(owner,theme) themes[owner]=theme end
function Kit.Theme(owner) return themes[owner] end
local function apply(obj,spec)
 local theme=themes[spec.owner];if not theme then return end
 local c=theme.colors[spec.role] or theme.colors.text or {1,1,1,1}
 local a=spec.alpha or c[4] or 1
 if spec.face then
  local face=theme.fonts and theme.fonts[spec.face] or spec.face
  if face~=spec.appliedFace then
   Kit.SetFont(obj,face,spec.size,spec.flags)
   spec.appliedFace=face
  end
 end
 if spec.kind=='fill' then obj:SetColorTexture(c[1],c[2],c[3],a)
 elseif spec.kind=='text' then obj:SetTextColor(c[1],c[2],c[3],a)
 elseif spec.kind=='vertex' then obj:SetVertexColor(c[1],c[2],c[3],a) end
end
function Kit.Paint(obj,owner,role,kind,alpha)
 local spec=painted[obj] or {}
 spec.owner,spec.role,spec.kind,spec.alpha=owner,role,kind,alpha
 painted[obj]=spec;apply(obj,spec);return obj
end
function Kit.Repaint(owner)
 for obj,spec in pairs(painted) do if spec.owner==owner then apply(obj,spec) end end
end

-- Solid fill covering a frame (or a region when points are given later).
function Kit.Fill(frame,owner,role,layer,alpha,sub)
 local t=frame:CreateTexture(nil,layer or 'BACKGROUND',nil,sub or 0)
 t:SetAllPoints(frame)
 return Kit.Paint(t,owner,role,'fill',alpha)
end
-- 1px border made of four textures (no backdrop templates, no legacy edge art).
function Kit.Border(frame,owner,role,thickness,alpha)
 local px=thickness or 1
 local edges={}
 for i,spec in ipairs({{'TOPLEFT','TOPRIGHT',true},{'BOTTOMLEFT','BOTTOMRIGHT',true},{'TOPLEFT','BOTTOMLEFT',false},{'TOPRIGHT','BOTTOMRIGHT',false}}) do
  local t=frame:CreateTexture(nil,'BORDER')
  t:SetPoint(spec[1]);t:SetPoint(spec[2])
  if spec[3] then t:SetHeight(px) else t:SetWidth(px) end
  Kit.Paint(t,owner,role,'fill',alpha)
  edges[i]=t
 end
 return edges
end
function Kit.Rule(parent,owner,role,horizontal,thickness,alpha)
 local t=parent:CreateTexture(nil,'ARTWORK')
 if horizontal then t:SetHeight(thickness or 1) else t:SetWidth(thickness or 1) end
 return Kit.Paint(t,owner,role,'fill',alpha)
end
function Kit.Text(parent,owner,face,size,role,flags,layer)
 local fs=parent:CreateFontString(nil,layer or 'OVERLAY')
 Kit.SetFont(fs,face,size,flags)
 fs:SetJustifyH('LEFT');fs:SetJustifyV('MIDDLE')
 if fs.SetWordWrap then fs:SetWordWrap(false) end
 Kit.Paint(fs,owner,role or 'text','text')
 if owner=='warroom' then
  local spec=painted[fs]
  spec.face,spec.size,spec.flags=face,size,flags
  apply(fs,spec)
 end
 return fs
end
-- Wrapped paragraph with a fixed width.
function Kit.Para(parent,owner,face,size,role,width)
 local fs=Kit.Text(parent,owner,face,size,role)
 fs:SetWidth(width);fs:SetJustifyV('TOP')
 if fs.SetWordWrap then fs:SetWordWrap(true) end
 if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
 return fs
end

-- Safe callback: an error in a page action is reported once, never thrown into
-- the client's error frame repeatedly, and never interrupts sync/event code.
function Kit.Safe(fn,...)
 local ok,err=pcall(fn,...)
 if not ok then
  K.Say('Interface error: '..tostring(err):sub(1,160))
  if K.Log then K.Log('UI',tostring(err)) end
 end
 return ok,err
end

local tooltipSpecs=setmetatable({},{__mode='k'})
function Kit.Tooltip(frame,title,body)
 local spec=tooltipSpecs[frame]
 if spec then spec.title,spec.body=title,body;return frame end
 spec={title=title,body=body};tooltipSpecs[frame]=spec
 frame:HookScript('OnEnter',function(self)
  if not GameTooltip then return end
  local current=tooltipSpecs[self];if not current then return end
  local t=type(current.title)=='function' and current.title(self) or current.title
  if not t or t=='' then return end
  GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
  GameTooltip:SetText(t,1,1,1,1,true)
  local b=type(current.body)=='function' and current.body(self) or current.body
  if b and b~='' then GameTooltip:AddLine(b,0.85,0.82,0.76,true) end
  GameTooltip:Show()
 end)
 frame:HookScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
 return frame
end

-- Edit box mechanics: no template art. Callers draw their own field chrome.
function Kit.EditBox(parent,owner,face,size,maxLetters,role)
 local e=CreateFrame('EditBox',nil,parent)
 e:SetAutoFocus(false)
 local ok=pcall(Kit.SetFont,e,face,size)
 if not ok and e.SetFontObject then e:SetFontObject(ChatFontNormal) end
 e:SetMaxLetters(maxLetters or 120)
 e:SetTextInsets(8,8,0,0)
 Kit.Paint(e,owner,role or 'text','text')
 e:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
 e:SetScript('OnEditFocusLost',function(self) if self.HighlightText then self:HighlightText(0,0) end end)
 return e
end

-- Clamp helper for numeric settings.
function Kit.Clamp(v,lo,hi) v=tonumber(v) or lo;if v<lo then return lo elseif v>hi then return hi end;return v end

-- Relative age text ("4m", "2h", "3d").
function Kit.Age(epoch)
 if type(epoch)~='number' or epoch<=0 then return '' end
 local s=math.max(0,time()-epoch)
 if s<60 then return 'now' elseif s<3600 then return math.floor(s/60)..'m'
 elseif s<86400 then return math.floor(s/3600)..'h' else return math.floor(s/86400)..'d' end
end
-- Parses K.Now() stamps ('%Y-%m-%d %H:%M') to epoch for age display.
function Kit.StampEpoch(at)
 if K.DangerZones and K.DangerZones.ParseStamp then return K.DangerZones.ParseStamp(at) end
end

-- Scroll list with row pooling. Visual rows are built by the caller:
--   list=Kit.List(parent,rowHeight,gap,buildRow(rowFrame),fillRow(rowFrame,data,index))
-- list:SetData(array); list:SetEmpty(fontString or fn) shows when empty.
-- The existing thumb keeps its range, hit target and paint contract. The
-- square thumb engraving stays centered as the scroll extent changes.
local function scrollbarArt(track,button)
 local media=Kit.MEDIA..'WarRoomClassic\\'
 local rail=track:CreateTexture(nil,'BORDER');rail:SetAllPoints(track);rail:SetTexture(media..'ScrollTrack_Normal')
 local grip=button:CreateTexture(nil,'OVERLAY');grip:SetSize(12,12);grip:SetPoint('CENTER')
 grip:SetTexture(media..'ScrollThumb_Normal')
 button:HookScript('OnEnter',function() grip:SetTexture(media..'ScrollThumb_Hover') end)
 button:HookScript('OnLeave',function() grip:SetTexture(media..'ScrollThumb_Normal') end)
end

-- Mouse wheel scrolls; a slim thumb is drawn by the caller through list.thumb.
function Kit.List(parent,rowHeight,gap,build,fill)
 local list=CreateFrame('Frame',nil,parent)
 list.rows={};list.data={};list.offset=0;list.rowHeight=rowHeight;list.gap=gap or 0
 list:EnableMouseWheel(true)
 local track=CreateFrame('Frame',nil,list)
 track:SetPoint('TOPRIGHT',-1,0);track:SetPoint('BOTTOMRIGHT',-1,0);track:SetWidth(10)
 track:EnableMouse(true);list.track=track
 local owner=K.WarRoomSkin and K.WarRoomSkin.OWNER or 'warroom'
 Kit.Fill(track,owner,'base','BACKGROUND',0.35)
 -- Keep thumb as a Texture: page builders theme list.thumb with Kit.Paint(),
 -- whose fill operation uses Texture:SetColorTexture. The hit button is a
 -- separate, transparent interaction layer so it cannot break page builds.
 local thumb=track:CreateTexture(nil,'OVERLAY')
 thumb:SetWidth(8);Kit.Paint(thumb,owner,'line','fill',0.9);list.thumb=thumb
 local thumbDrag=CreateFrame('Button',nil,track)
 thumbDrag:SetWidth(14);thumbDrag:EnableMouse(true);list.thumbDrag=thumbDrag
 scrollbarArt(track,thumbDrag)
 local function visible()
  local h=list:GetHeight() or 0
  return math.max(0,math.floor((h+list.gap)/(rowHeight+list.gap)))
 end
 function list:Refresh()
  local n=math.min(#self.data,visible())
  local maxOffset=math.max(0,#self.data-n)
  if self.offset>maxOffset then self.offset=maxOffset end
  for i=1,n do
   local row=self.rows[i]
   if not row then
    row=CreateFrame('Button',nil,self)
    row:SetHeight(rowHeight)
    build(row)
    self.rows[i]=row
   end
   row:ClearAllPoints()
   row:SetPoint('TOPLEFT',self,'TOPLEFT',0,-(i-1)*(rowHeight+self.gap))
   row:SetPoint('RIGHT',self,'RIGHT',-10,0)
   local index=self.offset+i
   local item=self.data[index]
   if item then
    row.item=item;row.index=index;Kit.Safe(fill,row,item,index)
    if row.UpdateClassicStyle then row:UpdateClassicStyle(index) end
    row:Show()
   else row.item=nil;row:Hide() end
  end
  for i=n+1,#self.rows do self.rows[i]:Hide() end
  if self.header then self.header:SetRange(self.offset,n,#self.data) end
  if self.empty then self.empty:SetShown(#self.data==0) end
  if n>0 and #self.data>n then
   local th=self:GetHeight()
   local size=math.min(th,math.max(28,th*n/#self.data))
   thumb:SetHeight(size)
   thumb:ClearAllPoints()
   thumb:SetPoint('TOP',track,'TOP',0,-(th-size)*(self.offset/maxOffset))
   thumbDrag:ClearAllPoints();thumbDrag:SetPoint('TOP',thumb,'TOP',0,0);thumbDrag:SetPoint('BOTTOM',thumb,'BOTTOM',0,0);thumbDrag:SetPoint('LEFT',track,'LEFT',-2,0);thumbDrag:SetPoint('RIGHT',track,'RIGHT',2,0)
   track:Show()
   thumb:Show();thumbDrag:Show()
  else track:Hide();thumb:Hide();thumbDrag:Hide() end
 end
 function list:SetData(data) self.data=data or {};self:Refresh() end
 function list:ScrollTo(index) self.offset=math.max(0,(index or 1)-1);self:Refresh() end
 function list:Page(delta)
  self:ScrollTo(self.offset+1+delta*math.max(1,visible()-1))
 end
 track:EnableMouse(true)
 track:SetScript('OnMouseDown',function(self)
  local _,y=GetCursorPosition()
  local scale=self:GetEffectiveScale()
  if not y or not scale or scale<=0 then return end
  local top=self:GetTop()
  local height=self:GetHeight()
  if not top or not height or height<=0 then return end
  local fraction=Kit.Clamp((top-y/scale)/height,0,1)
  list:ScrollTo(1+math.floor(fraction*math.max(0,#list.data-visible())+0.5))
 end)
 list:SetScript('OnMouseWheel',function(self,delta) self.offset=math.max(0,self.offset-delta*3);self:Refresh() end)
 list:SetScript('OnSizeChanged',function(self) self:Refresh() end)
 local function setFromCursor(y)
  local top,height=track:GetTop(),track:GetHeight();local scale=track:GetEffectiveScale()
  if not y or not top or not height or height<=0 or not scale or scale<=0 then return end
  local thumbHeight=thumb:GetHeight() or 0;local travel=math.max(0,height-thumbHeight)
  local fraction=travel>0 and Kit.Clamp((top-y/scale-thumbHeight/2)/travel,0,1) or 0
  list:ScrollTo(1+math.floor(fraction*math.max(0,#list.data-visible())+0.5))
 end
 track:SetScript('OnMouseDown',function(_,button)if button=='LeftButton' then local _,y=GetCursorPosition();setFromCursor(y)end end)
 thumbDrag:SetScript('OnMouseDown',function(self,button)if button=='LeftButton' then self.dragging=true;self.startY=select(2,GetCursorPosition())end end)
 thumbDrag:SetScript('OnMouseUp',function(self)self.dragging=nil end)
 thumbDrag:SetScript('OnUpdate',function(self)if self.dragging then local _,y=GetCursorPosition();setFromCursor(y)end end)
 thumbDrag:SetScript('OnHide',function(self)self.dragging=nil end)
 return list
end

-- Vertical scroll container for long forms/pages. Returns scroll, content.
function Kit.Scroll(parent)
 local scroll=CreateFrame('ScrollFrame',nil,parent)
 local content=CreateFrame('Frame',nil,scroll)
 content:SetSize(10,10)
 scroll:SetScrollChild(content)
 scroll:EnableMouseWheel(true)
 local owner=K.WarRoomSkin and K.WarRoomSkin.OWNER or 'warroom'
 local track=CreateFrame('Frame',nil,scroll);track:SetPoint('TOPRIGHT',-1,0);track:SetPoint('BOTTOMRIGHT',-1,0);track:SetWidth(10);track:EnableMouse(true)
 Kit.Fill(track,owner,'base','BACKGROUND',0.30)
 local thumb=CreateFrame('Button',nil,track);thumb:SetWidth(8);Kit.Fill(thumb,owner,'line','BACKGROUND',0.95);thumb:EnableMouse(true)
 scroll.scrollTrack,scroll.scrollThumb=track,thumb
 scrollbarArt(track,thumb)
 local function refreshBar(self)
  local range=self:GetVerticalScrollRange() or 0;local height=self:GetHeight() or 0
  if range<=1 or height<=0 then track:Hide();self:SetVerticalScroll(0);return end
  track:Show();local thumbHeight=math.min(height,math.max(32,height*height/(height+range)))
  thumb:SetHeight(thumbHeight);local travel=math.max(0,height-thumbHeight)
  local fraction=range>0 and Kit.Clamp((self:GetVerticalScroll() or 0)/range,0,1) or 0
  thumb:ClearAllPoints();thumb:SetPoint('TOP',track,'TOP',0,-travel*fraction)
 end
 scroll:SetScript('OnMouseWheel',function(self,delta)
  local range=self:GetVerticalScrollRange() or 0
  local v=Kit.Clamp((self:GetVerticalScroll() or 0)-delta*48,0,range)
  self:SetVerticalScroll(v)
  refreshBar(self)
 end)
 scroll:SetScript('OnSizeChanged',function(self,w) if w>0 then content:SetWidth(math.max(1,w-12));refreshBar(self) end end)
 scroll:SetScript('OnScrollRangeChanged',function(self,_,range)
  local value=self:GetVerticalScroll() or 0
  if range and value>range then self:SetVerticalScroll(math.max(0,range)) end
  refreshBar(self)
 end)
 local function setFromCursor(y)
  local top,height=track:GetTop(),track:GetHeight();local scale=track:GetEffectiveScale()
  if not y or not top or not height or height<=0 or not scale or scale<=0 then return end
  local thumbHeight=thumb:GetHeight() or 0;local travel=math.max(0,height-thumbHeight)
  local fraction=travel>0 and Kit.Clamp((top-y/scale-thumbHeight/2)/travel,0,1) or 0
  scroll:SetVerticalScroll(fraction*(scroll:GetVerticalScrollRange() or 0));refreshBar(scroll)
 end
 track:SetScript('OnMouseDown',function(_,button)if button=='LeftButton' then local _,y=GetCursorPosition();setFromCursor(y)end end)
 thumb:SetScript('OnMouseDown',function(self,button)if button=='LeftButton' then self.dragging=true end end)
 thumb:SetScript('OnMouseUp',function(self)self.dragging=nil end)
 thumb:SetScript('OnUpdate',function(self)if self.dragging then local _,y=GetCursorPosition();setFromCursor(y)end end)
 thumb:SetScript('OnHide',function(self)self.dragging=nil end)
 scroll:SetScript('OnShow',function(self)refreshBar(self)end)
 return scroll,content
end

-- Copy-to-clipboard fallback: WoW addons cannot write the clipboard, so we show
-- a focused, pre-selected edit box the player copies with Ctrl+C.
function Kit.CopyBox(owner,title,text)
 Kit.copy=Kit.copy or {}
 local c=Kit.copy[owner]
 if not c then
  c=CreateFrame('Frame',nil,UIParent)
  c:SetSize(420,96);c:SetPoint('CENTER',0,140);c:SetFrameStrata('DIALOG');c:SetToplevel(true)
  c:EnableMouse(true)
  Kit.Fill(c,owner,'surface')
  Kit.Border(c,owner,'accent')
  c.title=Kit.Text(c,owner,'narrow',13,'muted');c.title:SetPoint('TOPLEFT',12,-10)
  c.edit=Kit.EditBox(c,owner,'body',14,200)
  c.edit:SetPoint('TOPLEFT',12,-34);c.edit:SetPoint('TOPRIGHT',-12,-34);c.edit:SetHeight(26)
  Kit.Fill(c.edit,owner,'field','BACKGROUND')
  c.edit:SetScript('OnEscapePressed',function() c:Hide() end)
  c.edit:SetScript('OnEnterPressed',function() c:Hide() end)
  c.hint=Kit.Text(c,owner,'narrow',12,'muted');c.hint:SetPoint('BOTTOMLEFT',12,10)
  c.hint:SetText('Press Ctrl+C to copy, then Esc to close.')
  Kit.copy[owner]=c
 end
 c.title:SetText(title);c.edit:SetText(text or '');c:Show();c.edit:SetFocus();c.edit:HighlightText()
end

-- Confirmation modal, styled by the owning interface's theme.
function Kit.Confirm(owner,title,body,confirmLabel,onConfirm)
 Kit.modals=Kit.modals or {}
 local m=Kit.modals[owner]
 local theme=themes[owner]
 if not m then
  m=CreateFrame('Frame',nil,UIParent)
  m:SetSize(440,170);m:SetPoint('CENTER',0,80);m:SetFrameStrata('DIALOG');m:SetToplevel(true)
  m:EnableMouse(true)
  Kit.Fill(m,owner,'surface')
  Kit.Border(m,owner,'danger')
  m.title=Kit.Text(m,owner,theme and theme.headingFace or 'body',16,'text');m.title:SetPoint('TOPLEFT',18,-16)
  m.body=Kit.Para(m,owner,'body',13,'muted',404);m.body:SetPoint('TOPLEFT',18,-44)
  m.yes=theme.MakeButton(m,'Confirm','danger',function() m:Hide();if m.action then Kit.Safe(m.action) end end,150)
  m.yes:SetPoint('BOTTOMRIGHT',-18,16)
  m.no=theme.MakeButton(m,'Keep it','secondary',function() m:Hide() end,110)
  m.no:SetPoint('RIGHT',m.yes,'LEFT',-10,0)
  table.insert(UISpecialFrames,'KWC2Confirm'..owner)
  _G['KWC2Confirm'..owner]=m
  Kit.modals[owner]=m
 end
 m.title:SetText(title);m.body:SetText(body or '')
 if m.yes.SetLabel then m.yes:SetLabel(confirmLabel or 'Confirm') end
 m.action=onConfirm;m:Show()
end
