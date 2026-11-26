-- Guild SOS over the ordinary Call to Arms engine: creation, location, open-world
-- gate, duplicates and spam, alerts and preferences, responses, resolution, sync.
local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})
w:AddMember({name='Ash Ember',rank=3,guid='Player-1-0000000A'})
w:AddMember({name='Lok Tar',rank=3,guid='Player-1-0000000D'})
local function boot(name) local c=w:Client(name);w:LoadAddon(c,'KeepersWarCommand');w:Login(c);w:Advance(6);return c end
local ash,grom,lok=boot('Ash Ember'),boot('Grom Warcry'),boot('Lok Tar')
w:Advance(20)
local A=ash.env.KWC.Operations
local zone='Hillsbrad Foothills'
ash.env.GetRealZoneText=function() return zone end
local position={GetXY=function() return 0.54,0.61 end}
ash.env.C_Map={GetBestMapForUnit=function() return 1424 end,GetPlayerMapPosition=function() return position end}
local function sosList(c) local out={};for _,e in ipairs(c.env.KWCDB.ops) do if c.env.KWC.Operations.IsSOS(e) then out[#out+1]=e end end;return out end
local function popup(c) return c.env.KWC.Toast.channels.ctaNotice.frame end
local function enter(c,kind) c.instance=kind;w:Fire(c,'PLAYER_ENTERING_WORLD',false,false);w:Advance(1) end

local W=ash.env.KWC.WarRoom2;W.Show('dashboard')
local page=W.pages.dashboard
local button=page.sos
H.Check('button offers Request Backup',button.text:GetText()=='Request Backup' and button:IsShown())
for _,kind in ipairs({'party','raid','pvp'}) do
 enter(ash,kind);button:Click()
 H.Check(kind..' instance cannot request backup',#sosList(ash)==0)
end
enter(ash,nil);popup(grom):Hide();popup(lok):Hide()
lok.env.KWCDB.settings.ctaPopup=false
button:Click()
local mine=sosList(ash)[1]
H.Check('request creates one urgent call',#sosList(ash)==1 and mine.status=='ACTIVE' and mine.text=='[URGENT] Hillsbrad Foothills - SOS: backup needed - 54.0, 61.0',mine and mine.text)
H.Check('no enemy counts are invented',mine.details.horde==nil and mine.details.alliance==nil and not mine.text:find('H:A',1,true))
H.Check('button switches to resolve with the time left',button.text:GetText()=='Resolve SOS (10m)',button.text:GetText())
w:Advance(8)
local g=sosList(grom)[1]
H.Check('guildmate receives it with zone and coordinates',g and g.id==mine.id and g.details and g.details.zone==zone and g.details.coords=='54.0, 61.0' and g.details.priority=='URGENT')
H.Check('guildmate gets one popup',popup(grom):IsShown())
H.Check('popup preference is respected, data still syncs',not popup(lok):IsShown() and #sosList(lok)==1)
popup(grom):Hide();grom.env.KWC.UI.Refresh();w:Advance(25)
H.Check('no repeat popup',not popup(grom):IsShown())
local ok=A.RequestBackup();w:Advance(5)
H.Check('a second active request is refused',ok==false and #sosList(ash)==1 and #sosList(grom)==1 and not popup(grom):IsShown())
for _,status in ipairs({'Maybe','Busy','Coming'}) do
 w:Advance(2);grom.env.KWC.Operations.Respond(g.id,status);w:Advance(6)
 local found;for _,v in pairs(ash.env.KWCDB.responses[mine.id] or {}) do found=v end
 H.Check(status..' response reaches the requester',found==status,found)
end
H.Check('officer can take a command seat',grom.env.KWC.Operations.CanAssumeCommand(g)==true)
lok.env.KWC.Operations.ChangeStatus('CTA',mine.id,'RESOLVED')
H.Check('an ordinary member cannot resolve it',sosList(lok)[1].status=='ACTIVE')
H.Check('the dashboard of others still offers Request Backup',(function() local L=lok.env.KWC.WarRoom2;L.Show('dashboard');return L.pages.dashboard.sos.text:GetText()=='Request Backup' end)())
W.Show('dashboard');button:Click()
local modal=ash.env.KWC.Kit.modals[ash.env.KWC.WarRoomSkin.OWNER]
H.Check('resolving asks first',modal and modal:IsShown() and mine.status=='ACTIVE')
popup(grom):Hide();modal.yes:Click();w:Advance(8)
H.Check('requester resolves it for the guild',mine.status=='RESOLVED' and sosList(grom)[1].status=='RESOLVED' and sosList(lok)[1].status=='RESOLVED')
H.Check('resolution raises no new popup',not popup(grom):IsShown())
H.Check('button returns',button.text:GetText()=='Request Backup')
-- Cooldown restarts from the last request, then a new one is allowed.
local function age() return ash.env.time()-tonumber(mine.id:match('^(%d+)')) end
if age()<60 then
 H.Check('immediate re-request is held by the cooldown',A.RequestBackup()==false and #sosList(ash)==1,age())
else
 H.Check('immediate re-request is held by the cooldown',true)
end
w.now=w.now+61
-- Receiver inside an instance: data syncs, alert stays silent.
enter(grom,'party');popup(grom):Hide()
position=nil
H.Check('request after cooldown succeeds without coordinates',A.RequestBackup()==true)
w:Advance(8)
local second=sosList(ash)[1]
H.Check('missing position leaves coordinates out',second.text=='[URGENT] Hillsbrad Foothills - SOS: backup needed' and second.details.coords=='')
H.Check('instance receiver syncs it without a popup',#sosList(grom)==2 and not popup(grom):IsShown())
enter(grom,nil)
local immediate=A.RequestBackup()
H.Check('cooldown and duplicate rules still hold',immediate==false)
-- Without the officer companion only the creator may delete (existing rule).
H.Check('deletion rule unchanged without the companion',grom.env.KWC.Operations.Delete('CTA',second.id)==false)
local removed,why=A.Delete('CTA',second.id)
H.Check('creator deletes an SOS',removed==true,why)
w:Advance(8)
H.Check('deleted request leaves every board',#sosList(ash)==1 and #sosList(grom)==1 and #sosList(lok)==1)
-- Unknown zone.
w.now=w.now+61;zone=''
H.Check('unreadable zone is stated, never guessed',A.RequestBackup()==true and sosList(ash)[1].text=='[URGENT] Unknown zone - SOS: backup needed' and sosList(ash)[1].details.coords=='')
local hot=true;for _,z in ipairs(page.HotZones()) do if z.zone=='Unknown zone' then hot=false end end
H.Check('unknown zone stays out of Hot Zones',hot)
-- Offline member recovers an active request without a late popup storm.
A.ChangeStatus('CTA',sosList(ash)[1].id,'RESOLVED');w.now=w.now+61;zone='Ashenvale';A.RequestBackup();w:Advance(8)
local late=boot('Lok Tar');w:Advance(100)
local recovered=false;for _,e in ipairs(sosList(late)) do if e.text:find('Ashenvale') and e.status=='ACTIVE' then recovered=true end end
H.Check('a client logging in later recovers the active request',recovered)
-- Ordinary calls are unaffected.
grom.env.KWC.Operations.DetailedCTA('Durotar','Hold the road',2,3,'HIGH','','')
H.Check('ordinary calls are not treated as SOS',not grom.env.KWC.Operations.IsSOS(grom.env.KWCDB.ops[1]))
for _,width in ipairs({656,936,1456}) do
 W.content:SetSize(width,436);page.host:SetSize(width,436)
 H.Check(width..' button fits the half-width card header',button:GetWidth()+120+80<=math.floor((width-10)/2))
end
local errors={}
for _,c in ipairs(w.clients) do for _,e in ipairs(c.errors) do errors[#errors+1]=e end;if table.concat(c.printed,'\n'):find('Interface error',1,true) then errors[#errors+1]=c.name end end
H.Check('no Lua errors',#errors==0,table.concat(errors,' | '):sub(1,300))
os.exit(H.Summary('guild_sos') and 0 or 1)
