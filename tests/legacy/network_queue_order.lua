-- Network.lua queue order (recovery, normal, alert) while send result 11 holds an item.
local network=assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
local n=network(3,false)
local sender=n.client(1,nil,{scoped=true})
n.client(2,nil,{scoped=true})
n.client(3,nil,{scoped=true})
local net=sender.e.KWC.Net
local chat=sender.e.C_ChatInfo

local locked=false
local attempts,delivered,order={},{},{}
local attemptLog={}
chat.SendAddonMessage=function(prefix,message)
    if prefix~="KWCT" then return locked and 11 or 0 end
    attempts[message]=(attempts[message] or 0)+1
    attemptLog[#attemptLog+1]=message
    if locked then return 11 end
    delivered[message]=(delivered[message] or 0)+1
    order[#order+1]=message
    return 0
end
local function drain()
    for _=1,40 do
        if net.Status()==0 then return end
        n.run(10)
    end
    error("queue did not drain")
end
local function position(message)
    for i,m in ipairs(order) do if m==message then return i end end
    error("not delivered: "..message)
end
local function distinctSince(start)
    local seen,count={},0
    for i=start,#attemptLog do
        if not seen[attemptLog[i]] then seen[attemptLog[i]]=true;count=count+1 end
    end
    return count
end
drain()
local _,_,failed0,dropped0=net.Status()

-- 1. Recovery and normal items: result 11 keeps the same item selected (no recovery/normal
--    flip-flop), and order within each class survives the lockdown.
locked=true
assert(net.Send("KWCT","R1","GUILD",nil,"RECOVERY"))
assert(net.Send("KWCT","N1","GUILD"))
assert(net.Send("KWCT","R2","GUILD",nil,"RECOVERY"))
assert(net.Send("KWCT","N2","GUILD"))
n.run(30)
assert(#order==0,"nothing is delivered during lockdown")
assert(distinctSince(1)<=1,"result 11 must not alternate between recovery and normal items")
local held=attemptLog[1]
local queued,_,failed,dropped=net.Status()
assert(queued>=4 and failed==failed0 and dropped==dropped0)
locked=false
drain()
for _,m in ipairs({"R1","N1","R2","N2"}) do assert(delivered[m]==1,m.." delivered once") end
assert(position("R1")<position("R2"),"recovery order preserved")
assert(position("N1")<position("N2"),"normal order preserved")
if held then assert(order[1]==held,"the held item is sent first after lockdown") end

-- 2. An alert queued during lockdown goes to the front and is the only item retried.
order={}
locked=true
assert(net.Send("KWCT","R3","GUILD",nil,"RECOVERY"))
assert(net.Send("KWCT","N3","GUILD"))
n.run(10)
assert(net.Send("KWCT","A1","GUILD",nil,"ALERT"))
local mark=#attemptLog+1
n.run(20)
assert(attempts["A1"] and attempts["A1"]>=2,"alert is retried while locked")
assert(distinctSince(mark)==1 and attemptLog[mark]=="A1","only the front alert is retried")
locked=false
drain()
assert(order[1]=="A1","alert is delivered first after lockdown")
assert(delivered["A1"]==1 and delivered["R3"]==1 and delivered["N3"]==1)
local _,_,failed1,dropped1=net.Status()
assert(failed1==failed0 and dropped1==dropped0,"lockdown spends no attempts and drops nothing")

print("PASS: result 11 preserves recovery, normal and alert queue order without spending attempts")
