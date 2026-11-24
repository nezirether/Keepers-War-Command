-- Keepers Raid Tools traffic through the shared KWC queue (Network.lua): message routing,
-- AceComm-compatible framing, lockdown recovery, offline whispers, bounded group traffic,
-- and two-client simulations through the real LibSerialize/LibDeflate codec.
-- Run from the repository root with Lua 5.1 or LuaJIT.
local network=assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
local n=network(3,false)
local A=n.client(1,nil,{scoped=true})
local B=n.client(2,nil,{scoped=true})
local C=n.client(3,nil,{scoped=true}) -- guild member who is not in the raid
local folder="KeepersWarCommand/Modules/RaidTools/"
local PREFIX="KRTools"

-- Raid roster shared by both simulated clients. Pugger is in the raid but not the guild.
local raid={{A.name,"Realm"},{B.name,"Realm"},{"Pugger","Elsewhere"}}
local PUG="Pugger-Elsewhere"
local grouped=true
local offline={}
local attached={}
local attempts={} -- every KRTools send attempt: {from,msg,channel,target}
local log={}      -- every accepted send from an attached client, any prefix

local seed=4242
local function noise(len)
    local out={}
    for i=1,len do
        seed=(seed*16807)%2147483647
        out[i]=string.char(97+math.floor(seed/65536)%26)
    end
    return table.concat(out)
end

local function raidIndex(unit) return tonumber(tostring(unit):match("^raid(%d+)$")) end

-- Test-only copy of AceComm-3.0's receive logic (OnEvent and OnReceiveMultipart*):
-- a stream is prefix + channel + sender; \001 starts (and overwrites), \002 appends,
-- \003 completes, \004 escapes a single message, and unmarked text is a single message.
-- The optional note function stands in for the raw CHAT_MSG_ADDON listener in Comms.lua,
-- which sees every piece (Comms:NotePiece).
local function receiver(dispatch,note)
    local spool={}
    return function(prefix,message,channel,sender)
        if note then note(prefix,message,channel,sender) end
        local key=prefix.."\t"..channel.."\t"..sender
        local control,rest=message:match("^([\001-\009])(.*)$")
        if not control then
            dispatch(message,sender,channel)
        elseif control=="\001" then
            spool[key]={rest}
        elseif control=="\002" then
            if spool[key] then table.insert(spool[key],rest) end
        elseif control=="\003" then
            local parts=spool[key]
            if parts then
                spool[key]=nil
                parts[#parts+1]=rest
                dispatch(table.concat(parts),sender,channel)
            end
        elseif control=="\004" then
            dispatch(rest,sender,channel)
        end
    end
end

local function attach(c)
    local e=c.e
    local state={locked=false,ace=0,received={}}
    c.krt=state
    e.strmatch=string.match
    e.wipe=function(t) for k in pairs(t) do t[k]=nil end return t end
    e.Ambiguate=function(name,mode)
        if mode=="short" then return (name:match("^[^-]+")) end
        return name
    end
    e.KeepersRaidTools={RosterValidation={}}
    e.KeepersRaidToolsAttendanceDB={}
    e.IsInRaid=function() return grouped end
    e.IsInGroup=function() return grouped end
    e.GetNumGroupMembers=function() return grouped and #raid or 0 end
    e.UnitFullName=function(unit)
        if unit=="player" then return c.name end
        local i=raidIndex(unit)
        local member=grouped and i and raid[i]
        if member then return member[1],member[2] end
    end
    e.UnitExists=function(unit) return unit=="player" or e.UnitFullName(unit)~=nil end
    e.UnitIsConnected=function(unit) return not offline[unit] end
    e.UnitIsGroupLeader=function(unit)
        if unit=="player" then return c==B end
        local i=raidIndex(unit)
        return i~=nil and raid[i]~=nil and raid[i][1]==B.name
    end
    e.UnitIsGroupAssistant=function() return false end
    for _,file in ipairs({"Libs/LibStub/LibStub.lua","Libs/LibSerialize/LibSerialize.lua",
        "Libs/LibDeflate/LibDeflate.lua","Comms.lua","Modules/Attendance/AttendanceSync.lua"}) do
        setfenv(assert(loadfile(folder..file)),e)()
    end
    local comms=e.KeepersRaidTools.Comms
    assert(comms.sendFunc,"Comms must default to a sender without AceComm")
    -- AceComm is absent headless; this stub counts any fallback use.
    comms.SendCommMessage=function() state.ace=state.ace+1 end
    comms:RegisterHandler("kwcTest",function(data,sender,channel)
        state.received[#state.received+1]={note=data.note,sender=sender,channel=channel}
    end)
    state.comms=comms
    state.sync=e.KeepersRaidTools.AttendanceSync
    state.sync:RegisterHandlers()
    state.receive=receiver(function(message,sender,channel) comms:Dispatch(message,sender,channel) end,
        function(prefix,message,channel,sender) comms:NotePiece(prefix,message,channel,sender) end)
    local harness=e.C_ChatInfo.SendAddonMessage
    e.C_ChatInfo.SendAddonMessage=function(prefix,message,channel,target)
        if prefix==PREFIX then attempts[#attempts+1]={from=c,msg=message,channel=channel,target=target} end
        if state.locked then return 11 end
        if prefix==PREFIX and state.hook then
            local result=state.hook(message,channel,target)
            if result then return result end
        end
        log[#log+1]={from=c,prefix=prefix,msg=message,channel=channel,target=target}
        if prefix=="KWCT" then return 0 end
        if prefix~=PREFIX then return harness(prefix,message,channel,target) end
        for _,peer in ipairs(attached) do
            local hit
            if channel=="WHISPER" then hit=peer.name==target or peer.name.."-Realm"==target
            else hit=peer~=c and grouped end
            if hit then
                n.schedule(0.1,function() peer.krt.receive(prefix,message,channel,c.name.."-Realm") end)
            end
        end
        return 0
    end
    attached[#attached+1]=c
end
attach(A)
attach(B)
local net=A.e.KWC.Net

local function status(c) return c.e.KWC.Net.Status() end
-- Deliveries land a tick after the send and may queue replies, so both queues must stay
-- empty across a short delivery window.
local function drain(limit)
    for _=1,limit or 120 do
        if (status(A))==0 and (status(B))==0 then
            n.run(2)
            if (status(A))==0 and (status(B))==0 then return end
        else
            n.run(5)
        end
    end
    error("queues did not drain")
end
local function krtFrom(c,since)
    local out={}
    for i=since or 1,#log do
        local p=log[i]
        if p.from==c and p.prefix==PREFIX then p.index=i;out[#out+1]=p end
    end
    return out
end
local function logIndex(prefix,msg)
    for i,p in ipairs(log) do if p.prefix==prefix and p.msg==msg then return i end end
end
local function count(list,note)
    local total=0
    for _,r in ipairs(list) do if r.note==note then total=total+1 end end
    return total
end
local function attemptsTo(target,since)
    local total=0
    for i=since,#attempts do if attempts[i].target==target then total=total+1 end end
    return total
end

-- Let login-time guild sync settle so later counters only see this test's traffic.
n.run(120)
drain()

-- 1. Framing matches AceComm's SendCommMessage at a 250-byte piece limit.
local Split=A.krt.comms.Split
local function rebuild(parts)
    local got
    local r=receiver(function(message) got=message end)
    for _,p in ipairs(parts) do
        assert(#p<=250,"piece over 250 bytes")
        r(PREFIX,p,"RAID","X")
    end
    return got
end
for _,len in ipairs({1,200,249,250,251,498,499,500,747,748,1000,2600}) do
    local text=noise(len)
    local parts=Split(text)
    assert(rebuild(parts)==text,"round trip "..len)
    if len<=250 then
        assert(#parts==1 and parts[1]==text,"single piece "..len)
    else
        assert(#parts==math.ceil(len/249),"piece count "..len)
        assert(parts[1]:sub(1,1)=="\001" and parts[#parts]:sub(1,1)=="\003")
        for i=2,#parts-1 do assert(parts[i]:sub(1,1)=="\002") end
    end
end
local escaped=Split("\005short")
assert(#escaped==1 and escaped[1]=="\004\005short" and rebuild(escaped)=="\005short")
local forced="\001"..noise(249)
local forcedParts=Split(forced)
assert(#forcedParts==2 and rebuild(forcedParts)==forced,"a control-led 250-byte message is forced multipart")
print("PASS: Raid Tools framing is AceComm-compatible with pieces of at most 250 bytes")

-- 2. Routing: single-piece messages go through K.Net, duplicates are suppressed, never AceComm.
local mark=#log+1
local q0,_,_,_,_,g0=status(A)
assert(A.krt.comms:Send("kwcTest",{note="hello raid"},"RAID"))
local q1,_,_,_,_,g1=status(A)
assert(q1==q0+1 and g1==g0+1,"Raid Tools message must be queued in K.Net")
assert(A.krt.comms:Send("kwcTest",{note="hello raid"},"RAID"),"pending duplicate reports queued")
local q2,_,_,_,_,g2=status(A)
assert(q2==q1 and g2==g1,"pending duplicate must not be queued twice")
drain()
local packets=krtFrom(A,mark)
assert(#packets==1 and packets[1].channel=="RAID")
local encoded=A.krt.comms:Encode({type="kwcTest",data={note="hello raid"}})
assert(packets[1].msg==Split(encoded)[1],"wire bytes match the AceComm framing of the encoded message")
assert(#B.krt.received==1 and B.krt.received[1].note=="hello raid")
assert(B.krt.received[1].sender==A.name.."-Realm" and B.krt.received[1].channel=="RAID")
assert(A.krt.ace==0 and B.krt.ace==0,"AceComm must not send while K.Net is available")

-- Without K.Net the sender falls back to AceComm.
A.e.KWC.Net=nil
A.krt.comms:Send("kwcTest",{note="fallback"},"RAID")
A.e.KWC.Net=net
assert(A.krt.ace==1,"AceComm fallback when K.Net is absent")
print("PASS: Raid Tools messages route through K.Net with duplicate suppression and an AceComm fallback")

-- 3. Multi-piece messages: ordering lock, ALERT interruption, mid-stream throttle retry,
--    and guild traffic is not starved.
local big1,big2=noise(1400),noise(1400)
mark=#log+1
local _,_,failedBase,droppedBase=status(A)
local throttled=false
A.krt.hook=function(message)
    if not throttled and message:sub(1,1)=="\002" then throttled=true;return 3 end
end
local receivedBase=#B.krt.received
assert(A.krt.comms:Send("kwcTest",{note=big1},"RAID"))
assert(A.krt.comms:Send("kwcTest",{note=big2},"RAID"))
assert(net.Send("KWCT","guild behind raid","GUILD"))
for _=1,60 do
    if #krtFrom(A,mark)>=1 then break end
    n.run(1)
end
assert(#krtFrom(A,mark)>=1)
assert(net.Send("KWCT","alert mid-stream","GUILD",nil,"ALERT"))
drain()
A.krt.hook=nil
assert(throttled,"a continuation piece was throttled once")
local pieces=krtFrom(A,mark)
local open=false
local firstLast
for _,p in ipairs(pieces) do
    local marker=p.msg:sub(1,1)
    if marker=="\001" then
        assert(not open,"a second multi-piece message started before the first finished")
        open=true
    elseif marker=="\002" then
        assert(open,"continuation outside a message")
    elseif marker=="\003" then
        assert(open,"last piece outside a message")
        open=false
        firstLast=firstLast or p.index
    end
end
assert(not open and firstLast)
local firstPieces=0
for _,p in ipairs(pieces) do if p.index<=firstLast then firstPieces=firstPieces+1 end end
assert(firstPieces>=3,"the first message needs several pieces for this check")
assert(logIndex("KWCT","guild behind raid")<firstLast,"guild traffic interleaves with a long Raid Tools message")
assert(logIndex("KWCT","alert mid-stream")<firstLast,"an alert is sent mid-stream")
assert(count(B.krt.received,big1)==1 and count(B.krt.received,big2)==1,"both messages reassemble once")
assert(B.krt.received[receivedBase+1].note==big1 and B.krt.received[receivedBase+2].note==big2)
local _,_,failedAfter,droppedAfter=status(A)
assert(failedAfter==failedBase+1 and droppedAfter==droppedBase,"one retried throttle, nothing dropped")
-- A duplicate multi-piece message is queued once.
mark=#log+1
local big3=noise(1400)
assert(A.krt.comms:Send("kwcTest",{note=big3},"RAID"))
local _,_,_,_,_,groupQueued=status(A)
assert(A.krt.comms:Send("kwcTest",{note=big3},"RAID"))
assert(select(6,status(A))==groupQueued,"duplicate multi-piece message must not be queued twice")
drain()
assert(count(B.krt.received,big3)==1)
print("PASS: multi-piece Raid Tools messages stay ordered through alerts and throttles without starving guild sync")

-- Short and qualified whispers to one member share AceComm's receive spool.
-- A later message must wait for the first to finish even when its target spelling differs.
do
    local first,second=noise(1400),noise(1400)
    local before=#B.krt.received
    assert(A.krt.comms:Send("kwcTest",{note=first},"WHISPER",B.name))
    assert(A.krt.comms:Send("kwcTest",{note=second},"WHISPER",B.name.."-Realm"))
    drain()
    assert(#B.krt.received==before+2 and B.krt.received[before+1].note==first
        and B.krt.received[before+2].note==second,"target aliases must not interleave multipart whispers")
end
print("PASS: short and qualified group whispers share one multipart stream")

-- 4. Lockdown recovery mid-message (result 11 and InChatMessagingLockdown).
local big4=noise(1400)
mark=#log+1
local _,_,f0,d0,l0=status(A)
assert(A.krt.comms:Send("kwcTest",{note=big4},"RAID"))
for _=1,60 do
    if #krtFrom(A,mark)>=1 then break end
    n.run(1)
end
local held=#krtFrom(A,mark)
assert(held>=1 and A.krt.comms.Split(A.krt.comms:Encode({type="kwcTest",data={note=big4}}))[held+1],
    "the lock must start part-way through the message")
A.krt.locked=true
n.run(30)
assert(#krtFrom(A,mark)==held,"no pieces are sent during lockdown")
local ql,_,f1,d1,l1=status(A)
assert(ql>=1 and f1==f0 and d1==d0 and l1>=l0+4,"lockdown spends no attempts and drops nothing")
A.krt.locked=false
local queryMark=#attempts
A.e.C_ChatInfo.InChatMessagingLockdown=function() return true end
n.run(20)
assert(#attempts==queryMark,"the lockdown query pauses before any attempt")
A.e.C_ChatInfo.InChatMessagingLockdown=nil
drain()
assert(count(B.krt.received,big4)==1,"the held message completes in order after lockdown")
local _,_,f2,d2=status(A)
assert(f2==f0 and d2==d0)
print("PASS: lockdown holds a Raid Tools message mid-stream and it resumes in order with no failures")

-- 5. Offline whispers to group members, including a member outside the guild.
local _,_,fw,dw=status(A)
assert(not A.e.KWC.CurrentGuildMember(PUG),"fixture: the pug is not a guild member")
mark=#log+1
assert(A.krt.comms:Send("kwcTest",{note="to pug"},"WHISPER",PUG))
drain()
local pugPackets=krtFrom(A,mark)
assert(#pugPackets==1 and pugPackets[1].target==PUG and pugPackets[1].channel=="WHISPER")
local ace=A.krt.ace
assert(A.krt.comms:Send("kwcTest",{note="outside"},"WHISPER",C.name.."-Realm")==false,
    "a guild member outside the group is refused for Raid Tools whispers")
assert(A.krt.comms:Send("kwcTest",{note="stranger"},"WHISPER","Stranger-Realm")==false)
assert(A.krt.ace==ace,"refused whispers never fall back to AceComm")

A.krt.hook=function(_,channel,target) if channel=="WHISPER" and target==PUG then return 12 end end
local attemptMark=#attempts+1
mark=#log+1
local bBase=#B.krt.received
assert(A.krt.comms:Send("kwcTest",{note="offline one"},"WHISPER",PUG))
assert(A.krt.comms:Send("kwcTest",{note="raid after offline"},"RAID"))
assert(net.Send("KWCT","guild after offline","GUILD"))
assert(A.krt.comms:Send("kwcTest",{note="offline two"},"WHISPER",PUG))
assert(A.krt.comms:Send("kwcTest",{note="whisper member"},"WHISPER",B.name.."-Realm"))
drain()
assert(attemptsTo(PUG,attemptMark)==1,"result 12 is terminal and the peer is skipped for 30 s")
assert(logIndex("KWCT","guild after offline"),"result 12 does not block other traffic")
local newNotes={}
for i=bBase+1,#B.krt.received do newNotes[#newNotes+1]=B.krt.received[i] end
assert(count(newNotes,"raid after offline")==1 and count(newNotes,"whisper member")==1)
local _,_,fw1,dw1=status(A)
assert(fw1==fw+1 and dw1==dw+1,"one failure and one drop for the offline whisper")
A.krt.hook=nil
n.run(31)
mark=#log+1
assert(A.krt.comms:Send("kwcTest",{note="after cooldown"},"WHISPER",PUG))
drain()
assert(#krtFrom(A,mark)==1,"the peer is retried after the 30 s marker expires")

-- A disconnected group member is skipped without an attempt.
offline.raid3=true
attemptMark=#attempts+1
assert(A.krt.comms:Send("kwcTest",{note="disconnected"},"WHISPER",PUG))
drain()
assert(attemptsTo(PUG,attemptMark)==0)
offline.raid3=nil
-- A member who leaves the group before the send is skipped.
attemptMark=#attempts+1
assert(A.krt.comms:Send("kwcTest",{note="left group"},"WHISPER",PUG))
local pug=raid[3]
raid[3]=nil
drain()
raid[3]=pug
assert(attemptsTo(PUG,attemptMark)==0)
print("PASS: Raid Tools whispers reach non-guild group members, result 12 stays terminal, outsiders are refused")

-- 6. Bounded group traffic: piece cap, queue limit, and departure from the group.
A.krt.locked=true
local accepted=0
for i=1,40 do
    if A.krt.comms.NetSend(("%03d"):format(i)..noise(597),"RAID") then accepted=accepted+1 else break end
end
assert(accepted==21 and select(6,status(A))==63,"three-piece messages stop at the 64-piece cap")
assert(A.krt.comms.NetSend("tiny","RAID") and select(6,status(A))==64)
assert(A.krt.comms.NetSend("tiny two","RAID")==false,"group items over the cap are refused")
assert(net.Send("KWCT","guild while capped","GUILD"),"guild sync is still accepted at the group cap")
grouped=false
local _,_,_,dg=status(A)
A.krt.locked=false
mark=#log+1
drain()
assert(#krtFrom(A,mark)==0,"group items are dropped after leaving the group")
local _,_,_,dg1,_,gq=status(A)
assert(dg1==dg+22 and gq==0)
assert(logIndex("KWCT","guild while capped"))
grouped=true

A.krt.locked=true
local fill=0
while (status(A))<300 do
    fill=fill+1
    assert(net.Send("KWCT","fill "..fill,"GUILD"))
end
assert(A.krt.comms.NetSend("blocked by queue limit","RAID")==false,"group items yield to a 300-item backlog")
assert(net.Send("KWCT","guild still accepted","GUILD"))
-- Replies are held in a reserve outside the item limits: a guild backlog of 300 to 350
-- items never refuses one, and a queued reply never takes room from guild sync.
local replyTo=B.name.."-Realm"
assert(A.krt.comms.NetSend("reply beside 300","WHISPER",replyTo,nil,{reply=true}),
    "a reply is accepted beside a 300-item backlog")
local more=0
while net.Send("KWCT","fill more "..more,"GUILD") do more=more+1;assert(more<100,"guild items must stop at 350") end
assert((status(A))==351,"guild items still stop at 350 and the queued reply does not take their room")
assert(A.krt.comms.NetSend("reply beside 350","WHISPER",replyTo,nil,{reply=true}),
    "a reply is accepted beside a full 350-item queue")
assert(A.krt.comms.NetSend("still blocked","RAID")==false,"non-reply group items still yield to the backlog")
assert(net.Send("KWCT","guild still refused","GUILD")==false,"replies do not raise the guild limit")
net.CancelPrefix("KWCT",A.e.KWC.GuildScope())
A.krt.locked=false
drain()
print("PASS: group traffic is capped at 64 pieces, yields to a full queue, replies keep reserved room, and items are dropped outside a group")

-- 6b. A saved note larger than the group piece cap is still delivered (AceComm had no size
--     limit). While it is sending, ordinary Raid Tools sends are still accepted: ordered
--     ones (notes, clears) follow it in order, and order-independent single pieces
--     (version queries, attendance requests) are sent between its pieces. A second
--     oversized send is refused and the refusal reaches the UI caller.
do
    local krtB=B.e.KeepersRaidTools
    krtB.RegisterModule=function() end
    krtB.defaults=krtB.defaults or {}
    local notesSettings={savedNotes={},annotations={}}
    krtB.GetSetting=function(_,key) if key=="notes" then return notesSettings end end
    setfenv(assert(loadfile(folder.."Modules/Notes/Notes.lua")),B.e)()
    local Notes=krtB.Notes
    local gotNotes={}
    A.krt.comms:RegisterHandler("note",function(data,sender,channel)
        gotNotes[#gotNotes+1]={name=data.name,text=data.text,sender=sender,channel=channel}
    end)
    A.krt.comms:RegisterHandler("clear",function(_,sender,channel)
        gotNotes[#gotNotes+1]={clear=true,sender=sender,channel=channel}
    end)
    -- The first note piece throttles before the active-stream lock starts. The
    -- following clear must still arrive after the note.
    local retryText=noise(1400)
    local retryParts=B.krt.comms.Split(B.krt.comms:Encode({type="note",data={name="Retry Plan",text=retryText}}))
    local retried=false
    B.krt.hook=function(message,channel)
        if channel=="RAID" and message==retryParts[1] and not retried then
            retried=true
            return 3
        end
    end
    notesSettings.savedNotes["Retry Plan"]=retryText
    assert(Notes:BroadcastNote("Retry Plan"))
    for _=1,30 do if retried then break end n.run(1) end
    assert(retried,"fixture: first note piece was throttled")
    assert(Notes:BroadcastClear())
    drain()
    B.krt.hook=nil
    assert(#gotNotes==2 and gotNotes[1].text==retryText and gotNotes[2].clear,
        "a clear must not overtake a note whose first piece was retried")
    gotNotes={}
    print("PASS: first-piece retry preserves note then clear FIFO order")
    local longText=noise(40000)
    notesSettings.savedNotes["Long Plan"]=longText
    local pieceCount=#B.krt.comms.Split(B.krt.comms:Encode({type="note",data={name="Long Plan",text=longText}}))
    assert(pieceCount>64,"fixture: the note needs more pieces than the group cap, got "..pieceCount)
    assert(select(6,status(B))==0,"fixture: no group traffic is queued")
    local probes={}
    A.krt.comms:RegisterHandler("versionQuery",function(data,sender,channel)
        probes[#probes+1]={notesSoFar=#gotNotes,version=data.version,channel=channel}
    end)
    mark=#log+1
    local ok,reason=Notes:BroadcastNote("Long Plan")
    assert(ok==true and reason==nil,"an oversized note is accepted")
    assert(select(6,status(B))==pieceCount,"the whole note is queued in K.Net")
    -- A second oversized send in the same budget is refused, and the reason reaches the UI.
    notesSettings.savedNotes["Long Two"]=noise(40000)
    local refused,why=Notes:BroadcastNote("Long Two")
    assert(refused==false and type(why)=="string" and why~="","a refused note send returns a reason for the UI")
    -- Let the long note get part-way through its stream.
    for _=1,60 do
        if #krtFrom(B,mark)>=2 then break end
        n.run(1)
    end
    assert(#krtFrom(B,mark)>=2,"fixture: the long note has started")
    -- Ordinary sends are accepted while the oversized note is in progress.
    notesSettings.savedNotes["Short"]="pull at 10"
    assert(Notes:BroadcastNote("Short")==true,"a short note is accepted beside an oversized note")
    local cleared,clearWhy=Notes:BroadcastClear()
    assert(cleared==true and clearWhy==nil,"a clear is accepted beside an oversized note")
    assert(B.krt.comms:Send("versionQuery",{version="probe"},"RAID"),"a version query is accepted")
    assert(B.krt.sync:RequestInventory(),"an attendance inventory request is accepted")
    assert(B.e.KWC.Net.Send("KWCT","guild beside long note","GUILD"),"guild sync is still accepted")
    -- The order-independent query and the whole inventory round trip finish mid-note.
    local inventoryMidNote
    for _=1,120 do
        if B.krt.sync:GetInventory()[A.name.."-Realm"] then inventoryMidNote=#gotNotes==0;break end
        n.run(1)
    end
    assert(inventoryMidNote==true,"the inventory round trip completes while the long note is still sending")
    assert(#probes==1 and probes[1].notesSoFar==0 and probes[1].version=="probe" and probes[1].channel=="RAID",
        "an order-independent query is sent between the long note's pieces")
    drain(400)
    assert(#gotNotes==3,"the long note, the short note and the clear each arrive once")
    assert(gotNotes[1].text==longText and gotNotes[1].name=="Long Plan" and gotNotes[1].channel=="RAID",
        "the oversized note reassembles intact")
    assert(gotNotes[2].text=="pull at 10" and gotNotes[3].clear,"ordered sends follow the long note in send order")
    assert(logIndex("KWCT","guild beside long note"),"guild traffic was sent alongside the long note")
    assert(B.krt.ace==0,"no AceComm fallback was used")
end
print("PASS: oversized notes are delivered without refusing or reordering other Raid Tools traffic")

-- 6c. Duplicate sends while an item is held (for example repeated requests during
--     lockdown) keep a bounded callback list: the original and the latest caller.
do
    A.krt.locked=true
    local _,_,_,_,_,g0=status(A)
    local calls={}
    local probe=A.krt.comms:Encode({type="kwcUnhandledProbe",data={}})
    assert(#probe<=250,"fixture: the probe fits in one piece")
    for i=1,100 do
        assert(net.Send(PREFIX,probe,"RAID",nil,nil,{onComplete=function(sent)
            calls[#calls+1]={i=i,sent=sent}
        end}))
    end
    assert(select(6,status(A))==g0+1,"the duplicates share one queued item")
    n.run(10)
    A.krt.locked=false
    drain()
    assert(#calls==4,"at most four completion callbacks are kept, got "..#calls)
    assert(calls[1].i==1 and calls[#calls].i==100,"the original and the latest caller are notified")
    for _,call in ipairs(calls) do assert(call.sent==true) end
    -- Repeated inventory requests during lockdown keep working: the latest one's window opens.
    A.krt.locked=true
    B.krt.locked=true
    for _=1,50 do assert(B.krt.sync:RequestInventory()) end
    n.run(5)
    B.krt.locked=false
    A.krt.locked=false
    drain()
    assert(B.krt.sync:GetInventory()[A.name.."-Realm"],"the latest of repeated requests receives its reply")
end
print("PASS: duplicate sends keep a bounded callback list that notifies the original and latest callers")

-- 7. Two-client attendance pull and inventory through the real codec and handlers.
local day="2026-11-13"
local records,total={},0
for _=1,150 do
    local name=noise(8)
    if not records[name] then total=total+1 end
    records[name]=3
end
A.e.KeepersRaidToolsAttendanceDB[day]=records
B.e.KeepersRaidToolsAttendanceDB[day]={Old=1}
mark=#log+1
assert(B.krt.sync:RequestDay(A.name.."-Realm",day))
drain()
local reply=krtFrom(A,mark)
assert(#reply>=2 and reply[1].msg:sub(1,1)=="\001" and reply[1].channel=="WHISPER","attendance reply is multi-piece")
local pendingDay=assert(B.krt.sync:GetPendingDay(),"attendance reply reassembled and accepted for review")
assert(pendingDay.sender==A.name.."-Realm" and pendingDay.incomingCount==total)
assert(B.krt.sync:AcceptPendingDay())
for name in pairs(records) do assert(B.e.KeepersRaidToolsAttendanceDB[day][name].status==3) end
B.krt.sync:RequestInventory()
drain()
local inventory=B.krt.sync:GetInventory()[A.name.."-Realm"]
assert(inventory and inventory[day]==total,"inventory request and whisper reply round trip")
assert(A.krt.ace==1 and B.krt.ace==0,"only the explicit fallback check used AceComm")
print("PASS: two-client attendance pull and inventory complete over K.Net with AceComm-compatible reassembly")

-- 8. Two-client backlog: requests queued behind 36 group messages (more than 30 s at one
--    send per 0.85 s) still complete, because reply windows start when the request is sent.
do
    local day2="2026-11-14"
    A.e.KeepersRaidToolsAttendanceDB[day2]={Alpha=3,Beta=2}
    B.e.KeepersRaidToolsAttendanceDB[day2]=nil
    local sentAt={}
    local responderBacklog=0
    B.krt.hook=function(message)
        local ok,payload=B.krt.comms:Decode(message)
        if ok and not sentAt[payload.type] then
            sentAt[payload.type]=B.e.time()
            if payload.type=="attInventoryRequest" then
                -- The responder is busy too: its reply waits behind its own group backlog.
                for i=1,20 do
                    if A.krt.comms:Send("kwcTest",{note="responder backlog "..i},"RAID") then
                        responderBacklog=responderBacklog+1
                    end
                end
            end
        end
    end

    for i=1,36 do assert(B.krt.comms:Send("kwcTest",{note="backlog day "..i},"RAID")) end
    assert(select(6,status(B))==36,"fixture: 36 group messages are queued ahead of the request")
    local requestedAt=B.e.time()
    assert(B.krt.sync:RequestDay(A.name.."-Realm",day2))
    drain(200)
    -- The old deadline (request time + 30, rejected once time() >= it) had passed by now.
    assert(sentAt.attPullRequest and sentAt.attPullRequest-requestedAt>=30,
        "fixture: the pull request waited at least 30 s in the queue")
    local pendingDay=assert(B.krt.sync:GetPendingDay(),"the delayed pull reply is accepted")
    assert(pendingDay.day==day2 and pendingDay.incomingCount==2 and pendingDay.sender==A.name.."-Realm")
    B.krt.sync:DeclinePendingDay()

    for i=1,36 do assert(B.krt.comms:Send("kwcTest",{note="backlog inventory "..i},"RAID")) end
    requestedAt=B.e.time()
    assert(B.krt.sync:RequestInventory())
    drain(200)
    assert(sentAt.attInventoryRequest and sentAt.attInventoryRequest-requestedAt>=30,
        "fixture: the inventory request waited at least 30 s in the queue")
    assert(responderBacklog==20,"fixture: the responder had its own backlog")
    local inventory=B.krt.sync:GetInventory()[A.name.."-Realm"]
    assert(inventory and inventory[day2]==2,"the delayed inventory reply is accepted")
    B.krt.hook=nil

    -- The window still closes: a reply after it (REPLY_WINDOW, 360 s) is ignored.
    assert(B.krt.sync.REPLY_WINDOW==360,"fixture: the reply window covers the supported reply delivery time")
    n.run(B.krt.sync.REPLY_WINDOW+1)
    local late=B.krt.comms:Encode({type="attInventoryResponse",data={days={[day2]=9}}})
    B.krt.comms:Dispatch(late,A.name.."-Realm","WHISPER")
    assert(B.krt.sync:GetInventory()[A.name.."-Realm"][day2]==2,"a reply after the window is ignored")

    -- A request the queue drops (the group ended before it was sent) closes its window at once.
    assert(B.krt.sync:RequestInventory())
    grouped=false
    drain()
    grouped=true
    B.krt.comms:Dispatch(late,A.name.."-Realm","WHISPER")
    assert(next(B.krt.sync:GetInventory())==nil,"a dropped request accepts no replies")

    -- A request still held in the queue (here by lockdown) accepts no responses: one
    -- arriving before the request is sent is stale or unsolicited. Once it is sent, the
    -- real reply is accepted.
    B.krt.locked=true
    assert(B.krt.sync:RequestInventory())
    n.run(5)
    B.krt.comms:Dispatch(late,A.name.."-Realm","WHISPER")
    assert(next(B.krt.sync:GetInventory())==nil,"a response before the request is sent is ignored")
    B.krt.locked=false
    drain()
    local held=B.krt.sync:GetInventory()[A.name.."-Realm"]
    assert(held and held[day2]==2,"the reply after the held request is sent is accepted")
end
print("PASS: attendance requests survive a 36-message requester backlog and a responder backlog; windows still close")

-- 9. A pull answered while the responder's group send budget is full: the reply uses the
--    reserved reply budget. If the reply is refused anyway, it is retried a bounded number
--    of times.
do
    local day3="2026-11-15"
    A.e.KeepersRaidToolsAttendanceDB[day3]={Gamma=3,Delta=4}
    B.e.KeepersRaidToolsAttendanceDB[day3]=nil
    A.krt.locked=true
    assert(select(6,status(A))==0,"fixture: the responder has no group traffic queued")
    -- One 64-piece message fills the responder's send budget exactly.
    local fullText=noise(64*249)
    assert(#A.krt.comms.Split(fullText)==64)
    assert(A.krt.comms.NetSend(fullText,"RAID"),"a 64-piece message fits the send budget")
    assert(A.krt.comms.NetSend("one more","RAID")==false,"fixture: the responder's send budget is full")
    local before=select(6,status(A))
    assert(B.krt.sync:RequestDay(A.name.."-Realm",day3))
    n.run(5)
    assert(select(6,status(A))>before,"the pull reply is queued in the reserved reply budget")
    A.krt.locked=false
    drain(300)
    local pendingDay=assert(B.krt.sync:GetPendingDay(),"the reply arrives although the send budget was full")
    assert(pendingDay.day==day3 and pendingDay.incomingCount==2 and pendingDay.sender==A.name.."-Realm")
    B.krt.sync:DeclinePendingDay()

    -- Refused replies are retried (bounded) and still reach the requester in its window.
    local original=A.krt.comms.sendFunc
    local replyAttempts,refusals,replyFlag=0,2,nil
    A.krt.comms.sendFunc=function(encoded,channel,target,onComplete,sendOpts)
        if channel=="WHISPER" then
            replyAttempts=replyAttempts+1
            replyFlag=sendOpts and sendOpts.reply
            if refusals>0 then refusals=refusals-1;return false end
        end
        return original(encoded,channel,target,onComplete,sendOpts)
    end
    assert(B.krt.sync:RequestDay(A.name.."-Realm",day3))
    -- Retries are timers, not queue items, so run past them before draining.
    n.run(20)
    drain(300)
    assert(replyAttempts==3 and replyFlag==true,"two refusals then a reserved-budget reply, got "..replyAttempts)
    pendingDay=assert(B.krt.sync:GetPendingDay(),"the retried reply is accepted")
    assert(pendingDay.day==day3 and pendingDay.incomingCount==2)
    B.krt.sync:DeclinePendingDay()

    -- A reply that is always refused stops after three retries.
    replyAttempts,refusals=0,1000
    assert(B.krt.sync:RequestDay(A.name.."-Realm",day3))
    n.run(30)
    drain(300)
    n.run(60)
    assert(replyAttempts==4,"one attempt and three bounded retries, got "..replyAttempts)
    assert(B.krt.sync:GetPendingDay()==nil,"no reply was delivered")
    A.krt.comms.sendFunc=original
end
print("PASS: pull replies use reserved capacity when the responder's group budget is full, with bounded retry")

-- 10. Long responder backlog: the responder's queue holds 160 guild messages (about
--     144 s at one send per 0.9 s) when the pull request arrives. The reply is sent on
--     the reserved reply turns, so it arrives within 120 s (well inside REPLY_WINDOW)
--     while the backlog is still draining.
do
    local day4="2026-11-16"
    A.e.KeepersRaidToolsAttendanceDB[day4]={Epsilon=3,Zeta=1}
    B.e.KeepersRaidToolsAttendanceDB[day4]=nil
    assert((status(A))==0 and (status(B))==0,"fixture: both queues are empty")
    local requestSentAt
    local backlog=0
    B.krt.hook=function(message)
        local ok,payload=B.krt.comms:Decode(message)
        if ok and payload.type=="attPullRequest" and not requestSentAt then
            requestSentAt=B.e.time()
            for i=1,160 do
                if A.e.KWC.Net.Send("KWCT","responder guild backlog "..i,"GUILD") then backlog=backlog+1 end
            end
        end
    end
    assert(B.krt.sync:RequestDay(A.name.."-Realm",day4))
    local arrivedAt,leftInQueue
    for _=1,400 do
        if B.krt.sync:GetPendingDay() then arrivedAt=B.e.time();leftInQueue=(status(A));break end
        n.run(1)
    end
    B.krt.hook=nil
    assert(backlog==160,"fixture: the responder queued 160 guild messages, got "..backlog)
    assert(requestSentAt and arrivedAt,"the reply arrived despite the responder backlog")
    assert(arrivedAt-requestSentAt<120,"the reply arrived inside the reply window, took "..(arrivedAt-requestSentAt).." s")
    assert(leftInQueue>=100,"the reply went ahead of the backlog (still queued: "..tostring(leftInQueue)..")")
    local pendingDay=B.krt.sync:GetPendingDay()
    assert(pendingDay.day==day4 and pendingDay.incomingCount==2)
    B.krt.sync:DeclinePendingDay()
    A.e.KWC.Net.CancelPrefix("KWCT",A.e.KWC.GuildScope())
    drain()
end
print("PASS: a reply ahead of a responder backlog longer than the reply window is still accepted")

-- 11. Ready-check roster requests: a request accepts a whispered roster only after it
--     was sent. Request 1 is answered late (the leader is in lockdown), and request 2 is
--     still queued behind a backlog when reply 1 arrives. Reply 1 must not use up
--     request 2, so reply 2 (the newer roster) is accepted too.
do
    local prepared={}
    A.e.KeepersRaidTools.RosterValidation.PrepareEntries=function(_,entries)
        if type(entries)~="table" then return nil end
        prepared[#prepared+1]=entries[1] and entries[1].name
        return entries
    end
    A.krt.sync.confirmBeforeSyncing=nil
    local leader=B.name.."-Realm"
    B.e.KeepersRaidToolsRosterDB={{name="Version One"}}
    local requestsSent=0
    A.krt.hook=function(message)
        local ok,payload=A.krt.comms:Decode(message)
        if ok and payload.type=="attRosterRequest" then requestsSent=requestsSent+1 end
    end

    -- An unsolicited whisper before any request is ignored.
    local unsolicited=A.krt.comms:Encode({type="attRosterPush",data={entries={{name="Unsolicited"}}}})
    A.krt.comms:Dispatch(unsolicited,leader,"WHISPER")
    assert(#prepared==0,"an unsolicited whispered roster is ignored")

    B.krt.locked=true -- the leader holds reply 1
    A.krt.sync:OnReadyCheck(leader,true)
    -- A queued, unsent request accepts nothing.
    A.krt.comms:Dispatch(unsolicited,leader,"WHISPER")
    assert(#prepared==0,"a queued request accepts no reply before it is sent")
    for _=1,30 do
        if requestsSent>=1 then break end
        n.run(1)
    end
    assert(requestsSent==1,"fixture: request 1 was sent")
    n.run(2) -- delivered to the leader; reply 1 waits in the leader's queue
    assert((status(B))>=1,"fixture: reply 1 is held by the leader")

    -- Request 2 waits behind a backlog on the requester.
    for i=1,40 do assert(A.e.KWC.Net.Send("KWCT","requester guild backlog "..i,"GUILD")) end
    A.krt.sync:OnReadyCheck(leader,true)
    -- A further ready check while request 2 is still queued is served by it.
    A.krt.sync:OnReadyCheck(leader,true)
    B.krt.locked=false
    for _=1,20 do
        if #prepared>=1 then break end
        n.run(1)
    end
    assert(#prepared==1 and prepared[1]=="Version One","reply 1 is accepted")
    assert(requestsSent==1,"fixture: reply 1 arrived while request 2 was still queued")
    B.e.KeepersRaidToolsRosterDB={{name="Version Two"}}
    drain(300)
    assert(requestsSent==2,"one send for request 2 although two ready checks queued it, got "..requestsSent)
    assert(#prepared==2 and prepared[2]=="Version Two","reply 2 is accepted after reply 1, got "..#prepared)
    -- Every sent request has been answered: a further whisper is ignored.
    A.krt.comms:Dispatch(unsolicited,leader,"WHISPER")
    assert(#prepared==2,"no reply is accepted beyond the requests sent")
    A.krt.hook=nil
end
print("PASS: ready-check roster replies are credited per sent request, so a late reply cannot consume a newer request")

-- 12. Pushes report a refused send instead of claiming success.
do
    local day5="2026-11-17"
    A.e.KeepersRaidToolsAttendanceDB[day5]={Eta=3}
    local ok,reason=A.krt.sync:PushDay("2026-01-01")
    assert(ok==false and reason=="missing","a missing day is reported")
    A.krt.locked=true
    assert(select(6,status(A))==0,"fixture: no group traffic is queued")
    assert(A.krt.comms.NetSend(noise(64*249),"RAID"),"fixture: a 64-piece message fills the send budget")
    ok,reason=A.krt.sync:PushDay(day5)
    assert(ok==false and reason=="refused","a push refused by the queue is reported, got "..tostring(ok))
    assert(A.krt.sync:PushRoster()==false,"a refused roster push is reported")
    A.krt.locked=false
    drain(300)
    local bBase=#B.krt.received
    ok,reason=A.krt.sync:PushDay(day5)
    assert(ok==true and reason==nil,"a queued push reports success")
    assert(A.krt.sync:PushRoster()==true)
    drain()
    assert(#B.krt.received==bBase,"fixture: pushes are not test notes")
end
print("PASS: attendance and roster pushes return the queue's send result")

-- 13. Instance groups: guildless clients exchange Raid Tools version queries and
--     responses on INSTANCE_CHAT (GroupInspect's channel in instance groups). The queue
--     treats INSTANCE_CHAT as group traffic, so it needs no guild, and drops it after
--     leaving the group.
do
    drain()
    local guildA,guildB=A.e.IsInGuild,B.e.IsInGuild
    A.e.IsInGuild=function() return false end
    B.e.IsInGuild=function() return false end
    local queries,responses={},{}
    A.krt.comms:RegisterHandler("versionQuery",function(data,sender,channel)
        queries[#queries+1]={version=data.version,sender=sender,channel=channel}
        A.krt.comms:Send("versionResponse",{version=2},channel)
    end)
    B.krt.comms:RegisterHandler("versionResponse",function(data,sender,channel)
        responses[#responses+1]={version=data.version,sender=sender,channel=channel}
    end)
    local aceA,aceB=A.krt.ace,B.krt.ace
    mark=#log+1
    local q0,_,_,_,_,g0=status(B)
    assert(B.krt.comms:Send("versionQuery",{version=1},"INSTANCE_CHAT")==true,
        "a guildless INSTANCE_CHAT version query is accepted")
    local q1,_,_,_,_,g1=status(B)
    assert(q1==q0+1 and g1==g0+1,"the INSTANCE_CHAT query is queued as group traffic")
    assert(B.krt.comms:Send("versionQuery",{version=1},"INSTANCE_CHAT")==true and (status(B))==q1,
        "a pending INSTANCE_CHAT duplicate is not queued twice")
    drain()
    assert(#queries==1 and queries[1].version==1 and queries[1].channel=="INSTANCE_CHAT"
        and queries[1].sender==B.name.."-Realm","the query arrives once on INSTANCE_CHAT")
    assert(#responses==1 and responses[1].version==2 and responses[1].channel=="INSTANCE_CHAT"
        and responses[1].sender==A.name.."-Realm","the guildless response arrives on INSTANCE_CHAT")
    local fromA,fromB=krtFrom(A,mark),krtFrom(B,mark)
    assert(#fromA==1 and fromA[1].channel=="INSTANCE_CHAT" and #fromB==1 and fromB[1].channel=="INSTANCE_CHAT")
    assert(A.krt.ace==aceA and B.krt.ace==aceB,"no AceComm fallback was used")
    -- Leaving the instance group drops queued INSTANCE_CHAT traffic instead of sending it.
    A.krt.locked=true
    assert(A.krt.comms:Send("versionResponse",{version=3},"INSTANCE_CHAT")==true)
    grouped=false
    local _,_,_,dropped0=status(A)
    A.krt.locked=false
    mark=#log+1
    drain()
    local _,_,_,dropped1=status(A)
    assert(#krtFrom(A,mark)==0 and dropped1==dropped0+1,"INSTANCE_CHAT items are dropped after leaving the group")
    grouped=true
    A.e.IsInGuild,B.e.IsInGuild=guildA,guildB
end
print("PASS: guildless instance-group clients exchange version queries and responses on INSTANCE_CHAT")

-- 14. Queued group traffic is bound to the group it was queued in. A note or whisper held
--     while the player leaves one raid and joins another (here B is in both raids, so
--     an unbound item would reach it) is dropped instead of being sent to the new raid.
do
    drain()
    local oldPug=raid[3]
    local bBase=#B.krt.received
    local function newNotes()
        local out={}
        for i=bBase+1,#B.krt.received do out[#out+1]=B.krt.received[i] end
        return out
    end

    -- a) Leave and join while the items are held; the group events move the epoch.
    local _,_,_,d0=status(A)
    mark=#log+1
    A.krt.locked=true
    assert(A.krt.comms:Send("kwcTest",{note="old raid note"},"RAID"))
    assert(A.krt.comms:Send("kwcTest",{note="old raid whisper"},"WHISPER",B.name.."-Realm"))
    n.run(3)
    grouped=false
    net.GroupEvent("GROUP_LEFT")
    raid[3]={"Newcomer","Elsewhere"}
    grouped=true
    net.GroupEvent("GROUP_JOINED")
    A.krt.locked=false
    drain()
    local _,_,_,d1=status(A)
    assert(#krtFrom(A,mark)==0,"items queued in the old raid are not sent to the new raid")
    assert(d1==d0+2,"both stale group items are counted as dropped")
    assert(#newNotes()==0,"the new raid receives nothing from the old raid")

    -- b) No events: the queue turns see the departure during a lockdown hold.
    A.e.C_ChatInfo.InChatMessagingLockdown=function() return true end
    assert(A.krt.comms:Send("kwcTest",{note="held across raids"},"RAID"))
    n.run(5)
    grouped=false
    n.run(5)
    grouped=true
    n.run(5)
    A.e.C_ChatInfo.InChatMessagingLockdown=nil
    mark=#log+1
    drain()
    local _,_,_,d2=status(A)
    assert(#krtFrom(A,mark)==0 and d2==d1+1,"a group change seen during a lockdown hold drops the item")

    -- c) Control: a roster change inside the same raid keeps the item.
    A.krt.locked=true
    assert(A.krt.comms:Send("kwcTest",{note="same raid"},"RAID"))
    raid[3]={"Another","Elsewhere"}
    net.GroupEvent("GROUP_ROSTER_UPDATE")
    A.krt.locked=false
    drain()
    assert(count(newNotes(),"same raid")==1,"traffic queued in the current raid is still delivered")

    -- d) The same message sent again in the new raid is queued on its own, not merged
    --    into the stale item, and is delivered once.
    A.krt.locked=true
    assert(A.krt.comms:Send("kwcTest",{note="repeat"},"RAID"))
    local _,_,_,_,_,g0=status(A)
    grouped=false
    net.GroupEvent("GROUP_LEFT")
    grouped=true
    net.GroupEvent("GROUP_JOINED")
    assert(A.krt.comms:Send("kwcTest",{note="repeat"},"RAID"))
    assert(select(6,status(A))==g0+1,"the new-raid send does not merge into the stale item")
    local _,_,_,d3=status(A)
    A.krt.locked=false
    drain()
    local _,_,_,d4=status(A)
    assert(count(newNotes(),"repeat")==1 and d4==d3+1,"only the new-raid copy is delivered")
    raid[3]=oldPug
end
print("PASS: queued group traffic is dropped when the player changes groups before it is sent")

-- 15. Oversized attendance reply between two clients: a pull reply larger than the 64-piece
--     reply budget is sent one piece per two turns behind a responder guild backlog. It
--     takes longer than the old 120 s window but is accepted inside REPLY_WINDOW. A reply
--     larger than WINDOW_REPLY_PIECES is still sent (AceComm sent any size) and accepted
--     after REPLY_WINDOW because its first piece arrived inside the window.
do
    drain()
    local day6="2026-11-18"
    local maxPieces=A.krt.sync.WINDOW_REPLY_PIECES
    assert(maxPieces==128,"fixture: REPLY_WINDOW covers whole replies of up to 128 pieces")
    local big,total={},0
    local function grow(limit,step)
        local pieces=0
        while pieces<=limit do
            for _=1,step or 200 do
                local name=noise(12)
                if not big[name] then total=total+1 end
                big[name]=3
            end
            pieces=A.krt.sync.ReplyPieces("attPullResponse",{day=day6,request="1700000000-1-100000",records=big})
        end
        return pieces
    end
    local pieces=grow(80)
    assert(pieces>64 and pieces<maxPieces-2,"fixture: the reply is oversized but under the cap, got "..pieces)
    A.e.KeepersRaidToolsAttendanceDB[day6]=big
    B.e.KeepersRaidToolsAttendanceDB[day6]=nil
    local requestSentAt
    local backlog=0
    B.krt.hook=function(message)
        local ok,payload=B.krt.comms:Decode(message)
        if ok and payload.type=="attPullRequest" and not requestSentAt then
            requestSentAt=B.e.time()
            for i=1,250 do
                if A.e.KWC.Net.Send("KWCT","oversized reply backlog "..i,"GUILD") then backlog=backlog+1 end
            end
        end
    end
    mark=#log+1
    assert(B.krt.sync:RequestDay(A.name.."-Realm",day6))
    local arrivedAt
    for _=1,500 do
        if B.krt.sync:GetPendingDay() then arrivedAt=B.e.time();break end
        n.run(1)
    end
    B.krt.hook=nil
    assert(backlog==250,"fixture: the responder queued 250 guild messages, got "..backlog)
    assert(requestSentAt and arrivedAt,"the oversized reply was accepted")
    local took=arrivedAt-requestSentAt
    assert(took>120,"fixture: the oversized reply outlasts the old 120 s window, took "..took.." s")
    assert(took<A.krt.sync.REPLY_WINDOW,"the oversized reply arrives inside REPLY_WINDOW, took "..took.." s")
    local pendingDay=B.krt.sync:GetPendingDay()
    assert(pendingDay.day==day6 and pendingDay.incomingCount==total and pendingDay.sender==A.name.."-Realm")
    B.krt.sync:DeclinePendingDay()
    A.e.KWC.Net.CancelPrefix("KWCT",A.e.KWC.GuildScope())
    drain()

    -- Larger than the window covers: about 240 pieces at 1.7 s each behind a responder
    -- guild backlog takes longer than REPLY_WINDOW. The reply is still queued and sent,
    -- and accepted because its first piece arrived inside the window.
    pieces=grow(240,600)
    assert(pieces>=240,"fixture: the reply needs more pieces than the window covers, got "..pieces)
    A.e.KeepersRaidToolsAttendanceDB[day6]=big
    requestSentAt,backlog=nil,0
    B.krt.hook=function(message)
        local ok,payload=B.krt.comms:Decode(message)
        if ok and payload.type=="attPullRequest" and not requestSentAt then
            requestSentAt=B.e.time()
            for i=1,300 do
                if A.e.KWC.Net.Send("KWCT","long reply backlog "..i,"GUILD") then backlog=backlog+1 end
            end
        end
    end
    mark=#log+1
    assert(B.krt.sync:RequestDay(A.name.."-Realm",day6))
    arrivedAt=nil
    for _=1,900 do
        if B.krt.sync:GetPendingDay() then arrivedAt=B.e.time();break end
        n.run(1)
    end
    B.krt.hook=nil
    assert(backlog==300,"fixture: the responder queued 300 guild messages, got "..backlog)
    local replies=0
    for _,p in ipairs(krtFrom(A,mark)) do if p.channel=="WHISPER" then replies=replies+1 end end
    -- The fixture estimate uses a placeholder token, so allow a one-piece difference.
    assert(replies>=pieces-1,"every piece of the long reply was sent, got "..replies.." of about "..pieces)
    assert(requestSentAt and arrivedAt,"the reply larger than the window covers was accepted")
    took=arrivedAt-requestSentAt
    assert(took>A.krt.sync.REPLY_WINDOW,"fixture: the long reply completes after REPLY_WINDOW, took "..took.." s")
    pendingDay=B.krt.sync:GetPendingDay()
    assert(pendingDay.day==day6 and pendingDay.incomingCount==total and pendingDay.sender==A.name.."-Realm")
    B.krt.sync:DeclinePendingDay()
    A.e.KWC.Net.CancelPrefix("KWCT",A.e.KWC.GuildScope())
    drain()
    A.e.KeepersRaidToolsAttendanceDB[day6]=nil
end
print("PASS: oversized two-client attendance replies, including one longer than REPLY_WINDOW, are delivered and accepted")

-- 15b. Late acceptance is limited to whispered multi-piece replies whose first piece
--      arrived inside the window: one that started after the window closed is ignored.
do
    drain()
    local responder=A.name.."-Realm"
    local function inventoryReply(value)
        local days={}
        for i=1,300 do days[("%04d-%02d-%02d"):format(1700+i,1+i%12,1+i%28)]=(i*7919+value)%100003 end
        days["2026-11-19"]=value
        return B.krt.comms:Encode({type="attInventoryResponse",data={days=days}})
    end
    local early,lateStart=inventoryReply(5),inventoryReply(6)
    assert(#early>=256 and #lateStart>=256,"fixture: the replies are multi-piece messages")
    assert(B.krt.sync:RequestInventory())
    drain()
    n.run(10)
    B.krt.comms:NotePiece(PREFIX,"\001first piece","WHISPER",responder) -- inside the window
    n.run(B.krt.sync.REPLY_WINDOW)
    B.krt.comms:Dispatch(early,responder,"WHISPER")
    assert(B.krt.sync:GetInventory()[responder]["2026-11-19"]==5,
        "a multi-piece reply that started inside the window is accepted after it")
    B.krt.comms:NotePiece(PREFIX,"\001first piece","WHISPER",responder) -- after the window
    B.krt.comms:Dispatch(lateStart,responder,"WHISPER")
    assert(B.krt.sync:GetInventory()[responder]["2026-11-19"]==5,
        "a reply that started after the window is ignored")
    -- A single-piece reply after the window has no stream start and is ignored.
    local single=B.krt.comms:Encode({type="attInventoryResponse",data={days={["2026-11-19"]=7}}})
    assert(#single<256,"fixture: a single-piece reply")
    B.krt.comms:Dispatch(single,responder,"WHISPER")
    assert(B.krt.sync:GetInventory()[responder]["2026-11-19"]==5,"a single-piece reply after the window is ignored")
end
print("PASS: late acceptance needs a whispered multi-piece reply that started inside the window")

-- 16. Responder queue holding 300 to 350 guild items: the pull reply is queued in the
--     reply reserve (not refused by the item limits, where three 5 s retries would expire
--     before the backlog drains) and arrives on the reply turns while the backlog remains.
do
    drain()
    local day7="2026-11-20"
    A.e.KeepersRaidToolsAttendanceDB[day7]={Theta=3,Iota=2}
    B.e.KeepersRaidToolsAttendanceDB[day7]=nil
    local requestSentAt
    local backlog,refused=0,0
    B.krt.hook=function(message)
        local ok,payload=B.krt.comms:Decode(message)
        if ok and payload.type=="attPullRequest" and not requestSentAt then
            requestSentAt=B.e.time()
            for i=1,360 do
                if A.e.KWC.Net.Send("KWCT","full queue backlog "..i,"GUILD") then backlog=backlog+1
                else refused=refused+1 end
            end
        end
    end
    assert(B.krt.sync:RequestDay(A.name.."-Realm",day7))
    local arrivedAt,leftInQueue
    for _=1,400 do
        if B.krt.sync:GetPendingDay() then arrivedAt=B.e.time();leftInQueue=(status(A));break end
        n.run(1)
    end
    B.krt.hook=nil
    assert(backlog==350 and refused==10,"fixture: the responder's queue was full at 350 guild items, got "..backlog)
    assert(requestSentAt and arrivedAt,"the reply arrived despite a full responder queue")
    assert(arrivedAt-requestSentAt<60,"the reply was not delayed by the backlog, took "..(arrivedAt-requestSentAt).." s")
    assert(leftInQueue>=300,"the reply went ahead while 300 or more items were queued (still queued: "..tostring(leftInQueue)..")")
    local pendingDay=B.krt.sync:GetPendingDay()
    assert(pendingDay.day==day7 and pendingDay.incomingCount==2 and pendingDay.sender==A.name.."-Realm")
    B.krt.sync:DeclinePendingDay()
    A.e.KWC.Net.CancelPrefix("KWCT",A.e.KWC.GuildScope())
    drain()
end
print("PASS: a pull reply is delivered while the responder's queue holds 300 to 350 guild items")
