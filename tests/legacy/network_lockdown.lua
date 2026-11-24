-- Network.lua send results 11 (messaging lockdown) and 12 (whisper target offline).
-- Fallback literals are used because the headless environment has no Enum table.
local network=assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
local n=network(3,false)
local sender=n.client(1,nil,{scoped=true})
local peer=n.client(2,nil,{scoped=true})
local other=n.client(3,nil,{scoped=true})
local net=sender.e.KWC.Net
local chat=sender.e.C_ChatInfo

local locked=false
local failWith={}
local attempts,delivered={},{}
chat.SendAddonMessage=function(prefix,message)
    if prefix~="KWCT" then return locked and 11 or 0 end
    attempts[message]=(attempts[message] or 0)+1
    if locked then return 11 end
    if failWith[message] then return failWith[message] end
    delivered[message]=(delivered[message] or 0)+1
    return 0
end
local function drain()
    for _=1,30 do
        if net.Status()==0 then return end
        n.run(10)
    end
    error("queue did not drain")
end
drain()
local _,_,failed0,dropped0=net.Status()

-- 1. GUILD under result 11: the item stays queued far past the three-attempt budget.
locked=true
assert(net.Send("KWCT","guild during lockdown","GUILD"))
n.run(40)
assert(attempts["guild during lockdown"]>=4,"lockdown attempts should exceed the old three-attempt budget")
local queued,_,failed,dropped,lockdowns=net.Status()
assert(queued>=1 and failed==failed0 and dropped==dropped0 and lockdowns>=4)
assert(net.Send("KWCT","guild during lockdown","GUILD"),"pending item still dedupes")
locked=false
drain()
assert(delivered["guild during lockdown"]==1)
local _,_,failed1,dropped1=net.Status()
assert(failed1==failed0 and dropped1==dropped0)

-- 2. Lockdown pauses keep a backoff instead of retrying every 0.85 s.
locked=true
assert(net.Send("KWCT","paced","GUILD"))
n.run(1)
local first=attempts["paced"] or 0
n.run(3)
assert((attempts["paced"] or 0)-first<=1,"lockdown retries must back off")
locked=false
drain()
assert(delivered["paced"]==1)

-- 3. WHISPER under result 11: not dropped, peer not marked unavailable.
locked=true
assert(net.Send("KWCT","whisper during lockdown","WHISPER",peer.name))
n.run(20)
assert(attempts["whisper during lockdown"]>=2 and not delivered["whisper during lockdown"])
locked=false
drain()
assert(delivered["whisper during lockdown"]==1)
assert(net.Send("KWCT","whisper after lockdown","WHISPER",peer.name))
drain()
assert(delivered["whisper after lockdown"]==1,"lockdown must not mark the peer unavailable")
local _,_,failed2,dropped2=net.Status()
assert(failed2==failed0 and dropped2==dropped0)

-- 4. C_ChatInfo.InChatMessagingLockdown pauses before the send is attempted.
local query=true
chat.InChatMessagingLockdown=function() return query end
assert(net.Send("KWCT","queried lockdown","GUILD"))
n.run(20)
assert(not attempts["queried lockdown"] and net.Status()>=1)
chat.InChatMessagingLockdown=function() error("broken API") end
drain()
assert(delivered["queried lockdown"]==1,"a failing lockdown query must not block the queue")
chat.InChatMessagingLockdown=nil

-- 5. WHISPER result 12 (target offline) is terminal and never pauses the queue.
failWith["offline target"]=12
assert(net.Send("KWCT","offline target","WHISPER",peer.name))
assert(net.Send("KWCT","guild after offline","GUILD"))
assert(net.Send("KWCT","same peer within 30 s","WHISPER",peer.name))
assert(net.Send("KWCT","whisper other peer","WHISPER",other.name))
drain()
assert(attempts["offline target"]==1 and not delivered["offline target"])
assert(delivered["guild after offline"]==1)
assert(not attempts["same peer within 30 s"],"offline peer stays unavailable for 30 s")
assert(delivered["whisper other peer"]==1)
local _,_,failed3,dropped3=net.Status()
assert(failed3==failed0+1 and dropped3==dropped0+1)

-- 6. Only literal 11 is lockdown, even when the client Enum maps the lockdown name to 12.
sender.e.Enum={SendAddonMessageResult={AddOnMessageLockdown=12,AddonMessageLockdown=12}}
n.run(31)
local _,_,failed4,dropped4=net.Status()
locked=true
assert(net.Send("KWCT","guild lockdown with enum","GUILD"))
n.run(40)
assert(attempts["guild lockdown with enum"]>=4 and not delivered["guild lockdown with enum"],
    "result 11 must hold the item regardless of the Enum mapping")
local queued4,_,failed5,dropped5=net.Status()
assert(queued4>=1 and failed5==failed4 and dropped5==dropped4)
locked=false
drain()
assert(delivered["guild lockdown with enum"]==1)
failWith["offline with enum"]=12
assert(net.Send("KWCT","offline with enum","WHISPER",other.name))
assert(net.Send("KWCT","guild after enum offline","GUILD"))
drain()
assert(attempts["offline with enum"]==1 and not delivered["offline with enum"],
    "result 12 must stay terminal even if the Enum names it lockdown")
assert(delivered["guild after enum offline"]==1)
local _,_,failed6,dropped6=net.Status()
assert(failed6==failed4+1 and dropped6==dropped4+1)
sender.e.Enum=nil

print("PASS: result 11 pauses without spending attempts or marking peers unavailable; result 12 whispers stay terminal")
