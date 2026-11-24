-- Exercise the real handler registry and production communication dispatch.
local function client(name)
    local env=setmetatable({
        KeepersRaidTools={RosterValidation={}},
        KeepersRaidToolsAttendanceDB={},
        LibStub=function(_, silent) if not silent then return {} end end,
        Ambiguate=function(sender) return sender:match("^[^-]+") end,
        time=function() return 1794592800 end,
        IsInGroup=function() return true end,
        IsInRaid=function() return true end,
        UnitFullName=function(unit)
            if unit=="raid1" then return "Group Lead","Realm" end
            if unit=="raid2" then return "Recorder","Realm" end
            if unit=="raid3" then return "Recorder","OtherRealm" end
        end,
        UnitName=function(unit) if unit=="player" then return name end end,
        UnitIsGroupLeader=function(unit) return unit=="raid1" end,
        UnitIsGroupAssistant=function() return false end,
    },{__index=_G})
    local folder="KeepersWarCommand/Modules/RaidTools/"
    for _,file in ipairs({"Comms.lua","Modules/Attendance/AttendanceSync.lua"}) do
        setfenv(assert(loadfile(folder..file)),env)()
    end
    local comms=env.KeepersRaidTools.Comms
    local sync=env.KeepersRaidTools.AttendanceSync
    local sent={}
    comms.Encode=function(_,message) return message end
    comms.Decode=function(_,message) return true,message end
    comms.sendFunc=function(message,channel,target)
        sent[#sent+1]={message=message,channel=channel,target=target}
    end
    sync:RegisterHandlers()
    return env,comms,sync,sent
end

local holder, HC, _, replies=client("Recorder")
local receiver, RC, RS, requests=client("Group Lead")
local day="2026-11-13"
holder.KeepersRaidToolsAttendanceDB[day]={Member=3}
receiver.KeepersRaidToolsAttendanceDB[day]={Member=1}
local forged={type="attPullRequest",data={day=day,request="1-1-111111"}}
HC:Dispatch(forged,"Outside Player-Realm","WHISPER")
HC:Dispatch(forged,"Group Lead-OtherRealm","WHISPER")
HC:Dispatch(forged,"Group Lead-Realm","GUILD")
assert(#replies==0)
assert(not RS:RequestDay("Recorder",day)) -- same short name on two realms
assert(RS:RequestDay("Recorder-Realm",day))
local request=requests[1]
HC:Dispatch(request.message,"Group Lead-Realm",request.channel)
local reply=assert(replies[1])
-- The reply path must work with an injected transport whose encoder returns a table.
assert(RS.ReplyPieces("attPullResponse",{day=day})==1,"a non-string encoding counts as one piece")
assert(reply.target=="Group Lead-Realm" and reply.message.data.request==request.message.data.request)
RC:Dispatch(reply.message,"Recorder-OtherRealm","WHISPER")
RC:Dispatch(reply.message,"Recorder-Realm","RAID")
local stale={type="attPullResponse",data={day=day,request="2-2-222222",records={Member=4}}}
RC:Dispatch(stale,"Recorder-Realm","WHISPER")
assert(not RS:GetPendingDay() and receiver.KeepersRaidToolsAttendanceDB[day].Member==1)
RC:Dispatch(reply.message,"Recorder-Realm",reply.channel)
assert(RS:GetPendingDay().incomingCount==1)
assert(RS:AcceptPendingDay() and receiver.KeepersRaidToolsAttendanceDB[day].Member.status==3)
RC:Dispatch(reply.message,"Recorder-Realm",reply.channel)
assert(not RS:GetPendingDay())
print("PASS: attendance recovery from a group peer, with request correlation and explicit acceptance")
