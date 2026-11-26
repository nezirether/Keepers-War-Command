-- SOS expiry, countdown, offline recovery, editing, duplicates, delivery wording,
-- priority fairness and ordinary Call to Arms compatibility.
-- Pass a second add-on folder (an older build) as arg 1 for mixed-version checks.
local H=dofile('tests/harness/wow.lua')
local OLDER=arg and arg[1]
local DB={'KWCDB','KeepersRaidToolsDB','KeepersRaidToolsAttendanceDB','KeepersRaidToolsRosterDB','KRTForeverNotesDB'}
local function guild()
 local w=H.World()
 w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})
 w:AddMember({name='Ash Ember',rank=3,guid='Player-1-0000000A'})
 w:AddMember({name='Lok Tar',rank=3,guid='Player-1-0000000D'})
 local function boot(n,saved,dir)
  local c=w:Client(n,{saved=saved})
  -- The game clock is whole seconds; the harness steps in quarters.
  local clock=c.env.time;c.env.time=function(...) return math.floor(clock(...)) end
  w:LoadAddon(c,dir or 'KeepersWarCommand');c.env.GetRealZoneText=function() return 'Ashenvale' end
  w:Login(c);w:Advance(6);return c
 end
 return w,boot
end
local function sos(c,id) for _,e in ipairs(c.env.KWCDB.ops) do if c.env.KWC.Operations.IsSOS and c.env.KWC.Operations.IsSOS(e) and (not id or e.id==id) then return e end end end
local function byId(c,id) for _,e in ipairs(c.env.KWCDB.ops) do if e.id==id then return e end end end
local function popup(c) return c.env.KWC.Toast.channels.ctaNotice.frame end
local function said(c,text) return table.concat(c.printed,'\n'):find(text,1,true)~=nil end
local errors={}
local function collect(w) for _,c in ipairs(w.clients) do for _,e in ipairs(c.errors) do errors[#errors+1]=c.name..': '..e end;if said(c,'Interface error') then errors[#errors+1]=c.name..': interface error' end end end

local w,boot=guild()
local ash,grom=boot('Ash Ember'),boot('Grom Warcry');w:Advance(30)
local A,G=ash.env.KWC.Operations,grom.env.KWC.Operations
local _,mine=A.RequestBackup()
local created=tonumber(mine.id:match('^(%d+)'))
H.Check('status starts as queued, not delivered',A.SOSStatusText(mine):find('Queued to send',1,true) and not A.SOSStatusText(mine):find('received',1,true),A.SOSStatusText(mine))
w:Advance(8)
H.Check('status becomes sent without claiming delivery',A.SOSStatusText(mine)=='Sent by your client. Delivery is not confirmed.' and said(ash,'Delivery is not confirmed'),A.SOSStatusText(mine))
local W=ash.env.KWC.WarRoom2;W.Show('dashboard');local dash=W.pages.dashboard
H.Check('remaining time is shown',dash.sos.text:GetText()=='Resolve SOS (10m)' and A.SOSTimeText(mine)=='10m left',dash.sos.text:GetText())
local g=sos(grom)
H.Check('popup states the time left',popup(grom):IsShown())
G.Respond(g.id,'Coming');w:Advance(6)
H.Check('a response is reported as the only receipt evidence',A.SOSStatusText(mine):find('1 guildmate response received',1,true),A.SOSStatusText(mine))
w:Advance(200);dash:Update()
H.Check('countdown advances',dash.sos.text:GetText()~='Resolve SOS (10m)' and A.SOSRemaining(mine)<400,dash.sos.text:GetText())

-- Editing keeps identity, creator, creation time, expiry and permissions.
popup(grom):Hide()
local left=A.SOSRemaining(mine)
W.Show('cta',{select=mine.id});local cta=W.pages.cta
A.UpdateCTA(mine.id,'Ashenvale','','','Three of them at the bridge','NORMAL','bring heals');w:Advance(8)
g=byId(grom,mine.id)
H.Check('edit without enemy counts is accepted',mine.revision==1 and mine.details.horde==nil and mine.details.alliance==nil and not mine.text:find('H:A',1,true),mine.text)
H.Check('edited description keeps SOS identity and urgency',A.IsSOS(mine) and G.IsSOS(g) and g.text:find('Three of them',1,true) and mine.details.priority=='URGENT',g.text)
H.Check('creator, ID and expiry are unchanged',g.author==mine.author and g.id==mine.id and math.abs(A.SOSRemaining(mine)-(left-8))<=1)
H.Check('edit raises no second popup',not popup(grom):IsShown())
A.UpdateCTA(mine.id,'Ashenvale','','4','x','URGENT','')
H.Check('a single enemy count is refused',mine.revision==1)
A.Edit('CTA',mine.id,'words only');w:Advance(8)
H.Check('text edit cannot drop the SOS identity',A.IsSOS(mine) and mine.text:find('SOS: backup needed',1,true) and G.IsSOS(byId(grom,mine.id)))
local lok=boot('Lok Tar');w:Advance(5)
lok.env.KWC.Operations.UpdateCTA(mine.id,'Nowhere','','','vandalism','LOW','')
H.Check('another member still cannot edit it',not (byId(lok,mine.id) or {text=''}).text:find('vandalism',1,true))
-- The page's own edit form submits blank counts as blank.
W.Show('cta',{select=mine.id})
local function press(label) for _,b in ipairs(ash.allWidgets) do if b.kind=='Button' and rawget(b,'text') and type(b.text)=='table' and b.text:GetText()==label and b:IsVisible() then b:Click();return true end end return false end
local before=mine.revision
H.Check('edit form opens',press('Edit') and press('Save changes'))
w:Advance(8)
H.Check('saving the form keeps blank counts and identity',mine.revision==before+1 and mine.details.horde==nil and mine.details.alliance==nil and A.IsSOS(mine) and not mine.text:find('H:A',1,true),mine.text)
H.Check('no duplicate records',#ash.env.KWCDB.ops==1 and #grom.env.KWCDB.ops==1)

-- Lok goes offline holding an active copy.
local saved=w:Saved(lok,DB);w:Drop(lok);w:Member('Lok Tar').online=false
local savedAsh
popup(grom):Hide()
w.now=created+590;w:Advance(5)
H.Check('still active just before 10 minutes',mine.status=='ACTIVE' and byId(grom,mine.id).status=='ACTIVE')
w:Advance(20)
H.Check('expires at 10 minutes on both clients',mine.status=='RESOLVED' and byId(grom,mine.id).status=='RESOLVED' and A.SOSExpired(mine) and G.SOSExpired(byId(grom,mine.id)))
H.Check('requester publishes the expiry once',mine.sosExpirySent==true and not byId(grom,mine.id).sosExpirySent)
local revision=mine.revision;w:Advance(30)
H.Check('expiry does not repeat',mine.revision==revision and byId(grom,mine.id).revision==revision and not popup(grom):IsShown())
H.Check('dashboard offers a new request',(function() W.Show('dashboard');return dash.sos.text:GetText()=='Request Backup' and A.ActiveSOS()==nil end)())
A.ChangeStatus('CTA',mine.id,'ACTIVE')
H.Check('an expired request cannot be reopened',mine.status=='RESOLVED')
H.Check('a response after expiry is ignored',(function() local before=(grom.env.KWCDB.responses[mine.id] or {})['grom warcry'];G.Respond(mine.id,'Busy');return (grom.env.KWCDB.responses[mine.id] or {})['grom warcry']==before end)())
W.Show('cta',{select=mine.id})
-- Reload and late login.
w:Member('Lok Tar').online=true;lok=boot('Lok Tar',saved);popup(lok):Hide();w:Advance(200)
H.Check('offline member comes back to an expired request',byId(lok,mine.id).status=='RESOLVED' and not popup(lok):IsShown() and not said(lok,'CALL TO ARMS'))
local grom2saved=w:Saved(grom,DB);w:Drop(grom);grom=boot('Grom Warcry',grom2saved);w:Advance(100)
H.Check('stays expired after reload and resync',byId(grom,mine.id).status=='RESOLVED' and byId(ash,mine.id).status=='RESOLVED' and byId(lok,mine.id).status=='RESOLVED')
collect(w)

-- Requester gone: every remaining client closes it by itself.
w,boot=guild();ash,grom=boot('Ash Ember'),boot('Grom Warcry');w:Advance(30)
_,mine=ash.env.KWC.Operations.RequestBackup();w:Advance(10)
local ashSaved=w:Saved(ash,DB);w:Drop(ash);w:Member('Ash Ember').online=false
w:Advance(700)
H.Check('expires without the requester',byId(grom,mine.id).status=='RESOLVED' and grom.env.KWC.Operations.Stats().activeCTA==0)
lok=boot('Lok Tar');w:Advance(200)
H.Check('a new member is not shown it as active',not byId(lok,mine.id) or byId(lok,mine.id).status=='RESOLVED')
H.Check('no popup or chat call for it',not popup(lok):IsShown() and not said(lok,'CALL TO ARMS'))
w:Member('Ash Ember').online=true;ash=boot('Ash Ember',ashSaved);w:Advance(30)
H.Check('returning requester closes and publishes it',byId(ash,mine.id).status=='RESOLVED' and byId(ash,mine.id).sosExpirySent and byId(grom,mine.id).status=='RESOLVED')
collect(w)

-- Manual resolution, instance suppression and ordinary calls.
w,boot=guild();ash,grom=boot('Ash Ember'),boot('Grom Warcry');w:Advance(30)
grom.instance='raid';w:Fire(grom,'PLAYER_ENTERING_WORLD',false,false);w:Advance(2);popup(grom):Hide()
_,mine=ash.env.KWC.Operations.RequestBackup();w:Advance(10)
H.Check('no popup or chat inside an instance',byId(grom,mine.id) and not popup(grom):IsShown() and not said(grom,'CALL TO ARMS'))
ash.env.KWC.Operations.ChangeStatus('CTA',mine.id,'RESOLVED');w:Advance(10)
H.Check('requester can resolve early; it is not marked expired',byId(grom,mine.id).status=='RESOLVED' and not grom.env.KWC.Operations.SOSExpired(byId(grom,mine.id)))
w:Advance(700)
H.Check('a resolved request is untouched by expiry',byId(ash,mine.id).sosExpired==nil)
ash.env.KWC.Operations.DetailedCTA('Durotar','Hold the road',2,3,'URGENT','','')
local plain=ash.env.KWCDB.ops[1];w:Advance(8);w.now=w.now+3600;w:Advance(5)
H.Check('ordinary calls never expire',plain.status=='ACTIVE' and byId(grom,plain.id).status=='ACTIVE' and ash.env.KWC.Operations.SOSTimeText(plain)==nil)
ash.env.KWC.Operations.UpdateCTA(plain.id,'Durotar','','','x','HIGH','')
H.Check('ordinary calls still require enemy counts',plain.details.horde==2)

-- Priority traffic cannot starve ordinary messages.
local net=ash.env.KWC.Net;local order={}
local send=ash.env.C_ChatInfo.SendAddonMessage
ash.env.C_ChatInfo.SendAddonMessage=function(p,m,...) order[#order+1]=m;return send(p,m,...) end
w:Advance(60);order={}
for i=1,5 do net.Send('KWC3','2;NOISE;'..i,'GUILD') end
local mark=net.Mark();for i=1,40 do net.Send('KWC3','2;URGENT;'..i,'GUILD') end;net.Expedite(mark)
w:Advance(25)
local firstNoise,noise=nil,0
for i,m in ipairs(order) do if m:find('NOISE') then noise=noise+1;firstNoise=firstNoise or i end end
H.Check('ordinary traffic flows during a priority flood',firstNoise and firstNoise<=6 and noise>=4,tostring(firstNoise)..' '..noise)
collect(w)

if OLDER then
 w,boot=guild()
 ash,grom=boot('Ash Ember'),boot('Grom Warcry',nil,OLDER);w:Advance(30)
 _,mine=ash.env.KWC.Operations.RequestBackup();w:Advance(10)
 H.Check('older client receives a new SOS',byId(grom,mine.id) and byId(grom,mine.id).status=='ACTIVE')
 ash.env.KWC.Operations.UpdateCTA(mine.id,'Ashenvale','','','edited','URGENT','');w:Advance(10)
 H.Check('older client accepts an edit without counts',byId(grom,mine.id).text:find('edited',1,true),byId(grom,mine.id).text)
 w:Advance(620)
 H.Check('older client sees the requester\'s expiry',byId(grom,mine.id).status=='RESOLVED')
 if grom.env.KWC.Operations.RequestBackup then
 grom.env.KWC.Operations.RequestBackup();local theirs=grom.env.KWCDB.ops[1];w:Advance(10)
 H.Check('new client receives an older client\'s SOS',byId(ash,theirs.id) and ash.env.KWC.Operations.IsSOS(byId(ash,theirs.id)))
 w:Advance(620)
 H.Check('new client expires it locally',byId(ash,theirs.id).status=='RESOLVED')
 w:Advance(200)
 H.Check('and does not revive it from the older client',byId(ash,theirs.id).status=='RESOLVED')
 end
 grom.env.KWC.Operations.DetailedCTA('Durotar','Old style call',1,2,'HIGH','','');w:Advance(10)
 H.Check('ordinary calls cross versions',byId(ash,grom.env.KWCDB.ops[1].id)~=nil)
 collect(w)
end
H.Check('no Lua errors',#errors==0,table.concat(errors,' | '):sub(1,400))
os.exit(H.Summary('sos_lifecycle') and 0 or 1)
