-- War Room page: Settings & diagnostics.
local K=KWC
local Kit,S,P,W=K.Kit,K.WarRoomSkin,K.WarRoomPages,K.WarRoom2
local OWNER=S.OWNER

local page={id='settings',title='Settings',subtitle='Appearance, sync, sharing, diagnostics and credits.',group='system'}
local function v() return KWCDB and KWCDB.settings or {} end

function page.Build(self,host)
 local scroll,c=Kit.Scroll(host)
 self.content=c
 -- Appearance
 local help=S.Card(c,'Help & Tutorial');help.fullWidth=true
 help.launch=S.Button(help.body,'Launch Tutorial','primary',function() K.Tutorial.Start() end,160,28)
 function help:LayoutBody(st) st:Actions({self.launch}) end
 local a=S.Card(c,'Window and minimap')
 a.scaleLabel=S.Text(a.body,'kicker','muted');a.scaleLabel:SetPoint('TOPLEFT',0,-60);a.scaleLabel:SetText('WINDOW SCALE')
 a.scale=S.Text(a.body,'body','text');a.scale:SetPoint('TOPLEFT',0,-82)
 a.minus=S.Button(a.body,'-','secondary',function() K.UI.SetScale(K.UI.GetScale()-0.05);self:Update() end,34,26);a.minus:SetPoint('TOPLEFT',60,-76)
 a.plus=S.Button(a.body,'+','secondary',function() K.UI.SetScale(K.UI.GetScale()+0.05);self:Update() end,34,26);a.plus:SetPoint('LEFT',a.minus,'RIGHT',6,0)
 a.minimap=S.Switch(a.body,'Minimap button',function() return K.Minimap.IsVisible() end,function(x) K.Minimap.SetVisible(x) end,260)
 a.minimap:SetPoint('TOPLEFT',0,-116)
 a.winter=S.Switch(a.body,'Winter Veil decorations',function() return K.WinterVeil.Enabled() end,function(x) K.WinterVeil.SetEnabled(x) end,260,'Festive War Room art, shown from November 26 to January 2.')
 a.winter:SetPoint('TOPLEFT',0,-146)
 -- Sync
 local s=S.Card(c,'Guild sync')
 s.auto=S.Switch(s.body,'Automatic guild sync',function() return K.Sync.AutoSyncEnabled() end,function(x) K.Sync.SetAutoSync(x) end,300,'Catches up boards, deletions, honor and raid sign-ups on login, periodically and when you open the War Room.')
 s.auto:SetPoint('TOPLEFT')
 s.scout=S.Switch(s.body,'Auto Scout (zone enemy counts)',function() return K.AutoScout.Status() end,function(x) K.AutoScout.SetEnabled(x) end,300)
 s.scout:SetPoint('TOPLEFT',0,-30)
 s.now=S.Button(s.body,'Sync now','primary',function() K.Sync.RequestAll(false);self:Update() end,110,28);s.now:SetPoint('TOPLEFT',0,-66)
 s.honor=S.Button(s.body,'Refresh honor','secondary',function() K.PvP.RequestGuildHonor(false) end,130,28);s.honor:SetPoint('LEFT',s.now,'RIGHT',8,0)
 s.info=S.Para(s.body,380,'faint',12);s.info:SetPoint('TOPLEFT',0,-104)
 -- Sharing
 local sh=S.Card(c,'Sharing')
 sh.records=S.Switch(sh.body,'Share Guild Records and death counts',function() return K.GuildRecords.Sharing() end,function(x) K.GuildRecords.SetSharing(x) end,360,'Shares your game Statistics boards plus lifetime and open-world death counts with guildmates.')
 sh.records:SetPoint('TOPLEFT')
 sh.services=S.Switch(sh.body,'Share my professions (Guild Services)',function() return K.GuildServices.IsSharing() end,function(x) K.GuildServices.SetSharing(x) end,360)
 sh.services:SetPoint('TOPLEFT',0,-30)
 sh.note=S.Para(sh.body,380,'faint',12);sh.note:SetPoint('TOPLEFT',0,-64)
 sh.note:SetText('Shared data travels only on the guild addon channel and is scoped to this guild. Turning sharing off withdraws your values from guildmates\' boards.')
 -- Diagnostics
 local d=S.Card(c,'Diagnostics')
 d.text=S.Para(d.body,780,'text',12);d.text:SetPoint('TOPLEFT')
 -- Identity
 local id=S.Card(c,'Character identity')
 id.text=S.Para(id.body,780,'text',12);id.text:SetPoint('TOPLEFT')
 -- Addon checker
 local ac=S.Card(c,'Addon checker')
 ac.req=S.Button(ac.body,'Check online guildmates','primary',function() K.AddonChecker.Request();self:Update() end,200,28);ac.req:SetPoint('TOPLEFT')
 ac.text=S.Para(ac.body,780,'text',12);ac.text:SetPoint('TOPLEFT',0,-38)
 -- Integrations & credits
 local cr=S.Card(c,'Integrations and credits')
 cr.text=S.Para(cr.body,780,'muted',12);cr.text:SetPoint('TOPLEFT')
 self.cards={help,a,s,sh,cr,d,id,ac};self.a,self.s,self.sh,self.d,self.idc,self.ac,self.cr=a,s,sh,d,id,ac,cr
 d.fullWidth,id.fullWidth,ac.fullWidth=true,true,true
 function a:LayoutBody(st)
  st:Place(self.scaleLabel,nil,6)
  self.scale.keepWidth=true;self.scale:SetWidth(52);self.scale:SetHeight(26)
  st:Actions({self.scale,self.minus,self.plus})
  st:Place(self.minimap,nil,4);st:Place(self.winter,nil,8)
 end
 function s:LayoutBody(st)
  st:Place(self.auto,nil,4);st:Place(self.scout,nil,8)
  st:Actions({self.now,self.honor})
  st:Place(self.info,nil,0)
 end
 function sh:LayoutBody(st)
  st:Place(self.records,nil,4);st:Place(self.services,nil,8);st:Place(self.note,nil,0)
 end
 local function layoutText(card,st) st:Place(card.text,nil,0) end
 d.LayoutBody,id.LayoutBody,cr.LayoutBody=layoutText,layoutText,layoutText
 function ac:LayoutBody(st)
  self.req.keepWidth=true;st:Place(self.req,28,10);layoutText(self,st)
 end
 P.CardNavigation(host,scroll,{{'Tutorial',help},{'Window',a},{'Guild sync',s},{'Sharing',sh},{'Diagnostics',d},{'Identity',id},{'Addon checker',ac,118}})
 host:SetScript('OnSizeChanged',function() self:Layout() end)
 self:Layout()
end
function page.Layout(self)
 local c=self.content;if not c then return end
 local w=c:GetWidth()
 P.CardGrid(c,w>0 and w or 664,self.cards,340)
end
function page.OnShow(self,arg) end
function page.Update(self)
 if not self.content then return end
 self.a.minimap:Update();self.a.winter:Update()
 self.a.scale:SetText(math.floor(K.UI.GetScale()*100+0.5)..'%')
 self.s.auto:Update();self.s.scout:Update();self.sh.records:Update();self.sh.services:Update()
 local h=K.Sync.Health()
 local q,sent,failed,dropped,lock=K.Net.Status()
 self.s.info:SetText(('Board sync: %d requests, %d received, %d applied, %d rejected. Network: %d queued, %d sent, %d errors, %d dropped, %d lockdown pauses.'):format(h.requests or 0,h.received or 0,h.applied or 0,h.rejected or 0,q or 0,sent or 0,failed or 0,dropped or 0,lock or 0))
 local state,guild,actor,reason=K.GuildReadiness()
 local lines={
  'Version '..tostring(K.version)..'  -  protocols '..tostring(K.protocolFamily)..'  -  Interface 16001',
  'Guild identity: '..tostring(state)..(actor and ('  -  verified as '..actor) or '')..(reason and ('  ('..reason..')') or ''),
  K.InstanceStatusLine(),
  'Recovery: '..K.Sync.RecoveryStatus(),
 }
 local d=K.Sync.BoardDiagnostics()
 lines[#lines+1]=('CTA sync: sent %d, received %d, applied %d, rejected %d   |   Bounty sync: sent %d, received %d, applied %d, rejected %d'):format(d.CTA.sent,d.CTA.received,d.CTA.applied,d.CTA.rejected,d.Bounty.sent,d.Bounty.received,d.Bounty.applied,d.Bounty.rejected)
 local px=K.PvP.Diagnostics()
 lines[#lines+1]=('PvP sync: sent %d, received %d, rejected %d, pending %d'):format(px.sent or 0,px.received or 0,px.rejected or 0,px.pending or 0)
 lines[#lines+1]=S.Code('faint')..'Chat commands with more detail: /kt guilddebug, /kt syncdiag, /kt pvpdiag, /kt deathledger, /kt net|r'
 self.d.text:SetText(table.concat(lines,'\n'))
 local ist=K.Identity.Status()
 local log=K.Identity.Log()
 local il={('Characters known by GUID in this guild: %d. Verified renames this session: %d. Pending self-claims awaiting an officer: %d.'):format(ist.known,ist.renames,ist.claims)}
 for i,e in ipairs(log) do
  if i>4 then break end
  il[#il+1]=S.Code('muted')..tostring(e.from)..' is now '..tostring(e.to)..'|r  '..S.Code('faint')..'('..tostring(e.evidence)..', '..Kit.Age(e.at)..' ago; moved: '..(e.moved~='' and e.moved or 'nothing')..')|r'
 end
 if #log==0 then il[#il+1]=S.Code('faint')..'No renames recorded. When a guildmate changes their name, their history follows them automatically once their GUID is verified on the guild roster.|r' end
 self.idc.text:SetText(table.concat(il,'\n'))
 local entries=K.AddonChecker.Entries()
 local al={K.AddonChecker.Status()}
 for i,e in ipairs(entries) do if i>12 then al[#al+1]='...';break end;al[#al+1]=P.Short(e.name)..'  '..S.Code(tostring(e.version)==tostring(K.version) and 'good' or 'warn')..tostring(e.version)..'|r  '..S.Code('faint')..Kit.Age(e.lastSeen)..' ago|r' end
 if #entries==0 then al[#al+1]=S.Code('faint')..'No replies yet.|r' end
 self.ac.text:SetText(table.concat(al,'\n'))
 local ov=K.Companions.Overlord() and 'Overlord Forever: loaded (read-only objective snapshot)' or 'Overlord Forever: not installed'
 self.cr.text:SetText(ov..'\nWar Effort: '..K.Companions.WarEffortStatus()..'\n\nKeepers Raid Tools is adapted from Purplexity Raid Tools by nivthefox (Purplexity). Bundled libraries: LibStub, CallbackHandler, AceComm, ChatThrottleLib, LibSerialize, LibDeflate, LibSharedMedia (see THIRD_PARTY_NOTICES.txt).')
 self:Layout()
end
W.Register(page)
