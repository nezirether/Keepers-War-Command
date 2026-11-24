-- Run from the repository root with Lua 5.1: lua tests/danger_zones.lua
local secret={}
local env=setmetatable({KWC={},time=os.time,issecretvalue=function(v) return v==secret end},{__index=_G})
setfenv(assert(loadfile('KeepersWarCommand/DangerZones.lua')),env)()
local D=assert(env.KWC.DangerZones,'module registers K.DangerZones')

-- UI.lua's render() sits at the Lua 5.1 / LuaJIT limit of 60 upvalues. The
-- Danger Zones window state must not add a file-level local, or UI.lua fails
-- to compile and the whole War Command window is lost.
local uiChunk,uiError=loadfile('KeepersWarCommand/UI.lua')
assert(uiChunk,'UI.lua must compile (check the 60-upvalue limit in render): '..tostring(uiError))
print('PASS: UI.lua compiles within Lua 5.1 limits')

local now=os.time({year=2026,month=11,day=14,hour=12,min=0,sec=0})
local function stamp(secondsAgo) return os.date('%Y-%m-%d %H:%M',now-secondsAgo) end
local function rec(zone,secondsAgo,killer) return {victim='V',zone=zone,at=stamp(secondsAgo),killer=killer or 'Suspected: X'} end

-- ParseStamp round-trips K.Now() output and rejects malformed values.
assert(D.ParseStamp(stamp(0))==now)
assert(D.ParseStamp(stamp(600))==now-600)
assert(D.ParseStamp(nil)==nil)
local badStamps={42,'',secret,'now','2026-13-01 10:00','2026-00-01 10:00','2026-11-00 10:00','2026-11-14 24:00',
 '2026-11-14 10:60','2026-11-14 10:00 ','x2026-11-14 10:00','2026-11-14','2026-11-14 1:00',
 '2026-11-31 10:00','2026-04-31 10:00','2026-02-29 10:00','2024-02-30 10:00',
 '2100-02-29 10:00','0000-01-01 10:00',{}}
for i=1,#badStamps do
 assert(D.ParseStamp(badStamps[i])==nil,'rejects bad stamp #'..i)
end
assert(D.ParseStamp('2024-02-29 10:00')==os.time({year=2024,month=2,day=29,hour=10,min=0,sec=0}))
local clock=env.time
env.time=function(parts) return parts.day end
assert(D.ParseStamp('2000-02-29 10:00')==29)
assert(D.ParseStamp('1900-02-29 10:00')==nil)
env.time=clock
print('PASS: stamp parsing accepts K.Now() format and rejects malformed or secret values')

-- Grouping, window filtering, ordering and confirmed-kill counts.
local records={
 rec('Hillsbrad Foothills',60,'Killed by: Rogue'),
 rec('Arathi Highlands',120),
 rec('Hillsbrad Foothills',300,'Killed by: Mage'),
 rec('Hillsbrad Foothills',1800),
 rec('Stranglethorn Vale',3000),
 rec('Arathi Highlands',3500),
 rec('Ashenvale',7200,'Killed by: Hunter'),
 rec('Ashenvale',80000),
 rec('Desolace',90000),
}
local hour=D.Summarize(records,now,3600,5)
assert(#hour==3)
assert(hour[1].zone=='Hillsbrad Foothills' and hour[1].count==3 and hour[1].confirmed==2)
assert(hour[1].last==now-60 and hour[1].lastAt==stamp(60))
assert(hour[2].zone=='Arathi Highlands' and hour[2].count==2 and hour[2].confirmed==0)
assert(hour[3].zone=='Stranglethorn Vale' and hour[3].count==1)
local day=D.Summarize(records,now,86400,5)
-- Arathi and Ashenvale both have 2; Arathi's latest death is more recent.
assert(#day==4 and day[2].zone=='Arathi Highlands' and day[4].zone=='Stranglethorn Vale')
assert(day[3].zone=='Ashenvale' and day[3].count==2 and day[3].confirmed==1)
for _,row in ipairs(day) do assert(row.zone~='Desolace','records older than the window are excluded') end
print('PASS: grouping by zone, 1h and 24h windows, count/recency ordering, confirmed kills')

-- Deterministic tie-breaks: same count and same recency fall back to zone name.
local ties=D.Summarize({rec('Zeta',120),rec('Alpha',120),rec('Mid',60)},now,3600,5)
assert(ties[1].zone=='Mid' and ties[2].zone=='Alpha' and ties[3].zone=='Zeta')
print('PASS: deterministic tie ordering')

-- Limits: caller limit, hard ceiling, and only the first 75 records are read.
local many={}
for i=1,20 do many[i]=rec('Zone'..i,i*10) end
assert(#D.Summarize(many,now,3600,5)==5)
assert(#D.Summarize(many,now,3600,500)==D.MAX_ZONES)
assert(#D.Summarize(many,now,3600,0)==1)
assert(#D.Summarize(many,now,3600,-3)==1)
assert(#D.Summarize(many,now,3600,3.9)==3)
assert(#D.Summarize(many,now,3600)==5)
for _,limit in ipairs({'bad','nan',0/0,math.huge,-math.huge,{},secret}) do
 assert(#D.Summarize(many,now,3600,limit)==5,'invalid limits use the five-zone default')
end
local overflow={}
for i=1,75 do overflow[i]=rec('Inside',30) end
overflow[76]=rec('Beyond cap',30)
local capped=D.Summarize(overflow,now,3600,5)
assert(#capped==1 and capped[1].zone=='Inside' and capped[1].count==75)
print('PASS: result limit, hard ceiling and 75-record read cap')

-- Malformed input never raises and is skipped.
local mixed={
 'not a table',
 {zone=nil,at=stamp(10)},
 {zone='',at=stamp(10)},
 {zone='?',at=stamp(10)},
 {zone=secret,at=stamp(10)},
 {zone='Good',at=secret},
 {zone='Good',at='now'},
 {zone='Good',at=nil},
 {zone='Future',at=stamp(-7200)},
 {zone='Bad|cffff0000Zone\n',at=stamp(10),killer=secret},
 rec('Good',10),
}
local cleaned=D.Summarize(mixed,now,3600,5)
assert(#cleaned==2)
local seen={}
for _,row in ipairs(cleaned) do seen[row.zone]=row end
assert(seen.Good and seen.Good.count==1)
assert(seen['Bad cffff0000Zone'] and seen['Bad cffff0000Zone'].confirmed==0,'secret killer is not counted as confirmed')
for name in pairs(seen) do
 assert(not name:find('[%c|]'),'zone names are stripped of control and escape characters')
end
assert(not seen.Future,'records far in the future are ignored')
for _,args in ipairs({{nil,now,3600},{{},nil,3600},{{},now,0},{{},now,-5},{'x',now,3600}}) do
 local result=D.Summarize(args[1],args[2],args[3],5)
 assert(type(result)=='table' and #result==0)
end
local noClock=setmetatable({KWC={}},{__index=_G})
noClock.time=nil
setfenv(assert(loadfile('KeepersWarCommand/DangerZones.lua')),noClock)()
assert(noClock.KWC.DangerZones.ParseStamp(stamp(0))==nil,'missing time() is handled')
print('PASS: malformed, secret, future and missing records are skipped without errors')

-- Read-only: summarizing never mutates the stored records.
local before=#records
local first=records[1]
D.Summarize(records,now,86400,5)
assert(#records==before and records[1]==first and records[1].ts==nil and records[1].zone=='Hillsbrad Foothills')
print('PASS: stored records are not modified')

-- Display text.
assert(D.FormatLine(hour[1])=='Hillsbrad Foothills  |  3 deaths  |  2 confirmed kills  |  last 11:59')
assert(D.FormatLine(hour[3])=='Stranglethorn Vale  |  1 death  |  last 11:10')
assert(D.FormatLine({zone='Solo',count=1,confirmed=1,lastAt=stamp(0)})=='Solo  |  1 death  |  1 confirmed kill  |  last 12:00')
assert(D.WindowLabel(3600)=='last 1 hour' and D.WindowLabel(86400)=='last 24 hours')
print('PASS: display formatting')
