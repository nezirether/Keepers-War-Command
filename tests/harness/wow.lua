-- KWC 2.0 headless harness (Lua 5.1 / LuaJIT).
-- Loads the real add-on files listed in each TOC, in TOC order, into one
-- sandboxed environment per simulated client. Clients share a guild roster
-- (with Player GUIDs) and an addon-message bus. Time, timers, OnUpdate and
-- events are driven by the world clock. This is a SIMULATION: it proves Lua
-- loads, logic and message handling; it does not prove in-game rendering.
local H={}
local ROOT=(...) or '.'

local function readToc(path)
 local files,meta={},{}
 for line in io.lines(path) do
  line=line:gsub('\r','')
  local k,v=line:match('^##%s*([%w%-]+):%s*(.-)%s*$')
  if k then meta[k]=v
  elseif line:match('%S') and not line:match('^#') then files[#files+1]=line:match('^%s*(.-)%s*$') end
 end
 return files,meta
end
H.ReadToc=readToc


-- WoW provides a global `bit` library; LuaJIT has one built in. Plain Lua 5.1
-- does not, so provide a small arithmetic implementation for the 5.1 runs.
local bitlib=rawget(_G,'bit')
if not bitlib then
 local function tobits(op)
  return function(a,b)
   a,b=a%4294967296,(b or 0)%4294967296
   local r,p=0,1
   for _=1,32 do
    local x,y=a%2,b%2
    if op(x,y) then r=r+p end
    a,b,p=(a-x)/2,(b-y)/2,p*2
   end
   return r
  end
 end
 bitlib={band=tobits(function(x,y) return x==1 and y==1 end),bor=tobits(function(x,y) return x==1 or y==1 end),
  bxor=tobits(function(x,y) return x~=y end)}
 bitlib.bnot=function(a) return 4294967295-(a%4294967296) end
 bitlib.lshift=function(a,n) return (a*2^n)%4294967296 end
 bitlib.rshift=function(a,n) return math.floor((a%4294967296)/2^n) end
 bitlib.arshift=bitlib.rshift
 bitlib.tobit=function(a) return a end
end
H.bit=bitlib
-- Libraries that read getfenv(0) see the process globals, not the sandbox.
if not rawget(_G,"bit") then rawset(_G,"bit",bitlib) end

local World={};World.__index=World
function H.World(opts)
 opts=opts or {}
 local w=setmetatable({now=opts.now or 1795000000,clients={},bus={},roster={},guildID=opts.guildID or 4242,
  timers={},log={},delivered=0,guildName=opts.guildName or 'Keepers of Trogdor'},World)
 return w
end
-- roster entry: {name='Ash Ember', rank=0..9, guid='Player-1-0000000A', online=true, level=60, class='Warrior'}
function World:AddMember(m)
 m.rank=m.rank or 3;m.online=m.online~=false;m.level=m.level or 60;m.class=m.class or 'Warrior'
 self.roster[#self.roster+1]=m;return m
end
function World:Member(name) for _,m in ipairs(self.roster) do if m.name==name then return m end end end
function World:Rename(oldName,newName)
 local m=self:Member(oldName);assert(m,'no member '..oldName)
 m.name=newName
 for _,c in ipairs(self.clients) do if c.name==oldName then c.name=newName end end
 return m
end
function World:RemoveMember(name)
 for i,m in ipairs(self.roster) do if m.name==name then table.remove(self.roster,i);return end end
end

local noop=function() end
-- Widget factory shared by all object types.
local function makeWidgetSystem(client)
 local methods={}
 local all={}
 local function widget(kind,parent,name)
  local o=setmetatable({kind=kind,parent=parent,name=name,shown=kind~='Frame' or true,scripts={},hooks={},children={},points={},
   width=0,height=0,text='',alpha=1,scale=1,events={}},{__index=function(t,k)
    local m=methods[k];if m then return m end
    if type(k)=='string' and k:match('^%u') then return noop end
   end})
  if parent and parent.children then parent.children[#parent.children+1]=o end
  all[#all+1]=o
  return o
 end
 client.allWidgets=all
 function methods:CreateTexture() local t=widget('Texture',self);t.shown=true;return t end
 function methods:CreateFontString() local t=widget('FontString',self);t.shown=true;return t end
 function methods:CreateLine() return widget('Line',self) end
 function methods:SetText(t) self.text=t==nil and '' or tostring(t) end
 function methods:GetText() return self.text end
 function methods:SetFont(f,s,fl) self.font,self.fontSize,self.fontFlags=f,s,fl;return true end
 function methods:GetFont() return self.font,self.fontSize,self.fontFlags end
 function methods:GetStringWidth() return #(self.text or '')*((self.fontSize or 12)*0.5) end
 function methods:GetStringHeight()
  local size=self.fontSize or 12
  local cols=math.max(1,math.floor((self.width>0 and self.width or 300)/(size*0.5)))
  local rows=0
  for line in ((self.text or '')..'\n'):gmatch('([^\n]*)\n') do rows=rows+math.max(1,math.ceil(#line:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')/cols)) end
  return rows*(size+2)
 end
 function methods:SetSize(w,h) self.width,self.height=w,h;self:_sized() end
 function methods:SetWidth(w) self.width=w;self:_sized() end
 function methods:SetHeight(h) self.height=h;self:_sized() end
 function methods:_sized() local f=self.scripts.OnSizeChanged;if f and not self._insize then self._insize=true;pcall(f,self,self.width,self.height);self._insize=false end end
 function methods:GetWidth() return self.width end
 function methods:GetHeight()
  if self.height>0 then return self.height end
  if not self.parent then return 0 end
  local top,bottom
  for _,point in ipairs(self.points) do
   if point[1]=='ALL' then return (point[2] or self.parent):GetHeight() end
   if point[1]=='TOPLEFT' or point[1]=='TOPRIGHT' then top=point end
   if point[1]=='BOTTOMLEFT' or point[1]=='BOTTOMRIGHT' then bottom=point end
  end
  if top and bottom and (not bottom[2] or bottom[2]==self.parent) then
   local offset=top[5]-bottom[5]
   if top[2] and top[2]~=self.parent and (top[3] or ''):find('BOTTOM',1,true) then
    offset=offset-top[2]:GetHeight()
   end
   return math.max(0,self.parent:GetHeight()+offset)
  end
  return 0
 end
 function methods:GetSize() return self.width,self.height end
 function methods:SetPoint(p,rel,rp,x,y)
  if type(rel)=='number' then rel,rp,x,y=nil,nil,rel,rp end
  self.points[#self.points+1]={p,rel,rp,x or 0,y or 0}
  -- Approximate geometry for layout helpers: anchoring to both left and right of
  -- the parent stretches width.
  if self.parent and (p=='RIGHT' or p=='TOPRIGHT' or p=='BOTTOMRIGHT') and self.width==0 and self.parent.width then self.width=self.parent.width end
 end
 function methods:SetAllPoints(rel) local r=rel or self.parent;if r then self.width,self.height=r.width,r.height end;self.points[#self.points+1]={'ALL',r} end
 function methods:ClearAllPoints() self.points={} end
 function methods:GetPoint(i) local p=self.points[i or 1];if p then return p[1],p[2],p[3],p[4],p[5] end;return 'CENTER',nil,'CENTER',0,0 end
 function methods:GetNumPoints() return #self.points end
 function methods:Show() local was=self.shown;self.shown=true;if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
 function methods:Hide() local was=self.shown;self.shown=false;if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
 function methods:SetShown(v) if v then self:Show() else self:Hide() end end
 function methods:IsShown() return self.shown and true or false end
 function methods:IsVisible() local f=self;while f do if not f.shown then return false end;f=f.parent end;return true end
 function methods:SetAlpha(a) self.alpha=a end
 function methods:GetAlpha() return self.alpha end
 function methods:SetScale(s) self.scale=s end
 function methods:GetScale() return self.scale end
 function methods:GetEffectiveScale() return self.scale end
 function methods:GetParent() return self.parent end
 function methods:SetParent(p) self.parent=p end
 function methods:GetName() return self.name end
 function methods:SetScript(ev,fn) self.scripts[ev]=fn end
 function methods:GetScript(ev) return self.scripts[ev] end
 function methods:HookScript(ev,fn)
  local prev=self.scripts[ev]
  self.scripts[ev]=function(...) if prev then prev(...) end;return fn(...) end
 end
 function methods:RegisterEvent(ev) self.events[ev]=true;client.eventFrames[self]=true end
 function methods:UnregisterEvent(ev) self.events[ev]=nil end
 function methods:UnregisterAllEvents() self.events={} end
 function methods:IsEventRegistered(ev) return self.events[ev]==true end
 function methods:GetChildren() return unpack(self.children) end
 function methods:GetRegions() return end
 function methods:GetFrameLevel() return self.level or 1 end
 function methods:SetFrameLevel(l) self.level=l end
 function methods:GetFrameStrata() return self.strata or 'MEDIUM' end
 function methods:SetFrameStrata(s) self.strata=s end
 function methods:GetCenter() return 500,400 end
 function methods:GetLeft() return 0 end
 function methods:GetRight() return self.width end
 function methods:GetTop() return 800 end
 function methods:GetBottom() return 0 end
 function methods:IsMouseOver() return false end
 function methods:HasFocus() return self.focus==true end
 function methods:SetFocus() self.focus=true;if self.scripts.OnEditFocusGained then self.scripts.OnEditFocusGained(self) end end
 function methods:ClearFocus() if self.focus then self.focus=false;if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end end end
 function methods:GetVerticalScroll() return self.vscroll or 0 end
 function methods:SetVerticalScroll(v) self.vscroll=v end
 function methods:GetVerticalScrollRange() return 0 end
 function methods:GetHorizontalScroll() return self.hscroll or 0 end
 function methods:SetHorizontalScroll(v) self.hscroll=v end
 function methods:GetHorizontalScrollRange() return 0 end
 function methods:SetScrollChild(c) self.child=c end
 function methods:GetScrollChild() return self.child end
 function methods:GetNumber() return tonumber(self.text) or 0 end
 function methods:SetChecked(v) self.checked=v end
 function methods:GetChecked() return self.checked end
 function methods:SetValue(v) self.value=v end
 function methods:GetValue() return self.value or 0 end
 function methods:GetMinMaxValues() return 0,100 end
 function methods:IsEnabled() return self.disabled~=true end
 function methods:Enable() self.disabled=false end
 function methods:Disable() self.disabled=true end
 function methods:SetEnabled(v) self.disabled=not v end
 function methods:GetFontString() self.fs=self.fs or widget('FontString',self);return self.fs end
 function methods:GetTexture() return self.texture end
 function methods:SetTexture(t) self.texture=t;if type(t)=='string' then client.textures[t]=true end end
 function methods:GetObjectType() return self.kind end
 function methods:IsObjectType(t) return self.kind==t end
 function methods:IsForbidden() return false end
 function methods:Click(button) if self.scripts.OnClick then self.scripts.OnClick(self,button or 'LeftButton') end end
 function methods:SetMinResize() end
 for _,st in ipairs({'Normal','Pushed','Disabled','Highlight','Checked','DisabledChecked'}) do methods['Get'..st..'Texture']=function(self) self['_'..st]=self['_'..st] or widget('Texture',self);return self['_'..st] end end
 function methods:SetupMenu(cb) self.menu=cb end
 function methods:RegisterCallback(ev,fn) self.callbacks=self.callbacks or {};self.callbacks[ev]=fn end
 function methods:GetNumLines() return 0 end
 function methods:GetMaxLetters() return 255 end
 client.widget=widget
 return widget,methods
end

local function deepcopy(v,seen)
 if type(v)~='table' then return v end
 seen=seen or {}
 if seen[v] then return seen[v] end
 local r={};seen[v]=r
 for k,x in pairs(v) do r[deepcopy(k,seen)]=deepcopy(x,seen) end
 return r
end
H.DeepCopy=deepcopy

-- Creates a client. opts: {addons={'KeepersWarCommand',...}, saved={...}, realm='Forever'}
function World:Client(name,opts)
 opts=opts or {}
 local world=self
 local member=self:Member(name)
 local c={name=name,world=world,prefixes={},eventFrames={},textures={},errors={},printed={},timers={},loaded={},saved=opts.saved}
 local widget=makeWidgetSystem(c)
 local env={}
 c.env=env
 setmetatable(env,{__index=function(_,k) return _G[k] end})
 env._G=env
 env.bit=bitlib
 env.print=function(...) local t={};for i=1,select('#',...) do t[#t+1]=tostring((select(i,...))) end;c.printed[#c.printed+1]=table.concat(t,' ') end
 env.time=function(t) if t then return os.time(t) end;return world.now end
 env.GetTime=function() return world.now end
 env.GetServerTime=env.time
 env.date=function(fmt,t) return os.date(fmt,t or world.now) end
 env.debugprofilestop=function() return world.now*1000 end
 env.wipe=function(t) for k in pairs(t) do t[k]=nil end;return t end
 env.tinsert=table.insert;env.tremove=table.remove
 env.strsplit=function(sep,s,n) local out={};for p in (s..sep):gmatch('(.-)'..sep:gsub('%p','%%%0')) do out[#out+1]=p end;return unpack(out) end
 env.strtrim=function(s) return (s:match('^%s*(.-)%s*$')) end
 env.format=string.format;env.strlower=string.lower;env.strupper=string.upper;env.strsub=string.sub;env.strfind=string.find;env.strlen=string.len;env.strmatch=string.match;env.gsub=string.gsub
 env.floor=math.floor;env.ceil=math.ceil;env.max=math.max;env.min=math.min;env.abs=math.abs
 env.hooksecurefunc=function(a,b,c2) if type(a)=='table' then local o=a[b];a[b]=function(...) local r={o(...)};c2(...);return unpack(r) end else local o=env[a];env[a]=function(...) local r={o and o(...)};b(...);return unpack(r) end end end
 env.UISpecialFrames={};env.SlashCmdList={};env.STANDARD_TEXT_FONT='Fonts\\FRIZQT__.TTF'
 env.UIParent=widget('Frame',nil,'UIParent');env.UIParent.width,env.UIParent.height=1920,1080
 env.WorldFrame=widget('Frame',nil,'WorldFrame')
 env.Minimap=widget('Frame',env.UIParent,'Minimap');env.Minimap.width,env.Minimap.height=140,140
 env.GameTooltip=widget('GameTooltip',env.UIParent,'GameTooltip')
 env.UIErrorsFrame=widget('Frame',env.UIParent,'UIErrorsFrame')
 env.DEFAULT_CHAT_FRAME=widget('Frame',env.UIParent,'ChatFrame1')
 env.ChatFontNormal={isFontObject=true}
 env.GameFontNormal={isFontObject=true};env.GameFontHighlight={isFontObject=true};env.GameFontNormalSmall={isFontObject=true}
 env.CreateFont=function(name) local f=widget('Font');f.isFontObject=true;if name then env[name]=f end;return f end
 for _,n in ipairs({'GameFontHighlight','GameFontHighlightSmall','GameFontHighlightLarge','GameFontNormalLarge','GameFontDisable','GameFontDisableSmall'}) do local f=widget('Font');f.isFontObject=true;env[n]=f end
 env.MinimalSliderWithSteppersMixin={Event={OnValueChanged='OnValueChanged'}}
 env.CreateColor=function(r,g,b,a) return {r=r,g=g,b=b,a=a,GetRGBA=function() return r,g,b,a end,GetRGB=function() return r,g,b end} end
 env.CopyTable=function(t) return deepcopy(t) end
 env.GetCVar=function() return '0' end
 env.GetTimePreciseSec=function() return world.now end
 env.C_SpecializationInfo={GetSpecialization=function() return nil end}
 env.C_PlayerInfo={}
 env.C_UnitAuras={}
 env.GetInventoryItemLink=function() return nil end
 env.GetInventoryItemID=function() return nil end
 env.GetSpellTexture=function() return 123 end
 env.ChatFrameUtil=nil
 env.Ambiguate=function(n) return (n:match('^[^-]+')) end
 env.GetFramerate=function() return 60 end
 env.SetDontSavePosition=noop
 env.StaticPopupDialogs={};env.StaticPopup_Show=function(n) c.popup=n end;env.StaticPopup_Hide=noop;env.YES='Yes';env.NO='No';env.OKAY='Okay';env.CANCEL='Cancel';env.ACCEPT='Accept'
 env.CreateFrame=function(kind,name,parent,template)
  local f=widget(kind or 'Frame',parent,name)
  f.template=template
  if name then env[name]=f end
  if kind=='EditBox' then f.text='' end
  if type(template)=='string' then
   if template:find('ScrollFrame') then
    f.ScrollBar=widget('Slider',f);f.ScrollBar.ThumbTexture=widget('Texture',f.ScrollBar)
    f.ScrollBar.ScrollUpButton=widget('Button',f.ScrollBar);f.ScrollBar.ScrollDownButton=widget('Button',f.ScrollBar)
   end
   if template:find('CloseButton') or template:find('ButtonTemplate') then f.Text=widget('FontString',f) end
   if template:find('CheckButton') or template:find('Checkbox') then f.Text=widget('FontString',f);f.text=f.Text end
   if template:find('InputBox') then f.Left=widget('Texture',f);f.Right=widget('Texture',f);f.Middle=widget('Texture',f) end
   if template=='UIPanelScrollBarTemplate' then f.ThumbTexture=widget('Texture',f);f.ScrollUpButton,f.ScrollDownButton=widget('Button',f),widget('Button',f) end
   if template=='MinimalSliderWithSteppersTemplate' then f.Slider=widget('Slider',f) end
   if template=='ColorSwatchTemplate' then f.Color=widget('Texture',f) end
   if template:find('Dropdown') then f.Background,f.Arrow,f.Text=widget('Texture',f),widget('Texture',f),widget('FontString',f) end
  end
  return f
 end
 env.InCombatLockdown=function() return c.combat==true end
 env.UnitAffectingCombat=function() return c.combat==true end
 env.IsInGuild=function() return c.inGuild~=false end
 env.GetGuildInfo=function(unit)
  if c.inGuild==false then return nil end
  local m=world:Member(c.name);return world.guildName,m and ('Rank'..m.rank) or 'Member',m and m.rank or 9
 end
 env.GetNumGuildMembers=function() if c.inGuild==false then return 0,0 end;return #world.roster,#world.roster end
 env.GetGuildRosterInfo=function(i)
  local m=world.roster[i];if not m or c.inGuild==false then return nil end
  return m.name,'Rank'..m.rank,m.rank,m.level,m.class,'Orgrimmar','','',m.online,0,m.class:upper(),0,0,false,false,0,m.guid
 end
 env.GuildRoster=noop
 env.C_GuildInfo={GuildRoster=function() c.rosterRequested=true end}
 env.C_Club={GetGuildClubId=function() if c.inGuild==false then return nil end;return c.guildID or world.guildID end,GetMemberInfoForSelf=function() return nil end}
 env.CanGuildInvite=function() local m=world:Member(c.name);return m and m.rank<=1 end
 env.UnitName=function(unit)
  if unit=='player' then return c.name end
  if unit=='target' and c.target then return c.target.name end
  return nil
 end
 env.UnitFullName=env.UnitName
 env.GetUnitName=function(unit) return env.UnitName(unit) end
 env.UnitGUID=function(unit)
  if unit=='player' then local m=world:Member(c.name);return m and m.guid or c.guid end
  if unit=='target' and c.target then return c.target.guid end
 end
 env.UnitExists=function(unit) return unit=='player' or (unit=='target' and c.target~=nil) end
 env.UnitIsPlayer=function(unit) return env.UnitExists(unit) end
 env.UnitIsUnit=function(a,b) return a==b end
 env.UnitIsConnected=function() return true end
 env.UnitIsDeadOrGhost=function() return c.dead==true end
 env.UnitIsDead=env.UnitIsDeadOrGhost
 env.UnitFactionGroup=function(unit) if unit=='target' and c.target then return c.target.faction or 'Alliance' end;return 'Horde' end
 env.UnitLevel=function() return 60 end
 env.UnitIsEnemy=function(a,unit) local u=unit or a;return u=='target' and c.target~=nil and (c.target.faction or 'Alliance')~='Horde' end
 env.UnitCanAttack=function(a,b) return env.UnitIsEnemy('player',b) end
 env.UnitIsFriend=function(a,b) return not env.UnitIsEnemy('player',b) end
 env.UnitReaction=function() return 2 end
 env.UnitClass=function() return 'Warrior','WARRIOR' end
 env.UnitRace=function() return 'Orc','Orc' end
 env.UnitHealth=function() return 100 end;env.UnitHealthMax=function() return 100 end
 env.UnitIsGroupLeader=function() return c.groupLeader==true end
 env.UnitIsGroupAssistant=function() return false end
 env.UnitGroupRolesAssigned=function() return 'NONE' end
 env.GetNormalizedRealmName=function() return opts.realm or 'Forever' end
 env.GetRealmName=env.GetNormalizedRealmName
 env.IsInRaid=function() return false end
 env.IsInGroup=function() return c.inGroup==true end
 env.GetNumGroupMembers=function() return c.inGroup and 2 or 0 end
 env.GetNumSubgroupMembers=function() return 0 end
 env.IsInInstance=function() if c.instance then return true,c.instance end;return false,'none' end
 env.GetInstanceInfo=function() return c.instance and 'Dungeon' or 'Hillsbrad Foothills',c.instance or 'none',0,'',5,0,false,0 end
 env.GetRealZoneText=function() return c.zone or 'Hillsbrad Foothills' end
 env.GetZoneText=env.GetRealZoneText;env.GetSubZoneText=function() return '' end
 env.GetMinimapZoneText=env.GetRealZoneText
 env.GetCursorPosition=function() return 0,0 end
 env.PlaySound=function(id) c.sounds=(c.sounds or 0)+1 end
 env.PlaySoundFile=env.PlaySound
 env.GetStatistic=function(id) return c.stats and c.stats[id] or '--' end
 env.GetPVPLifetimeStats=function() return c.lifetimeHK or 0 end
 env.GetPVPSessionStats=function() return c.sessionHK or 0,0 end
 env.GetLocale=function() return 'enUS' end
 env.GetBuildInfo=function() return '1.60.1','00000','Nov 2026',16001 end
 env.GetAddOnMetadata=function(addon,key) return key=='Version' and '2.0.0-alpha.2' or nil end
 env.C_AddOns={IsAddOnLoaded=function(n) return c.loaded[n]==true end,GetAddOnMetadata=env.GetAddOnMetadata}
 env.IsAddOnLoaded=function(n) return c.loaded[n]==true end
 env.ChatFrame_OpenChat=function(text) c.chatDraft=text end
 env.SendChatMessage=function(msg,kind,lang,target) c.chatSent=c.chatSent or {};c.chatSent[#c.chatSent+1]={msg=msg,kind=kind,target=target};return true end
 env.C_FriendList={SendWho=function(q) c.whoQuery=q end,GetNumWhoResults=function() return #(c.whoResults or {}),#(c.whoResults or {}) end,
  GetWhoInfo=function(i) return c.whoResults and c.whoResults[i] end,SetWhoToUi=noop}
 env.C_Map={GetBestMapForUnit=function() return c.mapID end,GetPlayerMapPosition=function() if c.mapID then return {x=c.mapX,y=c.mapY} end end,
  SetUserWaypoint=function(p) c.waypoint=p end}
 env.UiMapPoint={CreateFromCoordinates=function(m,x,y) return {m=m,x=x,y=y} end}
 env.C_SuperTrack={SetSuperTrackedUserWaypoint=noop}
 env.C_DateAndTime={GetCurrentCalendarTime=function() local t=os.date('*t',world.now);return {year=t.year,month=t.month,monthDay=t.day,hour=t.hour,minute=t.min,weekday=t.wday} end,
  AdjustTimeByDays=function(d,o) local t=os.time({year=d.year,month=d.month,day=d.monthDay,hour=12})+o*86400;local x=os.date('*t',t);return {year=x.year,month=x.month,monthDay=x.day,hour=d.hour,minute=d.minute or 0} end}
 env.C_Timer={After=function(s,fn) table.insert(world.timers,{at=world.now+s,fn=fn,client=c}) end,
  NewTimer=function(s,fn) local t={at=world.now+s,fn=fn,client=c};function t:Cancel() self.cancelled=true end;table.insert(world.timers,t);return t end,
  NewTicker=function(s,fn,n) local t={every=s,at=world.now+s,fn=fn,client=c,left=n};function t:Cancel() self.cancelled=true end;table.insert(world.timers,t);return t end}
 env.Enum={SendAddonMessageResult={Success=0,AddonMessageThrottle=3,NotInGroup=5,ChannelThrottle=8,GeneralError=9}}
 env.C_ChatInfo={
  RegisterAddonMessagePrefix=function(p) c.prefixes[p]=true;return true end,
  IsAddonMessagePrefixRegistered=function(p) return c.prefixes[p]==true end,
  InChatMessagingLockdown=function() return c.lockdown==true end,
  SendAddonMessage=function(prefix,msg,channel,target)
   assert(type(msg)=='string' and #msg<=255,'addon message too long: '..tostring(#msg))
   world.bus[#world.bus+1]={prefix=prefix,msg=msg,channel=channel,target=target,from=c}
   world.sentCount=(world.sentCount or 0)+1
   c.sent=(c.sent or 0)+1
   return 0
  end,
 }
 env.SendAddonMessage=env.C_ChatInfo.SendAddonMessage
 env.RegisterAddonMessagePrefix=env.C_ChatInfo.RegisterAddonMessagePrefix
 env.C_Spell={GetSpellName=function(id) return 'Spell '..id end}
 env.GetSpellInfo=function(id) return 'Spell '..tostring(id) end
 env.C_Item={GetItemNameByID=function(id) return 'Item '..id end}
 env.GetItemInfo=function(id) return 'Item '..tostring(id) end
 env.GetNumSkillLines=function() return 0 end
 env.GetProfessions=function() return nil end
 env.GetNumTradeSkills=function() return 0 end
 env.C_TradeSkillUI=nil
 env.GetAchievementInfo=function() return nil end
 env.GetCategoryList=function() return {} end
 env.GetCategoryNumAchievements=function() return 0 end
 env.GetComparisonStatistic=function() return '--' end
 env.C_DeathRecap={GetRecapEvents=function() return c.recap end}
 env.C_NamePlate={GetNamePlates=function() return {} end}
 env.C_PartyInfo={InviteUnit=function(n) c.invited=c.invited or {};c.invited[#c.invited+1]=n;return true end}
 env.InviteUnit=env.C_PartyInfo.InviteUnit
 env.GetRaidRosterInfo=function() return nil end
 env.CalendarGetDate=nil
 env.SOUNDKIT={}
 env.ERR_GUILD_INVITE_S='You have invited %s to join your guild.'
 env.ERR_ALREADY_IN_GUILD_S='%s is already in a guild.'
 env.ERR_ALREADY_INVITED_TO_GUILD_S='%s has already been invited to a guild.'
 env.ERR_GUILD_DECLINE_S='%s declines your guild invitation.'
 env.ERR_GUILD_DECLINE_AUTO_S='%s declines your guild invitation (auto).'
 env.COMBATLOG_HONORGAIN='%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)'
 env.UnitPosition=function() return nil end
 env.GetPlayerInfoByGUID=function(g) local n=world.guidNames and world.guidNames[g];if n then return 'Rogue','ROGUE','Human','Human',2,n,'' end;return nil end
 env.MenuUtil=nil;env.Menu=nil
 env.issecretvalue=nil
 -- Saved variables (persist across "reloads" through c.saved)
 if opts.saved then for k,v in pairs(opts.saved) do env[k]=deepcopy(v) end end
 c.loadFiles={}
 self.clients[#self.clients+1]=c
 return c
end

function World:LoadAddon(c,addonDir)
 local addon=addonDir:match('([^/]+)/?$')
 local toc=addonDir..'/'..addon..'.toc'
 local files=readToc(toc)
 for _,f in ipairs(files) do
  local path=addonDir..'/'..f:gsub('\\','/')
  local chunk,err=loadfile(path)
  if not chunk then error('LOAD '..path..': '..tostring(err)) end
  setfenv(chunk,c.env)
  local ok,e=pcall(chunk,addon,c.ns or {})
  if not ok then error('RUN '..f..': '..tostring(e)) end
  c.loadFiles[#c.loadFiles+1]=f
 end
 c.loaded[addon]=true
 self:Fire(c,'ADDON_LOADED',addon)
 return files
end

function World:Fire(c,event,...)
 local targets={}
 for f in pairs(c.eventFrames) do if f.events[event] and f.scripts.OnEvent then targets[#targets+1]=f end end
 for _,f in ipairs(targets) do
  local ok,err=pcall(f.scripts.OnEvent,f,event,...)
  if not ok then c.errors[#c.errors+1]=event..': '..tostring(err) end
 end
end
function World:FireAll(event,...) for _,c in ipairs(self.clients) do self:Fire(c,event,...) end end
function World:Login(c)
 self:Fire(c,'PLAYER_LOGIN')
 self:Fire(c,'PLAYER_ENTERING_WORLD',true,false)
 self:Fire(c,'GUILD_ROSTER_UPDATE')
end

-- Deliver queued addon messages. GUILD reaches every online guild client
-- (including the sender's own echo, as in game); WHISPER reaches the target.
function World:Pump()
 local n=0
 while #self.bus>0 do
  local m=table.remove(self.bus,1)
  local senderName=m.from.name
  for _,c in ipairs(self.clients) do
   local member=self:Member(c.name)
   local online=member and member.online and not c.offline
   local deliver=false
   if m.channel=='GUILD' then deliver=online and c.inGuild~=false and m.from.inGuild~=false
   elseif m.channel=='WHISPER' then deliver=online and m.target and (m.target:lower()==c.name:lower() or m.target:lower():match('^[^-]+')==c.name:lower())
   elseif m.channel=='PARTY' or m.channel=='RAID' or m.channel=='INSTANCE_CHAT' then deliver=online and c.inGroup and m.from.inGroup end
   if deliver and c.prefixes[m.prefix] then
    self:Fire(c,'CHAT_MSG_ADDON',m.prefix,m.msg,m.channel,senderName,c.name,0,0,'',0)
    n=n+1
   end
  end
 end
 self.delivered=self.delivered+n
 return n
end
-- Advance simulated time: timers, OnUpdate scripts and message delivery.
function World:Advance(seconds,step)
 step=step or 0.25
 local t=0
 while t<seconds do
  self.now=self.now+step;t=t+step
  for _,c in ipairs(self.clients) do
   if not c.offline then
    for _,f in ipairs(c.allWidgets) do
     local fn=f.scripts.OnUpdate
     if fn then local ok,err=pcall(fn,f,step);if not ok then c.errors[#c.errors+1]='OnUpdate: '..tostring(err) end end
    end
   end
  end
  local due={}
  for i=#self.timers,1,-1 do
   local tm=self.timers[i]
   if tm.cancelled then table.remove(self.timers,i)
   elseif tm.at<=self.now and not tm.client.offline then
    if tm.every and (tm.left==nil or tm.left>1) then tm.at=tm.at+tm.every;if tm.left then tm.left=tm.left-1 end else table.remove(self.timers,i) end
    due[#due+1]=tm
   end
  end
  for _,tm in ipairs(due) do local ok,err=pcall(tm.fn,tm);if not ok then tm.client.errors[#tm.client.errors+1]='Timer: '..tostring(err) end end
  self:Pump()
 end
end
-- Snapshot SavedVariables for a "reload".
function World:Saved(c,names)
 local out={}
 for _,n in ipairs(names) do out[n]=deepcopy(c.env[n]) end
 return out
end
function World:Drop(c) for i,x in ipairs(self.clients) do if x==c then table.remove(self.clients,i) end end;for i=#self.timers,1,-1 do if self.timers[i].client==c then table.remove(self.timers,i) end end end

-- Tiny test runner
H.results={}
function H.Check(name,cond,detail)
 H.results[#H.results+1]={name=name,ok=cond and true or false,detail=detail}
 print((cond and 'PASS ' or 'FAIL ')..name..(not cond and detail and ('  -- '..tostring(detail)) or ''))
 return cond
end
function H.Summary(label)
 local p,f=0,0
 for _,r in ipairs(H.results) do if r.ok then p=p+1 else f=f+1 end end
 print(('%s: %d passed, %d failed'):format(label or 'suite',p,f))
 return f==0
end
return H
