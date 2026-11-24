local network=assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
local n=network(3,false)
local sender=n.client(1,nil,{scoped=true})
local peer=n.client(2,nil,{scoped=true})
local net=sender.e.KWC.Net
local calls=0
local result=9
sender.e.C_ChatInfo.SendAddonMessage=function(_,_,channel)
    if channel~="WHISPER" then return 0 end
    calls=calls+1
    return result
end
assert(net.Send("KWC4","queued while online","WHISPER",peer.name))
peer.online=false
n.run(12)
assert(calls==0)
peer.online=true
assert(net.Send("KWC4","unavailable outside the roster update","WHISPER",peer.name))
assert(net.Send("KWC4","second queued reply","WHISPER",peer.name.."-Realm"))
n.run(12)
assert(calls==1 and net.Status()==0)
n.run(30)
result=3
assert(net.Send("KWC4","server throttle","WHISPER",peer.name))
n.run(2)
assert(calls==2)
result=0
n.run(10)
assert(calls==3 and net.Status()==0)
print("PASS: queued whispers skip offline members, terminal failures do not retry, and throttled whispers recover")
