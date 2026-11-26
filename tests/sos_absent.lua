-- Officer stand-in publication for an absent requester, clock differences, and
-- zone names on calls without details. Arg 1: an older build's add-on folder.
local H=dofile('tests/harness/wow.lua')
local OLDER=arg and arg[1]
local errors={}
local function guild()
 local w=H.World()
 w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})
 w:AddMember({name='Vol Jin',rank=1,guid='Player-1-0000000E'})
 w:AddMember({name='Ash Ember',rank=3,guid='Player-1-0000000A'})
 w:AddMember({name='Lok Tar',rank=3,guid='Player-1-0000000D'})
 local function boot(n,dir,skew)
  local c=w:Client(n);local clock=c.env.time
  c.skew=skew or 0
  c.env.time=function(t) if t then return clock(t) end;return math.floor(clock())+c.skew end
  w:LoadAddon(c,dir or 'KeepersWarCommand');c.env.GetRealZoneText=function() return 'Ashenvale' end
  w:Login(c);w:Advance(6);return c
 end
 local function leave(c) w:Drop(c);w:Member(c.name).online=false;w:FireAll('GUILD_ROSTER_UPDATE') end
 return w,boot,leave
end
local function row(c,id) for _,e in ipairs(c.env.KWCDB.ops) do if e.id==id then return e end end end
local function collect(w) for _,c in ipairs(w.clients) do for _,e in ipairs(c.errors) do errors[#errors+1]=c.name..': '..e end end end

-- Requester gone; an older member is connected; two officers on the new build.
local w,boot,leave=guild()
local ash=boot('Ash Ember');local old=boot('Lok Tar',OLDER);local grom,vol=boot('Grom Warcry'),boot('Vol Jin');w:Advance(40)
local sent={}
for _,c in ipairs({grom,vol,old}) do
 local send=c.env.C_ChatInfo.SendAddonMessage
 c.env.C_ChatInfo.SendAddonMessage=function(p,m,...) if p=='KWC4' and m:match('^S|C|') and m:find('|RESOLVED|',1,true) then sent[#sent+1]=c.name end;return send(p,m,...) end
end
local _,e=ash.env.KWC.Operations.RequestBackup();w:Advance(10);leave(ash)
w:Advance(630)
H.Check('officers close it locally at expiry',row(grom,e.id).status=='RESOLVED')
H.Check('nothing is published inside the grace period',#sent==0,#sent)
w:Advance(260)
H.Check('an officer publishes the expiry after the grace period',#sent>=1,#sent)
local function others() for _,who in ipairs(sent) do if who~=sent[1] then return who end end end
-- Later copies from the same officer are ordinary sync replies.
H.Check('only one officer needed to publish it',#sent>=1 and not others(),table.concat(sent,','))
H.Check('the older client now shows it resolved',row(old,e.id).status=='RESOLVED',row(old,e.id).status)
H.Check('revision and expiry time are consistent',row(old,e.id).revision==1 and row(grom,e.id).revision==1 and row(vol,e.id).revision==1)
w:Advance(300)
H.Check('no second officer publishes and the revision never climbs',not others() and row(old,e.id).revision==1 and row(grom,e.id).revision==1,table.concat(sent,','))
w:Member('Ash Ember').online=true;ash=boot('Ash Ember');w:Advance(120)
H.Check('returning requester agrees without a conflicting revision',(not row(ash,e.id) or row(ash,e.id).status=='RESOLVED') and row(old,e.id).revision==1)
collect(w)

-- An online requester is left to publish; members never publish for others.
w,boot,leave=guild()
ash=boot('Ash Ember');local lok=boot('Lok Tar');grom=boot('Grom Warcry');w:Advance(40)
local count=0
for _,c in ipairs({grom,lok}) do local send=c.env.C_ChatInfo.SendAddonMessage
 c.env.C_ChatInfo.SendAddonMessage=function(p,m,...) if p=='KWC4' and m:match('^S|C|') and m:find('|RESOLVED|',1,true) then count=count+1 end;return send(p,m,...) end end
_,e=ash.env.KWC.Operations.RequestBackup();w:Advance(10)
w:Advance(900)
H.Check('with the requester online, others stay silent',count==0 and row(grom,e.id).status=='RESOLVED',count)
collect(w)
w,boot,leave=guild()
ash=boot('Ash Ember');lok=boot('Lok Tar');if OLDER then boot('Vol Jin',OLDER) end;w:Advance(40)
_,e=ash.env.KWC.Operations.RequestBackup();w:Advance(10);leave(ash);w:Advance(900)
H.Check('a member never publishes for an absent requester',row(lok,e.id).status=='RESOLVED' and row(lok,e.id).revision==0)
collect(w)

-- Clock differences, learned from the requester's own sync requests.
for _,case in ipairs({{'requester 15 minutes behind',-900,0},{'requester 15 minutes ahead',240,-660},{'receiver 15 minutes ahead',0,900}}) do
 local label,theirs,mine=case[1],case[2],case[3]
 w,boot=guild()
 grom=boot('Grom Warcry',nil,mine);ash=boot('Ash Ember',nil,theirs);w:Advance(5)
 ash.env.KWC.Sync.Request(true);w:Advance(40);ash.env.KWC.Sync.Request(true);w:Advance(10)
 grom.env.KWC.Toast.channels.ctaNotice.frame:Hide()
 local shown=false
 local frame=grom.env.KWC.Toast.channels.ctaNotice.frame
 _,e=ash.env.KWC.Operations.RequestBackup()
 for i=1,40 do w:Advance(0.25);shown=shown or frame:IsShown() end
 local copy=row(grom,e.id)
 local left=copy and grom.env.KWC.Operations.SOSRemaining(copy)
 if mine-theirs>0 then
  H.Check(label..': arrives active with the true time left',copy and copy.status=='ACTIVE' and left>560 and left<=600,tostring(copy and copy.status)..' '..tostring(left))
  H.Check(label..': popup shown',shown)
  w:Advance(620)
  H.Check(label..': expires on time',row(grom,e.id).status=='RESOLVED')
 else
  H.Check(label..': records stamped too far ahead are refused by existing sync (known limit)',copy==nil or copy.status=='ACTIVE')
 end
 collect(w)
end
-- Without any observed clock, the earlier behaviour is unchanged.
w,boot=guild();grom=boot('Grom Warcry');w:Advance(40)
local K=grom.env.KWC
H.Check('unknown clocks apply no correction',K.Sync.ClockOffset('Ash Ember')==0)
w:Fire(grom,'CHAT_MSG_ADDON','KWC4','Q|'..(grom.env.time()-30),'GUILD','Ash Ember')
H.Check('ordinary delay applies no correction',K.Sync.ClockOffset('Ash Ember')==0)
w:Fire(grom,'CHAT_MSG_ADDON','KWC4','Q|'..(grom.env.time()-90000),'GUILD','Vol Jin')
H.Check('absurd timestamps are ignored',K.Sync.ClockOffset('Vol Jin')==0)

-- Zone names for calls without details.
local W=K.WarRoom2;W.Show('dashboard');local page=W.pages.dashboard
local now=grom.env.time()
grom.env.KWCDB.worldPvPKills,grom.env.KWCDB.worldPvPDeaths,grom.env.KWCDB.bounties={},{},{}
grom.env.KWC.Operations.DetailedCTA('Hillsbrad Foothills','Hold',2,3,'HIGH','','')
local posted=grom.env.KWCDB.ops[1].text
grom.env.KWCDB.ops={{id=(now-60)..'-1111',author='Grom Warcry',status='ACTIVE',text=posted},
 {id=(now-50)..'-2222',author='Grom Warcry',status='ACTIVE',text='[URGENT] Tarren Mill | H:A 4:5 | x'},
 {id=(now-40)..'-3333',author='Grom Warcry',status='ACTIVE',text='[URGENT] Stonetalon - SOS: backup needed'},
 {id=(now-30)..'-4444',author='Grom Warcry',status='ACTIVE',text='come help me please'}}
local zones={};for _,z in ipairs(page.HotZones()) do zones[z.zone]=true end
H.Check('posted call without details keeps its zone',zones['Hillsbrad Foothills'],posted)
H.Check('other text forms keep theirs',zones['Tarren Mill'] and zones['Stonetalon'])
local n=0;for _ in pairs(zones) do n=n+1 end
H.Check('free text invents no zone',n==3,n)
collect(w)
H.Check('no Lua errors',#errors==0,table.concat(errors,' | '):sub(1,400))
os.exit(H.Summary('sos_absent') and 0 or 1)
