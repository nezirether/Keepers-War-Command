-- KWC 2.0 toast notifications (public War Room style).
-- A compact card: tone rail, icon, kicker, headline, detail, actions and a
-- countdown line. Replaces the 1.x full-width banner art entirely.
-- Detection, suppression (instance policy, Smart Mode) and sound decisions stay
-- in the engine modules; this module only presents, positions and times cards.
local K=KWC
local Kit,S=K.Kit,K.WarRoomSkin
local OWNER=S.OWNER
local T={channels={},order={}};K.Toast=T

local ICONS={
 death='Interface\\Icons\\Ability_Rogue_FeignDeath',
 kill='Interface\\Icons\\Ability_Warrior_Rampage',
 bounty='Interface\\Icons\\INV_Misc_Bag_10',
 cta='Interface\\Icons\\Ability_Warrior_BattleShout',
 lfg='Interface\\Icons\\INV_Misc_GroupNeedMore',
}
T.ICONS=ICONS

local function settings() return KWCDB and KWCDB.settings end

local function build(ch)
 local f=CreateFrame('Frame','KWC2Toast_'..ch.key,UIParent)
 f:SetSize(404,98)
 f:SetFrameStrata('HIGH');f:SetFrameLevel(40+#T.order);f:SetClampedToScreen(true);f:Hide()
 f:EnableMouse(true);f:SetMovable(true);f:RegisterForDrag('LeftButton')
 f.shadow=f:CreateTexture(nil,'BACKGROUND',nil,-2)
 f.shadow:SetPoint('TOPLEFT',-3,3);f.shadow:SetPoint('BOTTOMRIGHT',3,-3)
 Kit.Paint(f.shadow,OWNER,'shadow','fill')
 f.bg=Kit.Fill(f,OWNER,'surface');f.themeArt=S.Art(f,'alert')
 f.border=Kit.Border(f,OWNER,'lineSoft')
 f.rail=Kit.Rule(f,OWNER,'accent',false,4);f.rail:SetPoint('TOPLEFT');f.rail:SetPoint('BOTTOMLEFT')
 -- Card chrome that an event artwork plate replaces (UI/AlertArt.lua).
 f.chrome={f.shadow,f.bg,f.themeArt,f.rail}
 for _,edge in ipairs(f.border) do f.chrome[#f.chrome+1]=edge end
 f.icon=f:CreateTexture(nil,'ARTWORK');f.icon:SetSize(40,40);f.icon:SetPoint('TOPLEFT',16,-14)
 f.icon:SetTexCoord(0.08,0.92,0.08,0.92)
 f.kicker=Kit.Text(f,OWNER,'narrow',12,'accentText');f.kicker:SetPoint('TOPLEFT',f.icon,'TOPRIGHT',12,1)
 f.title=Kit.Text(f,OWNER,'body',15,'text');f.title:SetPoint('TOPLEFT',f.kicker,'BOTTOMLEFT',0,-3);f.title:SetPoint('RIGHT',f,'RIGHT',-34,0)
 f.detail=Kit.Text(f,OWNER,'body',12,'muted');f.detail:SetPoint('TOPLEFT',f.title,'BOTTOMLEFT',0,-4);f.detail:SetPoint('RIGHT',f,'RIGHT',-16,0)
 f.meta=Kit.Text(f,OWNER,'narrow',12,'faint');f.meta:SetPoint('BOTTOMLEFT',f.icon,'BOTTOMRIGHT',12,-30)
 f.close=CreateFrame('Button',nil,f);f.close:SetSize(22,22);f.close:SetPoint('TOPRIGHT',-6,-6)
 f.close.t=Kit.Text(f.close,OWNER,'narrow',16,'faint');f.close.t:SetPoint('CENTER');f.close.t:SetText('x')
 f.close:SetScript('OnClick',function() f:Hide() end)
 f.close:SetScript('OnEnter',function(self) Kit.Paint(self.t,OWNER,'text','text') end)
 f.close:SetScript('OnLeave',function(self) Kit.Paint(self.t,OWNER,'faint','text') end)
 f.timer=f:CreateTexture(nil,'OVERLAY');f.timer:SetPoint('BOTTOMLEFT',4,0);f.timer:SetHeight(2)
 Kit.Paint(f.timer,OWNER,'accent','fill')
 f.hint=Kit.Text(f,OWNER,'narrow',12,'warn');f.hint:SetPoint('BOTTOM',f,'TOP',0,4)
 f.hint:SetText('Drag to position - lock it again in War Room > Alerts')
 f.actions={}
 for i=1,4 do
  local b=S.Button(f,'',i==1 and 'primary' or 'secondary',function(self) if self.fn then self.fn() end end,130,24)
  b:SetPoint('BOTTOMRIGHT',f,'BOTTOMRIGHT',-12-(i-1)*138,10)
  b:Hide();f.actions[i]=b
 end
 Kit.Tooltip(f,function() return f.title:GetText() end,function() return f.detail:GetText() end)
 f:SetScript('OnDragStart',function(self) if ch:Unlocked() then self:StartMoving() end end)
 f:SetScript('OnDragStop',function(self)
  self:StopMovingOrSizing()
  local v=settings();if not v then return end
  local point,_,rel,x,y=self:GetPoint(1)
  v[ch.key..'Position']={point=point,relativePoint=rel,x=x,y=y}
 end)
 f:SetScript('OnUpdate',function(self,dt)
  if ch:Unlocked() then self.timer:SetWidth(self:GetWidth()-4);return end
  self.elapsed=(self.elapsed or 0)+dt
  local life=ch:Duration()
  self.timer:SetWidth(math.max(1,(self:GetWidth()-4)*(1-self.elapsed/life)))
  local preferences=K.Celebrations and K.Celebrations.Preferences()
  if not preferences or (preferences.animations and not preferences.reducedMotion) then
   self:SetAlpha(math.min(1,self.elapsed/0.16,math.max(0,(life-self.elapsed)/0.3)))
  else self:SetAlpha(1) end
  if self.elapsed>=life then self:Hide() end
 end)
 -- Each text line and action row owns a vertical lane, including wrapped surnames.
 function f:LayoutContent()
  if self.layingOut then return end
  self.layingOut=true
  local width=math.max(120,self:GetWidth()-102)
  local y=14
  local function line(region,size)
   region:ClearAllPoints()
   region:SetPoint('TOPLEFT',self,'TOPLEFT',68,-y)
   region:SetWidth(width)
   region:SetWordWrap(true)
   local text=region:GetText() or ''
   local height=text~='' and math.max(size,region:GetStringHeight() or size) or 0
   region:SetHeight(height)
   y=y+height
  end
  line(self.kicker,12);y=y+3
  line(self.title,18);y=y+4
  line(self.detail,14)
  if (self.meta:GetText() or '')~='' then y=y+6;line(self.meta,14) end
  local active=0
  for _,button in ipairs(self.actions) do if button:IsShown() then active=active+1 end end
  if active>0 then
   y=y+10
   for i,button in ipairs(self.actions) do
    button:ClearAllPoints()
    button:SetPoint('TOPRIGHT',self,'TOPRIGHT',-12-((i-1)%2)*138,-y-math.floor((i-1)/2)*30)
   end
   y=y+math.ceil(active/2)*30
  end
  self:SetHeight(math.max(98,y+12))
  self.layingOut=false
 end
 f:HookScript('OnSizeChanged',function(self) self:LayoutContent() end)
 return f
end

local Channel={}
Channel.__index=Channel
function Channel:Unlocked() local v=settings();return v and v[self.key..'Unlocked']==true end
function Channel:Duration()
 local v=settings()
 local d=v and tonumber(v[self.durationKey or (self.key..'Duration')])
 return Kit.Clamp(d or self.defaultDuration or 8,3,30)
end
function Channel:Enabled()
 local v=settings();if not v then return false end
 if self.enabledKey then return v[self.enabledKey]~=false end
 return true
end
function Channel:Initialize()
 local f=self.frame;local v=settings() or {}
 local pos=v[self.key..'Position']
 f:ClearAllPoints()
 if type(pos)=='table' and type(pos.x)=='number' and type(pos.y)=='number' and type(pos.point)=='string' then
  f:SetPoint(pos.point,UIParent,pos.relativePoint or pos.point,pos.x,pos.y)
 else f:SetPoint('TOP',UIParent,'TOP',0,-120-self.defaultSlot*112) end
 f:SetScale(Kit.Clamp(tonumber(v[self.key..'Scale']) or 1,0.5,2))
 f.hint:SetShown(self:Unlocked())
end
function Channel:SetUnlocked(on)
 local v=settings();if not v then return end
 v[self.key..'Unlocked']=on and true or false
 self:Initialize()
 if on then if self.demo then self.demo() end else self.frame:Hide() end
end
function Channel:SetScale(value)
 local v=settings();if not v then return end
 v[self.key..'Scale']=Kit.Clamp(tonumber(value) or 1,0.5,2)
 self:Initialize()
end
function Channel:Reset()
 local v=settings();if not v then return end
 v[self.key..'Position']=nil;v[self.key..'Scale']=nil
 self:Initialize()
end
function Channel:IsShown() return self.frame:IsShown() end
function Channel:Hide() self.frame:Hide() end
-- Explicit source identities prevent retransmitted notices without conflating nearby events.
local delivered={}
function T.Claim(kind,eventID)
 if eventID==nil then return true end
 local now=time()
 local key=kind..'|'..tostring(eventID)
 local count=0
 for id,at in pairs(delivered) do
  if now-at>=600 then delivered[id]=nil else count=count+1 end
 end
 if delivered[key] then return false end
 if count>=512 then
  local oldest,stamp
  for id,at in pairs(delivered) do if not stamp or at<stamp then oldest,stamp=id,at end end
  delivered[oldest]=nil
 end
 delivered[key]=now
 return true
end
-- content={kicker,title,detail,meta,icon,tone,actions={{label=,fn=}}}
-- automatic=true marks guild-driven alerts so instance suppression can dismiss them.
function Channel:Present(content,automatic)
 if automatic and K.InstanceAlerts and not K.InstanceAlerts.Allowed() then return false end
 if automatic and not T.Claim(self.key,content.eventID) then return false end
 local f=self.frame
 local tone=content.tone or self.tone or 'accent'
 Kit.Paint(f.rail,OWNER,tone,'fill');Kit.Paint(f.timer,OWNER,tone,'fill')
 Kit.Paint(f.kicker,OWNER,tone=='accent' and 'accentText' or tone,'text')
 f.icon:SetTexture(content.icon or ICONS[self.icon] or ICONS.cta)
 f.kicker:SetText((content.kicker or ''):upper())
 f.title:SetText(content.title or '')
 f.detail:SetText(content.detail or '')
 f.meta:SetText(content.meta or '')
 for i,b in ipairs(f.actions) do
  local a=content.actions and content.actions[i]
  if a then b:SetLabel(a.label);b.fn=a.fn;b:Show() else b.fn=nil;b:Hide() end
 end
 -- Optional event artwork behind the live content; failures keep the classic card.
 f:LayoutContent()
 if T.Decorate then Kit.Safe(T.Decorate,self,content) end
 self.automatic=automatic==true
 f.elapsed=0;f:SetAlpha(1)
 self:Initialize()
 f:Show()
 return true
end

-- Registers (or returns) a channel.
-- spec={key,label,icon,tone,defaultSlot,durationKey,enabledKey,defaultDuration}
function T.Channel(spec)
 if T.channels[spec.key] then return T.channels[spec.key] end
 local ch=setmetatable({},Channel)
 for k,v in pairs(spec) do ch[k]=v end
 ch.defaultSlot=ch.defaultSlot or #T.order
 ch.frame=build(ch)
 -- Placement object with the same contract the engine modules already use.
 ch.placement={
  Initialize=function() ch:Initialize() end,
  SetUnlocked=function(v) local s=settings();if s then s[ch.key..'Unlocked']=v and true or false end;ch:Initialize() end,
  SetScale=function(v) ch:SetScale(v) end,
  Reset=function() ch:Reset() end,
 }
 T.channels[spec.key]=ch
 T.order[#T.order+1]=ch
 return ch
end

-- Simple notice channels for new CTAs and Guild LFG (engine-side policy already
-- checked by the caller; this only respects the per-channel popup toggle).
local recent={}
function T.Notice(kind,title,detail,action,eventID)
 local ch=T.channels[kind];if not ch or not ch:Enabled() then return false end
 local now=time and time() or 0
 local key=kind..'\001'..tostring(eventID or title)
 if recent[key] and now-recent[key]<20 then return false end
 for id,at in pairs(recent) do if now-at>=20 then recent[id]=nil end end
 recent[key]=now
 ch:Present({eventID=eventID,kicker=ch.label,title=title,detail=detail,actions=action and {action} or nil},true)
 if PlaySound and not K.Celebrations and K.QOL and K.QOL.Enabled('alertSound') and K.QOL.Enabled(kind..'Sound') then pcall(PlaySound,8960,'Master') end
 return true
end

-- Dismiss automatic toasts when instance suppression begins (previews stay).
local hooked=false
function T.HookSuppression()
 if hooked or not (K.InstanceAlerts and K.InstanceAlerts.OnSuppressed) then return end
 hooked=true
 K.InstanceAlerts.OnSuppressed(function()
  for _,ch in ipairs(T.order) do
   if ch.automatic and ch.frame:IsShown() and not ch:Unlocked() then ch.frame:Hide() end
  end
 end)
end

-- Notice channels owned by the UI (CTA and Guild LFG).
T.Channel({key='ctaNotice',label='Call to Arms',icon='cta',tone='warn',defaultSlot=3,enabledKey='ctaPopup'})
T.Channel({key='lfgNotice',label='Guild Group',icon='lfg',tone='info',defaultSlot=4,enabledKey='lfgPopup'})
T.channels.cta=T.channels.ctaNotice
T.channels.lfg=T.channels.lfgNotice
T.channels.ctaNotice.demo=function() T.channels.ctaNotice:Present({kicker='Call to Arms',title='[HIGH] Hillsbrad Foothills  H:A 4:9',detail='Defend Tarren Mill - preview',actions={{label='Open',fn=function() if K.UI then K.UI.Toggle('Calls to Arms') end end}}}) end
T.channels.lfgNotice.demo=function() T.channels.lfgNotice:Present({kicker='Guild Group',title='Dungeon: Scarlet Monastery',detail='Needs 2 - Tank, Healer - preview'}) end
