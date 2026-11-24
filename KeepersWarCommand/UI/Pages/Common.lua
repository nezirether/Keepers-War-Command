-- Shared layout helpers for War Room pages (War Room look only).
local K=KWC
local Kit,S=K.Kit,K.WarRoomSkin
local OWNER=S.OWNER
local P={};K.WarRoomPages=P

-- Master/detail split: list on the left, detail drawer on the right.
function P.Split(host,detailWidth)
 local left=CreateFrame('Frame',nil,host)
 local right=CreateFrame('Frame',nil,host)
 right:SetPoint('TOPRIGHT');right:SetPoint('BOTTOMRIGHT');right:SetWidth(detailWidth or 380)
 Kit.Fill(right,OWNER,'surface');Kit.Border(right,OWNER,'lineSoft')
 left:SetPoint('TOPLEFT');left:SetPoint('BOTTOMLEFT');left:SetPoint('RIGHT',right,'LEFT',-18,0)
 return left,right
end

-- Fit search, action and filter controls into the space their column provides.
function P.Toolbar(parent,opts)
 local bar=CreateFrame('Frame',nil,parent)
 bar:SetPoint('TOPLEFT');bar:SetPoint('TOPRIGHT');bar:SetHeight(30)
 local box
 if opts.secondary then
  bar.secondary=S.Button(bar,opts.secondary,'secondary',opts.onSecondary,opts.secondaryWidth or 120,30)
 end
 if opts.search then
  box=CreateFrame('Frame',nil,bar);box:SetHeight(28)
  Kit.Fill(box,OWNER,'field');local line=Kit.Rule(box,OWNER,'line',true,1);line:SetPoint('BOTTOMLEFT');line:SetPoint('BOTTOMRIGHT')
  local e=Kit.EditBox(box,OWNER,'body',13,40);e:SetAllPoints(box)
  local ph=Kit.Text(box,OWNER,'body',12,'faint');ph:SetPoint('LEFT',8,0);ph:SetText(opts.searchHint or 'Search')
  e:SetScript('OnTextChanged',function(self) ph:SetShown(self:GetText()=='');Kit.Safe(opts.search,self:GetText()) end)
  e:SetScript('OnEnterPressed',function(self) self:ClearFocus() end)
  bar.search=e
 end
 if opts.segments then
  bar.seg=S.Segmented(bar,opts.segments,opts.get,opts.set,opts.segWidth)
 end
 if opts.action then
  bar.action=S.Button(bar,opts.action,'primary',opts.onAction,opts.actionWidth or 150,30)
 end
 function bar:Layout(width)
  width=math.max(1,width or self:GetWidth())
  local y=0
  local actions={}
  if self.action then actions[#actions+1]=self.action end
  if self.secondary then actions[#actions+1]=self.secondary end
  local x=width
  local row=false
  for _,action in ipairs(actions) do
   local size=action:GetWidth()
   if x-size<0 and row then x=width;y=y+36 end
   action:ClearAllPoints();action:SetPoint('TOPRIGHT',x-width,-y)
   x=x-size-8;row=true
  end
  if box then
   if row and x<130 then y=y+36;x=width end
   box:ClearAllPoints();box:SetPoint('TOPLEFT',0,-y)
   box:SetWidth(math.max(1,math.min(opts.searchWidth or 200,x)))
   row=true
  end
  if row then y=y+36 end
  local segmentTop=y
  if self.seg then
   local h=P.SegmentWidth(self.seg,width)
   y=y+h+6
  end
  self:SetHeight(math.max(30,y-6))
  if self.seg then
   -- Anchor after the toolbar's final dimensions have settled. In Forever a
   -- nested anchor set during the height change can have no resolved rectangle.
   self.seg:ClearAllPoints()
   self.seg:SetPoint('TOPLEFT',self,'TOPLEFT',0,-segmentTop)
  end
 end
 local function refresh(self)
  local width=self:GetWidth()
  if width>0 then self:Layout(width) end
 end
 bar:SetScript('OnShow',refresh)
 bar:SetScript('OnSizeChanged',function(self,width)
  if width<=0 or width==self.layoutWidth then return end
  self.layoutWidth=width
  refresh(self)
 end)
 local w=parent:GetWidth()
 bar.layoutWidth=w
 bar:Layout(w>0 and w or 300)
 return bar
end

-- Vertical stack inside a scroll content frame.
function P.Stack(parent,width,measureOnly)
 local st={parent=parent,y=0,width=width}
 function st:Reset() self.y=0 end
 function st:Place(f,height,gap,indent)
  f:ClearAllPoints();f:SetPoint('TOPLEFT',self.parent,'TOPLEFT',indent or 0,-self.y)
  if f.SetWidth and not f.keepWidth then f:SetWidth(math.max(1,self.width-(indent or 0))) end
  if f.FitHeight then f:FitHeight(math.max(1,self.width-(indent or 0))) end
  local h=height or (f:IsObjectType('FontString') and f:GetStringHeight()) or f:GetHeight() or 0
  if h<1 then h=f:GetHeight() or 14 end
  f:Show()
  self.y=self.y+h+(gap or 10)
  if not measureOnly then self.parent:SetHeight(math.max(10,self.y)) end
  return f
 end
 function st:Space(h) self.y=self.y+h end
 function st:Actions(buttons,gap)
  for _,b in ipairs(buttons) do b:Show() end
  self.y=P.Flow(buttons,self.parent,self.width,self.y,8)+(gap or 10)
  if not measureOnly then self.parent:SetHeight(math.max(10,self.y)) end
 end
 return st
end

-- Flow buttons left-to-right, wrapping. Hidden buttons are skipped.
function P.Flow(buttons,parent,width,top,gap)
 local x,y,rowH=0,top or 0,0
 gap=gap or 8
 for _,b in ipairs(buttons) do
  if b:IsShown() then
   local w=b:GetWidth()
   if x>0 and x+w>width then x=0;y=y+rowH+gap;rowH=0 end
   b:ClearAllPoints();b:SetPoint('TOPLEFT',parent,'TOPLEFT',x,-y)
   x=x+w+gap;rowH=math.max(rowH,b:GetHeight())
  end
 end
 return y+rowH
end

function P.SegmentWidth(seg,width)
 seg:SetWidth(width)
 local height=P.Flow(seg.segs,seg,width,0,6)
 seg:SetHeight(height)
 return height
end

-- Lay out card bodies before positioning the next row.
function P.CardGrid(content,width,cards,minimum)
 local gap=14
 local cols=width>=minimum*2+gap and 2 or 1
 local col=math.floor((width-(cols-1)*gap)/cols)
 local x,y,rowHeight=0,0,0
 for _,card in ipairs(cards) do
  local span=card.fullWidth and cols or 1
  if x+span>cols then x,y,rowHeight=0,y+rowHeight+gap,0 end
  local cardWidth=span==cols and width or col
  local body=P.Stack(card.body,math.max(1,cardWidth-28),true)
  card:LayoutBody(body)
  local height=math.max(62,body.y+46)
  card:ClearAllPoints();card:SetPoint('TOPLEFT',x*(col+gap),-y)
  card:SetSize(cardWidth,height);card.layoutTop=y
  rowHeight=math.max(rowHeight,height);x=x+span
 end
 content:SetHeight(y+rowHeight)
end

-- Section label + paragraph pair used in detail drawers.
function P.Section(parent,label,width)
 local f=CreateFrame('Frame',nil,parent);f:SetSize(width,20)
 f.k=S.Text(f,'kicker','faint');f.k:SetPoint('TOPLEFT');f.k:SetText((label or ''):upper())
 f.p=S.Para(f,width,'text',13);f.p:SetPoint('TOPLEFT',f.k,'BOTTOMLEFT',0,-5)
 function f:Set(text,label2)
  if label2 then self.k:SetText(label2:upper()) end
  self.p:SetText(text or '')
  self:FitHeight(self:GetWidth())
 end
 function f:FitHeight(w)
  self.p:SetWidth(w)
  self:SetHeight(18+math.max(14,self.p:GetStringHeight() or 14))
 end
 return f
end

-- Drawer header: big title + status chips line.
function P.DrawerHead(parent,width)
 local f=CreateFrame('Frame',nil,parent);f:SetSize(width,58)
 f.kick=S.Text(f,'kicker','accentText');f.kick:SetPoint('TOPLEFT')
 f.title=S.Para(f,width,'text',S.type.title);f.title:SetPoint('TOPLEFT',f.kick,'BOTTOMLEFT',0,-6)
 Kit.SetFont(f.title,'body',S.type.title)
 function f:Set(kick,title)
  self.kick:SetText((kick or ''):upper());self.title:SetText(title or '')
  self:SetHeight(22+math.max(18,self.title:GetStringHeight() or 18))
 end
 return f
end

-- Anchor page bodies to the measured height of a tab strip.
function P.TabStrip(parent,segment,below)
 segment:ClearAllPoints();segment:SetPoint('TOPLEFT')
 local function layout(_,width)
  if width<=0 then return end
  P.SegmentWidth(segment,width)
  if below then below(width) end
 end
 parent:HookScript('OnSizeChanged',layout)
 local width=parent:GetWidth()
 layout(parent,width>0 and width or 660)
end

-- A common list heading shows the slice on screen and pages through pooled rows.
function P.ListHeading(parent,list,anchor,label)
 local h=CreateFrame('Frame',nil,parent)
 h:SetHeight(29)
 h.label=S.Text(h,'kicker','accentText');h.label:SetPoint('LEFT',8,0);h.label:SetText(label:upper())
 h.range=S.Text(h,'small','muted');h.range:SetPoint('RIGHT',-61,0)
 local prev=S.Button(h,'‹','ghost',function() list:Page(-1) end,23,23)
 local next=S.Button(h,'›','ghost',function() list:Page(1) end,23,23)
 next:SetPoint('RIGHT',-2,0);prev:SetPoint('RIGHT',next,'LEFT',-4,0)
 local rule=Kit.Rule(h,OWNER,'lineSoft',true,1)
 rule:SetPoint('BOTTOMLEFT');rule:SetPoint('BOTTOMRIGHT')
 function h:SetAnchor(target)
  self:ClearAllPoints();self:SetPoint('TOPLEFT',target,'BOTTOMLEFT',0,-10);self:SetPoint('RIGHT',parent,'RIGHT',0,0)
 end
 function h:SetRange(offset,count,total)
  self.range:SetText(count>0 and (('%d–%d / %d'):format(offset+1,offset+count,total)) or tostring(total))
  prev:SetEnabledState(offset>0,'First page')
  next:SetEnabledState(offset+count<total,'Last page')
 end
 h:SetAnchor(anchor)
 list:ClearAllPoints();list:SetPoint('TOPLEFT',h,'BOTTOMLEFT',0,-6);list:SetPoint('BOTTOMRIGHT')
 list.header=h
 return h
end

-- Jump to controls in long configuration pages without hiding their settings.
function P.CardNavigation(host,scroll,entries)
 local nav=CreateFrame('Frame',nil,host)
 nav:SetPoint('TOPLEFT',host,'TOPLEFT',0,0);nav:SetPoint('TOPRIGHT',host,'TOPRIGHT',0,0);nav:SetHeight(32)
 local buttons={}
 for _,entry in ipairs(entries) do
  local label,card=entry[1],entry[2]
  buttons[#buttons+1]=S.Button(nav,label,'secondary',function()
   scroll:SetVerticalScroll(Kit.Clamp(card.layoutTop or 0,0,scroll:GetVerticalScrollRange() or 0))
   for _,tab in ipairs(buttons) do tab:SetSelected(tab.destination==card) end
  end,entry[3] or 105,32)
  buttons[#buttons].destination=card
 end
 if buttons[1] then buttons[1]:SetSelected(true) end
 local width
 local function layout(_,w)
  if w<=0 or w==width then return end
  width=w;nav:SetHeight(P.Flow(buttons,nav,w,0,8))
 end
 nav:SetScript('OnSizeChanged',layout)
 layout(nav,host:GetWidth()>0 and host:GetWidth() or 660)
 scroll:ClearAllPoints();scroll:SetPoint('TOPLEFT',nav,'BOTTOMLEFT',0,-12);scroll:SetPoint('BOTTOMRIGHT')
 return nav
end

-- Builds a scrollable drawer body inside a detail pane.
function P.DrawerBody(pane)
 local scroll,content=Kit.Scroll(pane)
 scroll:SetPoint('TOPLEFT',20,-18);scroll:SetPoint('BOTTOMRIGHT',-16,16)
 return scroll,content
end

-- Short name for display (drops realm).
-- Display name: proper-case roster spelling when known, realm dropped.
function P.Short(name)
 name=tostring(name or '?')
 local r=K.RosterRecord and K.RosterRecord(name)
 if r and type(r.name)=='string' then name=r.name end
 return name:match('^[^-]+') or name
end
function P.Me() return UnitName and UnitName('player') or '' end
function P.Lower(s) return tostring(s or ''):lower() end
function P.Matches(text,query)
 if not query or query=='' then return true end
 return P.Lower(text):find(P.Lower(query),1,true)~=nil
end
-- Current zone and (when readable) coordinates as a short label.
function P.HereZone()
 local z=GetRealZoneText and GetRealZoneText()
 if issecretvalue and issecretvalue(z) then z=nil end
 return type(z)=='string' and z or ''
end
function P.HereCoords()
 local map,x,y=K.Geo and K.Geo.PlayerPosition()
 if map then return K.Geo.Format(x,y) end
 return ''
end
