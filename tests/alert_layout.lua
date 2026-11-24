local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Nez Dankdabs',rank=1,guid='Player-1-0000000A'})
local c=w:Client('Nez Dankdabs')
w:LoadAddon(c,'KeepersWarCommand');w:Login(c);w:Advance(15)
local K=c.env.KWC
local ch=K.Toast.channels.worldPvPDeath
local f=ch.frame
local function top(region)
 local _,_,_,_,y=region:GetPoint(1)
 return -y
end
local pin,copy=0,0
local content={kicker='Guildmate slain | World PvP',title='Filibuster Fente Longsurname was slain',
 detail='Killed by: An Enemy With A Very Long Full Name',meta='Hillsbrad Foothills 48.2, 61.7',
 actions={{label='Post bounty',fn=function()end},{label='Death log',fn=function()end},
 {label='Drop Pin',fn=function()pin=pin+1 end},{label='Copy Coordinates',fn=function()copy=copy+1 end}}}
for _,width in ipairs({404,460,540}) do
 for _,scale in ipairs({0.64,1,1.35}) do
  c.env.KWCDB.settings.worldPvPDeathScale=scale
  f:SetWidth(width);ch:Present(content,false)
  local metaBottom=top(f.meta)+f.meta:GetHeight()
  local actionsTop=top(f.actions[1])
  local endOfActions=top(f.actions[4])+f.actions[4]:GetHeight()
  H.Check(width..' at '..scale..' has separate text, metadata and action rows',
   top(f.title)>=top(f.kicker)+f.kicker:GetHeight() and
   top(f.detail)>=top(f.title)+f.title:GetHeight() and
   top(f.meta)>=top(f.detail)+f.detail:GetHeight() and
   actionsTop>=metaBottom+8 and f:GetHeight()>=endOfActions+8)
 end
end
f.actions[3]:Click();f.actions[4]:Click()
H.Check('pin and coordinate controls retain callbacks with artwork',pin==1 and copy==1)
H.Check('full supplied names and location survive layout',f.title:GetText()==content.title and f.meta:GetText()==content.meta)
K.Celebrations.Preferences().eventArt=false
ch:Present(content,false)
H.Check('classic fallback also keeps controls below location',top(f.actions[1])>top(f.meta)+f.meta:GetHeight() and not f.artKey)
local text=f.title:GetText()
w:Fire(c,'PLAYER_ENTERING_WORLD');w:Advance(1)
H.Check('layout and artwork add no synthetic history',#(c.env.KWCDB.worldPvPDeaths or {})==0)
H.Check('no Lua errors',#c.errors==0)
os.exit(H.Summary('alert_layout') and 0 or 1)
