-- War Room page: Alerts. Each popup channel can be toggled, previewed,
-- positioned, timed and given its own sound preference. Automatic alerts never
-- appear inside raids, dungeons, battlegrounds or uncertain/loading states;
-- previews always work so players can place them anywhere.
local K=KWC
local Kit,S,P,W=K.Kit,K.WarRoomSkin,K.WarRoomPages,K.WarRoom2
local OWNER=S.OWNER

local page={id='alerts',title='Alerts',subtitle='Popups for kills, deaths, bounties, calls to arms and guild groups.',group='system'}
local cards={}
local function v() return KWCDB and KWCDB.settings or {} end
local function flag(key,default) return function() local x=v()[key];if x==nil then return default end;return x end end
local function setFlag(key) return function(val) v()[key]=val and true or false end end
local function lfgPrefs() local s=v();s.guildLFG=s.guildLFG or {};return s.guildLFG end

-- Channel definitions: switches and the engine calls behind them.
local DEFS={
 {key='worldPvPDeath',title='Guildmate slain',desc='When a guildmate dies to an enemy player in the open world.',mod=function() return K.WorldPvPDeaths end,
  switches={
   {'Popup',flag('worldPvPDeathAlerts',true),function(x) K.WorldPvPDeaths.SetEnabled(x) end},
   {'Sound',flag('worldPvPDeathSound',true),function(x) K.WorldPvPDeaths.SetSound(x) end},
   {'Chat line',flag('worldPvPDeathChat',true),function(x) K.WorldPvPDeaths.SetChat(x) end},
   {'Smart Mode (quiet during big fights)',flag('worldPvPDeathSmart',true),function(x) K.WorldPvPDeaths.SetSmart(x) end},
   {'Hide while I am in combat',flag('worldPvPDeathSuppressInCombat',false),function(x) K.WorldPvPDeaths.SetCombatSuppression(x) end},
   {'Report my own deaths to the guild',flag('worldPvPDeathBroadcast',true),setFlag('worldPvPDeathBroadcast')},
  }},
 {key='pvpKill',title='Enemy slain',desc='When a guildmate earns an honorable kill in the open world.',mod=function() return K.WorldPvPKills end,
  switches={
   {'Popup',flag('pvpKillAlerts',true),function(x) K.WorldPvPKills.SetEnabled(x) end},
   {'Sound',flag('pvpKillSound',true),function(x) K.WorldPvPKills.SetSound(x) end},
   {'Chat line',flag('pvpKillChat',true),function(x) K.WorldPvPKills.SetChat(x) end},
   {'Smart Mode (quiet during big fights)',flag('pvpKillSmart',true),function(x) K.WorldPvPKills.SetSmart(x) end},
   {'Share my kills with the guild',flag('pvpKillBroadcast',true),function(x) K.WorldPvPKills.SetBroadcast(x) end},
   {'Also pop up killing blows that earn no honor',function() return K.WorldPvPKills.KillMode()=='all' end,function(x) K.WorldPvPKills.SetKillMode(x and 'all' or 'honor') end},
  },
  note='Killing blows come from Forever\'s PARTY_KILL event: only your own (or your pet\'s) killing blow is visible. Kills a party member finishes still show only when they earn you honor.'},
 {key='bountyAlert',title='Bounty target spotted',desc='When an active bounty target appears on your screen (target, mouseover, nameplates).',mod=function() return K.BountyAlerts end,
  switches={
   {'Popup',flag('bountyAlerts',true),function(x) K.BountyAlerts.SetEnabled(x) end},
   {'Sound',function() return K.QOL.Enabled('bountySound') end,function(x) v().bountySound=x end},
   {'Friendly test mode (match allies for testing)',function() return K.BountyAlerts.TestMode() end,function(x) K.BountyAlerts.SetTestMode(x) end},
  }},
 {key='ctaNotice',title='New call to arms',desc='When a guildmate posts a new Call to Arms during your session.',
  switches={
   {'Popup',flag('ctaPopup',true),setFlag('ctaPopup')},
   {'Sound',function() return K.QOL.Enabled('ctaSound') end,function(x) v().ctaSound=x end},
   {'Chat line for calls received from older clients',flag('alerts',true),function(x) v().alerts=x end},
  }},
 {key='lfgNotice',title='Guild groups',desc='Guild LFG listings that match you, interest in your listing, and invitations.',
  switches={
   {'Popup',flag('lfgPopup',true),setFlag('lfgPopup')},
   {'Sound',function() return K.QOL.Enabled('lfgSound') end,function(x) v().lfgSound=x end},
   {'New listings in my level range',function() return lfgPrefs().matching==true end,function(x) lfgPrefs().matching=x end},
   {'Guildmates interested in my listing',function() return lfgPrefs().interest==true end,function(x) lfgPrefs().interest=x end},
   {'Invitations from listing leaders',function() return lfgPrefs().invitation==true end,function(x) lfgPrefs().invitation=x end},
  }},
}

local function channel(key) return K.Toast.channels[key] end
local function buildCard(parent,def)
 local c=S.Card(parent,def.title)
 c.desc=S.Para(c.body,300,'muted',12);c.desc:SetPoint('TOPLEFT');c.desc:SetText(def.desc)
 c.sw={}
 for i,s in ipairs(def.switches) do
  c.sw[i]=S.Switch(c.body,s[1],s[2],function(x) Kit.Safe(s[3],x) end,380)
 end
 c.duration=S.Field(c.body,'Seconds on screen (3-30)',180,2,'8')
 c.duration.keepWidth=true
 c.duration.edit:SetScript('OnEnterPressed',function(self)
  local n=tonumber(self:GetText());local ch=channel(def.key)
  if not n or n<3 or n>30 then c.duration:Error('3 to 30');return end
  v()[ch.durationKey or (def.key..'Duration')]=math.floor(n);self:ClearFocus()
 end)
 c.duration.edit:SetScript('OnEditFocusLost',function(self) local n=tonumber(self:GetText());local ch=channel(def.key);if n and n>=3 and n<=30 then v()[ch.durationKey or (def.key..'Duration')]=math.floor(n) end end)
 c.actions=CreateFrame('Frame',nil,c.body)
 c.preview=S.Button(c.actions,'Preview','primary',function() local ch=channel(def.key);if ch.demo then ch.demo() end end,90,28)
 c.place=S.Button(c.actions,'Move','secondary',function()
  local ch=channel(def.key);ch:SetUnlocked(not ch:Unlocked());page:Update()
 end,80,28)
 c.reset=S.Button(c.actions,'Reset position','ghost',function() channel(def.key):Reset() end,120,28)
 if def.note then c.note=S.Para(c.body,380,'faint',12);c.note:SetText(def.note) end
 function c:LayoutBody(st)
  st:Place(self.desc,nil,12)
  for _,sw in ipairs(self.sw) do st:Place(sw,nil,2) end
  st:Space(8)
  st:Place(self.duration,52,8)
  local buttons={self.preview,self.place,self.reset}
  self.actions:SetHeight(P.Flow(buttons,self.actions,st.width,0,8))
  st:Place(self.actions,nil,10)
  if self.note then st:Place(self.note,nil,0) end
 end
 c.def=def
 return c
end

function page.Build(self,host)
 local scroll,c=Kit.Scroll(host)
 self.content=c
 self.status=S.Card(c,'Alert policy')
 self.statusText=S.Para(self.status.body,700,'text',13);self.statusText:SetPoint('TOPLEFT')
 self.master=S.Switch(self.status.body,'All alert sounds',function() return K.QOL.Enabled('alertSound') end,function(x) v().alertSound=x end,260)
 self.celebrationControls={}
 local options={{'PvP celebrations','pvp'},{'Streak milestones','streaks'},{'Bounty celebrations','bounties'},
 {'Personal milestones','milestones'},{'CTA celebrations','cta'},{'Guild achievements','guild'},
 {'Animations','animations'},{'Reduced motion','reducedMotion'},{'Event artwork','eventArt'}}
 for _,option in ipairs(options) do
  local key=option[2]
  self.celebrationControls[#self.celebrationControls+1]=S.Switch(self.status.body,option[1],
   function() return K.Celebrations.Preferences()[key] end,
   function(value) K.Celebrations.Preferences()[key]=value end,300)
 end
 self.intensity=S.Segmented(self.status.body,{{'Off'},{'Quiet'},{'Balanced'},{'Epic'}},
 function() return K.Celebrations.Preferences().intensity end,
 function(value) K.Celebrations.Preferences().intensity=value end,95)
 self.previews={}
 for _,level in ipairs({'Standard','Heroic','Legendary'}) do
  local value=level
  self.previews[#self.previews+1]=S.Button(self.status.body,level..' preview','secondary',function() K.Celebrations.Preview(value) end,145,30)
 end
 self.previews[#self.previews+1]=S.Button(self.status.body,'Sound preview','secondary',function() K.Celebrations.PreviewSound() end,145,30)
 self.previews[#self.previews+1]=S.Button(self.status.body,'Artwork preview','secondary',function() K.AlertArt.Preview() end,145,30)
 self.chronicle=S.Para(self.status.body,600,'muted',12)
 self.status.fullWidth=true
 self.cards={self.status}
 function self.status:LayoutBody(st)
  st:Place(page.statusText,nil,10)
  st:Place(page.master,nil,8)
  st:Place(page.intensity,28,8)
  for _,control in ipairs(page.celebrationControls) do st:Place(control,28,3) end
  st:Actions(page.previews,8)
  st:Place(page.chronicle,nil,6)
 end
 for i,def in ipairs(DEFS) do cards[i]=buildCard(c,def);self.cards[#self.cards+1]=cards[i] end
 P.CardNavigation(host,scroll,{{'Policy',self.status,80},{'Guild deaths',cards[1]},{'Kills',cards[2],70},
  {'Bounties',cards[3],90},{'Calls to Arms',cards[4],112},{'Guild LFG',cards[5],96}})
 host:SetScript('OnSizeChanged',function() self:Layout() end)
 self:Layout()
end
function page.Layout(self)
 local c=self.content;if not c then return end
 local w=self.host:GetWidth()
 P.CardGrid(c,w>0 and w or 664,self.cards,340)
end
function page.Update(self)
 if not self.content then return end
 local P2=K.InstanceAlerts
 local allowed=P2 and P2.Allowed and P2.Allowed()
 self.statusText:SetText((allowed and S.Code('good')..'Automatic alerts are active (open world confirmed).|r' or S.Code('warn')..'Automatic alerts are paused here.|r')..
  '  Alerts never fire automatically inside raids, dungeons, battlegrounds, or while loading/uncertain. They resume only after the open world is confirmed. Previews always work.')
 self.master:Update()
 K.Celebrations.Preferences().sounds=K.QOL.Enabled('alertSound')
 self.intensity:Update()
 for _,control in ipairs(self.celebrationControls) do control:Update() end
 local kills,best=K.Celebrations.Stats()
 local entries={'War Chronicle • recent personal commendations',kills..' locally observed killing blows • best observed streak '..best}
 for i,event in ipairs(K.Celebrations.History()) do
  if i>8 then break end
  entries[#entries+1]=date('%Y-%m-%d %H:%M',event.at)..' • '..event.title..' • '..(event.detail or '')
 end
 self.chronicle:SetText(table.concat(entries,'\n'))
 for _,card in ipairs(cards) do
  for _,sw in ipairs(card.sw) do sw:Update() end
  local ch=channel(card.def.key)
  card.place:SetLabel(ch and ch:Unlocked() and 'Lock' or 'Move')
  if not card.duration.edit:HasFocus() and ch then card.duration:Set(math.floor(ch:Duration())) end
 end
 self:Layout()
end
W.Register(page)
