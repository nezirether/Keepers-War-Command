-- War Room page: PvP leaderboards. World PvP is the flagship board with the
-- Warlords of Trogdor showcase; battlegrounds and lifetime honorable kills are
-- plain ranking tables. Values come only from each member's own game
-- Statistics, shared by their client; nothing is estimated or inferred.
local K=KWC
local Kit,S,P,W=K.Kit,K.WarRoomSkin,K.WarRoomPages,K.WarRoom2
local OWNER=S.OWNER
local ART=Kit.MEDIA..'WarRoomClassic\\WorldPvP\\'

local page={id='leaderboards',title='Leaderboards',subtitle='Honorable kills by guildmate - world PvP first.',group='ops'}
local state={board='world',query=''}
local BOARDS={
 world={label='World PvP',icon='Icon_WorldPvP',heading='World PvP honorable kills'},
 battleground={label='Battlegrounds',icon='Icon_Battlegrounds',heading='Battleground honorable kills',
  title='Battleground Kills',note='Honorable kills earned in battlegrounds, kept separate from the world.'},
 lifetime={label='Lifetime HKs',icon='Icon_Lifetime',heading='Lifetime honorable kills',
  title='Lifetime Honorable Kills',note='All-time honorable kills from each character.'},
}
local ORDER={'world','battleground','lifetime'}

-- Presentation tiers for the World PvP board. v is the used part of the row art.
local LEGENDARY={row='Row_Legendary',emblem='Emblem_Legendary',v=1,name={1,0.92,0.62},accent={1,0.78,0.25}}
local EPIC={row='Row_Epic',emblem='Emblem_Epic',v=63/64,name={0.96,0.86,1},accent={0.86,0.62,1}}
local ELITE={row='Row_Elite',emblem='Emblem_Elite',v=59/64,name={0.88,0.95,1},accent={0.58,0.82,1}}
local STANDARD={row='Row_Standard',v=1,name={0.93,0.89,0.82},accent={0.76,0.62,0.42}}
local TIERS={LEGENDARY,EPIC,EPIC,ELITE,ELITE}
local DESIGNATION='WARLORD OF TROGDOR'

local WORLD_ROW,PLAIN_ROW,TAB_W,TAB_H=44,30,170,36
local hostFrame,tabs,hero,bar,boards

-- 1234567 -> "1,234,567"
local function commas(n)
 local text=tostring(math.floor(n))
 while true do
  local replaced,count=text:gsub('^(%-?%d+)(%d%d%d)','%1,%2')
  text=replaced
  if count==0 then return text end
 end
end

-- A Warlord is one of the top five ranks that has actually scored.
local function warlordRank(r) return r.rank and r.rank<=5 and r.value and r.value>0 and r.rank or nil end

local function rows()
 local out={}
 local data=K.PvP.Rankings(state.board) or {}
 for i,r in ipairs(data) do
  if P.Matches(r.name,state.query) then out[#out+1]={rank=r.value~=nil and i or nil,name=r.name,value=r.value,at=r.snapshot and r.snapshot.at,status=r.status} end
 end
 return out
end
local function isMe(name)
 local me=K.PvP.PlayerName and K.PvP.PlayerName()
 return me and P.Lower(name)==P.Lower(me)
end
local function color(fs,c) fs:SetTextColor(c[1],c[2],c[3],1) end
local function shadow(fs) if fs.SetShadowOffset then fs:SetShadowOffset(1,-1);fs:SetShadowColor(0,0,0,1) end end

-- Three horizontal slices of one texture: end caps keep their proportions and
-- only the plain middle stretches. capL/capR are source pixels.
local function slices(frame,layer,sub)
 local t={}
 for i=1,3 do t[i]=frame:CreateTexture(nil,layer,nil,sub) end
 t[1]:SetPoint('TOPLEFT');t[1]:SetPoint('BOTTOMLEFT')
 t[3]:SetPoint('TOPRIGHT');t[3]:SetPoint('BOTTOMRIGHT')
 t[2]:SetPoint('TOPLEFT',t[1],'TOPRIGHT');t[2]:SetPoint('BOTTOMRIGHT',t[3],'BOTTOMLEFT')
 return t
end
local function fitSlices(t,file,capL,capR,srcW,srcH,width,height,v)
 local scale=height/srcH
 local left=math.max(1,capL*scale)
 local right=math.max(1,math.min(capR*scale,width*0.45))
 -- A narrow frame shows less of the right cap rather than squashing it.
 local u2=1-(right/scale)/srcW
 local u1=capL/srcW
 local middleEnd=1-capR/srcW
 if t.file~=file then
  for i=1,3 do t[i]:SetTexture(ART..file) end
  t.file=file
 end
 t[1]:SetWidth(left);t[3]:SetWidth(right)
 t[1]:SetTexCoord(0,u1,0,v);t[2]:SetTexCoord(u1,middleEnd,0,v);t[3]:SetTexCoord(u2,1,0,v)
end

local function rowTooltip(row)
 Kit.Tooltip(row,function(self) return self.item and self.item.name end,function(self)
  local r=self.item
  if not r then return end
  local lines={}
  if self.designated then lines[#lines+1]='Warlord of Trogdor' end
  if r.rank then lines[#lines+1]='Rank #'..r.rank end
  lines[#lines+1]=r.value~=nil and (commas(r.value)..' '..BOARDS[state.board].heading) or 'Awaiting Stats'
  if r.at and r.at>0 then lines[#lines+1]='Shared '..Kit.Age(r.at)..(r.status=='Stale' and ' (stale)' or '') end
  return table.concat(lines,'\n')
 end)
end

-- The standard (rank 6+) row art, shared with the Dashboard activity feed.
function P.StandardRowArt(row,width,height)
 row.art=row.art or slices(row,'BACKGROUND',1)
 fitSlices(row.art,STANDARD.row,48,364,1024,64,width,height,STANDARD.v)
end

-- World PvP flagship row.
local function buildWorld(row)
 row.art=slices(row,'BACKGROUND',1)
 row.glow=row:CreateTexture(nil,'BORDER');row.glow:SetPoint('TOPLEFT',5,-4);row.glow:SetPoint('BOTTOMRIGHT',-5,4)
 row.glow:SetColorTexture(1,0.9,0.7,0.10);row.glow:Hide()
 row.emblem=row:CreateTexture(nil,'ARTWORK');row.emblem:SetSize(34,34);row.emblem:SetPoint('LEFT',8,0)
 row.rank=Kit.Text(row,OWNER,'display',17,'text');row.rank:SetPoint('LEFT',46,0);row.rank:SetWidth(48);row.rank:SetJustifyH('CENTER');shadow(row.rank)
 row.name=Kit.Text(row,OWNER,'display',15,'text');row.name:SetJustifyH('LEFT');shadow(row.name)
 row.sub=Kit.Text(row,OWNER,'narrow',11,'muted');row.sub:SetJustifyH('LEFT');shadow(row.sub)
 row.val=Kit.Text(row,OWNER,'narrow',20,'text');row.val:SetJustifyH('RIGHT');shadow(row.val)
 function row:FitColumns()
  local width=self:GetWidth()
  if width<=0 then width=620 end
  local tier=self.tier or STANDARD
  fitSlices(self.art,tier.row,48,364,1024,64,width,WORLD_ROW,tier.v)
  local valueW=math.floor(Kit.Clamp(width*0.22,84,130))
  local textW=math.max(24,width-98-valueW-30)
  self.val:ClearAllPoints();self.val:SetPoint('RIGHT',self,'RIGHT',-18,0);self.val:SetWidth(valueW)
  local twoLines=self.sub:IsShown()
  self.name:ClearAllPoints();self.name:SetPoint('LEFT',self,'LEFT',98,twoLines and 7 or 0);self.name:SetWidth(textW)
  self.sub:ClearAllPoints();self.sub:SetPoint('LEFT',self,'LEFT',98,-9);self.sub:SetWidth(textW)
 end
 row:HookScript('OnSizeChanged',row.FitColumns)
 row:SetScript('OnEnter',function(self) self.glow:Show() end)
 row:SetScript('OnLeave',function(self) self.glow:Hide() end)
 rowTooltip(row)
end
local function fillWorld(row,r)
 local warlord=warlordRank(r)
 local tier=warlord and TIERS[warlord] or STANDARD
 row.tier,row.designated=tier,warlord~=nil
 if warlord then row.emblem:SetTexture(ART..tier.emblem);row.emblem:Show() else row.emblem:Hide() end
 row.rank:SetText(r.rank and ('#'..r.rank) or '-')
 row.name:SetText(r.name..(isMe(r.name) and '  (you)' or ''))
 local note=warlord and DESIGNATION or ''
 if r.status=='Stale' then note=note..(note~='' and '  -  ' or '')..'STALE' end
 row.sub:SetText(note);row.sub:SetShown(note~='')
 row.val:SetText(r.value~=nil and commas(r.value) or 'Awaiting Stats')
 Kit.SetFont(row.val,S.theme.fonts and S.theme.fonts.narrow or 'narrow',r.value~=nil and 20 or 12)
 color(row.rank,tier.accent);color(row.name,tier.name);color(row.sub,tier.accent)
 color(row.val,r.value~=nil and tier.name or STANDARD.accent)
 row:FitColumns()
end

-- Secondary boards: a plain ranking table.
local function buildPlain(row)
 row.bg=Kit.Fill(row,OWNER,'surface')
 row.rank=S.Text(row,'body','faint');row.rank:SetPoint('LEFT',10,0);row.rank:SetWidth(46)
 row.name=S.Text(row,'body','text');row.name:SetJustifyH('LEFT');row.name:SetPoint('LEFT',62,0)
 row.val=Kit.Text(row,OWNER,'narrow',15,'text');row.val:SetPoint('RIGHT',-14,0);row.val:SetJustifyH('RIGHT')
 row.stale=S.Text(row,'small','faint');row.stale:SetPoint('RIGHT',row.val,'LEFT',-10,0);row.stale:SetWidth(36);row.stale:SetJustifyH('RIGHT');row.stale:SetText('stale')
 local rule=Kit.Rule(row,OWNER,'lineSoft',true,1,0.6);rule:SetPoint('BOTTOMLEFT');rule:SetPoint('BOTTOMRIGHT')
 function row:FitColumns()
  local width=self:GetWidth()
  if width<=0 then width=620 end
  local valueW=math.floor(Kit.Clamp(width*0.22,84,130))
  self.val:SetWidth(valueW)
  self.name:SetWidth(math.max(24,width-62-valueW-76))
 end
 row:HookScript('OnSizeChanged',row.FitColumns)
 function row:UpdateClassicStyle(index)
  self.index=index
  Kit.Paint(self.bg,OWNER,self.hovered and 'hover' or index and index%2==0 and 'raised' or 'surface','fill')
 end
 row:SetScript('OnEnter',function(self) self.hovered=true;self:UpdateClassicStyle(self.index) end)
 row:SetScript('OnLeave',function(self) self.hovered=nil;self:UpdateClassicStyle(self.index) end)
 rowTooltip(row)
end
local function fillPlain(row,r)
 row.designated=false
 local mine=isMe(r.name)
 row.rank:SetText(r.rank and ('#'..r.rank) or '-')
 row.name:SetText(r.name..(mine and '  (you)' or ''))
 row.val:SetText(r.value~=nil and commas(r.value) or 'Awaiting Stats')
 row.stale:SetShown(r.status=='Stale')
 Kit.Paint(row.name,OWNER,mine and 'accentText' or 'text','text')
 Kit.Paint(row.val,OWNER,r.value~=nil and 'text' or 'faint','text')
 row:FitColumns()
end

-- Textured board tabs. Same segs/Update shape as S.Segmented.
local function buildTabs(parent)
 local f=CreateFrame('Frame',nil,parent)
 f:SetHeight(TAB_H);f.segs={}
 for i,value in ipairs(ORDER) do
  local b=CreateFrame('Button',nil,f)
  b:SetSize(TAB_W,TAB_H);b:SetPoint('TOPLEFT',f,'TOPLEFT',(i-1)*(TAB_W+6),0)
  b.value=value
  b.art=slices(b,'BACKGROUND',1)
  b.icon=b:CreateTexture(nil,'ARTWORK');b.icon:SetSize(24,24);b.icon:SetPoint('LEFT',14,0);b.icon:SetTexture(ART..BOARDS[value].icon)
  b.text=Kit.Text(b,OWNER,'display',13,'text');b.text:SetPoint('LEFT',b,'LEFT',44,0);b.text:SetWidth(TAB_W-54);b.text:SetText(BOARDS[value].label);shadow(b.text)
  b:SetScript('OnClick',function()
   if state.board~=value then state.board=value;page:Update() end
  end)
  b:SetScript('OnEnter',function(self) self.hovered=true;f:Update() end)
  b:SetScript('OnLeave',function(self) self.hovered=nil;self.pressed=nil;f:Update() end)
  b:SetScript('OnMouseDown',function(self) self.pressed=true;f:Update() end)
  b:SetScript('OnMouseUp',function(self) self.pressed=nil;f:Update() end)
  f.segs[i]=b
 end
 function f:Update()
  for _,b in ipairs(self.segs) do
   local on=state.board==b.value
   b.state=on and 'Tab_Selected' or b.pressed and 'Tab_Active' or b.hovered and 'Tab_Hover' or 'Tab_Inactive'
   fitSlices(b.art,b.state,32,32,256,64,TAB_W,TAB_H,62/64)
   color(b.text,on and {1,0.92,0.66} or b.hovered and STANDARD.name or {0.72,0.68,0.61})
   b.icon:SetAlpha(on and 1 or 0.7)
  end
 end
 return f
end

-- Hero strip: baked-title art on World PvP (never both pieces, no live title on
-- top of it); a small crest and live heading elsewhere. Art keeps its aspect.
local function buildHero(parent)
 local f=CreateFrame('Frame',nil,parent)
 f.art=f:CreateTexture(nil,'ARTWORK');f.art:SetPoint('TOP')
 f.crest=f:CreateTexture(nil,'ARTWORK');f.crest:SetPoint('LEFT');f.crest:SetTexture(ART..'KWC_Crest')
 f.title=S.Text(f,'title','text');f.title:SetJustifyH('LEFT')
 f.note=S.Text(f,'small','muted');f.note:SetJustifyH('LEFT')
 return f
end
local function layout()
 if not hero then return end
 local width,height=hostFrame:GetWidth(),hostFrame:GetHeight()
 if width<=0 then width=660 end
 if height<=0 then height=440 end
 local board=BOARDS[state.board]
 local world=state.board=='world'
 hero.art:SetShown(world);hero.crest:SetShown(not world);hero.title:SetShown(not world);hero.note:SetShown(not world)
 if world then
  -- Short windows get the compact title plate so all five Warlords stay visible.
  local tall=height>=560
  local h=tall and math.min(150,math.floor(height*0.24)) or 72
  h=math.min(h,math.floor(width/5))
  local file=tall and 'Warlords_Banner' or 'WorldPvP_Header'
  hero:SetHeight(h);hero.art:SetSize(h*5,h)
  if hero.file~=file then hero.art:SetTexture(ART..file);hero.file=file end
 else
  hero:SetHeight(52)
  local crestW=width>=520 and 200 or 0
  hero.crest:SetShown(crestW>0);hero.crest:SetSize(200,52)
  local x=crestW>0 and crestW+14 or 0
  hero.title:ClearAllPoints();hero.title:SetPoint('TOPLEFT',hero,'TOPLEFT',x,-6);hero.title:SetWidth(math.max(1,width-x));hero.title:SetText(board.title)
  hero.note:ClearAllPoints();hero.note:SetPoint('TOPLEFT',hero,'TOPLEFT',x,-34);hero.note:SetWidth(math.max(1,width-x));hero.note:SetText(board.note)
 end
end

local function buildBoard(host,anchor,id,rowHeight,gap,build,fill)
 local list=Kit.List(host,rowHeight,gap,build,fill)
 local heading=P.ListHeading(host,list,anchor,BOARDS[id].heading)
 Kit.Paint(list.thumb,OWNER,'line','fill')
 list.empty=S.Empty(list,'No scores shared yet','Guildmates appear after their client shares a valid honor total.',480)
 list.empty:SetPoint('TOPLEFT',4,-6)
 list.heading=heading
 return list
end

function page.Build(self,host)
 hostFrame=host
 tabs=buildTabs(host);tabs:SetPoint('TOPLEFT');tabs:SetPoint('TOPRIGHT')
 hero=buildHero(host);hero:SetPoint('TOPLEFT',tabs,'BOTTOMLEFT',0,-6);hero:SetPoint('RIGHT',host,'RIGHT',0,0);hero:SetHeight(72)
 bar=P.Toolbar(host,{search=function(t) state.query=t;if boards then for _,list in pairs(boards) do list.offset=0 end;self:Update() end end,searchHint='Find a guildmate',
  action='Refresh my stats',onAction=function() K.PvP.RefreshMyStats();self:Update() end,actionWidth=160})
 bar:ClearAllPoints();bar:SetPoint('TOPLEFT',hero,'BOTTOMLEFT',0,-8);bar:SetPoint('TOPRIGHT',hero,'BOTTOMRIGHT',0,-8)
 boards={
  world=buildBoard(host,bar,'world',WORLD_ROW,2,buildWorld,fillWorld),
  battleground=buildBoard(host,bar,'battleground',PLAIN_ROW,1,buildPlain,fillPlain),
  lifetime=buildBoard(host,bar,'lifetime',PLAIN_ROW,1,buildPlain,fillPlain),
 }
 self.tabs,self.hero,self.bar,self.boards=tabs,hero,bar,boards
 host:HookScript('OnSizeChanged',layout)
end
function page.Update(self)
 if not boards then return end
 tabs:Update()
 layout()
 for id,list in pairs(boards) do
  local on=id==state.board
  list:SetShown(on);list.heading:SetShown(on)
 end
 local list=boards[state.board]
 if state.query~='' then list.empty:Set('No guildmate matches that search','Clear the search box to see the whole board.')
 else list.empty:Set('No scores shared yet','Guildmates appear after their client shares a valid honor total.') end
 list:SetData(rows())
end
W.Register(page)
