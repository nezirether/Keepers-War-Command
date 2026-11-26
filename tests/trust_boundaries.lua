-- Receiver trust checks carried over from the 1.x audit: attendance exchange,
-- future-stamped RSVP, cross-realm command spoofing and forged service records.
local network,packet,find=assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
local n=network(4,false)
local owner,peer,member=n.client(1),n.client(2),n.client(4)
local A,B=owner.e,peer.e
assert(A.KWC.RaidSignup.Create("Audit raid","Tomorrow"))
A.KWC.Operations.CreateCTA("[HIGH] Audit Zone - defend")
local rid=next(A.KWCDB.raidSignups.events)
local cid=A.KWCDB.ops[1].id
n.run(20)
local t=B.time()
packet(peer,"KWRS1",("RS|%s|%s|Attending|%d"):format(rid,member.name,t),member)
packet(peer,"KWRS1",("RS|%s|%s|Absent|%d"):format(rid,member.name,t+400),member)
assert(B.KWCDB.raidSignups.responses[rid][member.name].status=="Attending","future-stamped RSVP accepted")
packet(peer,"KWRS1",("RS|%s|%s|Absent|2147483647"):format(rid,owner.name),member)
local mine=B.KWCDB.raidSignups.responses[rid][owner.name]
assert(not mine or mine.status~="Absent","a member set another member's RSVP")
local entry=assert(find(B.KWCDB.ops,cid))
local foreign={name=owner.name.."-Foreign"}
packet(peer,"KWC4","E|"..cid.."|foreign|A|"..owner.name.."-Foreign|",foreign)
assert(not (entry.commandEvents or {}).foreign,"cross-realm name took command")
packet(peer,"KWC3","2;SERVICE;CACHEZONE,"..cid..","..owner.name..","..t,member)
assert(not B.KWC.GuildService.CTARecords(cid)[owner.name],"member relayed a service record")
assert(#n.errors()==0,n.errors()[1])
print("PASS: future and forged RSVPs, cross-realm command and forged service relay are refused")

-- Raid Tools attendance through its real handler registry.
local handlers,replies={},{}
local comm={
    RegisterHandler=function(_,kind,fn) handlers[kind]=fn end,
    Send=function(_,kind,data,channel,target) replies[#replies+1]={kind,data,channel,target} end,
    IsSenderPrivileged=function(_,sender) return sender=="Recorder" or sender=="Group Lead" end,
    -- The module keeps request targets lower-cased.
    GroupUnit=function(_,sender) return ({recorder="player",["group lead"]="raid1",["other member"]="raid2"})[sender:lower()] end,
}
local raid=setmetatable({
    KeepersRaidTools={Comms=comm,RosterValidation={}},
    KeepersRaidToolsAttendanceDB={["2026-11-13"]={Member={status=3}}},
    Ambiguate=function(sender) return sender end,
    UnitName=function() return "Recorder" end,
    time=function() return 1794592800 end,
},{__index=_G})
setfenv(assert(loadfile("KeepersWarCommand/Engine/RaidTools/Modules/Attendance/AttendanceSync.lua")),raid)()
local sync=raid.KeepersRaidTools.AttendanceSync
sync:RegisterHandlers()
local date="2026-11-13"
handlers.attPullRequest({day=date,request="1-1-111111"},"Outside Player","WHISPER")
handlers.attPullRequest({day=date,request="1-1-111111"},"Group Lead","RAID")
assert(#replies==0)
handlers.attPullRequest({day=date,request="1-1-111111"},"Group Lead","WHISPER")
assert(replies[1][1]=="attPullResponse" and replies[1][4]=="Group Lead")
handlers.attDayPush({day=date,records={Member=1}},"Other Member","RAID")
handlers.attDayPush({day=date,records={Member=1}},"Group Lead","WHISPER")
handlers.attPullResponse({day=date,records={Member=1}},"Group Lead","WHISPER")
assert(not sync:GetPendingDay())
sync:RequestDay("Group Lead",date)
local request=replies[#replies][2].request
handlers.attPullResponse({day=date,request=request,records={Member=1}},"Other Member","WHISPER")
handlers.attPullResponse({day="2026-11-12",request=request,records={Member=1}},"Group Lead","WHISPER")
handlers.attPullResponse({day=date,request="2-2-222222",records={Member=1}},"Group Lead","WHISPER")
assert(not sync:GetPendingDay())
handlers.attPullResponse({day=date,request=request,records={Member=1}},"Group Lead","WHISPER")
assert(sync:GetPendingDay().sender=="Group Lead")
assert(sync:AcceptPendingDay() and raid.KeepersRaidToolsAttendanceDB[date].Member.status==1)
handlers.attPullResponse({day=date,request=request,records={Member=3}},"Group Lead","WHISPER")
assert(not sync:GetPendingDay())
print("PASS: attendance rejects unsolicited and mismatched responses, unauthorized requests and pushes, and replay")
