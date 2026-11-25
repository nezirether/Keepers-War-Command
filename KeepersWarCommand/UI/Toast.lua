-- War Room notification presentation, placement and countdown.
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

-- Each event plate has a transparent silhouette. Slice only its horizontal
-- middle so the emblem and the right metal corners keep their native aspect.
local eventPlates={pvpKill='alertPvPKill',worldPvPDeath='alertDeath',bountyAlert='alertBounty',
 ctaNotice='alertCta',lfgNotice='alertLFG'}
local honors={
 warCelebration={base='secondaryNormal',badge='crestSmallMark',rim='bountyStandard'},
 warCelebrationHeroic={base='secondaryNormal',badge='warlord02',rim='bountyEpic'},
 warCelebrationLegendary={base='primaryNormal',badge='warlord01',rim='bountyLegendary'},
}

local function build(ch)
 local f=CreateFrame('Frame','KWC2Toast_'..ch.key,UIParent)
 f:SetSize(404,98)
 f:SetFrameStrata('HIGH');f:SetFrameLevel(40+#T.order);f:SetClampedToScreen(true);f:Hide()
 f:EnableMouse(true);f:SetMovable(true);f:RegisterForDrag('LeftButton')
 local plate=eventPlates[ch.key]
 local aspect=plate and S.AssetAspect(plate)
 local honor=honors[ch.key]
 local strips={}
 if plate then
  local uv=K.PublicThemes.Get('war-room-classic').assetUV[plate]
  local cuts={0,.37,.78,1}
  for i=1,3 do
   local t=f:CreateTexture(nil,'BACKGROUND')
   t:SetTexture(S.AssetPath(plate))
   t:SetTexCoord(uv[1]+(uv[2]-uv[1])*cuts[i],uv[1]+(uv[2]-uv[1])*cuts[i+1],uv[3],uv[4])
   t:SetPoint('TOPLEFT',i==1 and f or strips[i-1],i==1 and 'TOPLEFT' or 'TOPRIGHT')
   strips[i]=t
  end
 else
  local base=S.SliceAsset(f,honor and honor.base or 'secondaryNormal',14,256,'BACKGROUND',1,nil,16)
  if honor then
   if ch.key=='warCelebration' then
    for _,t in ipairs(base.textures) do t:SetVertexColor(.82,.70,.56) end
   end
   local rim=S.ThemedTexture(f,honor.rim,66,'BORDER',1);rim:SetPoint('LEFT',12,0)
   local badge=S.ThemedTexture(f,honor.badge,44,'ARTWORK',1);badge:SetPoint('CENTER',rim,'CENTER')
  else
   f.icon=f:CreateTexture(nil,'ARTWORK');f.icon:SetSize(40,40);f.icon:SetPoint('LEFT',16,0)
  end
 end
 f.kicker=Kit.Text(f,OWNER,'narrow',12,'accentText')
 f.title=Kit.Text(f,OWNER,'body',17,'text')
 f.detail=Kit.Text(f,OWNER,'body',13,'text')
 f.meta=Kit.Text(f,OWNER,'narrow',12,'muted')
 local lines={f.kicker,f.title,f.detail,f.meta}
 for _,line in ipairs(lines) do
  line:SetWordWrap(true)
  if line.SetNonSpaceWrap then line:SetNonSpaceWrap(true) end
 end
 f.close=CreateFrame('Button',nil,f);f.close:SetSize(18,18)
 f.close.t=Kit.Text(f.close,OWNER,'body',14,'muted');f.close.t:SetPoint('CENTER');f.close.t:SetText('x')
 f.close:SetScript('OnClick',function() f:Hide() end)
 f.close:SetScript('OnEnter',function(self) Kit.Paint(self.t,OWNER,'text','text') end)
 f.close:SetScript('OnLeave',function(self) Kit.Paint(self.t,OWNER,'muted','text') end)
 f.timer=f:CreateTexture(nil,'OVERLAY');f.timer:SetHeight(2)
 Kit.Paint(f.timer,OWNER,'accent','fill')
 f.hint=Kit.Text(f,OWNER,'narrow',12,'warn');f.hint:SetPoint('BOTTOM',f,'TOP',0,4)
 f.hint:SetText('Drag to position - lock it again in War Room > Alerts');f.hint:Hide()
 f.actions={}
 for i=1,4 do
  local b=S.Button(f,'',i==1 and 'primary' or 'secondary',function(self) if self.fn then self.fn() end end,120,24)
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
  if ch:Unlocked() then self:SetAlpha(ch:Opacity());self.timer:SetWidth(self.timerWidth or 1);return end
  self.elapsed=(self.elapsed or 0)+dt
  local life=ch:Duration()
  self.timer:SetWidth(math.max(1,(self.timerWidth or 1)*(1-self.elapsed/life)))
  local preferences=K.Celebrations and K.Celebrations.Preferences()
  if not preferences or (preferences.animations and not preferences.reducedMotion) then
   self:SetAlpha(ch:Opacity()*math.min(1,self.elapsed/0.16,math.max(0,(life-self.elapsed)/0.3)))
  else self:SetAlpha(ch:Opacity()) end
  if self.elapsed>=life then self:Hide() end
 end)
 -- Measure the actual strings at the channel's logical width. The configured
 -- scale applies to the completed composition, including its artwork and controls.
 function f:LayoutContent()
  local target=self.preferredWidth or 404
  local left=honor and 91 or 68
  local right=18
  local width=plate and target-134 or target-left-right
  local rowWidth=math.floor((width-6)/2)
  local actions=0
  for _,button in ipairs(self.actions) do if button:IsShown() then actions=actions+1 end end
  local offsets={}
  local used=0
  for i,line in ipairs(lines) do
   line:SetWidth(width-(used==0 and 22 or 0));line:SetHeight(0)
   if (line:GetText() or '')~='' then
    if used>0 then used=used+2 end
    offsets[i]=used
    local height=math.ceil(line:GetStringHeight())+1
    line:SetHeight(height);used=used+height
   end
  end
  local actionTop=used+5
  if actions>0 then used=actionTop+math.ceil(actions/2)*27-3 end
  local h,top
  if plate then
   -- The common clear field is between 28% and 72% of the cropped art.
   h=math.max(116,math.ceil((used+8)/.44))
   local nativeWidth=h*aspect
   left=math.ceil(nativeWidth*.38);right=math.ceil(nativeWidth*.057)
   local w=math.max(left+width+right,nativeWidth*.59+8)
   local capL,capR=nativeWidth*.37,nativeWidth*.22
   strips[1]:SetSize(capL,h);strips[2]:SetSize(w-capL-capR,h);strips[3]:SetSize(capR,h)
   self:SetSize(w,h)
   top=math.floor(h*.28+(h*.44-used-6)/2)
   self.timerY=h*.72-2
  else
   h=math.max(90,used+34);self:SetSize(target,h)
   top=math.floor((h-used)/2)-1;self.timerY=h-9
  end
  for i,line in ipairs(lines) do
   line:ClearAllPoints();line:SetPoint('TOPLEFT',self,'TOPLEFT',left,-top-(offsets[i] or 0))
  end
  self.close:ClearAllPoints();self.close:SetPoint('TOPRIGHT',self,'TOPRIGHT',-right,-top)
  local slot=0
  for _,button in ipairs(self.actions) do
   if button:IsShown() then
    button:SetSize(math.min(136,rowWidth),24);button:ClearAllPoints()
    button:SetPoint('TOPLEFT',self,'TOPLEFT',left+(slot%2)*(math.min(136,rowWidth)+6),-top-actionTop-math.floor(slot/2)*27)
    slot=slot+1
   end
  end
  self.timerWidth=width;self.timer:ClearAllPoints()
  self.timer:SetPoint('TOPLEFT',self,'TOPLEFT',left,-self.timerY);self.timer:SetWidth(width)
 end
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
 else
  local slot=self.defaultSlot
  if self:Unlocked() then
   local column=math.floor(slot/4)
   f:SetPoint('TOP',UIParent,'TOP',(column==0 and -1 or 1)*math.min(230,UIParent:GetWidth()/4),-100-(slot%4)*150)
  else f:SetPoint('TOP',UIParent,'TOP',0,-120-(slot%5)*112) end
 end
 f:SetScale(Kit.Clamp(tonumber(v[self.key..'Scale']) or 1,0.5,2))
 f.hint:SetShown(self:Unlocked())
end
function Channel:SetUnlocked(on)
 local v=settings();if not v then return end
 v[self.key..'Unlocked']=on and true or false
 self:Initialize()
 if on then if self.demo then self.demo() end else self.frame:Hide() end
end
function Channel:Scale()
 local v=settings() or {}
 return Kit.Clamp(tonumber(v[self.key..'Scale']) or 1,0.5,2)
end
function Channel:SetScale(value)
 local v=settings();if not v then return end
 v[self.key..'Scale']=Kit.Clamp(tonumber(value) or 1,0.5,2)
 self:Initialize()
end
function Channel:Opacity()
 local v=settings() or {}
 return Kit.Clamp(tonumber(v[self.key..'Opacity']) or 1,0.25,1)
end
function Channel:SetOpacity(value)
 local v=settings();if not v then return end
 v[self.key..'Opacity']=Kit.Clamp(tonumber(value) or 1,0.25,1)
 self.frame:SetAlpha(self:Opacity())
end
function Channel:Reset()
 local v=settings();if not v then return end
 v[self.key..'Position']=nil;v[self.key..'Scale']=nil;v[self.key..'Opacity']=nil;self.frame:SetAlpha(1)
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
 if automatic and self:Unlocked() then return false end
 if automatic and K.InstanceAlerts and not K.InstanceAlerts.Allowed() then return false end
 if automatic and not T.Claim(self.key,content.eventID) then return false end
 local f=self.frame
 local tone=content.tone or self.tone or 'accent'
 Kit.Paint(f.timer,OWNER,tone,'fill')
 Kit.Paint(f.kicker,OWNER,tone=='accent' and 'accentText' or tone,'text')
 if f.icon then f.icon:SetTexture(content.icon or ICONS[self.icon] or ICONS.cta) end
 f.kicker:SetText((content.kicker or ''):upper())
 f.title:SetText(content.title or '')
 f.detail:SetText(content.detail or '')
 f.meta:SetText(content.meta or '')
 for i,b in ipairs(f.actions) do
  local a=content.actions and content.actions[i]
  if a then b:SetLabel(a.label);b.fn=a.fn;b:Show() else b.fn=nil;b:Hide() end
 end
 f:LayoutContent()
 if T.Decorate then Kit.Safe(T.Decorate,self,content) end
 self.automatic=automatic==true
 f.elapsed=0;f:SetAlpha(self:Opacity())
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
function T.Notice(kind,title,detail,action,eventID,kicker)
 local ch=T.channels[kind];if not ch or not ch:Enabled() then return false end
 local now=time and time() or 0
 local key=kind..'\001'..tostring(eventID or title)
 if recent[key] and now-recent[key]<20 then return false end
 for id,at in pairs(recent) do if now-at>=20 then recent[id]=nil end end
 recent[key]=now
 ch:Present({eventID=eventID,kicker=kicker or ch.label,title=title,detail=detail,actions=action and {action} or nil},true)
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
   if ch.automatic and ch.frame:IsShown() then ch.frame:Hide() end
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
