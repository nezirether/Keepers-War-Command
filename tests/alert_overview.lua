-- The Alerts page (successor of the 1.x Alert Command Center window): per-alert
-- preview, move, lock, reset, enable and sound controls, routing, instance
-- behaviour and widget reuse. Run from the repository root.
local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})
local c=w:Client('Grom Warcry');w:LoadAddon(c,'KeepersWarCommand');w:Login(c);w:Advance(6)
local K,env=c.env.KWC,c.env
local W=K.WarRoom2
W.Show('alerts')
local page=W.pages.alerts
local settings=env.KWCDB.settings
local function card(key) for _,x in ipairs(page.cards) do if x.def and x.def.key==key then return x end end end
local function switch(key,label) for _,s in ipairs(card(key).sw) do if s.text:GetText()==label then return s end end error(key..' has no switch '..label) end
local death,bounty=K.Toast.channels.worldPvPDeath,K.Toast.channels.bountyAlert
assert(W.Current()==page and card('worldPvPDeath') and card('bountyAlert') and card('pvpKill') and card('ctaNotice'))
card('worldPvPDeath').preview:Click()
assert(death.frame:IsShown() and #(env.KWCDB.worldPvPDeaths or {})==0)
death.frame:Hide()
card('worldPvPDeath').place:Click()
assert(settings.worldPvPDeathUnlocked and death.frame:IsShown() and not settings.bountyAlertUnlocked)
settings.worldPvPDeathPosition={point='TOP',relativePoint='TOP',x=40,y=-60}
card('worldPvPDeath').place:Click()
assert(not settings.worldPvPDeathUnlocked and not death.frame:IsShown() and settings.worldPvPDeathPosition.x==40)
card('worldPvPDeath').reset:Click()
assert(settings.worldPvPDeathPosition==nil)
local was=settings.bountyAlerts~=false
switch('bountyAlert','Popup'):Click();assert((settings.bountyAlerts~=false)==not was)
switch('bountyAlert','Popup'):Click();assert((settings.bountyAlerts~=false)==was)
local sound=K.QOL.Enabled('bountySound')
switch('bountyAlert','Sound'):Click();assert(K.QOL.Enabled('bountySound')==not sound and settings.worldPvPDeathUnlocked~=true)
card('bountyAlert').place:Click();assert(settings.bountyAlertUnlocked and not settings.worldPvPDeathUnlocked)
card('bountyAlert').place:Click();assert(not settings.bountyAlertUnlocked)
card('bountyAlert').preview:Click();assert(bounty.frame:IsShown());bounty.frame:Hide()
print('PASS: alert preview, placement, reset, enable and sound controls')
local before=#c.allWidgets
for _=1,15 do page:Update() end
assert(#c.allWidgets==before,'redrawing should reuse frames')
for _,route in ipairs({'dashboard','bounties','lfg','records','settings'}) do
 W.Show(route);assert(W.Current().id==route);K.UI.Open('Alerts');assert(W.Current()==page,route)
end
for _,button in ipairs(page.previews) do assert(button.text:GetText()~='Artwork preview','retired control') end
for _,control in ipairs(page.celebrationControls) do assert(control.text:GetText()~='Event artwork','retired control') end
assert(K.Celebrations.Preferences().eventArt==true,'the saved preference is kept')
c.instance='party';w:Fire(c,'PLAYER_ENTERING_WORLD',false,false);w:Advance(1)
card('worldPvPDeath').preview:Click();assert(death.frame:IsShown(),'manual previews work anywhere')
assert(not death:Present({title='automatic'},true),'automatic alerts stay suppressed')
assert(#c.errors==0 and not table.concat(c.printed,'\n'):find('Interface error',1,true),c.errors[1])
print('PASS: routes, widget reuse, retired artwork controls and instance behaviour')
