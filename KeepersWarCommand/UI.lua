local K=KWC;local U={};K.UI=U
local scrollChild
local navButtons={}
local frame,body,scroll,header,active=nil,nil,nil,nil,'Overview'
local boardFilter={CTA='ACTIVE',BOUNTY='ACTIVE'}
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

local editingKind,editingId=nil,nil
local pendingBountyTarget=nil
local achievementPage=1
local achievementFilter='All'
local selectedCTA=nil
local selectedBounty=nil
local selectedAAR=nil
local tabs={'Overview','War Room','CTA Board','Bounty Board','War Intelligence','PvP Leaderboard','Recruitment','Achievements'}
-- War Command design system: larger readable type, restrained gold headings,
-- ember accents, and distinct surfaces for navigation and action buttons.
local C={gold={0.92,0.94,0.98},cream={0.91,0.94,0.98},muted={0.56,0.62,0.71},ember={0.44,0.70,0.98},dark={0.045,0.055,0.075}}
local FONT='Fonts\\FRIZQT__.TTF'
local function label(p,t,x,y,w,font)
 local f=p:CreateFontString(nil,'OVERLAY')
 local title=font=='GameFontNormalLarge'
 local section=font=='GameFontNormal'
 f:SetFont(FONT,title and 20 or (section and 14 or 12),'')
 local color=title and C.gold or (section and C.cream or C.muted)
 f:SetTextColor(color[1],color[2],color[3],1)
 f:SetPoint('TOPLEFT',x,y);f:SetWidth(w);f:SetJustifyH('LEFT');f:SetJustifyV('TOP')
 f:SetText(tostring(t or ''))
 if title then
  local rule=p:CreateTexture(nil,'ARTWORK')
  rule:SetPoint('TOPLEFT',p,'TOPLEFT',x,y-27);rule:SetSize(math.min(w,545),1)
  rule:SetColorTexture(0.22,0.26,0.32,0.55)
 end
 return f
end
local function button(p,t,x,y,w,cb)
 local b=CreateFrame('Button',nil,p);b:SetSize(w,34);b:SetPoint('TOPLEFT',x,y)
 local isNav=(p==frame and w>=180)
 local function colors(hover)
  if isNav and active==t then return 0.16,0.25,0.36
  elseif hover then return 0.14,0.18,0.24
  else return 0.075,0.09,0.12 end
 end
 local edge=b:CreateTexture(nil,'BACKGROUND');edge:SetAllPoints(b);edge:SetColorTexture(0.18,0.23,0.30,isNav and 0.15 or 0.48)
 local bg=b:CreateTexture(nil,'ARTWORK');bg:SetPoint('TOPLEFT',1,-1);bg:SetPoint('BOTTOMRIGHT',-1,1)
 local function paint(hover)
  local rr,gg,bb=colors(hover);bg:SetColorTexture(rr,gg,bb,1)
 end
 paint(false)
 local tx=b:CreateFontString(nil,'OVERLAY');tx:SetFont(FONT,12,'');tx:SetPoint('CENTER');tx:SetWidth(w-12);tx:SetJustifyH('CENTER')
 tx:SetTextColor(C.cream[1],C.cream[2],C.cream[3]);tx:SetText(t)
 if isNav then tx:ClearAllPoints();tx:SetPoint('LEFT',b,'LEFT',14,0);tx:SetJustifyH('LEFT') end
 b:SetScript('OnEnter',function(self)self.kwcHovered=true;paint(true) end)
 b:SetScript('OnLeave',function(self)self.kwcHovered=false;paint(false) end)
 if isNav then b.kwcPaint=paint;navButtons[#navButtons+1]=b end
 b:SetScript('OnClick',cb)
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
 local bg=e:CreateTexture(nil,'BACKGROUND');bg:SetAllPoints(e);bg:SetColorTexture(0.10,0.13,0.17,0.97)
 e:SetFont(FONT,13,'');e:SetTextColor(0.95,0.96,0.98);e:SetTextInsets(9,9,0,0);e:SetText(value or '');return e
end
local function surface(p,x,y,w,h,shade)
 local t=p:CreateTexture(nil,'BACKGROUND');t:SetPoint('TOPLEFT',p,'TOPLEFT',x,y);t:SetSize(w,h)
 local v=shade or 0.09;t:SetColorTexture(v,v+0.016,v+0.038,0.98)
 return t
end
local function single(p,value,x,y,w,style)
 local f=label(p,value,x,y,w,style);f:SetWordWrap(false);f:SetMaxLines(1);return f
end
local function count(t) local n=0;for _ in pairs(t or {}) do n=n+1 end;return n end
local function reset()
 if body then
  local children={body:GetChildren()};for _,child in ipairs(children) do child:Hide() end
  local regions={body:GetRegions()};for _,region in ipairs(regions) do region:Hide() end
  body:Hide()
 end
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

local function render()
 if InCombatLockdown and InCombatLockdown() then U.needsRefresh=true;return end
 if not frame or not frame:IsShown() or not KWCDB then return end
 for _,nav in ipairs(navButtons) do if nav.kwcPaint then nav.kwcPaint(nav.kwcHovered or false) end end
 if type(active)~='string' then active='Overview' end
 header:SetText(string.upper(active));reset();local d=KWCDB
 if active=='Overview' then
  label(body,'Command center',18,-16,540,'GameFontNormalLarge')
  label(body,'Your guild at a glance. Everything important, nothing extra.',18,-57,545)
  local st=K.Operations.Stats()
  local metrics={{tostring(st.activeCTA),'ACTIVE CTAs'},{tostring(st.activeBounty),'BOUNTIES'},{tostring(st.sightings),'SIGHTINGS'}}
  for i,m in ipairs(metrics) do
   local x=18+(i-1)*184;surface(body,x,-102,171,102,0.095)
   local n=label(body,m[1],x+16,-118,140,'GameFontNormalLarge');n:SetFont(FONT,30,'')
   label(body,m[2],x+16,-170,145)
  end
  label(body,'OPERATIONS',18,-239,520,'GameFontNormal')
  surface(body,18,-275,539,121,0.085)
  single(body,st.urgent..' urgent  /  '..st.coming..' reinforcements responding',34,-292,500,'GameFontNormal')
  label(body,'Coordinate your next fight, or review active operations.',34,-323,495)
  button(body,'Open War Room',34,-350,195,function()active='War Room';render() end)
  button(body,'New Call to Arms',244,-350,195,function()active='CTA Entry';render() end)
  label(body,'INTELLIGENCE',18,-434,520,'GameFontNormal')
  surface(body,18,-471,539,111,0.085)
  label(body,'Enemy sightings, bounties, and scout reports.',34,-491,495)
  button(body,'Scout Network',34,-528,195,function()active='Scout Network';render() end)
  button(body,'Bounty Board',244,-528,195,function()active='Bounty Board';render() end)
  label(body,'SYSTEM',18,-621,530,'GameFontNormal')
  label(body,'Overlord: '..(K.Companions.Overlord() and 'Connected' or 'Not loaded')..'   /   War Effort: '..(K.Companions.WarEffort() and 'Connected' or 'Not loaded'),18,-657,530)
  button(body,'Sync status',18,-696,160,function()active='Sync Health';render() end)
 elseif active=='Recruitment' then
  label(body,'KEEPERS RECRUITER  /  Player-driven discovery',12,-12,570,'GameFontNormalLarge')
  local query=edit(body,'10-20',12,-53,155)
  button(body,'Search /who',183,-53,130,function()K.Recruiter.Search(query:GetText()) end)
  button(body,'Next range',330,-53,125,function()K.Recruiter.Next() end)
  local r=K.Recruiter;local db=d.recruiter
  label(body,'Searches: '..(db.searches or 0)..' | Whisper drafts: '..(db.drafts or 0)..' | Invite drafts: '..(db.inviteDrafts or 0)..' | Confirmed joins: '..(db.joins or 0),12,-97,575)
  label(body,'Select an unguilded player:',12,-129,570,'GameFontNormal')
  for i,c in ipairs(r.results) do
   if i>14 then break end
   button(body,(r.selected==c.name and '* ' or '')..c.name..'  L'..tostring(c.level or '?')..'  '..tostring(c.class or ''),12,-160-(i-1)*29,540,function()r.Select(i) end)
  end
  label(body,'Selected: '..tostring(r.selected or 'none'),12,-586,550,'GameFontNormal')
  button(body,'Prepare whisper',12,-618,165,function()r.Whisper() end)
  button(body,'Prepare invite',188,-618,160,function()r.PrepareInvite() end)
  button(body,'Ignore',360,-618,130,function()r.Ignore() end)
  label(body,'Invites and whispers are drafts. You must send them yourself.',12,-661,570)
  label(body,'Recruiting message:',12,-707,560)
  local pitch=edit(body,d.settings.pitch,12,-736,540)
  button(body,'Save message',12,-775,165,function()d.settings.pitch=K.Clean(pitch:GetText(),165);K.Say('Message saved.') end)
 elseif active=='PvP Leaderboard' then
  label(body,'PvP leaderboard',18,-16,530,'GameFontNormalLarge')
  label(body,'Lifetime honorable kills · guild-reported statistics',18,-57,400)
  button(body,'Refresh honor',410,-49,146,function()K.PvP.RefreshHonor();K.PvP.RequestGuildHonor() end)
  surface(body,18,-108,539,43,0.12)
  local columns={{x=30,w=33},{x=73,w=105},{x=181,w=188},{x=379,w=92},{x=478,w=69}}
  local titles={'#','TIER','PLAYER','KILLS','POINTS'}
  for j,c in ipairs(columns) do single(body,titles[j],c.x,-123,c.w,'GameFontNormal') end
  -- Group known aliases for DISPLAY without deleting stored records. This
  -- avoids duplicate leaderboard rows even before SavedVariables migration.
  if K.PvP and K.PvP.CleanupSelfEchoes then K.PvP.CleanupSelfEchoes() end
  local players,byName={},{}
  for n,p in pairs(d.pvp or {}) do
   if p.honor and p.honor.available and type(p.honor.lifetime)=='number' then
    local display=K.PvP and K.PvP.CanonicalDisplayName and K.PvP.CanonicalDisplayName(n) or n
    local k=display and display:lower()
    local existing=k and byName[k]
    if k and not existing then
     existing={name=display,data=p};byName[k]=existing;players[#players+1]=existing
    elseif k and existing and (p.honor.lastRead or 0)>(existing.data.honor.lastRead or 0) then
     existing.data=p
    end
   end
  end
  table.sort(players,function(a,b) local ah=a.data.honor.lifetime;local bh=b.data.honor.lifetime;if ah==bh then return a.name:lower()<b.name:lower() end;return ah>bh end)
  local function tier(rank) if rank<=5 then return 'Warlord' elseif rank<=10 then return 'Gladiator' elseif rank<=20 then return 'Elite' elseif rank<=35 then return 'Duelist' elseif rank<=50 then return 'Rival' elseif rank<=75 then return 'Challenger' else return 'Combatant' end end
  for i,p in ipairs(players) do if i>100 then break end
   local y=-166-(i-1)*39
   if i%2==1 then surface(body,18,y+7,539,37,0.075) end
   local pts=(K.PvP and p.name==K.PvP.PlayerName()) and K.QOL.Points() or p.data.achievementPoints
   local values={tostring(i),tier(i),p.name,tostring(p.data.honor.lifetime),pts and tostring(pts) or '--'}
   for j,c in ipairs(columns) do single(body,values[j],c.x,y,c.w,i<=3 and 'GameFontNormal' or nil) end
  end
  if #players==0 then label(body,'No honor data yet. Refresh to begin.',30,-181,480) end
  label(body,'Ranks are internal guild titles, not official Arena ratings.',18,-207-math.max(#players,1)*39,530)
 elseif active=='CTA Entry' then
  label(body,'NEW CALL TO ARMS  /  Request reinforcements',12,-12,570,'GameFontNormalLarge')
  button(body,'View CTA Board',365,-35,170,function()active='CTA Board';render() end)
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
   button(body,'SAVE CTA UPDATE',238,-320,270,function()
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
  button(body,'+ New CTA',12,-48,165,function()active='CTA Entry';render() end)
  button(body,'Report to Guild',190,-48,170,function()K.Operations.ListActive('CTA',true) end)
  for i,v in ipairs({'ACTIVE','RESOLVED','ALL'}) do
   button(body,v,12+(i-1)*165,-92,155,function()boardFilter.CTA=v;render() end)
  end
  local shown=0
  for _,a in ipairs(d.ops) do
   local status=a.status or 'ACTIVE'
   if boardFilter.CTA=='ALL' or boardFilter.CTA==status or (boardFilter.CTA=='RESOLVED' and status=='CANCELLED') then
    shown=shown+1;if shown>20 then break end
    local y=-146-(shown-1)*105
    local panel=body:CreateTexture(nil,'BACKGROUND');panel:SetPoint('TOPLEFT',12,y+8);panel:SetSize(545,94);panel:SetColorTexture(0.095,0.115,0.15,0.96)
    local heading=label(body,tostring(a.time or '')..'   |   '..status,23,y,500,'GameFontNormal')
    local desc=label(body,tostring(a.text or ''),23,y-25,510);desc:SetMaxLines(1);desc:SetWordWrap(false)
    local rs=d.responses and d.responses[a.id] or {};local coming=0
    for _,v in pairs(rs) do if v=='Coming' then coming=coming+1 end end
    label(body,'Reinforcements: '..coming..'   |   Commander: '..tostring(a.author or '?'),23,y-51,355)
    button(body,'View Details',405,y-49,145,function()selectedCTA=a.id;active='CTA Details';render() end)
   end
  end
  if shown==0 then label(body,'No operations in this view.',12,-155,500) end
 elseif active=='CTA Details' then
  local a;for _,entry in ipairs(d.ops) do if entry.id==selectedCTA then a=entry;break end end
  button(body,'< Back to CTAs',12,-12,170,function()active='CTA Board';render() end)
  if a then
   label(body,'OPERATION DETAILS',12,-62,545,'GameFontNormalLarge')
   label(body,tostring(a.text or ''),12,-112,545)
   label(body,'Status: '..tostring(a.status or 'ACTIVE')..'   |   Commander: '..tostring(K.Operations.Commander(a)),12,-162,545)
   local rs=d.responses and d.responses[a.id] or {};local coming,maybe,busy=0,0,0
   for _,v in pairs(rs) do if v=='Coming' then coming=coming+1 elseif v=='Maybe' then maybe=maybe+1 elseif v=='Busy' then busy=busy+1 end end
   label(body,'Lieutenant: '..tostring(a.lieutenant or 'Not assigned')..'  |  Warlord: '..tostring(K.Operations.Warlord() or 'Not in group'),12,-188,545)
   label(body,'Coming: '..coming..'     Maybe: '..maybe..'     Busy: '..busy,12,-218,545,'GameFontNormal')
   if K.Operations.CanAssumeCommand(a) then
    button(body,'Assume Command',375,-315,175,function()
     StaticPopupDialogs['KWC_ASSUME_COMMAND']={text='Join this operation as a Co-Commander? Existing commanders retain their seats.',button1='Assume Command',button2='Cancel',OnAccept=function(_,data) K.Operations.AssumeCommand(data) end,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3}
     StaticPopup_Show('KWC_ASSUME_COMMAND',nil,nil,a.id)
    end)
   end
   if K.Operations.IsCommander(a,UnitName('player')) then
    button(body,'Assign LT',375,-376,175,function()
     StaticPopupDialogs['KWC_ASSIGN_LT']={text='Enter the character name for your Lieutenant:',button1='Assign',button2='Cancel',hasEditBox=true,OnAccept=function(dialog,data) K.Operations.AssignLieutenant(data,dialog.editBox:GetText()) end,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3}
     StaticPopup_Show('KWC_ASSIGN_LT',nil,nil,a.id)
    end)
    button(body,'Restore Commander',375,-409,175,function()
     StaticPopupDialogs['KWC_RESTORE_COMMAND']={text='Hand your command seat to which character?',button1='Transfer',button2='Cancel',hasEditBox=true,OnAccept=function(dialog,data) K.Operations.RestoreCommander(data,dialog.editBox:GetText()) end,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3}
     StaticPopup_Show('KWC_RESTORE_COMMAND',nil,nil,a.id)
    end)
   end
   label(body,'YOUR RESPONSE',12,-244,540,'GameFontNormal')
   button(body,'Coming',12,-276,115,function()K.Operations.Respond(a.id,'Coming');render() end)
   button(body,'Maybe',137,-276,115,function()K.Operations.Respond(a.id,'Maybe');render() end)
   button(body,'Busy',262,-276,115,function()K.Operations.Respond(a.id,'Busy');render() end)
   button(body,'Roster',387,-276,155,function()editingId=a.id;active='CTA Roster';render() end)
   label(body,'MANAGE OPERATION',12,-346,540,'GameFontNormal')
   if a.status=='ACTIVE' then
    button(body,'Resolve',12,-382,125,function()K.Operations.ChangeStatus('CTA',a.id,'RESOLVED');render() end)
    button(body,'Cancel',147,-382,125,function()K.Operations.ChangeStatus('CTA',a.id,'CANCELLED');render() end)
   else button(body,'Reopen',12,-382,125,function()K.Operations.ChangeStatus('CTA',a.id,'ACTIVE');render() end) end
   button(body,'Edit',282,-382,125,function()editingKind='CTA';editingId=a.id;active='Edit Entry';render() end)
   button(body,'Guild Report',12,-432,160,function()K.Operations.Report('CTA',a.id) end)
   button(body,'Discord Export',184,-432,160,function()showDiscordExport('CTA',a) end)
   button(body,'Draft OV',12,-482,160,function()K.Operations.DraftExternal('CTA',a.id,'OV') end)
   button(body,'Draft War Effort',184,-482,175,function()K.Operations.DraftExternal('CTA',a.id,'WE') end)
   if K.Operations.CanDelete(a) then
    button(body,'Delete Guild-Wide',375,-482,175,function()
     StaticPopupDialogs['KWC_CONFIRM_DELETE']={text='Permanently delete this %s for the guild? This cannot be undone.',button1='Delete',button2='Cancel',OnAccept=function(_,data)
      if K.Operations.Delete(data.kind,data.id) then selectedCTA=nil;selectedBounty=nil;active=data.kind=='CTA' and 'CTA Board' or 'Bounty Board';render() end
     end,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3}
     StaticPopup_Show('KWC_CONFIRM_DELETE','CTA',nil,{kind='CTA',id=a.id})
    end)
   end
  end
 elseif active=='War Room' then
  label(body,'WAR ROOM  /  Operations command',12,-12,565,'GameFontNormalLarge')
  label(body,'Existing CTA board sync is reused; no new network protocol in this build.',12,-52,565)
  button(body,'New CTA',12,-85,165,function()active='CTA Entry';render() end)
  button(body,'Request guild sync',189,-85,175,function()K.Operations.RequestSync() end)
  button(body,'Scout Network',376,-85,175,function()active='Scout Network';render() end)
  local entries=K.WarRoom.Active()
  label(body,'ACTIVE OPERATIONS  ('..#entries..')',12,-140,560,'GameFontNormal')
  for i,e in ipairs(entries) do
   if i>12 then break end
   local y=-180-(i-1)*125
   local c,m,b=K.WarRoom.Roster(e)
   label(body,((e.details and e.details.urgent) and '[URGENT] ' or '')..tostring(e.text or ''),12,y,550,'GameFontNormal')
   label(body,'Commander: '..tostring(K.Operations.Commander(e))..'  |  Lieutenant: '..tostring(e.lieutenant or '—')..'  |  Coming: '..c..'  Maybe: '..m..'  Busy: '..b,12,y-32,545)
   button(body,'Respond',12,y-61,125,function()active='CTA Board';render() end)
   button(body,'After-action report',151,y-61,185,function()selectedAAR=e.id;active='After Action';render() end)
   button(body,'View Operation',350,y-61,145,function()selectedCTA=e.id;active='CTA Details';render() end)
  end
  if #entries==0 then label(body,'No active CTAs. Create one or request a board sync.',12,-190,550) end
 elseif active=='Scout Network' then
  label(body,'Scout network',12,-12,560,'GameFontNormalLarge')
  label(body,'Manual reports are local; Auto Scout can share enemy sightings with guild.',12,-48,560)
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
 elseif active=='War Intelligence' then
  label(body,'WAR INTELLIGENCE  /  Companion status',12,-12,565,'GameFontNormalLarge')
  label(body,'OVERLORD FOREVER',12,-67,560,'GameFontNormal')
  local ov,reason=K.Companions.OverlordSnapshot()
  if ov then
   label(body,ov.fronts..' fronts  |  '..ov.objectives..' objectives  |  '..ov.contested..' contested',12,-99,565)
   label(body,'Held: '..ov.heldHorde..' Horde  |  '..ov.heldAlliance..' Alliance',12,-126,565)
   label(body,'Read-only objective registry; this is not a live battle report.',12,-151,565)
  else
   label(body,reason or 'Overlord unavailable',12,-99,565)
  end
  button(body,'Open Overlord',12,-184,175,function()K.Companions.OpenOverlord() end)
  label(body,'WAR EFFORT SCOUT',12,-246,560,'GameFontNormal')
  label(body,K.Companions.WarEffortStatus(),12,-279,560)
  button(body,'Open War Effort',12,-314,175,function()K.Companions.OpenWarEffort() end)
  label(body,'War Effort does not expose its scouting data through a public API.',12,-356,565)
  label(body,'Draft buttons prepare text; they do not submit to either network.',12,-386,565)
  button(body,'Refresh Companion Status',12,-434,250,function()render() end)
 elseif active=='CTA Roster' then
  label(body,'CTA RESPONSE ROSTER',12,-12,550,'GameFontNormalLarge')
  button(body,'Back to CTA Board',12,-47,210,function()active='CTA Board';render() end)
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
  else label(body,'CTA not found.',12,-100,540) end
 elseif active=='World PvP Deaths' then
  label(body,'WORLD PVP DEATH INTELLIGENCE',12,-12,555,'GameFontNormalLarge')
  label(body,'Recent guild reports (most recent first). Attacker is best available combat-log match.',12,-43,555)
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
 elseif active=='Achievements' then
  local q=K.QOL
  local unlocked,total=q.Summary()
  label(body,'GUILD PvP ACHIEVEMENTS',12,-12,550,'GameFontNormalLarge')
  label(body,'Unlocked '..unlocked..' / '..total..'  |  Achievement Points: '..q.Points(),12,-48,570)
  label(body,'Earn points through addon actions and lifetime honorable kill milestones.',12,-72,575)
  local categories={'All','PvP Kills','Calls to Arms','Bounty Board','Bounty Claims','Scouting','Reinforcements'}
  for i,cat in ipairs(categories) do
   local row=math.floor((i-1)/4);local col=(i-1)%4
   button(body,(achievementFilter==cat and '* ' or '')..cat,12+col*145,-108-row*40,138,function()achievementFilter=cat;achievementPage=1;render() end)
  end
  local filtered={}
  for _,a in ipairs(q.Catalog()) do if achievementFilter=='All' or achievementFilter=='Unlocked' or a.category==achievementFilter then filtered[#filtered+1]=a end end
  if achievementFilter=='Unlocked' then
   local earned={};for _,a in ipairs(filtered) do if q.Unlocked(a.id) then earned[#earned+1]=a end end
   filtered=earned
  end
  local perPage=12
  local pages=math.max(1,math.ceil(#filtered/perPage))
  achievementPage=math.max(1,math.min(achievementPage,pages))
  label(body,achievementFilter..'  |  Page '..achievementPage..' / '..pages..'  |  '..#filtered..' achievements',12,-199,570,'GameFontNormal')
  button(body,'< Previous',12,-229,130,function()achievementPage=math.max(1,achievementPage-1);render() end)
  button(body,'Next >',158,-229,130,function()achievementPage=math.min(pages,achievementPage+1);render() end)
  button(body,'Unlocked only',304,-229,175,function()achievementFilter='Unlocked';achievementPage=1;render() end)
  for i=(achievementPage-1)*perPage+1,math.min(#filtered,achievementPage*perPage) do
   local a=filtered[i];local n=i-(achievementPage-1)*perPage
   local y=-285-(n-1)*65
   local current=q.Count(a.kind);local earned=q.Unlocked(a.id)
   label(body,(earned and '|cff66dd88[UNLOCKED]|r ' or '|cff999999[LOCKED]|r ')..a.title,12,y,560,'GameFontNormal')
   label(body,a.description..'   |   '..(a.points or 5)..' pts   |   Progress: '..math.min(current,a.required)..' / '..a.required,24,y-26,545)
  end
  if #filtered==0 then label(body,'No unlocked achievements in this view yet.',12,-285,550) end
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
  local current
  for _,e in ipairs(d.bounties) do if e.id==editingId then current=e;break end end
  label(body,'REPORT ENEMY SIGHTING',12,-12,550,'GameFontNormalLarge')
  if current then
   label(body,'Target: '..current.text,12,-60,540)
   label(body,'Zone / landmark',12,-103,520)
   local zone=edit(body,GetZoneText and GetZoneText() or '',12,-125,530)
   label(body,'Additional details',12,-166,520)
   local note=edit(body,'',12,-188,530)
   button(body,'SUBMIT SIGHTING',12,-240,240,function()K.Operations.AddSighting(editingId,zone:GetText(),note:GetText());active='Bounty Board';render() end)
  end
  button(body,'Back to Bounty Board',12,-290,230,function()active='Bounty Board';render() end)
 elseif active=='Bounty Board' then
  label(body,'Bounty board',18,-16,530,'GameFontNormalLarge')
  button(body,'+ New Bounty',12,-48,165,function()active='Bounty Entry';render() end)
  button(body,'Report to Guild',190,-48,170,function()K.Operations.ListActive('BOUNTY',true) end)
  for i,v in ipairs({'ACTIVE','COMPLETED','ALL'}) do
   button(body,v,12+(i-1)*165,-92,155,function()boardFilter.BOUNTY=v;render() end)
  end
  local shown=0
  for _,b in ipairs(d.bounties) do
   local status=b.status or 'ACTIVE'
   if boardFilter.BOUNTY=='ALL' or boardFilter.BOUNTY==status or (boardFilter.BOUNTY=='COMPLETED' and status=='CANCELLED') then
    shown=shown+1;if shown>20 then break end
    local y=-146-(shown-1)*110
    local panel=body:CreateTexture(nil,'BACKGROUND');panel:SetPoint('TOPLEFT',12,y+8);panel:SetSize(545,99);panel:SetColorTexture(0.095,0.115,0.15,0.96)
    local target=(b.details and b.details.target) or b.text or 'Unknown target'
    local reward=(b.details and b.details.reward) or (b.text or ''):match('[Rr]eward:%s*([^|]+)') or 'Not listed'
    local name=label(body,tostring(target),23,y,350,'GameFontNormal');name:SetMaxLines(1);name:SetWordWrap(false)
    label(body,status,420,y,125,'GameFontNormal')
    label(body,'Reward: '..tostring(reward),23,y-28,350)
    local last=(b.sightings or {})[1]
    label(body,'Sightings: '..#(b.sightings or {})..'   |   Last: '..tostring(last and last.zone or 'Unknown'),23,y-56,365)
    button(body,'View Details',405,y-52,145,function()selectedBounty=b.id;active='Bounty Details';render() end)
   end
  end
  if shown==0 then label(body,'No bounties in this view.',12,-155,500) end
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
   if b.status=='ACTIVE' then
    button(body,'Claim Kill',12,-307,155,function()K.Operations.ClaimBounty(b.id) end)
    button(body,'Report Sighting',180,-307,180,function()editingId=b.id;active='Report Sighting';render() end)
   end
   button(body,'Sighting History',12,-354,175,function()editingId=b.id;active='Sighting History';render() end)
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
  label(body,'|cffffa84bGUILD SYNC HEALTH|r',12,-12,500,'GameFontNormalLarge')
  label(body,'Sync requests CTAs, bounties, deletions and honor. Peer replies are automatic.',12,-43,580)
  local h=K.Sync and K.Sync.Health and K.Sync.Health()
  if h then
   label(body,'Requests: '..h.requests..' | Sent: '..h.sent..' | Received: '..h.received,12,-75,570)
   label(body,'Records applied: '..h.applied..' | Rejected: '..h.rejected,12,-98,580)
   local age=h.lastReceived>0 and (time()-h.lastReceived) or nil
   label(body,'Last message: '..(age and (age..' seconds ago') or 'None'),12,-121,580)
   local peers={}
   for name,v in pairs(h.peers) do peers[#peers+1]={name=name,age=time()-v.lastSeen,count=v.received} end
   table.sort(peers,function(a,b)return a.age<b.age end)
   label(body,'|cffffa84bRECENT PEERS|r',12,-158,500,'GameFontNormal')
   if #peers==0 then label(body,'No addon peers observed yet.',12,-187,570) end
   for i=1,math.min(11,#peers) do
    local v=peers[i]
    label(body,v.name..' | '..v.age..'s ago | '..v.count..' messages',12,-181-i*24,570)
   end
  end
  button(body,'Sync All Guild Data',12,-510,190,function()if K.Sync then K.Sync.RequestAll(false) end;render() end)
  button(body,'Refresh Diagnostics',216,-510,190,function()render() end)
 elseif active=='Addon Checker' then
  label(body,'ADDON CHECKER  /  Guild clients',12,-12,565,'GameFontNormalLarge')
  label(body,'Check online guildmates to see which addon versions are responding.',12,-47,565)
  button(body,'Check Online Guildmates',12,-80,245,function()K.AddonChecker.Request();render() end)
  button(body,'Refresh View',270,-80,150,function()render() end)
  local me,ver=K.AddonChecker.Self()
  label(body,'YOU: '..me..'  |  v'..ver..'  |  Installed',12,-134,565,'GameFontNormal')
  local peers=K.AddonChecker.Entries()
  label(body,'OTHER DETECTED CLIENTS ('..#peers..')',12,-180,565,'GameFontNormal')
  if #peers==0 then label(body,'No other addon clients detected yet. Ask members to log in and run /kt addons.',12,-211,565) end
  for i=1,math.min(15,#peers) do
   local p=peers[i]
   local age=math.max(0,time()-(p.lastSeen or time()))
   local status=p.legacy and 'Legacy / unknown' or (p.version==K.version and 'Current' or 'Different version')
   label(body,p.name..'  |  '..(p.legacy and 'Unknown version' or ('v'..p.version))..'  |  '..status..'  |  '..age..'s ago',12,-208-i*25,565)
  end
  button(body,'Back to Settings',12,-555,190,function()active='Settings';render() end)
 elseif active=='Settings' then
  label(body,'SETTINGS / GUILD DATA',12,-12,565,'GameFontNormalLarge')
  label(body,'WINDOW SIZE',12,-410,540,'GameFontNormal')
  label(body,'Current: '..math.floor(U.GetScale()*100+0.5)..'%  |  Choose a size below or use /kt scale 90',12,-440,550)
  button(body,'75%',12,-475,100,function()U.SetScale(0.75);render() end)
  button(body,'90%',124,-475,100,function()U.SetScale(0.90);render() end)
  button(body,'100%',236,-475,100,function()U.SetScale(1);render() end)
  button(body,'115%',348,-475,100,function()U.SetScale(1.15);render() end)
  button(body,'125%',460,-475,100,function()U.SetScale(1.25);render() end)

  label(body,'Roster and Chronicle remain available here. Background data collection stays active.',12,-52,560)
  button(body,'View Guild Roster',12,-100,220,function()active='Guild Roster';render() end)
  button(body,'View Chronicle',250,-100,220,function()active='Chronicle';render() end)
  label(body,'Guild roster data still supports recruiting, guild checks and other features.',12,-153,560)
  button(body,(d.settings.autoGuildReports and 'Auto guild reports: ON' or 'Auto guild reports: OFF'),12,-205,280,function()
   d.settings.autoGuildReports=not d.settings.autoGuildReports;render()
  end)
  label(body,'Auto reports show a reminder. Forever requires manual guild chat sending.',12,-245,550)
  label(body,'!cta / !bounties request reports locally; use the board to send.',12,-275,550)
  button(body,'Addon Checker',272,-365,245,function()active='Addon Checker';K.AddonChecker.Request();render() end)
  button(body,'Alert Settings',12,-545,245,function()active='Alert Settings';render() end)
  button(body,'Sync Health Monitor',12,-365,245,function()active='Sync Health';render() end)
  button(body,'Request board sync',12,-316,245,function()K.Operations.RequestSync() end)
  button(body,(d.settings.alerts and 'CTA alerts: ON' or 'CTA alerts: OFF'),272,-316,245,function()d.settings.alerts=not d.settings.alerts;render() end)
 elseif active=='Alert Settings' then
  label(body,'ALERT SETTINGS',12,-12,550,'GameFontNormalLarge')
  label(body,'Adjust sounds without changing detection or guild sync.',12,-48,540)
  local q=K.QOL
  for i,item in ipairs({{'alertSound','All alert sounds'},{'bountySound','Bounty sound'},{'guildmateSound','Guildmate sound'}}) do
   local key,text=item[1],item[2]
   button(body,text..': '..(q.Enabled(key) and 'ON' or 'OFF'),12,-95-(i-1)*52,350,function()q.Toggle(key);render() end)
  end
  button(body,'Bounty Alerts: '..(K.BountyAlerts.Status() and 'ON' or 'OFF'),12,-280,350,function()K.BountyAlerts.SetEnabled(not K.BountyAlerts.Status());render() end)
  button(body,'Guildmate Alerts: '..(K.GuildmateAlerts.Status() and 'ON' or 'OFF'),12,-332,350,function()K.GuildmateAlerts.SetEnabled(not K.GuildmateAlerts.Status());render() end)
  label(body,'Friendly bounty test mode: /kt bountyalert test on/off',12,-392,550)
  button(body,'Back to Settings',12,-450,180,function()active='Settings';render() end)
 elseif active=='Guild Roster' then
  button(body,'Back to Settings',12,-53,180,function()active='Settings';render() end)
  label(body,'GUILD ROSTER  /  Live game roster',12,-12,560,'GameFontNormalLarge')
  button(body,'Refresh roster',200,-53,170,function()if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end;K.Roster.Scan() end)
  local members={};for _,m in pairs(d.roster) do table.insert(members,m) end
  table.sort(members,function(a,b)return tostring(a.name)<tostring(b.name) end)
  for i,m in ipairs(members) do if i>48 then break end;label(body,(m.online and '|cff55ff77ONLINE|r ' or '')..m.name..'  |  '..tostring(m.rank)..'  |  L'..tostring(m.level)..' '..tostring(m.class),12,-105-(i-1)*27,565) end
 elseif active=='Chronicle' then
  button(body,'Back to Settings',12,-53,180,function()active='Settings';render() end)
  label(body,'GUILD CHRONICLE  /  Recent recorded events',12,-12,565,'GameFontNormalLarge')
  for i,e in ipairs(d.history) do if i>48 then break end;label(body,e.time..' ['..e.category..'] '..e.text,12,-56-(i-1)*30,565) end
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
function U.OpenBountyForUnit(unit)
 if InCombatLockdown and InCombatLockdown() then K.Say('Open bounty entry after combat.');return end
 if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then K.Say('Target a player first.');return end
 local name=UnitName(unit)
 if not name or name=='' then K.Say('Player name unavailable.');return end
 pendingBountyTarget=K.Clean(name,80)
 if not frame or not frame:IsShown() then U.Toggle('Bounty Entry') else active='Bounty Entry';render() end
end
function U.CheckerRefresh() if active=='Addon Checker' then U.Refresh() end end
function U.Refresh() if InCombatLockdown and InCombatLockdown() then U.needsRefresh=true;return end;render() end
K.On('PLAYER_REGEN_ENABLED',function() if U.needsRefresh then U.needsRefresh=false;U.Refresh() end end)
function U.Toggle(page)
 if InCombatLockdown and InCombatLockdown() then K.Say('Open War Command after combat.');return end
 if not frame then
  frame=CreateFrame('Frame','KeepersWarCommandFrame',UIParent);frame:SetSize(860,680);frame:SetPoint('CENTER',UIParent,'CENTER',0,30);frame:SetMovable(true);frame:EnableMouse(true);frame:SetClampedToScreen(true);frame:SetFrameStrata('FULLSCREEN_DIALOG');frame:SetFrameLevel(100);frame:SetScale(fitScale(U.GetScale()))
  -- Dragging is restricted to the header so the parent frame cannot capture clicks
  -- meant for edit boxes inside the scroll area.
  local dragHeader=CreateFrame('Frame',nil,frame)
  dragHeader:SetPoint('TOPLEFT',frame,'TOPLEFT',2,-2)
  dragHeader:SetPoint('TOPRIGHT',frame,'TOPRIGHT',-65,-2)
  dragHeader:SetHeight(43)
  dragHeader:EnableMouse(true)
  dragHeader:RegisterForDrag('LeftButton')
  dragHeader:SetScript('OnDragStart',function()frame:StartMoving() end)
  dragHeader:SetScript('OnDragStop',function()frame:StopMovingOrSizing() end)
  local border=frame:CreateTexture(nil,'BACKGROUND');border:SetAllPoints(frame);border:SetColorTexture(0.23,0.27,0.34,1)
  local backdrop=frame:CreateTexture(nil,'ARTWORK');backdrop:SetPoint('TOPLEFT',2,-2);backdrop:SetPoint('BOTTOMRIGHT',-2,2);backdrop:SetColorTexture(0.043,0.053,0.072,1)
  local sidebar=frame:CreateTexture(nil,'BACKGROUND')
  sidebar:SetPoint('TOPLEFT',frame,'TOPLEFT',8,-57);sidebar:SetPoint('BOTTOMLEFT',frame,'BOTTOMLEFT',8,12)
  sidebar:SetWidth(211);sidebar:SetColorTexture(0.060,0.075,0.10,1)
  local sidebarAccent=frame:CreateTexture(nil,'ARTWORK')
  sidebarAccent:SetPoint('TOPLEFT',frame,'TOPLEFT',218,-58);sidebarAccent:SetPoint('BOTTOMLEFT',frame,'BOTTOMLEFT',218,14)
  sidebarAccent:SetWidth(2);sidebarAccent:SetColorTexture(0.23,0.27,0.34,0.6)
  local stripe=frame:CreateTexture(nil,'OVERLAY');stripe:SetPoint('TOPLEFT',frame,'TOPLEFT',2,-46);stripe:SetPoint('TOPRIGHT',frame,'TOPRIGHT',-2,-46);stripe:SetHeight(2);stripe:SetColorTexture(0.25,0.31,0.40,0.65)
  label(frame,'KEEPERS OF TROGDOR',18,-12,255,'GameFontNormal');header=label(frame,'OVERVIEW',282,-12,475,'GameFontNormalLarge')
  local close=button(frame,'X',800,-8,28,function()frame:Hide() end)
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

  local positions={-98,-148,-187,-226,-293,-332,-399,-438}
  label(frame,'WORKSPACE',22,-70,175)
  label(frame,'INTELLIGENCE',22,-267,175)
  label(frame,'GUILD',22,-373,175)
  for i,t in ipairs(tabs) do
   button(frame,t,16,positions[i],195,function()active=t;render() end)
  end
  button(frame,'Settings',16,-523,195,function()active='Settings';render() end)
  button(frame,'Sync Health',16,-562,195,function()active='Sync Health';render() end)
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
 if type(page)=='string' and page~='' then active=page;frame:Show() else if frame:IsShown() then frame:Hide() else frame:Show() end end
 if frame:IsShown() then frame:SetScale(fitScale(U.GetScale())) end
 if frame:IsShown() and K.Sync and K.Sync.OnWindowOpened then K.Sync.OnWindowOpened() end
 render()
end
