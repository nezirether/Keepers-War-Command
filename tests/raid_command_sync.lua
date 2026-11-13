-- Production receiver tests. Packet injection controls order independently of WoW.
local network,packet=assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
local n=network(3,false)
local lead,peer,member=n.client(1),n.client(2),n.client(3)
local function group(c)
 local e=c.e
 e.GetNumGroupMembers=function() return 3 end
 e.IsInRaid=function() return false end
 e.UnitExists=function() return true end
 e.UnitIsPlayer=function() return true end
 e.UnitClass=function() return "Warrior","WARRIOR" end
 e.UnitIsConnected=function() return true end
 e.UnitIsGroupLeader=function(unit) return unit=="party1" end
 e.UnitName=function(unit) return unit=="player" and c.name or unit=="party1" and lead.name or member.name end
end
group(peer)
local R=peer.e.KWC.RaidCommand
local t=peer.e.time()
local function send(kind,rev,name,value,sender,session,prefix)
 packet(peer,prefix or "KWCR3",table.concat({kind,session or t,rev,name,value},"|"),sender or lead,"PARTY")
end
send("END",1,lead.name,1)
send("TASK",1,peer.name,"Interrupt")
send("TASK",1,peer.name,"Interrupt")
assert(R.CountAssignments()==0)
send("BEGIN",1,lead.name,1)
local d=peer.e.KWCDB.raidCommand
assert(R.CountAssignments()==1 and d.assignments[peer.name]=="Interrupt")
send("BEGIN",2,lead.name,2)
send("TASK",2,peer.name,"New")
send("END",2,lead.name,2)
assert(d.revision==1 and d.assignments[peer.name]=="Interrupt")
send("TASK",2,member.name,"Taunt",member)
assert(d.revision==1)
send("TASK",2,member.name,"Taunt")
assert(d.revision==2 and R.CountAssignments()==2)
send("TASK",1,peer.name,"Stale")
send("BEGIN",9,lead.name,"",nil,nil,"KWCR2")
assert(d.revision==2 and d.assignments[peer.name]=="New")
send("READY",2,member.name,t..":1",member)
send("READY",2,member.name,(t+1)..":0",member)
send("READY",2,member.name,t..":1",member)
send("READY",2,member.name,(t+1)..":1",member)
send("READY",2,member.name,(t+2)..":1",peer)
assert(d.ready[member.name]==false)
peer.online=false
peer=n.client(2,peer.e.KWCDB)
group(peer)
d=peer.e.KWCDB.raidCommand
send("READY",2,member.name,t..":1",member)
assert(d.ready[member.name]==false)
send("BEGIN",1,lead.name,0,nil,t+2)
send("END",1,lead.name,0,nil,t+2)
assert(d.session==tostring(t+2) and peer.e.KWC.RaidCommand.CountAssignments()==0)
send("READY",2,member.name,(t+3)..":1",member)
assert(d.ready[member.name]==nil)
print("PASS: atomic reorder, duplicates, loss, sender checks, legacy isolation, and persisted readiness ordering")
