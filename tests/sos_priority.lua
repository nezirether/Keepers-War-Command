-- SOS request, responses and resolution jump the send backlog without losing
-- order, extra messages or ordinary traffic.
local H=dofile('tests/harness/wow.lua')
local function scene()
 local w=H.World()
 w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})
 w:AddMember({name='Ash Ember',rank=3,guid='Player-1-0000000A'})
 -- The game clock is whole seconds; the harness clock steps in quarters.
 local function boot(n) local c=w:Client(n);local clock=c.env.time;c.env.time=function(...) return math.floor(clock(...)) end;w:LoadAddon(c,'KeepersWarCommand');w:Login(c);w:Advance(6);return c end
 local ash,grom=boot('Ash Ember'),boot('Grom Warcry');w:Advance(60)
 local sent={}
 for _,c in ipairs({ash,grom}) do
  local send=c.env.C_ChatInfo.SendAddonMessage
  c.env.C_ChatInfo.SendAddonMessage=function(prefix,msg,...)
   if c.throttle and c.throttle>0 and msg:find('SOS',1,true) then c.throttle=c.throttle-1;return 3 end
   sent[#sent+1]={from=c.name,msg=msg};return send(prefix,msg,...)
  end
 end
 return w,ash,grom,sent
end
local function backlog(c,tag,n) for i=1,n do c.env.KWC.Net.Send('KWC3','2;NOISE;'..tag..i,'GUILD') end end
local function waitFor(w,limit,done) local start=w.now;while not done() and w.now-start<limit do w:Advance(0.25) end;return w.now-start,done() end
local function count(sent,from,pattern) local n=0;for _,m in ipairs(sent) do if m.from==from and m.msg:find(pattern) then n=n+1 end end;return n end

local w,ash,grom,sent=scene()
backlog(ash,'a',60)
local ok=ash.env.KWC.Operations.RequestBackup()
local function got() return grom.env.KWCDB.ops[1] end
local seconds,arrived=waitFor(w,120,function() local e=got();return e and e.details end)
H.Check('SOS with full details arrives within 6 seconds despite 60 queued messages',ok and arrived and seconds<=6,seconds)
H.Check('details and popup intact',got().details.priority=='URGENT' and got().boardVersioned and grom.env.KWC.Toast.channels.ctaNotice.frame:IsShown())
w:Advance(4)
local order={};for _,m in ipairs(sent) do if m.from=='Ash Ember' and m.msg:find('SOS',1,true) then order[#order+1]=m.msg:sub(1,2) end end
H.Check('messages keep their original order, each sent once',table.concat(order,' ')=='S| F| 2;',table.concat(order,' '))
local id=got().id
backlog(grom,'g',60)
grom.env.KWC.Operations.Respond(id,'Coming')
seconds,arrived=waitFor(w,120,function() for _,v in pairs(ash.env.KWCDB.responses[id] or {}) do if v=='Coming' then return true end end return false end)
H.Check('Coming reaches the requester within 6 seconds',arrived and seconds<=6,seconds)
backlog(ash,'b',40)
ash.env.KWC.Operations.ChangeStatus('CTA',id,'RESOLVED')
seconds,arrived=waitFor(w,120,function() return got().status=='RESOLVED' end)
H.Check('resolution arrives within 6 seconds',arrived and seconds<=6,seconds)
w:Advance(200)
H.Check('every backlog message is still delivered once',count(sent,'Ash Ember','NOISE')==100 and count(sent,'Grom Warcry','NOISE')==60,count(sent,'Ash Ember','NOISE'))
H.Check('one record on each board',#ash.env.KWCDB.ops==1 and #grom.env.KWCDB.ops==1)

-- Throttled sends keep their place and still arrive.
w,ash,grom,sent=scene();backlog(ash,'t',60);ash.throttle=4
ash.env.KWC.Operations.RequestBackup()
seconds,arrived=waitFor(w,120,function() local e=grom.env.KWCDB.ops[1];return e and e.details end)
H.Check('four throttled attempts do not drop or bury the SOS',arrived and seconds<=20,seconds)
-- Request then immediate resolve: order holds, the receiver ends resolved.
w,ash,grom,sent=scene();backlog(ash,'r',60)
ash.env.KWC.Operations.RequestBackup();local e=ash.env.KWCDB.ops[1]
ash.env.KWC.Operations.ChangeStatus('CTA',e.id,'RESOLVED')
w:Advance(30)
H.Check('quick resolve cannot overtake the request',grom.env.KWCDB.ops[1] and grom.env.KWCDB.ops[1].status=='RESOLVED' and #grom.env.KWCDB.ops==1)
-- Ordinary calls keep normal queue order.
w,ash,grom,sent=scene();backlog(ash,'o',20)
ash.env.KWC.Operations.DetailedCTA('Durotar','Hold the road',1,1,'URGENT','','')
w:Advance(8)
H.Check('an ordinary call still waits its turn',#grom.env.KWCDB.ops==0)
w:Advance(40)
H.Check('and still arrives',#grom.env.KWCDB.ops==1)
local errors=0;for _,c in ipairs(w.clients) do errors=errors+#c.errors end
H.Check('no Lua errors',errors==0)
os.exit(H.Summary('sos_priority') and 0 or 1)
