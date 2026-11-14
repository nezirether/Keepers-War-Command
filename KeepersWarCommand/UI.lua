local K=KWC;local U={};K.UI=U
local scrollChild
local navButtons={}
local navScroll,navChild=nil,nil
local frame,body,scroll,header,active=nil,nil,nil,nil,'Home'
local boardFilter={CTA='ACTIVE',BOUNTY='ACTIVE'}
local recruitmentRefresh, recruitmentQuery, recruitmentPitch
local pvpView='lifetime'
local rosterQuery,checkerQuery='',''
local function safeScale(value)
 local n=tonumber(value) or 1
 if n<0.65 then n=0.65 elseif n>1.35 then n=1.35 end
 return math.floor(n*100+0.5)/100
end
-- Keep the full window inside the viewport, leaving room for action bars.
local function fitScale(requested)
 local width=UIParent and UIParent:GetWidth() or 1024
 local height=UIParent and UIParent:GetHeight() or 768
 local maxScale=math.min((width-24)/860,(height-100)/680)
 return math.max(0.50,math.min(safeScale(requested),maxScale))
end
function U.SetScale(value)
 if not KWCDB then return end
 KWCDB.settings=KWCDB.settings or {}
 local n=safeScale(value)
 KWCDB.settings.windowScale=n
 if frame then frame:SetScale(fitScale(n)) end
 K.Say('Window scale: '..math.floor(n*100+0.5)..'%. Use /kt scale 100 to reset.')
end
function U.GetScale()
 return safeScale(KWCDB and KWCDB.settings and KWCDB.settings.windowScale)
end

local render
local surface
local pendingSetting,focusedSetting
local function navigate(page)
 pendingSetting,focusedSetting=nil,nil
 if page~=active then scroll:SetVerticalScroll(0) end
 active=page
 render()
end
local editingKind,editingId=nil,nil
local pendingBountyTarget=nil
local selectedCTA=nil
local selectedBounty=nil
local bountyCapture
local selectedAAR=nil
local C=K.UITheme
local FONT=C.font
local settingsQuery,settingsCategory='',''
local alertSelection='death'
local settingIndex={
 {'Window Scale','Interface & Minimap','Change the size of the War Command window.','Settings',-410,'Account-wide'},
 {'Minimap Launcher','Interface & Minimap','Show or hide the launcher and reset its position.','Settings',-226,'Account-wide'},
 {'Guild Services Sharing','Guild & Sharing','Share profession skills and observed recipes.','Settings',-149,'Character and guild'},
 {'Automatic Guild Synchronization','Sync & Network','Control automatic shared-record requests.','Settings',-274,'Account-wide'},
 {'Sync Health','Sync & Network','Inspect board, PvP, and transport outcomes.','Sync Health',-12},
 {'Auto Scout','World PvP','Share observed enemy activity with guildmates.','Settings',-274,'Account-wide','autoscout',264},
 {'Alert Sound','Alerts','Turn all alert sounds on or off.','Alerts',-53,'Account-wide'},
 {'Guild Death Alerts','Alerts','Manage popup, sound, position, size, and duration.','Alerts',-95,'Account-wide',nil,253,'death'},
 {'Smart Mode','World PvP','Set the death threshold, detection window, and quiet period.','Alerts',-640,'Account-wide','guild death',253,'death'},
 {'Bounty Alerts','Alerts','Manage bounty target popup, sound, and preview.','Alerts',-95,'Account-wide',nil,253,'bounty'},
 {'Call to Arms Chat Alerts','Alerts','Show incoming Calls to Arms in chat.','Alerts',-102,'Account-wide','cta',253,'calls'},
 {'Battle Resurrection','Raids','Enable the raid-only indicator and adjust its layout.','Raid Tools: Battle Resurrection',-14,'Account-wide','battle rez brez'},
 {'Ready Check','Raids','Manage readiness notifications and display.','Raid Tools: Ready Check Advanced',-14},
 {'Combat Tools','Raids','Configure raid combat displays.','Raid Tools: Combat Tools',-14},
 {'Automatic Invitations','Raids','Manage whisper invitations and conditions.','Raid Tools: Auto-Invite',-14},
 {'Death Protection','Raids','Adjust raid release protection.','Raid Tools: Don\'t Release',-14},
 {'Addon Checker','Advanced','View versions reported by compatible guildmates.','Addon Checker',-12},
 {'Ready Check Sounds','Raids','Configure readiness sound and notification preferences.','Raid Tools: Ready Check Advanced',-14},
 {'Guild Death Broadcast','World PvP','Control guild-wide death reports.','Alerts',-601,'Account-wide',nil,253,'death'},
 {'Hide Death Alerts in Combat','World PvP','Suppress the local popup during combat.','Alerts',-562,'Account-wide',nil,253,'death'},
 {'Death Alert Display','Alerts','Preview, move, resize, and time the death popup.','Alerts',-340,'Account-wide','test preview position',253,'death'},
 {'Bounty Alert Display','Alerts','Preview, move, resize, and time the bounty popup.','Alerts',-340,'Account-wide','test preview position',253,'bounty'},
 {'Friendly Bounty Test Mode','Alerts','Allow friendly targets in the existing bounty test mode.','Alerts',-523,'Account-wide',nil,253,'bounty'},
 {'Report reminders','General','Show local report reminders in chat.','Alerts',-102,'Account-wide',nil,253,'reminders'},
 {'Guild LFG Notices','Guild & Sharing','Configure interest, invitation, and matching notices.','Looking for Group',-167,'Account-wide'},
}
local function openSetting(entry)
 if InCombatLockdown and InCombatLockdown() then return end
 active=entry[4]
 if entry[9] then alertSelection=entry[9] end
 pendingSetting,focusedSetting=entry,entry
 render()
end
local function activeBounty(id)
 for _,entry in ipairs((KWCDB and KWCDB.bounties) or {}) do
  if entry.id==id and (entry.status or 'ACTIVE')=='ACTIVE' then return entry end
 end
end
local function setActionEnabled(control,enabled)
 control:SetEnabled(enabled)
 control:SetAlpha(enabled and 1 or 0.5)
end
local function label(p,t,x,y,w,font)
 local f=p:CreateFontString(nil,'OVERLAY')
 local title=font=='GameFontNormalLarge'
 local section=font=='GameFontNormal'
 f:SetFont(FONT,title and C.size.title or (section and C.size.section or C.size.body),'')
 local color=(title or section) and C.gold or C.cream
 f:SetTextColor(color[1],color[2],color[3],1)
 f:SetPoint('TOPLEFT',x,y);f:SetWidth(w);f:SetJustifyH('LEFT');f:SetJustifyV('TOP')
 f:SetText(tostring(t or ''))
 if title then
  local rule=p:CreateTexture(nil,'ARTWORK')
  rule:SetPoint('TOPLEFT',p,'TOPLEFT',x,y-27);rule:SetSize(math.min(w,545),1)
  rule:SetColorTexture(unpack(C.steel))
 end
 return f
end
local function tooltip(control,title,help)
 if control.SetMotionScriptsWhileDisabled then control:SetMotionScriptsWhileDisabled(true) end
 control:HookScript('OnEnter',function(self)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
  GameTooltip:SetText(title)
  GameTooltip:AddLine(type(help)=='function' and help() or help,0.87,0.89,0.93,true)
  GameTooltip:Show()
 end)
 control:HookScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
end
local function button(p,t,x,y,w,cb,help,selected)
 local b=CreateFrame('Button',nil,p);b:SetSize(w,34);b:SetPoint('TOPLEFT',x,y)
 local isNav=(p==navChild and w>=180)
 local function isSelected()
  if not isNav then return selected end
  local page=b.kwcPage or t
  return active==page or (page=='Raid Tools' and active:sub(1,12)=='Raid Tools: ')
 end
 local edge=b:CreateTexture(nil,'BACKGROUND');edge:SetAllPoints(b);edge:SetColorTexture(unpack(C.steel))
 local bg=b:CreateTexture(nil,'ARTWORK');bg:SetPoint('TOPLEFT',1,-1);bg:SetPoint('BOTTOMRIGHT',-1,1)
 local function paint(hover)
  local color=isSelected() and C.crimson or (hover and C.hover or C.graphite)
  bg:SetColorTexture(unpack(color))
  if isNav and b.kwcAccent then
   b.kwcAccent:SetColorTexture(C.accent[1],C.accent[2],C.accent[3],isSelected() and 1 or 0)
  end
 end
 paint(false)
 local tx=b:CreateFontString(nil,'OVERLAY');tx:SetFont(FONT,isNav and C.size.nav or C.size.body,'');tx:SetPoint('CENTER');tx:SetWidth(w-12);tx:SetJustifyH('CENTER')
 tx:SetTextColor(C.cream[1],C.cream[2],C.cream[3]);tx:SetText(t)
 if isNav then
  tx:ClearAllPoints();tx:SetPoint('LEFT',b,'LEFT',14,0);tx:SetJustifyH('LEFT')
  local accent=b:CreateTexture(nil,'OVERLAY');accent:SetPoint('TOPLEFT',b,'TOPLEFT',0,0);accent:SetPoint('BOTTOMLEFT',b,'BOTTOMLEFT',0,0);accent:SetWidth(2)
  b.kwcAccent=accent
 end
 b:SetScript('OnEnter',function(self)self.kwcHovered=true;paint(true) end)
 b:SetScript('OnLeave',function(self)self.kwcHovered=false;paint(false) end)
 if isNav then b.kwcPaint=paint;navButtons[#navButtons+1]=b end
 b:SetScript('OnClick',cb)
 if help then tooltip(b,t,help) end
 return b
end
local function settingLink(parent,caption,x,y,w,index)
 return button(parent,caption,x,y,w,function()openSetting(settingIndex[index]) end)
end
local function confirmReset(title,reset)
 StaticPopupDialogs.KWC_CONFIRM_SETTING_RESET={
  text=title,button1='Reset',button2='Cancel',timeout=0,whileDead=true,hideOnEscape=true,
  OnAccept=function(_,action) action();render() end,
 }
 StaticPopup_Show('KWC_CONFIRM_SETTING_RESET',nil,nil,reset)
end
-- DEV39: consistent native KWC settings rows, with accessible status text.
local function settingRow(parent,caption,description,settings,key,y,refresh)
 surface(parent,18,y,538,65,0.10)
 local name=label(parent,caption,32,y-10,345,'GameFontNormal')
 label(parent,description or '',32,y-36,345)
 local enabled=settings[key]==true
 local b=button(parent,enabled and 'Enabled' or 'Disabled',407,y-14,133,function()
  settings[key]=not (settings[key]==true)
  if refresh then refresh() end
  render()
 end)
 return b
end
local function edit(p,value,x,y,w)
 local e=CreateFrame('EditBox',nil,p);e:SetSize(w,26);e:SetPoint('TOPLEFT',x,y);e:SetAutoFocus(false)
 e:EnableMouse(true)
 e:EnableKeyboard(true)
 e:SetFrameLevel(p:GetFrameLevel()+5)
 e:SetScript('OnMouseDown',function(self,button) if button=='LeftButton' then self:SetFocus() end end)
 e:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
 e:SetScript('OnEnterPressed',function(self) self:ClearFocus() end)
 local bg=e:CreateTexture(nil,'BACKGROUND');bg:SetAllPoints(e);bg:SetColorTexture(unpack(C.graphite))
 e:SetFont(FONT,C.size.field,'');e:SetTextColor(unpack(C.cream));e:SetTextInsets(9,9,0,0);e:SetText(value or '');return e
end
local function localFilter(parent,value,x,y,width,apply)
 local field=edit(parent,value,x,y,width)
 button(parent,'Filter',x+width+10,y+4,78,function()apply(field:GetText());render() end)
 field:SetScript('OnEnterPressed',function(self) self:ClearFocus();apply(self:GetText());render() end)
end
local function multilineEdit(p,value,x,y,w,h)
 local holder=CreateFrame('Frame',nil,p)
 holder:SetSize(w,h);holder:SetPoint('TOPLEFT',x,y)
 local bg=holder:CreateTexture(nil,'BACKGROUND');bg:SetAllPoints(holder);bg:SetColorTexture(unpack(C.graphite))
 local scroll=CreateFrame('ScrollFrame',nil,holder,'UIPanelScrollFrameTemplate')
 scroll:SetPoint('TOPLEFT',holder,'TOPLEFT',8,-7)
 scroll:SetPoint('BOTTOMRIGHT',holder,'BOTTOMRIGHT',-27,7)
 local e=CreateFrame('EditBox',nil,scroll)
 e:SetMultiLine(true);e:SetAutoFocus(false);e:SetFont(FONT,C.size.field,'')
 e:SetTextColor(unpack(C.cream));e:SetWidth(w-48);e:SetHeight(h-14)
 e:SetScript('OnEscapePressed',function(self)self:ClearFocus() end)
 e:SetScript('OnTextChanged',function(self)
  local _,lineCount=self:GetText():gsub('\n','\n')
  local needed=math.max(h-14,(lineCount+2)*18)
  if self:GetHeight()~=needed then self:SetHeight(needed) end
  if self:GetHeight()>h-14 and scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
 end)
 scroll:SetScrollChild(e);e:SetText(value or '')
 holder:EnableMouse(true);holder:SetScript('OnMouseDown',function()e:SetFocus() end)
 return e
end
surface=function(p,x,y,w,h,shade)
 local t=p:CreateTexture(nil,'BACKGROUND');t:SetPoint('TOPLEFT',p,'TOPLEFT',x,y);t:SetSize(w,h)
 local v=shade or 0.09;t:SetColorTexture(v,v,v+0.008,1)
 return t
end
local function single(p,value,x,y,w,style)
 local f=label(p,value,x,y,w,style);f:SetWordWrap(false);f:SetMaxLines(1);return f
end
local function count(t) local n=0;for _ in pairs(t or {}) do n=n+1 end;return n end
local raidTabs={{'Overview','Raid Tools'},{'Raid Command','Raid Tools: Command'},{'Raid Sign-Ups','Raid Tools: Sign-Ups'}}
local function raidTabFor(page)
 if page=='Raid Tools: Command' or page=='Raid Tools: Sign-Ups' then return page end
 if page=='Raid Tools' or page:sub(1,12)=='Raid Tools: ' then return 'Raid Tools' end
end

local function pageTitle(page)
 if raidTabFor(page)==page then return 'Raid Operations' end
 local names={
  Home='Command Center',Settings='Settings Center',Alerts='Alert Command Center',['Settings Search']='Settings Search',
  ['CTA Board']='Calls to Arms',['CTA Entry']='New Call to Arms',
  ['CTA Details']='Call to Arms Details',['CTA Roster']='Call to Arms Roster',
  ['CTA Attendance']='Call to Arms Attendance',
  ['Raid Tools']='Raid Operations',
  ['Raid Tools: Attendance']='Raid Attendance',
  ['Raid Tools: Roster']='Raid Roster',
  ['Raid Tools: Ready Check']='Readiness',
  ['Raid Tools: Ready Check Advanced']='Readiness Settings',
  ['Raid Tools: Combat Tools']='Combat',
  ['Raid Tools: Combat Advanced']='Combat Settings',
  ['Raid Tools: Battle Resurrection']='Battle Resurrection Button',
  ['Raid Tools: Auto-Invite']='Invites',
  ['Raid Tools: Auto-Invite Advanced']='Invite Settings',
  ["Raid Tools: Don't Release"]='Death Protection',
  ['Raid Tools: Notes']='Raid Notes',
 }
 return names[page] or page
end
local function reset()
 if K.RaidTools and K.RaidTools.Close then K.RaidTools.Close() end
 if body then
  local children={body:GetChildren()};for _,child in ipairs(children) do child:Hide() end
  local regions={body:GetRegions()};for _,region in ipairs(regions) do region:Hide() end
  body:Hide()
 end
 scrollChild:SetHeight(3900)
 body=CreateFrame('Frame',nil,scrollChild);body:SetSize(605,3900);body:SetPoint('TOPLEFT',scrollChild,'TOPLEFT',0,0)
end
-- Discord export: plain text shown in a selectable edit box; WoW addons cannot
-- write to the operating system clipboard or post directly to Discord.
local function discordText(kind,e)
 local d=e.details or {}
 local function val(v,fallback)
  v=tostring(v or ''):gsub('[\r\n]',' '):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
  if v=='' then return fallback or 'Unknown / TBD' end
  return v
 end
 if kind=='BOUNTY' then
  local target=val(d.target or (e.text or ''):match('^([^|%-]+)'), 'Unknown')
  local reward=d.reward or (e.text or ''):match('[Rr]eward:%s*([^|]+)')
  local last=(e.sightings or {})[1]
  local loc=val((last and last.zone) or d.location)
  return table.concat({
   '💀 **BOUNTY** 💀','',
   '**Target:** '..target,
   '**Guild:** '..val(d.guild),
   '**Last Known Location:** '..loc,
   '**Bounty:** '..val(reward,'Not listed'),
   '**Posted By:** '..val(e.author),
   '**Status:** '..val(e.status,'ACTIVE'),
   '**Proof:** Screenshot of the kill','',
   'Bounties are player-funded. The poster is responsible for paying the reward.','',
   'Happy hunting. Burninate responsibly.'
  },'\n')
 end
 local zone=val(d.zone or (e.text or ''):match('%]%s*([^|%-]+)'), 'Unknown')
 local coords=val(d.coords,'Not provided')
 local objective=val(d.objective or e.text,'Reinforcements requested')
 local enemy=val(d.alliance,'Unknown')
 local friendly=val(d.horde,'Unknown')
 local state=(e.status=='RESOLVED' and 'FIGHT OVER') or (e.status=='CANCELLED' and 'CANCELLED') or 'REINFORCEMENTS NEEDED'
 return table.concat({
  '⚔️ **CALL TO ARMS** ⚔️','',
  '**LOCATION:** '..zone,
  '**RALLY POINT / COORDS:** '..coords,
  '**ENEMY FORCES:** '..enemy..' Alliance',
  '**FRIENDLY FORCES:** '..friendly..' Horde',
  '**OBJECTIVE:** '..objective,
  '**VOICE CHANNEL:** PvP Party',
  '**STATUS:** '..state,
  '**POSTED BY:** '..val(e.author),'',
  'React below:',
  '⚔️ — On my way',
  '🛡️ — Defending / Already there',
  '✅ — Fight over','',
  '@Call To Arms','',
  '**FOR THE HORDE!**'
 },'\n')
end
local discordPopup
local function showDiscordExport(kind,e)
 if not e then K.Say('Report not found.');return end
 if not discordPopup then
  local p=CreateFrame('Frame','KWCDiscordExportFrame',UIParent)
  p:SetSize(630,520);p:SetPoint('CENTER');p:SetFrameStrata('DIALOG');p:SetFrameLevel(200)
  p:EnableMouse(true);p:SetMovable(true);p:RegisterForDrag('LeftButton')
  p:SetScript('OnDragStart',p.StartMoving);p:SetScript('OnDragStop',p.StopMovingOrSizing)
  local bg=p:CreateTexture(nil,'BACKGROUND');bg:SetAllPoints(p);bg:SetColorTexture(0.055,0.07,0.095,1)
  local border=p:CreateTexture(nil,'ARTWORK');border:SetPoint('TOPLEFT',p,'TOPLEFT',0,0);border:SetSize(630,3);border:SetColorTexture(0.35,0.58,0.83,1)
  local title=p:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');title:SetPoint('TOPLEFT',18,-18);title:SetText('DISCORD EXPORT')
  local hint=p:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');hint:SetPoint('TOPLEFT',18,-50);hint:SetText('Click the text, press Ctrl+A then Ctrl+C. Paste into Discord with Ctrl+V.')
  local sc=CreateFrame('ScrollFrame',nil,p,'UIPanelScrollFrameTemplate');sc:SetPoint('TOPLEFT',18,-82);sc:SetPoint('BOTTOMRIGHT',-36,65)
  local eb=CreateFrame('EditBox',nil,sc)
  eb:SetMultiLine(true);eb:SetAutoFocus(false);eb:SetFont('Fonts\\FRIZQT__.TTF',14,'')
  eb:SetTextColor(0.97,0.91,0.82);eb:SetWidth(555);eb:SetHeight(900)
  eb:SetScript('OnEscapePressed',function()p:Hide() end)
  eb:SetScript('OnTextChanged',function(self)self:SetHeight(math.max(900,self:GetNumLetters()/55*18+100)) end)
  sc:SetScrollChild(eb)
  p.exportEdit=eb
  local select=CreateFrame('Button',nil,p,'UIPanelButtonTemplate');select:SetSize(150,28);select:SetPoint('BOTTOMLEFT',18,19);select:SetText('Select All Text')
  select:SetScript('OnClick',function()eb:SetFocus();eb:HighlightText() end)
  local close=CreateFrame('Button',nil,p,'UIPanelButtonTemplate');close:SetSize(90,28);close:SetPoint('BOTTOMRIGHT',-18,19);close:SetText('Close');close:SetScript('OnClick',function()p:Hide() end)
  discordPopup=p
 end
 discordPopup.exportEdit:SetText(discordText(kind,e))
 discordPopup:Show();discordPopup.exportEdit:SetFocus();discordPopup.exportEdit:HighlightText()
end

-- The KRT panel is parented to the KWC window; no separate minimap/window.
function U.GetHost() return frame end
render=function()
 if InCombatLockdown and InCombatLockdown() then U.needsRefresh=true;return end
 if not frame or not frame:IsShown() or not KWCDB then return end
 for _,nav in ipairs(navButtons) do if nav.kwcPaint then nav.kwcPaint(nav.kwcHovered or false) end end
 if type(active)~='string' then active='Home' end
 header:SetText(string.upper(pageTitle(active)));reset();local d=KWCDB
 if raidTabFor(active)==active then
  for i,tab in ipairs(raidTabs) do
   local name,page=tab[1],tab[2]
   local selected=active==page
   local control=button(body,name,18+(i-1)*181,-14,169,function()
    if active~=page then scroll:SetVerticalScroll(0);active=page;render() end
   end)
   if selected then
    local underline=control:CreateTexture(nil,'OVERLAY')
    underline:SetPoint('BOTTOMLEFT',1,1);underline:SetPoint('BOTTOMRIGHT',-1,1)
    underline:SetHeight(3);underline:SetColorTexture(0.59,0.23,0.29,1)
   end
  end
 end
 if active=='Home' then
  label(body,'Command Center',18,-14,540,'GameFontNormalLarge')
  local stats=K.Operations and K.Operations.Stats and K.Operations.Stats()
  if stats then
   for i,metric in ipairs({{stats.activeCTA,'Active Calls to Arms'},{stats.activeBounty,'Active Bounties'},{stats.sightings,'Recorded Sightings'}}) do
    local x=18+(i-1)*182
    surface(body,x,-58,171,78,0.11)
    label(body,metric[1] or '—',x+12,-69,145,'GameFontNormalLarge')
    label(body,metric[2],x+12,-108,145)
   end
  else
   label(body,'Guild activity is unavailable.',18,-67,540)
  end
  local shortcuts={
   {'Find a Group','Looking for Group','Browse guild groups or start your own listing.'},
   {'PvP Operations','War Room','View guild PvP activity, scouting, and operations.'},
   {'Raid Operations','Raid Tools','Open assignments, sign-ups, and raid tools.'},
   {'Guild Services','Guild Services','Find guildmates by profession or known recipe.'},
   {'Settings','Settings','Manage sharing, the minimap launcher, and window size.'},
   {'Guild Overview','Overview','See the guild activity dashboard and group counts.'},
  }
  for i,item in ipairs(shortcuts) do
   local x=18+((i-1)%2)*274
   local y=-154-math.floor((i-1)/2)*111
   surface(body,x,y,263,98,0.092)
   button(body,item[1],x+10,y-9,243,function() navigate(item[2]) end)
   label(body,item[3],x+13,y-52,237)
  end
 elseif active=='Overview' then
  -- DEV28: UI-only command dashboard. Reads existing data; no writes or sync.
  local st=K.Operations.Stats()
  local ops=KWCDB.ops or {}
  local chosen=nil
  for _,entry in ipairs(ops) do
   if (entry.status or 'ACTIVE')=='ACTIVE' and (not chosen or (tonumber(entry.created) or 0)>(tonumber(chosen.created) or 0)) then
    chosen=entry
   end
  end
  label(body,'War Command',18,-14,530,'GameFontNormalLarge')
  label(body,'KEEPERS OF TROGDOR  /  GUILD OPERATIONS',18,-58,535)
  local guildState=IsInGuild and IsInGuild()
  local status=single(body,guildState and 'GUILD CONNECTED' or 'NOT IN GUILD',395,-18,164)
  status:SetTextColor(guildState and 0.39 or 0.87,guildState and 0.82 or 0.55,guildState and 0.62 or 0.45)
  local metrics={
   {tostring(st.activeCTA or 0),'ACTIVE CALLS TO ARMS','Open operations'},
   {tostring(st.activeBounty or 0),'BOUNTIES','Tracked targets'},
   {tostring(st.sightings or 0),'SIGHTINGS','Intel reports'}
  }
  for i,m in ipairs(metrics) do
   local x=18+(i-1)*184
   surface(body,x,-99,171,105,0.088)
   local n=label(body,m[1],x+16,-114,139,'GameFontNormalLarge')
   n:SetFont(FONT,30,'')
   label(body,m[2],x+16,-163,140)
   label(body,m[3],x+16,-185,140)
  end
  label(body,'ACTIVE OPERATIONS',18,-238,360,'GameFontNormal')
  surface(body,18,-271,539,157,0.083)
  if chosen then
   local priority=chosen.details and chosen.details.priority or ''
   local heading=tostring(chosen.text or 'Active operation'):gsub('[\r\n]',' '):sub(1,92)
   single(body,heading,34,-288,498,'GameFontNormal')
   local commander=chosen.author or chosen.commander or 'Unknown'
   if K.Operations.CTALeadership then
    local lead=K.Operations.CTALeadership(chosen)
    if lead and lead.creator then commander=lead.creator end
   end
   single(body,'Commander: '..tostring(commander),34,-319,496)
   single(body,tostring(st.coming or 0)..' reinforcements responding  /  '..tostring(st.urgent or 0)..' urgent operations',34,-343,496)
   button(body,'View Operation',34,-378,170,function()selectedCTA=chosen.id;active='CTA Details';render() end)
   button(body,'All Operations',216,-378,170,function()active='War Room';render() end)
  else
   label(body,'No active calls to arms.',34,-290,490,'GameFontNormal')
   label(body,'Create an operation when your guild needs reinforcements.',34,-321,490)
   button(body,'New Call to Arms',34,-371,195,function()active='CTA Entry';render() end)
  end
  label(body,'GUILD ACTIVITY',18,-462,520,'GameFontNormal')
  surface(body,18,-496,262,161,0.083)
  surface(body,295,-496,262,161,0.083)
  label(body,'RAID SIGN-UPS',34,-512,224,'GameFontNormal')
  local raidCount=0
  local raidData=KWCDB.raidSignups
  if raidData and type(raidData.events)=='table' then
   for _,e in pairs(raidData.events) do if not e.cancelled then raidCount=raidCount+1 end end
  end
  single(body,raidCount==0 and 'No scheduled raids' or (tostring(raidCount)..' scheduled raid(s)'),34,-545,228)
  label(body,'View schedules and RSVP in-game.',34,-571,228)
  button(body,'Open Sign-Ups',34,-611,218,function()active='Raid Tools: Sign-Ups';render() end)
  label(body,'SCOUT NETWORK',311,-512,229,'GameFontNormal')
  single(body,tostring(st.sightings or 0)..' recorded sightings',311,-545,228)
  label(body,'Review enemy sightings and reports.',311,-571,228)
  button(body,'Open Scout Network',311,-611,218,function()active='Scout Network';render() end)
  label(body,'QUICK ACCESS',18,-695,520,'GameFontNormal')
  button(body,'Raid Command',18,-730,168,function()active='Raid Tools: Command';render() end)
  button(body,'Bounty Board',198,-730,168,function()active='Bounty Board';render() end)
  button(body,'Sync Health',378,-730,178,function()active='Sync Health';render() end)
  local listings,seekers=K.GuildLFG.Summary()
  button(body,('Looking for Group  |  %d active  /  %d seeking'):format(listings,seekers),18,-785,538,function()active='Looking for Group';render() end)
 elseif active=='Guild Services' then
  K.GuildServices.Draw(body,label,button,edit,surface,render)
  settingLink(body,'Sharing Settings',380,-8,173,3)
 elseif active=='Looking for Group' then
  K.GuildLFG.Draw(body,label,button,edit,surface,render)
 elseif active=='Recruitment' then
  label(body,'Guild Recruitment',12,-12,570,'GameFontNormalLarge')
  local r=K.Recruiter
  local db=d.recruiter
  r.Restore()
  local query=edit(body,recruitmentQuery or db.lastQuery or '10-20',12,-53,155)
  query:SetScript('OnTextChanged',function(self) recruitmentQuery=self:GetText() end)
  local search=button(body,'Search /who',183,-53,130,function() r.Search(query:GetText()) end,
   'Look up unguilded players in the selected level range.')
  local nextRange=button(body,'Next range',330,-53,125,function()
   if r.Next() then query:SetText(db.lastQuery) end
  end)
  local summary=label(body,'',12,-97,550)
  local status=label(body,'',12,-126,550,'GameFontNormal')
  local candidateScroll=CreateFrame('ScrollFrame',nil,body,'UIPanelScrollFrameTemplate')
  candidateScroll:SetPoint('TOPLEFT',12,-156)
  candidateScroll:SetSize(512,270)
  local candidateList=CreateFrame('Frame',nil,candidateScroll)
  candidateList:SetSize(510,270)
  candidateScroll:SetScrollChild(candidateList)
  local rows={}
  local lastResults
  local selected=label(body,'',12,-448,550,'GameFontNormal')
  local whisper=button(body,'Prepare whisper',12,-480,165,r.Whisper)
  local invite=button(body,'Prepare invite',188,-480,160,r.PrepareInvite)
  local ignore=button(body,'Ignore',360,-480,130,r.Ignore)
  label(body,'Invites and whispers are drafts. You must send them yourself.',12,-523,550)
  label(body,'Recruiting message:',12,-563,550)
  local pitch=multilineEdit(body,recruitmentPitch or d.settings.pitch,12,-588,540,112)
  pitch:HookScript('OnTextChanged',function(self) recruitmentPitch=self:GetText() end)
  button(body,'Save message',12,-713,165,function()
   d.settings.pitch=tostring(pitch:GetText() or ''):gsub('|',' '):gsub('\r\n','\n'):gsub('\r','\n'):sub(1,500)
   recruitmentPitch=d.settings.pitch
   K.Say('Message saved.')
  end)
  recruitmentRefresh=function()
   summary:SetText(('Searches: %d  |  Whisper drafts: %d  |  Invite drafts: %d  |  Confirmed joins: %d')
    :format(db.searches or 0,db.drafts or 0,db.inviteDrafts or 0,db.joins or 0))
   if r.pending then status:SetText('Searching WHO...')
   elseif r.error then status:SetText(r.error)
   elseif #r.results>0 then status:SetText(('%d eligible candidates'):format(#r.results))
   elseif r.received then status:SetText('No eligible candidates in the latest results.')
   else status:SetText('Search WHO to find unguilded players.') end
   search:SetEnabled(r.SearchReady())
   nextRange:SetEnabled(r.SearchReady())
   local candidate=r.Candidate()
   selected:SetText('Selected: '..(candidate and candidate.name or 'none'))
   whisper:SetEnabled(candidate~=nil)
   invite:SetEnabled(candidate~=nil)
   ignore:SetEnabled(candidate~=nil)
   for i,c in ipairs(r.results) do
    local row=rows[i]
    if not row then
     local index=i
     local control=button(candidateList,'',0,-(i-1)*46,510,function() r.Select(index) end)
     control:SetHeight(43)
     row={control=control,
      name=single(control,'',10,-6,280,'GameFontNormal'),
      status=single(control,'',300,-8,198),
      detail=single(control,'',10,-25,490)}
     rows[i]=row
    end
    row.name:SetText((candidate==c and '* ' or '')..c.name)
    row.status:SetText(c.status or 'discovered')
    local details=('Level %s  |  %s'):format(tostring(c.level or '?'),c.class or 'Unknown class')
    if c.zone and c.zone~='' then details=details..'  |  '..c.zone end
    row.detail:SetText(details)
    row.control:Show()
   end
   for i=#r.results+1,#rows do rows[i].control:Hide() end
   local height=math.max(270,#r.results*46)
   candidateList:SetHeight(height)
   candidateScroll:UpdateScrollChildRect()
   local offset=lastResults==r.results and (candidateScroll:GetVerticalScroll() or 0) or 0
   candidateScroll:SetVerticalScroll(math.min(offset,height-270))
   lastResults=r.results
  end
  recruitmentRefresh()
 elseif active=='CTA Attendance' then
  if K.GuildService then K.GuildService.DrawCTA(body,label,button) end
 elseif active=='PvP Leaderboard' then
  label(body,'PvP leaderboard',18,-16,530,'GameFontNormalLarge')
  local views={{'lifetime','All-Time HKs'},{'world','World PvP'},{'battleground','Battlegrounds'}}
  for i,view in ipairs(views) do
   local metric,caption=view[1],view[2]
   local tab=button(body,caption,18+(i-1)*135,-53,128,function()
    pvpView=metric
    scroll:SetVerticalScroll(0)
    render()
   end)
   if pvpView==metric then
    local accent=tab:CreateTexture(nil,'OVERLAY')
    accent:SetPoint('BOTTOMLEFT',1,1);accent:SetPoint('BOTTOMRIGHT',-1,1)
    accent:SetHeight(3);accent:SetColorTexture(0.63,0.23,0.30,1)
   end
  end
  button(body,'Refresh honor',423,-53,134,function()
   K.PvP.RefreshHonor()
   K.PvP.RequestGuildHonor()
   if K.GuildService then K.GuildService.Request() end
  end,'Refreshes your Forever PvP totals and requests current totals from compatible guildmates.')
  local lifetime=pvpView=='lifetime'
  label(body,lifetime and 'Lifetime honorable kills. Tiers are internal guild titles.' or
   'Forever character history. Players without reported totals are unranked.',18,-100,539)
  surface(body,18,-124,539,38,0.12)
  local columns=lifetime and {
   {'#',25,28},{'TIER',57,89},{'PLAYER',150,155},{'HKs',309,46},{'BOUNTIES',363,75},{'CALLS TO ARMS',445,112}
  } or {
   {'#',25,38},{'PLAYER',72,305},{pvpView=='world' and 'WORLD HKs' or 'BATTLEGROUND HKs',390,165}
  }
  for _,column in ipairs(columns) do single(body,column[1],column[2],-136,column[3],'GameFontNormal') end
  local function tier(rank) if rank<=5 then return 'Warlord' elseif rank<=10 then return 'Gladiator' elseif rank<=20 then return 'Elite' elseif rank<=35 then return 'Duelist' elseif rank<=50 then return 'Rival' elseif rank<=75 then return 'Challenger' else return 'Combatant' end end
  local players=K.PvP.Rankings(pvpView)
  local playerColumn=lifetime and 3 or 2
  for i,p in ipairs(players) do
   if i>100 then break end
   local y=-175-(i-1)*34
   if i%2==1 then surface(body,18,y+7,539,32,0.075) end
   local values={tostring(i),p.name,tostring(p.value)}
   if lifetime then
    local bounties,ctas=0,0
    if K.GuildService then bounties,ctas=K.GuildService.Totals(p.name) end
    values={tostring(i),tier(i),p.name,tostring(p.value),tostring(bounties),tostring(ctas)}
   end
   for j,column in ipairs(columns) do
    local field=single(body,values[j],column[2],y,column[3],i<=3 and 'GameFontNormal' or nil)
    if j==playerColumn and field:IsTruncated() then
     local hover=CreateFrame('Frame',nil,body)
     hover:SetAllPoints(field)
     hover:EnableMouse(true)
     hover:SetScript('OnEnter',function(self)
      GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
      GameTooltip:SetText(p.name)
      GameTooltip:Show()
     end)
     hover:SetScript('OnLeave',function() GameTooltip:Hide() end)
     hover:SetScript('OnHide',function(self) if GameTooltip:GetOwner()==self then GameTooltip:Hide() end end)
    end
   end
  end
  if #players==0 then label(body,'No totals reported for this view yet.',25,-175,500) end
 elseif active=='Raid Tools' then
  local groups={
   {'OPERATIONS',{{'Attendance & Records','Attendance'},{'Raid Roster','Roster'}}},
   {'RAID PREPARATION',{{'Ready Checks','Ready Check'},{'Invitations','Auto-Invite'},{'Raid Notes','Notes'}}},
   {'IN COMBAT',{{'Combat Tools','Combat Tools'},{'Battle Resurrection Button','Battle Resurrection'},{'Death Protection',"Don't Release"}}},
  }
  local y=-99
  for _,group in ipairs(groups) do
   label(body,group[1],18,y,530,'GameFontNormal')
   y=y-39
   for i,entry in ipairs(group[2]) do
    local destination='Raid Tools: '..entry[2]
    local x=18+((i-1)%2)*272
    local row=math.floor((i-1)/2)
    button(body,entry[1],x,y-row*47,255,function()navigate(destination) end)
   end
   y=y-math.ceil(#group[2]/2)*47-20
  end
 elseif active=="Raid Tools: Don't Release" then
  label(body,'Death Protection',18,-14,538,'GameFontNormalLarge')
  label(body,'Prevent accidental release after death.',18,-55,535)
  local rt=KeepersRaidTools
  local cfg=rt and rt.GetSetting and rt:GetSetting('dontRelease')
  if not cfg then label(body,'Death Protection is unavailable.',18,-105,520)
  else
   local function refresh() if rt.EvaluateAllModules then rt:EvaluateAllModules() end end
   label(body,'GENERAL',18,-99,520,'GameFontNormal')
   settingRow(body,'Death protection','Block accidental release when enabled.',cfg,'enabled',-129,refresh)
   label(body,'ACTIVATE IN',18,-219,520,'GameFontNormal')
   local ct=cfg.contentTypes or {}
   settingRow(body,'Open world','Outside instances.',ct,'openWorld',-249,refresh)
   if ct.dungeon then settingRow(body,'Dungeons','Classic dungeon instances.',ct.dungeon,'normal',-322,refresh) end
   if ct.raid then settingRow(body,'Raids','Classic raid instances.',ct.raid,'normal',-395,refresh) end
   label(body,'RELEASE SAFETY',18,-488,520,'GameFontNormal')
   settingRow(body,'Require modifier','Hold the required key to release.',cfg,'requireModifier',-518,refresh)
   settingRow(body,'Randomize modifier','Choose a different required key.',cfg,'randomizeModifier',-591,refresh)
   label(body,'Release delay',18,-692,350,'GameFontNormal')
   label(body,tostring(cfg.delay or 0)..' seconds',400,-692,145)
   button(body,'Decrease',18,-729,166,function()cfg.delay=math.max(0,(tonumber(cfg.delay) or 0)-1);render() end)
   button(body,'Increase',198,-729,166,function()cfg.delay=math.min(60,(tonumber(cfg.delay) or 0)+1);render() end)
  end
 elseif active=='Raid Tools: Ready Check' then
  label(body,'Readiness',18,-14,535,'GameFontNormalLarge')
  label(body,'Choose the checks used before your group pulls.',18,-55,535)
  local rt=KeepersRaidTools
  local cfg=rt and rt.GetSetting and rt:GetSetting('readyCheck')
  if not cfg then label(body,'Readiness settings unavailable.',18,-110,530)
  else
   label(body,'GENERAL',18,-98,520,'GameFontNormal')
   settingRow(body,'Enable notifications','Show ready-check feedback.',cfg,'enabled',-130)
   label(body,'PLAYER CHECKS',18,-220,520,'GameFontNormal')
   settingRow(body,'Dead players','Identify dead group members.',cfg,'checkDead',-250)
   settingRow(body,'Soulstones','Check available soulstones.',cfg,'checkSoulstones',-323)
   label(body,'CLASSIC BUFF CHECKS',18,-415,520,'GameFontNormal')
   settingRow(body,'Arcane Intellect','Mage intellect buff.',cfg,'arcaneIntellect',-445)
   settingRow(body,'Battle Shout','Warrior attack power buff.',cfg,'battleShout',-518)
   settingRow(body,'Mark of the Wild','Druid group buff.',cfg,'markOfTheWild',-591)
   settingRow(body,'Power Word: Fortitude','Priest stamina buff.',cfg,'powerWordFortitude',-664)
   button(body,'Additional notification options',18,-753,360,function()active='Raid Tools: Ready Check Advanced';render() end)
  end
 elseif active=='Raid Tools: Ready Check Advanced' then
  label(body,'Advanced Readiness',18,-14,540,'GameFontNormalLarge')
  button(body,'Back to Readiness',18,-68,240,function()active='Raid Tools: Ready Check';render() end)
  local mount=CreateFrame('Frame',nil,body)
  mount:SetPoint('TOPLEFT',body,'TOPLEFT',18,-133)
  mount:SetSize(550,760)
  if K.RaidTools and K.RaidTools.Mount then K.RaidTools.Mount(mount,'Ready Check') end
 elseif active=='Raid Tools: Combat Tools' then
  label(body,'Combat',18,-14,535,'GameFontNormalLarge')
  label(body,'Cooldowns, battle resurrection, and combat timer.',18,-55,535)
  local rt=KeepersRaidTools
  local cds=rt and rt.GetSetting and rt:GetSetting('cooldownRoster')
  local timer=rt and rt.GetSetting and rt:GetSetting('combatTimer')
  local function refresh()if rt and rt.EvaluateAllModules then rt:EvaluateAllModules() end end
  label(body,'COOLDOWN ROSTER',18,-100,530,'GameFontNormal')
  if cds then
   settingRow(body,'Enable cooldown roster','Display available raid cooldowns.',cds,'enabled',-130,refresh)
   local cats=cds.categories or {}
   settingRow(body,'Defensives','Defensive abilities.',cats,'defensive',-203,refresh)
   settingRow(body,'External cooldowns','Defensives cast on allies.',cats,'external',-276,refresh)
   settingRow(body,'Movement','Group movement abilities.',cats,'movement',-349,refresh)
   label(body,'SHOW IN',18,-438,520,'GameFontNormal')
   local ct=cds.contentTypes or {}
   settingRow(body,'Open world','Outside instances.',ct,'openWorld',-468,refresh)
   if ct.dungeon then settingRow(body,'Dungeons','Classic dungeon instances.',ct.dungeon,'normal',-541,refresh) end
   if ct.raid then settingRow(body,'Raids','Classic raid instances.',ct.raid,'normal',-614,refresh) end
  end
  label(body,'COMBAT TIMER',18,-711,520,'GameFontNormal')
  if timer then settingRow(body,'Enable combat timer','Display elapsed encounter time.',timer,'enabled',-741,refresh) end
  button(body,'Battle Resurrection Button',18,-838,260,function()active='Raid Tools: Battle Resurrection';render() end)
  button(body,'Advanced combat settings',292,-838,255,function()active='Raid Tools: Combat Advanced';render() end)
 elseif active=='Raid Tools: Battle Resurrection' then
  label(body,'Battle Resurrection Button',18,-14,535,'GameFontNormalLarge')
  button(body,'Back to Raid Operations',18,-58,240,function()active='Raid Tools';render() end)
  local rt=KeepersRaidTools
  local br=rt and rt.BattleResCounter
  local cfg=br and rt:GetSetting('battleResCounter')
  if cfg then
   local function control(text,x,y,w,action,help)
    return button(body,text,x,y,w,function()action();render() end,help)
   end
   label(body,'The indicator shows Rebirth charges and cooldowns. Cast Rebirth from your spell bar.',18,-107,530)
   control(cfg.widgetEnabled and 'Disable button' or 'Enable button',18,-145,255,function()br:SetWidgetEnabled(not cfg.widgetEnabled) end,
    'Show the Battle Resurrection button while in a raid.')
   local function positionHelp()
    if not br:CanConfigurePosition() then return 'Enable the button and join a raid to move or preview it outside combat.' end
    return 'Unlock the indicator to drag it, then lock it to keep the position.'
   end
   local preview=control(br:IsPreviewShown() and 'Hide Preview' or 'Show Preview',292,-145,255,function()
    if br:IsPreviewShown() and not cfg.lockFrames then br:SetWidgetUnlocked(false) end
    br:SetPreview(not br:IsPreviewShown())
   end,positionHelp)
   local lock=control(cfg.lockFrames and 'Unlock Position' or 'Lock Position',18,-190,255,function()br:SetWidgetUnlocked(cfg.lockFrames) end,positionHelp)
   setActionEnabled(preview,br:CanConfigurePosition())
   setActionEnabled(lock,not cfg.lockFrames or br:CanConfigurePosition())
   control('Reset Position',292,-190,255,function()br:ResetPosition() end)
   label(body,'Show the Battle Resurrection button while in a raid.',18,-233,525)
   local size=br:GetWidgetScale()
   control('Size -',18,-263,120,function()br:SetWidgetScale(size-10) end)
   label(body,('Size: %g%%'):format(size),157,-272,130)
   control('Size +',292,-263,120,function()br:SetWidgetScale(size+10) end)
   control('Reset Defaults',18,-308,255,function()
    confirmReset('Reset Battle Resurrection display settings?',function()br:ResetWidgetDefaults() end)
   end)
   settingRow(body,'Zero charge overlay','Dim the Rebirth icon when no charges are available.',cfg,'zeroChargeOverlay',-366,
    function()rt:ApplySettings('battleResCounter') end)
   settingRow(body,'Show in Cooldowns','Show a Battle Resurrection row in the cooldown roster.',cfg,'rosterRowEnabled',-444,
    function()rt:ApplySettings('battleResCounter') end)
  end
 elseif active=='Raid Tools: Combat Advanced' then
  label(body,'Advanced Combat Settings',18,-14,530,'GameFontNormalLarge')
  button(body,'Back to Combat',18,-67,240,function()active='Raid Tools: Combat Tools';render() end)
  local mount=CreateFrame('Frame',nil,body)
  mount:SetPoint('TOPLEFT',body,'TOPLEFT',18,-132)
  mount:SetSize(550,760)
  if K.RaidTools and K.RaidTools.Mount then K.RaidTools.Mount(mount,'Combat Tools') end
 elseif active=='Raid Tools: Auto-Invite' then
  label(body,'INVITES',18,-14,540,'GameFontNormalLarge')
  label(body,'KEEPERS WAR COMMAND  /  RAID OPERATIONS',18,-56,540)
  local rt=KeepersRaidTools
  local settings=rt and rt.GetSetting and rt:GetSetting('autoInvite')
  if not settings then
   label(body,'Invite settings are unavailable. Check module initialization.',18,-105,520)
  else
   label(body,'WHISPER INVITATIONS',18,-104,530,'GameFontNormal')
   label(body,'Automatically invite players who whisper an exact keyword.',18,-138,520)
   local function toggle(title,key,y)
    button(body,(settings[key] and '[ON]  ' or '[OFF]  ')..title,18,y,320,function()
     settings[key]=not settings[key];render()
    end)
   end
   toggle('Enable whisper invitations','whisperInviteEnabled',-179)
   toggle('Guild members only','guildOnly',-222)
   label(body,'Invite keywords (separate with spaces)',18,-284,520,'GameFontNormal')
   local keywords=edit(body,settings.keywords or 'inv invite 123',18,-318,390)
   local function saveKeywords()
    local value=(keywords:GetText() or ''):gsub('^%s+',''):gsub('%s+$','')
    settings.keywords=value
    keywords:SetText(value)
    keywords:ClearFocus()
   end
   keywords:SetScript('OnEnterPressed',saveKeywords)
   keywords:SetScript('OnEditFocusLost',function(self)
    settings.keywords=(self:GetText() or ''):gsub('^%s+',''):gsub('%s+$','')
   end)
   button(body,'Save Keywords',419,-318,136,saveKeywords)
   label(body,'Example: inv invite 123',18,-369,520)
   label(body,'Whisper detection uses the existing raid-tools invite engine.',18,-398,535)
   label(body,'GROUP INVITES',18,-462,530,'GameFontNormal')
   label(body,'Invite guild members by rank using the existing invitation controls.',18,-495,535)
   button(body,'Open Guild Invite Controls',18,-534,300,function()
    active='Raid Tools: Auto-Invite Advanced';render()
   end)
  end
 elseif active=='Raid Tools: Auto-Invite Advanced' then
  label(body,'GUILD INVITE CONTROLS',18,-14,540,'GameFontNormalLarge')
  button(body,'Back to Invites',18,-66,240,function()active='Raid Tools: Auto-Invite';render() end)
  local mount=CreateFrame('Frame',nil,body)
  mount:SetPoint('TOPLEFT',body,'TOPLEFT',18,-130)
  mount:SetSize(550,760)
  if K.RaidTools and K.RaidTools.Mount then K.RaidTools.Mount(mount,'Auto-Invite') end
 elseif active=='Raid Tools: Attendance' then
  label(body,'Raid Attendance',18,-14,530,'GameFontNormalLarge')
  label(body,'OBSERVED RAID ATTENDANCE AND HISTORICAL RECORDS',18,-56,530)
  label(body,'RECENT RAID DAYS',18,-105,530,'GameFontNormal')
  local db=KeepersRaidToolsAttendanceDB or {}
  local days={}
  for day,records in pairs(db) do
   if type(day)=='string' and day:match('^%d%d%d%d%-%d%d%-%d%d$') and type(records)=='table' then
    days[#days+1]=day
   end
  end
  table.sort(days,function(a,b)return a>b end)
  if #days==0 then
   label(body,'No attendance has been recorded yet.',30,-158,510)
   label(body,'KWC records attendance through the integrated raid countdown system.',30,-187,510)
  end
  local y=-153
  for i=1,math.min(#days,15) do
   local day=days[i]
   local total,present=0,0
   for name,record in pairs(db[day]) do
    if type(name)=='string' and name:sub(1,2)~='__' then
     total=total+1
     local status=type(record)=='table' and record.status or record
     if status==3 then present=present+1 end
    end
   end
   surface(body,18,y+5,538,48,0.095)
   single(body,day,32,y-7,195,'GameFontNormal')
   single(body,tostring(present)..' present / '..tostring(total)..' recorded',251,y-7,286)
   y=y-58
  end
  label(body,'MANAGE ATTENDANCE',18,y-24,530,'GameFontNormal')
  label(body,'Open the complete records editor to review, correct, or sync attendance.',18,y-59,530)
  button(body,'Open Attendance Records',18,y-95,290,function()active='Raid Tools: Attendance Editor';render() end)
 elseif active=='Raid Tools: Roster' then
  label(body,'Raid Roster',18,-14,530,'GameFontNormalLarge')
  label(body,'CURRENT GROUP  /  LIVE PARTICIPANTS',18,-56,530)
  local size=(GetNumGroupMembers and GetNumGroupMembers()) or 0
  single(body,tostring(size)..' group members',18,-104,450,'GameFontNormal')
  local y=-150
  if size==0 then label(body,'Not currently in a party or raid.',18,y,500) end
  local prefix=IsInRaid and IsInRaid() and 'raid' or 'party'
  for i=1,math.min(size,40) do
   local unit=prefix..i
   if UnitExists(unit) then
    local name=GetUnitName and GetUnitName(unit,true) or UnitName(unit)
    local _,class=UnitClass(unit)
    surface(body,18,y+6,538,34,0.08)
    single(body,tostring(name or 'Unknown'),32,y,335,'GameFontNormal')
    single(body,tostring(class or ''),388,y,150)
    y=y-39
   end
  end
  label(body,'ROSTER MANAGEMENT',18,y-30,530,'GameFontNormal')
  label(body,'Manage saved players, specifications, and attendance imports.',18,y-64,530)
  button(body,'Open Roster Manager',18,y-101,285,function()active='Raid Tools: Roster Manager';render() end)
 elseif active=='Raid Tools: Attendance Editor' or active=='Raid Tools: Roster Manager' then
  local tab=active=='Raid Tools: Attendance Editor' and 'Attendance' or 'Roster'
  label(body,tab=='Attendance' and 'Attendance Records' or 'Roster Management',18,-14,530,'GameFontNormalLarge')
  button(body,'Back',18,-68,220,function()active='Raid Tools: '..tab;render() end)
  local mount=CreateFrame('Frame',nil,body)
  mount:SetPoint('TOPLEFT',body,'TOPLEFT',18,-133)
  mount:SetSize(550,760)
  if K.RaidTools and K.RaidTools.Mount then K.RaidTools.Mount(mount,tab) end
 elseif active=='Raid Tools: Sign-Ups' or active=='Raid Tools: Command' then
  local module=active=='Raid Tools: Command' and K.RaidCommand or K.RaidSignup
  if module then
   module.Draw(body,function(p,t,x,y,...) return label(p,t,x,y-53,...) end,
    function(p,t,x,y,...) return button(p,t,x,y-53,...) end,
    function(p,t,x,y,...) return edit(p,t,x,y-53,...) end)
  end
 elseif active:sub(1,12)=='Raid Tools: ' then
  local tab=active:sub(13)
  local titles={['Attendance']='Operations / Attendance',['Roster']='Operations / Raid Roster',
    ['Ready Check']='Raids / Readiness',['Combat Tools']='Combat',
    ['Auto-Invite']='Raids / Invites',["Don't Release"]='Raids / Death Protection',
    ['Notes']='Command / Notes'}
  label(body,titles[tab] or 'RAID OPERATIONS',18,-14,540,'GameFontNormalLarge')
  label(body,'KEEPERS WAR COMMAND  /  RAID OPERATIONS',18,-56,540)
  button(body,'Back to Raid Operations',18,-89,240,function()active='Raid Tools';render() end)
  local mount=CreateFrame('Frame',nil,body)
  mount:SetPoint('TOPLEFT',body,'TOPLEFT',18,-138)
  mount:SetSize(550,760)
  if not (K.RaidTools and K.RaidTools.Mount and K.RaidTools.Mount(mount,tab)) then
   label(body,'Raid module could not initialize. Check Lua errors and reload.',18,-120,535)
  end
 elseif active=='CTA Entry' then
  label(body,'NEW CALL TO ARMS  /  Request reinforcements',12,-12,570,'GameFontNormalLarge')
  button(body,'View Calls to Arms',365,-42,170,function()active='CTA Board';render() end)
  label(body,'Zone / location',12,-47,280)
  local zone=edit(body,GetZoneText and GetZoneText() or '',12,-69,265)
  button(body,'Current zone',292,-69,145,function()zone:SetText(GetZoneText and GetZoneText() or '') end)
  label(body,'Horde already there',12,-110,245)
  label(body,'Alliance spotted',280,-110,245)
  local horde=edit(body,'0',12,-132,225)
  local alliance=edit(body,'0',280,-132,225)
  label(body,'Map coordinates / landmark (optional)',12,-173,550)
  local coords=edit(body,'',12,-195,510)
  label(body,'What is happening / objective?',12,-235,550)
  local objective=edit(body,'Need reinforcements',12,-257,540)
  label(body,'Extra details (optional)',12,-297,550)
  local notes=edit(body,'',12,-319,540)
  local priorities={'LOW','NORMAL','HIGH','URGENT'}
  local priorityIndex=2
  button(body,'Priority: NORMAL',12,-363,200,function(self)
   priorityIndex=priorityIndex%#priorities+1
   self:SetText('Priority: '..priorities[priorityIndex])
  end)
  button(body,'POST CALL TO ARMS',230,-363,310,function()
   K.Operations.DetailedCTA(zone:GetText(),objective:GetText(),horde:GetText(),alliance:GetText(),priorities[priorityIndex],coords:GetText(),notes:GetText())
  end)
  label(body,'Counts are member estimates, not live population data.',12,-406,565)
 elseif active=='Edit Entry' then
  local entries=editingKind=='CTA' and d.ops or d.bounties
  local current
  for _,v in ipairs(entries or {}) do if v.id==editingId then current=v;break end end
  label(body,'EDIT '..(editingKind=='CTA' and 'CALL TO ARMS' or 'BOUNTY'),12,-12,550,'GameFontNormalLarge')
  if current and editingKind=='CTA' then
   local d0=current.details or {}
   label(body,'Location',12,-62,520)
   local zone=edit(body,d0.zone or (current.text:match('%] ([^|]+)') or ''),12,-84,510)
   label(body,'Horde present',12,-126,240);label(body,'Alliance present',275,-126,240)
   local h=edit(body,tostring(d0.horde or 0),12,-148,220);local a=edit(body,tostring(d0.alliance or 0),275,-148,220)
   label(body,'Objective',12,-192,520)
   local obj=edit(body,d0.objective or current.text,12,-214,530)
   label(body,'Additional intelligence',12,-256,520)
   local notes=edit(body,d0.notes or '',12,-278,530)
   local priorities={'LOW','NORMAL','HIGH','URGENT'}
   local stored=d0.priority or (d0.urgent and 'URGENT') or (current.text or ''):match('^%[([A-Z]+)%]') or 'NORMAL'
   local priorityIndex=2
   for i,v in ipairs(priorities) do if v==stored then priorityIndex=i;break end end
   button(body,'Priority: '..priorities[priorityIndex],12,-320,210,function(self)
    priorityIndex=priorityIndex%#priorities+1
    self:SetText('Priority: '..priorities[priorityIndex])
   end)
   button(body,'Save Call to Arms Update',238,-320,270,function()
    K.Operations.UpdateCTA(editingId,zone:GetText(),h:GetText(),a:GetText(),obj:GetText(),priorities[priorityIndex],notes:GetText())
    active='CTA Board';render()
   end)
  elseif current and editingKind=='BOUNTY' then
   local d0=current.details or {}
   label(body,'Target name',12,-62,520)
   local target=edit(body,d0.target or current.text:match('^([^ %-]+)') or '',12,-84,530)
   label(body,'Last known location',12,-126,520)
   local location=edit(body,d0.location or '',12,-148,530)
   label(body,'Reason / details',12,-192,520)
   local reason=edit(body,d0.reason or current.text,12,-214,530)
   label(body,'Reward (optional)',12,-256,520)
   local reward=edit(body,d0.reward or '',12,-278,530)
   button(body,'SAVE BOUNTY UPDATE',12,-330,240,function()
    K.Operations.UpdateBounty(editingId,target:GetText(),location:GetText(),reason:GetText(),reward:GetText())
    active='Bounty Board';render()
   end)
  else label(body,'Entry no longer exists.',12,-65,540) end
  button(body,'Back to Board',12,-395,200,function()active=editingKind=='CTA' and 'CTA Board' or 'Bounty Board';render() end)
 elseif active=='CTA Board' then
  label(body,'Calls to arms',18,-16,530,'GameFontNormalLarge')
  button(body,'New Call to Arms',12,-48,165,function()active='CTA Entry';render() end)
  button(body,'Report to Guild',190,-48,170,function()K.Operations.ListActive('CTA',true) end,
   'Posts the active Calls to Arms to guild chat.')
  button(body,'Attendance History',372,-48,182,function()active='CTA Attendance';render() end)
  for i,v in ipairs({'ACTIVE','RESOLVED','ALL'}) do
   button(body,v,12+(i-1)*165,-92,155,function()boardFilter.CTA=v;render() end,nil,boardFilter.CTA==v)
  end
  local shown=0
  for _,a in ipairs(d.ops) do
   local status=a.status or 'ACTIVE'
   if boardFilter.CTA=='ALL' or boardFilter.CTA==status or (boardFilter.CTA=='RESOLVED' and status=='CANCELLED') then
    shown=shown+1;if shown>20 then break end
    local y=-146-(shown-1)*105
    surface(body,12,y+8,545,94,0.10)
    local priority=a.details and a.details.priority
    single(body,tostring(a.time or '')..'  /  '..status..(priority and ('  /  '..priority) or ''),23,y,514,'GameFontNormal')
    local desc=label(body,K.Operations.FactionText(a),23,y-25,510);desc:SetMaxLines(1);desc:SetWordWrap(false)
    local rs=d.responses and d.responses[a.id] or {};local coming=0
    for _,v in pairs(rs) do if v=='Coming' then coming=coming+1 end end
    local leaders=K.Operations.CTALeadership(a)
    local heading=(leaders.warchief and ('War Chief: '..leaders.warchief..'   |   ') or '')..'Commander: '..tostring(leaders.creator)
    if #leaders.officers>0 then heading=heading..'   |   Co-Commander: '..table.concat(leaders.officers,', ') end
    local leadLabel=label(body,heading,23,y-46,365);leadLabel:SetMaxLines(1);leadLabel:SetWordWrap(false)
    label(body,'Reinforcements: '..coming,23,y-65,355)
    button(body,'View Details',405,y-49,145,function()selectedCTA=a.id;active='CTA Details';render() end)
   end
  end
  if shown==0 then label(body,'No operations in this view.',12,-155,500) end
 elseif active=='CTA Details' then
  local a;for _,entry in ipairs(d.ops) do if entry.id==selectedCTA then a=entry;break end end
  button(body,'Back to Calls to Arms',12,-12,170,function()active='CTA Board';render() end)
  if a then
   label(body,'OPERATION DETAILS',12,-62,545,'GameFontNormalLarge')
   label(body,K.Operations.FactionText(a),12,-112,545)
   local leaders=K.Operations.CTALeadership(a)
   local priority=a.details and a.details.priority
   label(body,'Status: '..tostring(a.status or 'ACTIVE')..(priority and ('  /  Priority: '..priority) or ''),12,-162,545)
   local rs=d.responses and d.responses[a.id] or {};local coming,maybe,busy=0,0,0
   for _,v in pairs(rs) do if v=='Coming' then coming=coming+1 elseif v=='Maybe' then maybe=maybe+1 elseif v=='Busy' then busy=busy+1 end end
   local ly=-184
   if leaders.warchief then label(body,'War Chief: '..leaders.warchief,12,ly,545);ly=ly-22 end
   label(body,'Commander: '..tostring(leaders.creator or '?'),12,ly,545);ly=ly-22
   if #leaders.officers>0 then single(body,'Co-Commander: '..table.concat(leaders.officers,', '),12,ly,545);ly=ly-22 end
   label(body,'Coming: '..coming..'     Maybe: '..maybe..'     Busy: '..busy,12,ly-2,545,'GameFontNormal')
   label(body,'YOUR RESPONSE',12,-260,540,'GameFontNormal')
   button(body,'Coming',12,-292,115,function()K.Operations.Respond(a.id,'Coming');render() end)
   button(body,'Maybe',137,-292,115,function()K.Operations.Respond(a.id,'Maybe');render() end)
   button(body,'Busy',262,-292,115,function()K.Operations.Respond(a.id,'Busy');render() end)
   button(body,'Roster',387,-292,155,function()editingId=a.id;active='CTA Roster';render() end)
   if a.status=='ACTIVE' then
    button(body,'Join the Fight',12,-324,180,function()K.CTAJoin.Request(a.id) end)
    local requests=K.CTAJoin.Pending(a.id)
    if #requests>0 then
     label(body,'INVITE REQUESTS',210,-326,340,'GameFontNormal')
     for i=1,math.min(3,#requests) do
      local name=requests[i]
      button(body,'Invite '..name,210,-348-(i-1)*27,335,function()K.CTAJoin.Invite(a.id,name) end)
     end
    end
   end
   label(body,'MANAGE OPERATION',12,-446,540,'GameFontNormal')
   button(body,'Guild Report',12,-484,160,function()K.Operations.Report('CTA',a.id) end)
   button(body,'Discord Export',184,-484,160,function()showDiscordExport('CTA',a) end)
   button(body,'Draft OV',12,-530,160,function()K.Operations.DraftExternal('CTA',a.id,'OV') end)
   button(body,'Draft War Effort',184,-530,175,function()K.Operations.DraftExternal('CTA',a.id,'WE') end)
   if a.status=='ACTIVE' then
    button(body,'Resolve',12,-576,125,function()K.Operations.ChangeStatus('CTA',a.id,'RESOLVED');render() end)
    button(body,'Cancel',147,-576,125,function()K.Operations.ChangeStatus('CTA',a.id,'CANCELLED');render() end)
   else button(body,'Reopen',12,-576,125,function()K.Operations.ChangeStatus('CTA',a.id,'ACTIVE');render() end) end
   button(body,'Edit',282,-576,125,function()editingKind='CTA';editingId=a.id;active='Edit Entry';render() end)
   if K.Operations.CanDelete(a) then
    button(body,'Delete Guild-Wide',12,-622,180,function()
     StaticPopupDialogs['KWC_CONFIRM_DELETE']={text='Permanently delete this %s for the guild? This cannot be undone.',button1='Delete',button2='Cancel',OnAccept=function(_,data)
      if K.Operations.Delete(data.kind,data.id) then selectedCTA=nil;selectedBounty=nil;active=data.kind=='CTA' and 'CTA Board' or 'Bounty Board';render() end
     end,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3}
     StaticPopup_Show('KWC_CONFIRM_DELETE','Call to Arms',nil,{kind='CTA',id=a.id})
    end)
   end
  end
 elseif active=='War Room' then
  label(body,'WAR ROOM  /  Operations command',12,-12,565,'GameFontNormalLarge')
  label(body,'Review active Calls to Arms, commanders, and guild responses.',12,-52,565)
  button(body,'New Call to Arms',12,-85,165,function()active='CTA Entry';render() end)
  button(body,'Request guild sync',189,-85,175,function()K.Operations.RequestSync() end)
  button(body,'Scout Network',376,-85,175,function()active='Scout Network';render() end)
  local entries=K.WarRoom.Active()
  label(body,'ACTIVE OPERATIONS  ('..#entries..')',12,-140,560,'GameFontNormal')
  for i,e in ipairs(entries) do
   if i>12 then break end
   local y=-180-(i-1)*125
   surface(body,12,y+9,545,115,0.095)
   local c,m,b=K.WarRoom.Roster(e)
   single(body,((e.details and e.details.urgent) and '[URGENT] ' or '')..tostring(e.text or ''),22,y,525,'GameFontNormal')
   local leaders=K.Operations.CTALeadership(e)
   local leadership=(leaders.warchief and ('War Chief: '..leaders.warchief..'  |  ') or '')..'Commander: '..tostring(leaders.creator)
   if #leaders.officers>0 then leadership=leadership..'  |  Co-Commander: '..table.concat(leaders.officers,', ') end
   single(body,leadership,22,y-28,525)
   label(body,'Coming: '..c..'  Maybe: '..m..'  Busy: '..b,22,y-47,525)
   button(body,'Respond',12,y-61,125,function()active='CTA Board';render() end)
   button(body,'After-action report',151,y-61,185,function()selectedAAR=e.id;active='After Action';render() end)
   button(body,'View Operation',350,y-61,145,function()selectedCTA=e.id;active='CTA Details';render() end)
  end
  if #entries==0 then label(body,'No active Calls to Arms. Create one or request a board sync.',12,-190,550) end
 elseif active=='Scout Network' then
  label(body,'Scout network',12,-12,560,'GameFontNormalLarge')
  settingLink(body,'Auto Scout Settings',357,-43,195,6)
  label(body,'Manual reports are local. Auto Scout can share sightings.',12,-48,336)
  label(body,'Auto Scout starts enabled by default; /kt autoscout off disables it.',12,-69,540)
  label(body,'Zone',12,-91,120)
  local zone=edit(body,GetZoneText and GetZoneText() or '',12,-113,250)
  label(body,'Enemy / guild',282,-91,270)
  local enemy=edit(body,'',282,-113,270)
  label(body,'Enemy count',12,-160,170)
  local qty=edit(body,'1',12,-183,150)
  label(body,'Details / landmark',180,-160,350)
  local notes=edit(body,'',180,-183,370)
  button(body,'Save scout report',12,-230,225,function()K.WarRoom.ReportScout(zone:GetText(),enemy:GetText(),qty:GetText(),notes:GetText()) end)
  button(body,'War Room',251,-230,160,function()active='War Room';render() end)
  label(body,'RECENT SIGHTINGS (LOCAL + GUILD AUTO)',12,-300,540,'GameFontNormal')
  for i,r in ipairs(d.scoutReports or {}) do
   if i>18 then break end
   label(body,tostring(r.when)..'  '..tostring(r.zone)..'  |  '..tostring(r.enemy)..' x'..tostring(r.count),12,-334-(i-1)*58,545)
   label(body,tostring(r.notes or '')..'  /  '..tostring(r.author or '?'),12,-359-(i-1)*58,545)
  end
 elseif active=='After Action' then
  label(body,'AFTER-ACTION REPORTS  /  Development preview',12,-12,565,'GameFontNormalLarge')
  label(body,'Local draft records; no automatic kill verification or guild sync.',12,-47,560)
  local choices={}
  for _,e in ipairs(d.ops or {}) do if #choices>=8 then break end;choices[#choices+1]=e end
  local picked=selectedAAR
  if not picked and choices[1] then picked=choices[1].id end
  label(body,'Choose operation:',12,-90,520,'GameFontNormal')
  for i,e in ipairs(choices) do
   local y=-125-(i-1)*37
   button(body,(picked==e.id and '* ' or '')..tostring(e.text or ''):sub(1,55),12,y,540,function()selectedAAR=e.id;render() end)
  end
  local base=-145-#choices*37
  label(body,'Outcome (Victory / Defeat / Draw / Other)',12,base,530)
  local outcome=edit(body,'Victory',12,base-24,240)
  label(body,'Estimated enemy kills',275,base,260)
  local kills=edit(body,'0',275,base-24,200)
  label(body,'Notes',12,base-72,520)
  local notes=edit(body,'',12,base-96,540)
  button(body,'Save AAR locally',12,base-141,210,function()K.WarRoom.SaveAAR(picked or '',outcome:GetText(),kills:GetText(),notes:GetText()) end)
  button(body,'War Room',235,base-141,150,function()active='War Room';render() end)
  label(body,'RECENT REPORTS',12,base-195,520,'GameFontNormal')
  for i,r in ipairs(d.afterAction or {}) do
   if i>10 then break end
   label(body,tostring(r.when)..'  '..tostring(r.result)..'  |  '..tostring(r.title):sub(1,65),12,base-231-(i-1)*54,550)
   label(body,'Estimated kills: '..tostring(r.kills)..'  |  '..tostring(r.notes or ''),12,base-253-(i-1)*54,550)
  end
 elseif active=='CTA Roster' then
  label(body,'Call to Arms Response Roster',12,-12,550,'GameFontNormalLarge')
  button(body,'Back to Calls to Arms',12,-47,210,function()active='CTA Board';render() end)
  local current;for _,e in ipairs(d.ops) do if e.id==editingId then current=e;break end end
  if current then
   label(body,current.text,12,-92,545)
   local names={};for name,response in pairs((d.responses or {})[editingId] or {}) do
    names[#names+1]={name=name,response=response}
   end
   table.sort(names,function(a,b)return a.name<b.name end)
   if #names==0 then label(body,'No responses yet.',12,-130,545) end
   for i,v in ipairs(names) do if i>55 then break end
    label(body,v.name..'  |  '..tostring(v.response),12,-130-(i-1)*28,540)
   end
  else label(body,'Call to Arms not found.',12,-100,540) end
 elseif active=='World PvP Deaths' then
  label(body,'WORLD PVP DEATH INTELLIGENCE',12,-12,555,'GameFontNormalLarge')
  label(body,'Recent guild reports. Suspected attackers are not confirmed killing blows.',12,-43,555)
  button(body,'Test death alert',12,-75,180,function()K.WorldPvPDeaths.Demo();render() end)
  button(body,'Back to Overview',205,-75,185,function()active='Overview';render() end)
  for i,e in ipairs(d.worldPvPDeaths or {}) do
   if i>75 then break end
   local y=-122-(i-1)*73
   label(body,tostring(e.at or '?')..'  '..tostring(e.victim or '?')..'  slain by  '..tostring(e.killer or '?'),12,y,555,'GameFontNormal')
   label(body,tostring(e.zone or '?')..'  |  '..tostring(e.method or 'Reported by victim'),12,y-24,555)
   if e.killer and e.killer~='Unknown Alliance attacker' then
    button(body,'Bounty',470,y-4,88,function()U.OpenBountyForName(e.killer) end)
   end
  end
 elseif active=='Bounty Entry' then
  label(body,'NEW BOUNTY  /  All guild members can submit',12,-12,565,'GameFontNormalLarge')
  button(body,'View Bounty Board',350,-40,190,function()active='Bounty Board';render() end)
  label(body,'Enemy character name',12,-48,520)
  local target=edit(body,pendingBountyTarget or '',12,-72,350)
  pendingBountyTarget=nil
  label(body,'Reason or location (optional)',12,-115,520)
  local reason=edit(body,'',12,-139,540)
  label(body,'Reward (optional; not automatically paid)',12,-182,520)
  local reward=edit(body,'',12,-206,330)
  button(body,'POST BOUNTY',12,-249,220,function()K.Operations.QuickBounty(target:GetText(),reason:GetText(),reward:GetText()) end)
  label(body,'Bounties are player-submitted and unverified.',12,-291,565)
 elseif active=='Report Sighting' then
  local current=activeBounty(editingId)
  label(body,'REPORT ENEMY SIGHTING',12,-12,550,'GameFontNormalLarge')
  if current then
   label(body,'Target: '..current.text,12,-60,540)
   label(body,'Zone / landmark',12,-103,520)
   local zone=edit(body,GetZoneText and GetZoneText() or '',12,-125,530)
   label(body,'Additional details',12,-166,520)
   local note=edit(body,'',12,-188,530)
   button(body,'SUBMIT SIGHTING',12,-240,240,function()if activeBounty(editingId) then K.Operations.AddSighting(editingId,zone:GetText(),note:GetText()) end;active='Bounty Board';render() end)
  else label(body,'Select an active bounty before reporting a sighting.',12,-60,530) end
  button(body,'Back to Bounty Board',12,-290,230,function()active='Bounty Board';render() end)
 elseif active=='Bounty Board' then
  label(body,'Bounty board',18,-16,530,'GameFontNormalLarge')
  settingLink(body,'Bounty Alert Settings',377,-10,180,10)
  local available=math.min(545,body:GetWidth()-24)
  local gap,minimum=12,155
  local columns=math.max(1,math.min(3,math.floor((available+gap)/(minimum+gap))))
  local width=math.floor((available-(columns-1)*gap)/columns)
  local function action(index,caption,callback,help)
   local column=(index-1)%columns
   local row=math.floor((index-1)/columns)
   return button(body,caption,12+column*(width+gap),-50-row*42,width,callback,help)
  end
  action(1,'New Bounty',function() active='Bounty Entry';render() end)
  local sighting=action(2,'Report Sighting',function()
   if not activeBounty(selectedBounty) then return end
   editingId=selectedBounty;active='Report Sighting';render()
  end,function()
   return activeBounty(selectedBounty) and 'Open the zone and notes form for this bounty.' or 'Select an active bounty first.'
  end)
  local selected=activeBounty(selectedBounty)
  setActionEnabled(sighting,selected~=nil)
  bountyCapture=action(3,'Capture Target',function()
   if U.GetBountyPlayerName('target') then U.OpenBountyForUnit('target') end
  end,function()
   return U.GetBountyPlayerName('target') and 'Use your current player target in the new bounty form.' or 'Target a valid player first.'
  end)
  setActionEnabled(bountyCapture,U.GetBountyPlayerName('target')~=nil)
  local nextRow=-50-math.ceil(3/columns)*42
  button(body,'Report to Guild',12,nextRow,155,function()K.Operations.ListActive('BOUNTY',true) end,
   'Posts the active bounties to guild chat.')
  local target=selected and ((selected.details and selected.details.target) or selected.text)
  single(body,target and ('Selected: '..target) or 'Select an active bounty to report a sighting.',180,nextRow-9,365)
  local filterY=nextRow-45
  for i,v in ipairs({'ACTIVE','COMPLETED','ALL'}) do
   button(body,v,12+(i-1)*165,filterY,155,function()boardFilter.BOUNTY=v;selectedBounty=nil;render() end,nil,boardFilter.BOUNTY==v)
  end
  local shown=0
  for _,b in ipairs(d.bounties) do
   local status=b.status or 'ACTIVE'
   if boardFilter.BOUNTY=='ALL' or boardFilter.BOUNTY==status or (boardFilter.BOUNTY=='COMPLETED' and status=='CANCELLED') then
    shown=shown+1;if shown>20 then break end
    local y=filterY-54-(shown-1)*110
    local panel=body:CreateTexture(nil,'BACKGROUND');panel:SetPoint('TOPLEFT',12,y+8);panel:SetSize(545,99);panel:SetColorTexture(0.095,0.115,0.15,0.96)
    local target=(b.details and b.details.target) or b.text or 'Unknown target'
    local reward=(b.details and b.details.reward) or (b.text or ''):match('[Rr]eward:%s*([^|]+)') or 'Not listed'
    button(body,(selectedBounty==b.id and '> ' or '')..tostring(target),23,y+2,350,function()selectedBounty=b.id;render() end,nil,selectedBounty==b.id)
    label(body,status,420,y,125,'GameFontNormal')
    label(body,'Reward: '..tostring(reward),23,y-36,350)
    local last=(b.sightings or {})[1]
    label(body,'Sightings: '..#(b.sightings or {})..'   |   Last: '..tostring(last and last.zone or 'Unknown'),23,y-62,365)
    button(body,'View Details',405,y-52,145,function()selectedBounty=b.id;active='Bounty Details';render() end)
   end
  end
  if shown==0 then label(body,'No bounties in this view.',12,filterY-63,500) end
 elseif active=='Bounty Details' then
  local b;for _,entry in ipairs(d.bounties) do if entry.id==selectedBounty then b=entry;break end end
  button(body,'< Back to Bounties',12,-12,185,function()active='Bounty Board';render() end)
  if b then
   local target=(b.details and b.details.target) or b.text or 'Unknown target'
   local reward=(b.details and b.details.reward) or (b.text or ''):match('[Rr]eward:%s*([^|]+)') or 'Not listed'
   label(body,'BOUNTY DETAILS',12,-62,545,'GameFontNormalLarge')
   local name=label(body,tostring(target),12,-112,540,'GameFontNormal');name:SetMaxLines(2)
   label(body,'Reward: '..tostring(reward)..'   |   Status: '..tostring(b.status or 'ACTIVE'),12,-163,545)
   label(body,'Posted by '..tostring(b.author or '?')..' on '..tostring(b.time or '?'),12,-192,545)
   local last=(b.sightings or {})[1]
   label(body,'Sightings: '..#(b.sightings or {})..'   |   Last seen: '..tostring(last and last.zone or 'Unknown'),12,-220,545)
   label(body,'HUNT THE TARGET',12,-272,545,'GameFontNormal')
   if activeBounty(b.id) then
    button(body,'Claim Kill',12,-307,155,function()K.Operations.ClaimBounty(b.id) end)
    button(body,'Report Sighting',180,-307,180,function()if activeBounty(b.id) then editingId=b.id;active='Report Sighting';render() end end)
   end
   button(body,'Sighting History',12,-354,175,function()editingId=b.id;active='Sighting History';render() end)
   if K.GuildService then
    local pending=K.GuildService.Pending(b.id)
    if #pending>0 then
     label(body,'Pending claim: '..pending[1],207,-355,333)
     if K.IsOfficer() then button(body,'Approve Claim',385,-385,165,function()K.GuildService.Approve(b.id,pending[1]);render() end) end
    end
   end
   label(body,'MANAGE BOUNTY',12,-415,545,'GameFontNormal')
   if b.status=='ACTIVE' then
    button(body,'Complete',12,-450,135,function()K.Operations.ChangeStatus('BOUNTY',b.id,'COMPLETED');render() end)
    button(body,'Cancel',157,-450,135,function()K.Operations.ChangeStatus('BOUNTY',b.id,'CANCELLED');render() end)
   else button(body,'Reopen',12,-450,135,function()K.Operations.ChangeStatus('BOUNTY',b.id,'ACTIVE');render() end) end
   button(body,'Edit',307,-450,135,function()editingKind='BOUNTY';editingId=b.id;active='Edit Entry';render() end)
   button(body,'Guild Report',12,-500,160,function()K.Operations.Report('BOUNTY',b.id) end)
   button(body,'Discord Export',184,-500,160,function()showDiscordExport('BOUNTY',b) end)
   button(body,'Draft OV',12,-550,160,function()K.Operations.DraftExternal('BOUNTY',b.id,'OV') end)
   button(body,'Draft War Effort',184,-550,175,function()K.Operations.DraftExternal('BOUNTY',b.id,'WE') end)
   if K.Operations.CanDelete(b) then
    button(body,'Delete Guild-Wide',375,-550,175,function()
     StaticPopupDialogs['KWC_CONFIRM_DELETE']={text='Permanently delete this %s for the guild? This cannot be undone.',button1='Delete',button2='Cancel',OnAccept=function(_,data)
      if K.Operations.Delete(data.kind,data.id) then selectedCTA=nil;selectedBounty=nil;active=data.kind=='CTA' and 'CTA Board' or 'Bounty Board';render() end
     end,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3}
     StaticPopup_Show('KWC_CONFIRM_DELETE','Bounty',nil,{kind='BOUNTY',id=b.id})
    end)
   end
  end
 elseif active=='Sighting History' then
  label(body,'BOUNTY SIGHTING HISTORY',12,-12,550,'GameFontNormalLarge')
  button(body,'Back to Bounty Board',12,-50,225,function()active='Bounty Board';render() end)
  local current;for _,e in ipairs(d.bounties) do if e.id==editingId then current=e;break end end
  if current then
   label(body,'Target: '..tostring(current.details and current.details.target or current.text),12,-100,545)
   local sightings=current.sightings or {}
   if #sightings==0 then label(body,'No sightings reported.',12,-140,540) end
   for i,v in ipairs(sightings) do if i>15 then break end
    local y=-145-(i-1)*65
    label(body,tostring(v.zone or '?')..'  |  '..tostring(v.at or '?'),12,y,545,'GameFontNormal')
    label(body,'Reported by '..tostring(v.who or '?')..'  '..tostring(v.note or ''),12,y-25,545)
   end
   label(body,'Reports are player-submitted, not live location tracking.',12,-1180,545)
  end
 elseif active=='Sync Health' then
  label(body,'Guild Sync Health',12,-12,500,'GameFontNormalLarge')
  settingLink(body,'Sync Settings',395,-8,157,4)
  label(body,'Sync requests Calls to Arms, bounties, deletions, and honor. Peers reply automatically.',12,-43,580)
  local h=K.Sync and K.Sync.Health and K.Sync.Health()
  if h then
   surface(body,12,-69,548,82,0.10)
   label(body,'BOARD TRAFFIC',22,-76,156,'GameFontNormal')
   label(body,('Requests %d  /  Legacy queued %d  /  Received %d'):format(h.requests,h.sent,h.received),184,-76,366)
   label(body,('Applied records %d  /  Handler rejections %d'):format(h.applied,h.rejected),22,-105,520)
   local age=h.lastReceived>0 and (time()-h.lastReceived) or nil
   label(body,'Last message: '..(age and (age..' seconds ago') or 'None'),22,-128,520)
   local peers={}
   for name,v in pairs(h.peers) do peers[#peers+1]={name=name,age=time()-v.lastSeen,count=v.received} end
   table.sort(peers,function(a,b)return a.age<b.age end)
   label(body,'Recent Peers',12,-163,500,'GameFontNormal')
   if #peers==0 then label(body,'No addon peers observed yet.',12,-187,570) end
   for i=1,math.min(11,#peers) do
    local v=peers[i]
    label(body,v.name..' | '..v.age..'s ago | '..v.count..' messages',12,-181-i*24,570)
   end
  end
  local queued,sent,errors,dropped=K.Net.Status()
  surface(body,12,-465,548,112,0.10)
  label(body,('Transport (all protocols): %d queued / %d accepted / %d errors / %d dropped'):format(queued,sent,errors,dropped),22,-474,525)
  button(body,'Sync All Guild Data',12,-510,190,function()if K.Sync then K.Sync.RequestAll(false) end;render() end,
   'Requests current shared records from compatible guildmates. Private settings stay local.')
  button(body,'Refresh Diagnostics',216,-510,190,function()render() end)
  local pvp=K.PvP.Diagnostics()
  label(body,('PvP honor queued: %d  /  PvP records applied: %d  /  PvP rejections: %d'):format(pvp.sent,pvp.received,pvp.rejected),22,-552,525)
  local outcomes,recent=K.Sync.Outcomes()
  local rows={}
  for protocol,counts in pairs(outcomes) do
   for reason,count in pairs(counts) do rows[#rows+1]=protocol..'  /  '..reason..': '..count end
  end
  table.sort(rows)
  label(body,'Packet Outcomes',12,-598,560,'GameFontNormal')
  label(body,'Outcomes include duplicates, stale revisions, and valid no-ops.',12,-624,560)
  local y=-648
  for _,row in ipairs(rows) do
   label(body,row,12,y,560);y=y-24
  end
  if outcomes['KWC3 PvP'] and outcomes['KWC3 PvP']['Unsupported PvP protocol'] then
   label(body,'Compatibility: a guild peer sent an unsupported PvP protocol. Compare builds in Addon Checker.',12,y-8,550)
   y=y-65
  end
  label(body,'RECENT OUTCOMES (no payloads)',12,y-12,560,'GameFontNormal')
  y=y-43
  for i=#recent,math.max(1,#recent-7),-1 do
   local event=recent[i]
   label(body,event.protocol..'  /  '..event.reason..'  /  '..math.max(0,time()-event.at)..'s ago',12,y,560)
   y=y-24
  end
 elseif active=='Addon Checker' then
  label(body,'ADDON CHECKER  /  Guild clients',12,-12,565,'GameFontNormalLarge')
  label(body,'Check online guildmates to see which addon versions are responding.',12,-47,565)
  button(body,'Check Online Guildmates',12,-80,245,function()K.AddonChecker.Request();render() end,
   'Requests version reports from online guildmates with compatible KWC builds.')
  button(body,'Refresh View',270,-80,150,function()render() end)
  local me,ver=K.AddonChecker.Self()
  label(body,'YOU: '..me..'  |  v'..ver..'  |  Installed',12,-134,565,'GameFontNormal')
  label(body,'Search player or version',12,-168,540)
  localFilter(body,checkerQuery,12,-190,340,function(value) checkerQuery=value end)
  local peers={}
  for _,peer in ipairs(K.AddonChecker.Entries()) do
   if (peer.name..' '..tostring(peer.version or '')):lower():find(checkerQuery:lower(),1,true) then peers[#peers+1]=peer end
  end
  label(body,'PLAYER',12,-237,215,'GameFontNormal')
  label(body,'VERSION',237,-237,122,'GameFontNormal')
  label(body,'STATUS',372,-237,190,'GameFontNormal')
  if #peers==0 then label(body,'No detected clients match this view.',12,-270,565) end
  for i=1,math.min(15,#peers) do
   local p=peers[i]
   local age=math.max(0,time()-(p.lastSeen or time()))
   local status=p.unsupported and 'Unsupported checker protocol' or p.legacy and 'Legacy / unknown' or (p.version==K.version and 'Current' or 'Different version')
   local y=-242-i*38
   if i%2==1 then surface(body,12,y+5,553,36,0.085) end
   single(body,p.name,18,y,209)
   single(body,p.legacy and 'Unknown' or ('v'..tostring(p.version or '?')),237,y,122)
   label(body,status..'  /  '..age..'s ago',372,y,184)
  end
  button(body,'Back to Settings',12,-286-math.min(15,#peers)*38,190,function()navigate('Settings') end)
 elseif active=='Settings Search' then
  label(body,'Settings Search',12,-12,565,'GameFontNormalLarge')
  button(body,'Back to Settings',379,-49,174,function()navigate('Settings') end)
  local query=edit(body,settingsQuery,12,-53,345)
  local results={}
  for _,entry in ipairs(settingIndex) do
   local row=CreateFrame('Frame',nil,body)
   row:SetSize(560,74)
   surface(row,12,0,541,74,0.09)
   button(row,entry[1],21,-7,263,function()openSetting(entry) end)
   label(row,entry[2]..(entry[6] and '  /  '..entry[6] or ''),297,-17,244)
   label(row,entry[3],24,-48,517)
   results[#results+1]=row
  end
  local firstResultY=-212
  local empty=label(body,'No settings match this search.',12,firstResultY-8,541)
  local function showSettings()
   local term=settingsQuery:lower():gsub('^%s+',''):gsub('%s+$','')
   local y=firstResultY
   for i,entry in ipairs(settingIndex) do
    local keywords=table.concat({entry[1],entry[2],entry[3],entry[7] or ''},' '):lower()
    local matches=true
    for word in term:gmatch('%S+') do if not keywords:find(word,1,true) then matches=false;break end end
    local visible=matches and (settingsCategory=='' or settingsCategory==entry[2])
    local row=results[i]
    row:SetShown(visible)
    if visible then
     row:ClearAllPoints()
     row:SetPoint('TOPLEFT',body,'TOPLEFT',0,y)
     y=y-83
    end
   end
   empty:SetShown(y==firstResultY)
   local height=math.max(500,16-y)
   body:SetHeight(height);scrollChild:SetHeight(height)
   scroll:SetVerticalScroll(0)
  end
  local categories={'All Settings','General','Interface & Minimap','Alerts','World PvP','Raids','Guild & Sharing','Sync & Network','Advanced'}
  for i,category in ipairs(categories) do
   local value=i==1 and '' or category
   button(body,category,12+((i-1)%3)*183,-89-math.floor((i-1)/3)*38,175,function()
    settingsCategory=value;render()
   end,nil,settingsCategory==value)
  end
  query:SetScript('OnTextChanged',function(self)
   settingsQuery=self:GetText()
   showSettings()
  end)
  showSettings()
 elseif active=='Settings' then
  label(body,'Settings Center',12,-12,565,'GameFontNormalLarge')
  label(body,'Find a setting or open a section.',12,-61,230)
  button(body,'Search Settings',250,-51,220,function()
   settingsQuery,settingsCategory='','';navigate('Settings Search')
  end)
  label(body,'WINDOW SIZE',12,-410,540,'GameFontNormal')
  label(body,'Current: '..math.floor(U.GetScale()*100+0.5)..'%  |  Choose a size below or use /kt scale 90',12,-440,550)
  button(body,'75%',12,-475,100,function()U.SetScale(0.75);render() end)
  button(body,'90%',124,-475,100,function()U.SetScale(0.90);render() end)
  button(body,'100%',236,-475,100,function()U.SetScale(1);render() end)
  button(body,'115%',348,-475,100,function()U.SetScale(1.15);render() end)
  button(body,'125%',460,-475,100,function()U.SetScale(1.25);render() end)

  button(body,'View Guild Roster',12,-100,220,function()active='Guild Roster';render() end)
  button(body,'View Chronicle',250,-100,220,function()active='Chronicle';render() end)
  label(body,'Guild Services sharing',12,-149,540,'GameFontNormal')
  local services=K.GuildServices
  local _,guild,actor=services.Context()
  local ready=guild~=nil
  local sharing=button(body,ready and (services.IsSharing() and 'Sharing On' or 'Sharing Off') or 'Sharing unavailable',
   12,-174,220,function()
    local _,currentGuild,currentActor=services.Context()
    if ready and guild==currentGuild and actor==currentActor then services.SetSharing(not services.IsSharing()) end
    render()
   end,function()
    if ready then return 'Share this character’s profession skills and observed learned recipes with this guild.' end
    local state=K.GuildReadiness()
    return state=='Ready' and 'The Guild Services data format is unsupported.' or state
   end)
  setActionEnabled(sharing,ready)
  local minimap=K.MinimapLauncher
  button(body,minimap.IsVisible() and 'Hide Minimap Icon' or 'Show Minimap Icon',12,-226,220,function()
   minimap.SetVisible(not minimap.IsVisible());render()
  end)
  button(body,'Reset Minimap Position',250,-226,220,minimap.ResetPosition)
  if K.Sync and K.Sync.AutoSyncEnabled then
   local sync=K.Sync.AutoSyncEnabled()
   button(body,'Automatic Guild Sync: '..(sync and 'On' or 'Off'),12,-274,245,function()
    K.Sync.SetAutoSync(not K.Sync.AutoSyncEnabled());render()
   end,'Account-wide. Automatically requests shared records from compatible guildmates.')
  end
  if K.AutoScout and K.AutoScout.Status then
   button(body,'Auto Scout: '..(K.AutoScout.Status() and 'On' or 'Off'),272,-274,245,function()
    K.AutoScout.SetEnabled(not K.AutoScout.Status());render()
   end,'Account-wide. Controls automatic guild scouting.')
  end
  button(body,'Addon Checker',272,-365,245,function()active='Addon Checker';K.AddonChecker.Request();render() end)
  button(body,'Sync Health Monitor',12,-365,245,function()active='Sync Health';render() end)
  button(body,'Request board sync',12,-316,245,function()K.Operations.RequestSync() end)
  settingLink(body,'Alert Settings',272,-316,245,7)
  settingLink(body,'Raid Settings',12,-525,245,12)
  settingLink(body,'World PvP Settings',272,-525,245,9)
  body:SetHeight(580);scrollChild:SetHeight(580)
 elseif active=='Alerts' then
  label(body,'Alert Command Center',12,-12,550,'GameFontNormalLarge')
  button(body,'Settings Center',400,-7,155,function()navigate('Settings') end)
  local settings,q=d.settings,K.QOL
  local deaths,bounty=K.WorldPvPDeaths,K.BountyAlerts
  local panelX,panelWidth=253,303
  local function toggle(text,enabled,x,y,width,change,help)
   button(body,text..': '..(enabled and 'ON' or 'OFF'),x,y,width,function()
    change(not enabled);render()
   end,help,enabled)
  end
  if q then
   toggle('All alert sounds',q.Enabled('alertSound'),12,-53,224,function()q.Toggle('alertSound') end,
    'Master sound switch for supported War Command alerts.')
  end

  local function status(value)
   if value==nil then return 'Unavailable' end
   return value and 'Enabled' or 'Disabled'
  end
  local function raidStatus(key,field)
   local rt=KeepersRaidTools
   local cfg=rt and rt.GetSetting and rt:GetSetting(key)
   return cfg and status(cfg[field]==true) or 'Unavailable'
  end
  local function countLFG()
   local prefs=settings.guildLFG or {}
   local count=0
   for _,key in ipairs({'interest','invitation','matching'}) do
    if prefs[key] then count=count+1 end
   end
   return count..' of 3 enabled'
  end
  local function guildBroadcast(value) settings.worldPvPDeathBroadcast=value end
  local function callsToArms(value) settings.alerts=value end
  local function reminders(value) settings.autoGuildReports=value end
  local cards={
   {'death','Guild Death','Popup for reported guild deaths.',status(deaths and settings.worldPvPDeathAlerts~=false),deaths and deaths.Demo},
   {'bounty','Bounty Spotted','Popup when a bounty target is seen.',status(bounty and q and bounty.Status()),bounty and bounty.Demo},
   {'calls','Calls to Arms','Incoming announcements in chat.',status(settings.alerts~=false)},
   {'reminders','Report reminders','Local reminders in chat.',status(not not settings.autoGuildReports)},
   {'lfg','Guild LFG notices','Interest, invites, and matching.',countLFG(),nil,'Looking for Group'},
   {'ready','Ready Check','Raid readiness feedback.',raidStatus('readyCheck','enabled'),nil,'Raid Tools: Ready Check Advanced'},
   {'combat','Combat displays','Cooldowns and encounter timers.',raidStatus('combatTimer','enabled')..' timer',nil,'Raid Tools: Combat Tools'},
   {'rez','Battle Resurrection','Raid-only indicator.',raidStatus('battleResCounter','widgetEnabled'),nil,'Raid Tools: Battle Resurrection'},
   {'release','Death Protection','Existing release protection.',raidStatus('dontRelease','enabled'),nil,"Raid Tools: Don't Release"},
  }
  for i,card in ipairs(cards) do
   local y=-100-(i-1)*114
   local selected=alertSelection==card[1]
   surface(body,12,y,224,107,selected and 0.18 or 0.12)
   label(body,card[2],21,y-6,205,'GameFontNormal')
   label(body,card[3],21,y-24,205)
   local state=label(body,card[4],21,y-49,205)
   state:SetTextColor(unpack(card[4]=='Enabled' and C.gold or C.muted))
   local caption=card[1]=='death' and 'Configure Death' or card[1]=='bounty' and 'Configure Bounty' or 'Configure '..card[2]
   button(body,caption,21,y-66,card[5] and 116 or 205,function()
    if card[6] then navigate(card[6]);return end
    alertSelection=card[1]
    pendingSetting,focusedSetting=nil,nil
    scroll:SetVerticalScroll(0)
    render()
   end,'Open '..card[2]..' configuration.',selected)
   if card[5] then
    button(body,'Test Alert',143,y-66,84,card[5],'Play the existing local preview.')
   end
  end

  local title
  for _,card in ipairs(cards) do if card[1]==alertSelection then title=card[2];break end end
  local isBounty=alertSelection=='bounty'
  local api=deaths
  if isBounty then api=bounty end
  local popup=alertSelection=='death' or isBounty
  surface(body,panelX,-53,panelWidth,popup and (isBounty and 525 or 760) or 130,0.115)
  local x=panelX+10
  label(body,title,x,-63,280,'GameFontNormal')
  if not popup then
   local calls=alertSelection=='calls'
   toggle(calls and 'Incoming Calls to Arms' or 'Report reminders',
    calls and settings.alerts~=false or (not calls and not not settings.autoGuildReports),x,-102,280,
    calls and callsToArms or reminders,'Show this type of message in local chat.')
  elseif not (api and api.SetDuration and (not isBounty or q)) then
   label(body,'This alert is unavailable.',x,-101,280)
  else
   local key=isBounty and 'bountyAlert' or 'worldPvPDeath'
   local enabled=not isBounty and settings.worldPvPDeathAlerts~=false
   local sound=not isBounty and settings.worldPvPDeathSound~=false
   if isBounty then enabled=bounty.Status();sound=q.Enabled('bountySound') end
   toggle('Show popup',enabled,x,-95,280,api.SetEnabled,'Show this alert on screen.')
   toggle('Play sound',sound,x,-136,280,isBounty and function()q.Toggle('bountySound') end or deaths.SetSound,
    'Use the existing alert sound when master alert sounds are on.')

   label(body,'Appearance',x,-181,280,'GameFontNormal')
   local scale=math.floor((tonumber(settings[key..'Scale']) or 1)*100+0.5)
   local duration=isBounty and api.GetDuration() or tonumber(settings.worldPvPDeathDuration) or 8
   local function stepper(name,value,y,change,help)
    label(body,name..'  '..value,x,y-8,166)
    button(body,name..' -',x+168,y,54,function()change(-1);render() end,help)
    button(body,name..' +',x+226,y,54,function()change(1);render() end,help)
   end
   stepper('Size',scale..'%',-204,function(delta)api.SetScale((scale+delta*10)/100) end,'Adjust popup scale.')
   stepper('Time',duration..'s',-243,function(delta)
    api.SetDuration(delta<0 and math.max(3,duration-1) or math.min(30,duration+1))
   end,'Adjust popup duration.')

   label(body,'Screen Position',x,-288,280,'GameFontNormal')
   local unlocked=settings[key..'Unlocked']
   local position=settings[key..'Position']
   local place='Default position'
   if type(position)=='table' and type(position.nx)=='number' and type(position.ny)=='number' then
    place=('Saved: %.0f%% from left, %.0f%% from bottom'):format(position.nx*100,position.ny*100)
   end
   label(body,unlocked and 'Positioning mode: drag the preview, then lock it.' or place,x,-313,280)
   button(body,unlocked and 'Lock position' or 'Move Alert',x,-340,134,function()
    api.SetUnlocked(not unlocked);render()
   end,'Drag the existing preview to save its position.',unlocked)
   button(body,'Reset Position',x+144,-340,136,function()api.ResetPosition();render() end,'Restore the default position.')
   surface(body,x,-381,280,68,0.065)
   local artwork=body:CreateTexture(nil,'ARTWORK')
   artwork:SetPoint('TOPLEFT',body,'TOPLEFT',x+62,-383)
   artwork:SetSize(156,62)
   artwork:SetTexture('Interface\\AddOns\\KeepersWarCommand\\Textures\\'..(isBounty and 'BountyAlertFrame.tga' or 'DeathAlertFrame.tga'))
   artwork:SetTexCoord(0,1,0,410/512)
   button(body,'Test preview',x,-455,280,api.Demo,'Play a local preview without reporting an event.')

   label(body,'Behavior',x,-499,280,'GameFontNormal')
   if isBounty then
    toggle('Friendly bounty test mode',bounty.TestMode(),x,-523,280,bounty.SetTestMode,
     'Allow friendly bounty targets in the existing test mode.')
   else
    toggle('Chat alerts',settings.worldPvPDeathChat~=false,x,-523,280,deaths.SetChat,'Show qualifying death reports in chat.')
    toggle('Hide in combat',not not settings.worldPvPDeathSuppressInCombat,x,-562,280,deaths.SetCombatSuppression,
     'Suppress the local popup during combat.')
    toggle('Guild broadcast',settings.worldPvPDeathBroadcast~=false,x,-601,280,guildBroadcast,
     'Share qualifying guild death reports.')
    toggle('Smart Mode',settings.worldPvPDeathSmart~=false,x,-640,280,deaths.SetSmart,
     'Suppress repeated death popups during heavy guild PvP activity.')
    local smart=deaths.GetBattleSettings()
    label(body,'Deaths (2–20)',x,-682,89)
    label(body,'Window (s)',x+96,-682,89)
    label(body,'Quiet (s)',x+192,-682,88)
    local threshold=edit(body,tostring(smart.threshold),x,-702,86)
    local window=edit(body,tostring(smart.window),x+96,-702,86)
    local quiet=edit(body,tostring(smart.quiet),x+192,-702,88)
    for _,field in ipairs({threshold,window,quiet}) do field:SetNumeric(true) end
    button(body,'Apply Smart Mode settings',x,-738,164,function()
     deaths.SetBattleSettings({threshold=threshold:GetText(),window=window:GetText(),quiet=quiet:GetText()})
     render()
    end,'Window: 15–180 seconds. Quiet period: 15–300 seconds.')
    button(body,'Reset Defaults',x+172,-738,108,function()
     confirmReset('Reset Guild Death Smart Mode settings?',deaths.ResetBattleSettings)
    end)
    label(body,('%d unique deaths in %ds suppress popups. Each new report extends the %ds quiet period.')
     :format(smart.threshold,smart.window,smart.quiet),x,-782,280)
   end
  end
  body:SetHeight(1135);scrollChild:SetHeight(1135)
 elseif active=='Guild Roster' then
  button(body,'Back to Settings',12,-53,180,function()active='Settings';render() end)
  label(body,'GUILD ROSTER  /  Live game roster',12,-12,560,'GameFontNormalLarge')
  button(body,'Refresh roster',200,-53,170,function()if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end;K.Roster.Scan() end)
  button(body,'Check addon versions',380,-53,195,function()K.AddonChecker.Request();render() end)
  label(body,'Search player, rank, or class',12,-96,560)
  localFilter(body,rosterQuery,12,-120,350,function(value) rosterQuery=value end)
  local members={}
  for _,m in pairs(d.roster) do
   if type(m)=='table' and m.name then
    local value=table.concat({m.name,tostring(m.rank or ''),tostring(m.class or '')},' '):lower()
    if value:find(rosterQuery:lower(),1,true) then members[#members+1]=m end
   end
  end
  table.sort(members,function(a,b)
   if (a.online and true or false)~=(b.online and true or false) then return a.online and true or false end
   return tostring(a.name):lower()<tostring(b.name):lower()
  end)
  label(body,'PLAYER',12,-168,215,'GameFontNormal')
  label(body,'RANK / CLASS',237,-168,137,'GameFontNormal')
  label(body,'ADDON STATUS',383,-168,190,'GameFontNormal')
  local y=-199
  if #members==0 then label(body,'No guild members match this view.',12,y,553) end
  local section=nil
  for _,m in ipairs(members) do
   local online=m.online and true or false
   if section~=online then
    section=online
    label(body,online and 'ONLINE' or 'OFFLINE',12,y,560,'GameFontNormal');y=y-27
   end
   local peer=K.AddonChecker.ForRoster(m.name)
   local fresh=peer and (time()-(peer.lastSeen or 0)<600)
   local status='Not detected'
   if peer and (fresh or not online) then
    if peer.localClient then status='Installed v'..peer.version
    elseif peer.unsupported then status='Unsupported checker protocol'
    elseif not peer.legacy and peer.version==K.version then status='Confirmed v'..peer.version
    else status=peer.legacy and 'Version unknown' or ('v'..tostring(peer.version)) end
    if not fresh then status=status..' (last seen)' end
   elseif online then status='No response' end
   surface(body,12,y+5,553,37,0.085)
   single(body,m.name,18,y,209)
   single(body,tostring(m.rank or ''),237,y,137)
   single(body,'L'..tostring(m.level or '?')..' '..tostring(m.class or ''),237,y-15,137)
   label(body,status,383,y,178)
   y=y-42
  end
  local height=math.max(680,-y+24)
  body:SetHeight(height);scrollChild:SetHeight(height)
 elseif active=='Chronicle' then
  button(body,'Back to Settings',12,-53,180,function()active='Settings';render() end)
  label(body,'GUILD CHRONICLE  /  Recent recorded events',12,-12,565,'GameFontNormalLarge')
  for i,e in ipairs(d.history) do if i>48 then break end;label(body,e.time..' ['..e.category..'] '..e.text,12,-56-(i-1)*30,565) end
 end
 if focusedSetting and focusedSetting[4]==active then
  local y=focusedSetting[5]
  local marker=body:CreateTexture(nil,'OVERLAY')
  marker:SetPoint('TOPLEFT',body,'TOPLEFT',focusedSetting[8] or 3,y)
  marker:SetSize(4,35)
  marker:SetColorTexture(unpack(C.accent))
  if pendingSetting then
   scroll:SetVerticalScroll(math.max(0,-y-24))
   pendingSetting=nil
  end
 end
end
-- Prefill only; posting still requires the user's explicit confirmation.
function U.OpenBountyForName(name)
 if InCombatLockdown and InCombatLockdown() then K.Say('Open bounty entry after combat.');return end
 name=K.Clean(name,45)
 if name=='' then return end
 pendingBountyTarget=name
 if not frame or not frame:IsShown() then U.Toggle('Bounty Entry') else active='Bounty Entry';render() end
end
function U.GetBountyPlayerName(unit)
 if type(unit)~='string' or (issecretvalue and issecretvalue(unit)) then return end
 if not UnitExists or not UnitIsPlayer or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
 local name,realm
 if UnitFullName then name,realm=UnitFullName(unit) end
 if issecretvalue and issecretvalue(name) then return end
 if not name or name=='' then name,realm=UnitName(unit) end
 if issecretvalue and (issecretvalue(name) or issecretvalue(realm)) then return end
 if not name or name=='' then return end
 if realm and realm~='' and not name:find('-',1,true) then return name..'-'..realm end
 return name
end
function U.OpenBountyForUnit(unit)
 if InCombatLockdown and InCombatLockdown() then K.Say('Open bounty entry after combat.');return end
 if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then K.Say('Target a player first.');return end
 local name=U.GetBountyPlayerName(unit)
 if not name then K.Say('Player name unavailable.');return end
 U.OpenBountyForName(name)
end
K.On('PLAYER_TARGET_CHANGED',function()
 if active=='Bounty Board' and frame and frame:IsShown() and bountyCapture then
  setActionEnabled(bountyCapture,U.GetBountyPlayerName('target')~=nil)
 end
end)
function U.LFGRefresh()
 if active=='Looking for Group' or active=='Guild Services' or active=='Overview' or active=='Settings' then render() end
end
K.On('GROUP_ROSTER_UPDATE',function()
 if active=='Raid Tools: Battle Resurrection' then render() end
end)
function U.RaidRefresh() if active=='Raid Tools: Command' then render() end end
function U.CheckerRefresh() if active=='Addon Checker' or active=='Guild Roster' then U.Refresh() end end
function U.RecruitmentRefresh()
 if active~='Recruitment' or not frame or not frame:IsShown() or not recruitmentRefresh then return end
 if InCombatLockdown and InCombatLockdown() then U.needsRecruitmentRefresh=true;return end
 U.needsRecruitmentRefresh=false
 recruitmentRefresh()
end
function U.Refresh()
 if InCombatLockdown and InCombatLockdown() then U.needsRefresh=true;return end
 -- Background synchronization must not destroy the user's active text form.
 if active=='Raid Tools: Command' or active=='Raid Tools: Sign-Ups' or active=='CTA Entry' or active=='Bounty Entry' or active=='Edit Entry' or active=='Report Sighting' or active=='Recruitment' or active=='Looking for Group' or active=='Guild Services' then
  U.needsFormRefresh=true
  return
 end
 U.needsFormRefresh=false
 render()
end
K.On('PLAYER_REGEN_ENABLED',function()
 if U.needsRefresh then U.needsRefresh=false;U.Refresh() end
 if U.needsRecruitmentRefresh then U.RecruitmentRefresh() end
end)
function U.Toggle(page)
 if page=='Alert Settings' then page='Alerts' end
 if page=='KT Raid' then page='Raid Tools: Command' end
 if page=='Raid Sign-Ups' then page='Raid Tools: Sign-Ups' end
 if page=='Raid Attendance' then page='Raid Tools: Attendance' end
 if InCombatLockdown and InCombatLockdown() then K.Say('Open War Command after combat.');return end
 if not frame then
  frame=CreateFrame('Frame','KeepersWarCommandFrame',UIParent);frame:SetSize(860,680);frame:SetPoint('CENTER',UIParent,'CENTER',0,30);frame:SetMovable(true);frame:EnableMouse(true);frame:SetClampedToScreen(true);frame:SetFrameStrata('FULLSCREEN_DIALOG');frame:SetFrameLevel(100);frame:SetScale(fitScale(U.GetScale()))
  -- Dragging is restricted to the header so the parent frame cannot capture clicks
  -- meant for edit boxes inside the scroll area.
  local dragHeader=CreateFrame('Frame',nil,frame)
  dragHeader:SetPoint('TOPLEFT',frame,'TOPLEFT',2,-2)
  dragHeader:SetPoint('TOPRIGHT',frame,'TOPRIGHT',-143,-2)
  dragHeader:SetHeight(43)
  dragHeader:EnableMouse(true)
  dragHeader:RegisterForDrag('LeftButton')
  dragHeader:SetScript('OnDragStart',function()frame:StartMoving() end)
  dragHeader:SetScript('OnDragStop',function()frame:StopMovingOrSizing() end)
  local border=frame:CreateTexture(nil,'BACKGROUND',nil,-4);border:SetAllPoints(frame);border:SetColorTexture(unpack(C.steel))
  local backdrop=frame:CreateTexture(nil,'BACKGROUND',nil,-3);backdrop:SetPoint('TOPLEFT',2,-2);backdrop:SetPoint('BOTTOMRIGHT',-2,2);backdrop:SetColorTexture(unpack(C.charcoal))
  local sidebar=frame:CreateTexture(nil,'BACKGROUND',nil,-2)
  sidebar:SetPoint('TOPLEFT',frame,'TOPLEFT',8,-57);sidebar:SetPoint('BOTTOMLEFT',frame,'BOTTOMLEFT',8,12)
  sidebar:SetWidth(211);sidebar:SetColorTexture(unpack(C.graphite))
  local sidebarAccent=frame:CreateTexture(nil,'ARTWORK')
  sidebarAccent:SetPoint('TOPLEFT',frame,'TOPLEFT',218,-58);sidebarAccent:SetPoint('BOTTOMLEFT',frame,'BOTTOMLEFT',218,14)
  sidebarAccent:SetWidth(1);sidebarAccent:SetColorTexture(unpack(C.bronze))
  local stripe=frame:CreateTexture(nil,'OVERLAY');stripe:SetPoint('TOPLEFT',frame,'TOPLEFT',2,-48);stripe:SetPoint('TOPRIGHT',frame,'TOPRIGHT',-2,-48);stripe:SetHeight(2);stripe:SetColorTexture(unpack(C.crimson))
  local mark=frame:CreateTexture(nil,'ARTWORK')
  mark:SetPoint('TOPLEFT',12,-8);mark:SetSize(32,32)
  mark:SetTexture('Interface\\AddOns\\KeepersWarCommand\\Textures\\TrogdorMinimap.tga')
  local brand=single(frame,'KEEPERS WAR COMMAND',51,-17,176,'GameFontNormal')
  brand:SetFont(FONT,C.size.nav,'')
  header=single(frame,'COMMAND CENTER',235,-14,468,'GameFontNormalLarge')
  local settingsButton=button(frame,'Preferences',716,-8,88,function()navigate('Settings') end,'Open the Settings Center.')
  local close=button(frame,'X',813,-8,34,function()frame:Hide() end,'Close War Command.')
  settingsButton:SetFrameLevel(dragHeader:GetFrameLevel()+1)
  close:SetFrameLevel(dragHeader:GetFrameLevel()+1)
  -- Bottom-right resize grip: scales the entire native UI proportionally.
  -- Unlike StartSizing, this keeps fixed-position controls aligned.
  local grip=CreateFrame('Button',nil,frame)
  grip:SetSize(30,30)
  grip:SetPoint('BOTTOMRIGHT',frame,'BOTTOMRIGHT',-5,5)
  grip:SetFrameLevel(frame:GetFrameLevel()+12)
  grip:EnableMouse(true)
  local gripLines={}
  for i=1,3 do
   local line=grip:CreateTexture(nil,'OVERLAY')
   line:SetColorTexture(0.55,0.62,0.71,0.8)
   line:SetSize(3,3)
   line:SetPoint('BOTTOMRIGHT',grip,'BOTTOMRIGHT',-5-(i-1)*7,5)
   local line2=grip:CreateTexture(nil,'OVERLAY')
   line2:SetColorTexture(0.55,0.62,0.71,0.8)
   line2:SetSize(3,3)
   line2:SetPoint('BOTTOMRIGHT',grip,'BOTTOMRIGHT',-5,5+(i-1)*7)
  end
  local dragging=false
  local originX,originY,originScale
  local function stopGrip()
   if not dragging then return end
   dragging=false
   grip:SetScript('OnUpdate',nil)
   if KWCDB then
    KWCDB.settings=KWCDB.settings or {}
    KWCDB.settings.windowScale=U.GetScale()
   end
  end
  grip:SetScript('OnMouseDown',function(self,mouseButton)
   if mouseButton~='LeftButton' then return end
   if InCombatLockdown and InCombatLockdown() then return end
   originX,originY=GetCursorPosition()
   originScale=U.GetScale()
   dragging=true
   self:SetScript('OnUpdate',function()
    if not dragging then return end
    if IsMouseButtonDown and not IsMouseButtonDown('LeftButton') then stopGrip();return end
    local x,y=GetCursorPosition()
    local uiScale=UIParent:GetEffectiveScale()
    if not uiScale or uiScale<=0 then uiScale=1 end
    -- Dragging right or down enlarges the frame.
    local dx=(x-originX)/uiScale
    local dy=(originY-y)/uiScale
    local nextScale=safeScale(originScale+(dx/860+dy/680)*0.55)
    if frame:GetScale()~=nextScale then
     frame:SetScale(fitScale(nextScale))
     KWCDB.settings=KWCDB.settings or {}
     KWCDB.settings.windowScale=nextScale
    end
   end)
  end)
  grip:SetScript('OnMouseUp',stopGrip)
  grip:SetScript('OnHide',stopGrip)
  grip:SetScript('OnEnter',function(self)
   if GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_TOP');GameTooltip:SetText('Drag to scale War Command');GameTooltip:AddLine('Size saves automatically. /kt scale 100 resets.',0.85,0.70,0.48);GameTooltip:Show() end
  end)
  grip:SetScript('OnLeave',function()if GameTooltip then GameTooltip:Hide() end end)

  -- DEV35: Dedicated scrollable sidebar. Page identifiers and callbacks unchanged.
  -- Navigation is a separate scroll surface so it never overlaps the content.
  local navViewport=CreateFrame('Frame',nil,frame)
  navViewport:SetPoint('TOPLEFT',frame,'TOPLEFT',10,-63)
  navViewport:SetPoint('BOTTOMLEFT',frame,'BOTTOMLEFT',10,18)
  navViewport:SetWidth(207)
  navScroll=CreateFrame('ScrollFrame',nil,navViewport)
  navScroll:SetAllPoints(navViewport)
  navChild=CreateFrame('Frame',nil,navScroll)
  navChild:SetSize(207,1010)
  navScroll:SetScrollChild(navChild)
  navScroll:EnableMouseWheel(true)
  navScroll:SetScript('OnMouseWheel',function(self,delta)
   local max=math.max(0,navChild:GetHeight()-self:GetHeight())
   self:SetVerticalScroll(math.max(0,math.min(max,self:GetVerticalScroll()-delta*58)))
  end)
  local navY=-8
  local function section(title)
   navY=navY-13
   local h=label(navChild,title,11,navY,181)
   h:SetFont(FONT,10,'')
   h:SetTextColor(unpack(C.gold))
   navY=navY-25
  end
  local function item(text,page)
   local b=button(navChild,text,5,navY,194,function() navigate(page) end)
   b:SetHeight(32)
   b.kwcPage=page
   navY=navY-38
  end
  section('HOME')
  item('Home','Home')
  section('PVP')
  item('War Room','War Room')
  item('Calls to Arms','CTA Board')
  item('Bounty Board','Bounty Board')
  item('PvP Leaderboard','PvP Leaderboard')
  section('RAIDS')
  item('Raid Operations','Raid Tools')
  section('GUILD')
  item('Recruitment','Recruitment')
  item('Looking for Group','Looking for Group')
  item('Guild Services','Guild Services')
  item('Guild Roster','Guild Roster')
  item('Addon Checker','Addon Checker')
  section('SETTINGS')
  item('Preferences','Settings')
  item('Alerts','Alerts')
  item('Sync Health','Sync Health')
  navChild:SetHeight(math.max(-navY+20,620))
  scroll=CreateFrame('ScrollFrame',nil,frame);scroll:SetPoint('TOPLEFT',224,-65);scroll:SetPoint('BOTTOMRIGHT',-34,22)
  scrollChild=CreateFrame('Frame',nil,scroll);scrollChild:SetSize(605,3900);scroll:SetScrollChild(scrollChild)
  scroll:EnableMouseWheel(true)
  scroll:SetScript('OnMouseWheel',function(self,delta)
   if not body then return end
   local max=math.max(0,(body:GetHeight() or 0)-(self:GetHeight() or 0))
   self:SetVerticalScroll(math.max(0,math.min(max,(self:GetVerticalScroll() or 0)-delta*55)))
  end)
  frame:Hide()
 end
 if type(page)=='string' and page~='' then
  if page~=active then
   pendingSetting,focusedSetting=nil,nil
   scroll:SetVerticalScroll(0)
  end
  active=page;frame:Show()
 elseif frame:IsShown() then
  frame:Hide()
 else
  active='Home';pendingSetting,focusedSetting=nil,nil
  scroll:SetVerticalScroll(0);navScroll:SetVerticalScroll(0);frame:Show()
 end
 if not frame:IsShown() and K.RaidTools and K.RaidTools.Close then K.RaidTools.Close() end
 if frame:IsShown() then frame:SetScale(fitScale(U.GetScale())) end
 if frame:IsShown() and K.Sync and K.Sync.OnWindowOpened then K.Sync.OnWindowOpened() end
 render()
end
