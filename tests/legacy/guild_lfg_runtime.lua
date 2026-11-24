local network,packet=assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
local function fields()
 return {activity="Dungeon",name="Library",minLevel=30,maxLevel=45,roles={Tank=true},needed=2,
  description="Bring a key",lifetimeMinutes=15}
end
for _,size in ipairs({2,5,10,25,50}) do
 local n=network(math.max(3,size),true)
 local a,b,c
 for i=1,math.max(3,size) do
  local client=n.client(i,nil,{scoped=true,legacy=i>2 and i%5==0,noLFG=i>2 and i<math.max(3,size) and i%5==0})
  if i==1 then a=client elseif i==2 then b=client else c=client end
 end
 local A,B,C=a.e.KWC.GuildLFG,b.e.KWC.GuildLFG,c.e.KWC.GuildLFG
 c.online=false
 local id=assert(A.Create(fields()))
 n.run(12)
 if #B.Browse()==0 then
  for _,p in ipairs(n.packets) do if p.prefix=="KWL1" then packet(b,p.prefix,p.message,a) end end
 end
 assert(#B.Browse({level=40,role="Tank",activity="Dungeon"})==1)
 assert(not B.Update(id,1,"delete"))
 assert(B.Interest(id,true))
 n.run(12)
 local r=A.Browse({mine=true})[1]
 assert(#r.interestedMembers==1)
 local count,seekers=A.Summary()
 assert(count==1 and seekers==2)
 local edited=fields();edited.name="Armory"
 assert(A.Update(id,1,"edit",edited))
 n.run(12)
 assert(B.Browse()[1].name=="Armory")
 a.online=false;c.online=true
 local first,bytes=#n.packets,n.bytes
 assert(c.e.KWC.Sync.Request(true))
 n.run(20)
 assert(C.Browse()[1].name=="Armory")
 assert(not C.Browse()[1].interested)
 local packets,amount=#n.packets-first,n.bytes-bytes
 assert(packets<=20 and amount<4000)
 local drops=0
 for _,peer in ipairs(n.clients) do
  local _,_,_,d=peer.e.KWC.Net.Status();drops=drops+d
  for _,log in ipairs(peer.logs) do assert(not log:find("CHAT_MSG_ADDON error",1,true),log) end
 end
 assert(drops==0)
 print(("%d clients | offline recovery by 20s | %d packets | %d bytes | %d drops"):format(size,packets,amount,drops))
end

local n=network(4,false)
local scoped={scoped=true}
local a,b,c,d=n.client(1,nil,scoped),n.client(2,nil,scoped),n.client(3,nil,scoped),n.client(4,nil,scoped)
local A,B,C=a.e.KWC.GuildLFG,b.e.KWC.GuildLFG,c.e.KWC.GuildLFG
c.online=false
local id=assert(A.Create(fields()))
n.run(8)
assert(B.Interest(id,true))
n.run(8)
assert(B.Interest(id,false))
n.run(8)
local first,joined,withdrawn
for _,p in ipairs(n.packets) do
 if p.prefix=="KWL1" and p.message:match("^1|L|") then first=p.message end
 if p.prefix=="KWL1" and p.message:match("^1|I|") then
  if p.message:match("|1$") then joined=p.message else withdrawn=p.message end
 end
end
assert(first and joined and withdrawn)
-- Opt-in notices are local and repeat delivery does not repeat them.
local notices=0
c.e.UnitLevel=function() return 40 end
c.e.UIErrorsFrame={AddMessage=function() notices=notices+1 end}
c.e.KWCDB.settings.guildLFG={matching=true}
packet(c,"KWL1",withdrawn,b);packet(c,"KWL1",joined,b)
packet(c,"KWL1",first,a);packet(c,"KWL1",first,a);packet(c,"KWL1",joined,b)
assert(notices==1)
local count,seekers=C.Summary()
assert(count==1 and seekers==1)
packet(c,"KWL1",joined,d)
packet(c,"KWL1",first,d)
assert(not C.Browse()[1].interested)
assert(A.Update(id,1,"close"))
assert(A.Update(id,2,"delete"))
n.run(10)
local deleted
for _,p in ipairs(n.packets) do if p.prefix=="KWL1" and p.message:find("|deleted|",1,true) then deleted=p.message end end
assert(deleted)
-- Recover the terminal record from the officer, with the creator offline.
a.online=false;c.online=true
assert(c.e.KWC.Sync.Request(true))
n.run(10)
local relayDelete
for _,p in ipairs(n.packets) do
 if p.from==b.name and p.prefix=="KWC4" and p.message:find("|LFG|",1,true)
  and p.message:find("|deleted|",1,true) then relayDelete=true end
end
assert(relayDelete,"officer did not send the deletion marker")
packet(c,"KWL1",first,a)
assert(#C.Browse()==0)
c.online=false
c=n.client(3,c.e.KWCDB,scoped)
C=c.e.KWC.GuildLFG
packet(c,"KWL1",first,a);assert(#C.Browse()==0)
c.guildID=2;c.event("PLAYER_GUILD_UPDATE")
packet(c,"KWL1",first,a);assert(#C.Browse()==0)
c.guildID=1;c.event("PLAYER_GUILD_UPDATE")
packet(c,"KWL1",first,a);assert(#C.Browse()==0)
a.online=true
local other=assert(A.Create(fields()))
n.run(901)
assert(A.Summary()==0)
assert(A.Update(other,1,"renew"))
assert(A.Summary()==1)
print("PASS: live lifecycle, sender checks, reordered withdrawal, replay, expiry, reload and guild isolation")
