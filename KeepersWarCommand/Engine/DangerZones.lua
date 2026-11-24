-- Danger Zones: local, read-only summary of KWCDB.worldPvPDeaths by zone.
-- No network traffic, chat output, event registration or SavedVariables writes.
-- Records keep their existing schema; timestamps come from the stored `at`
-- string ('%Y-%m-%d %H:%M', local time, written by K.Now()).
local K=KWC
local D={};K.DangerZones=D

D.MAX_RECORDS=75   -- matches the WorldPvPDeaths history cap
D.MAX_ZONES=10     -- hard ceiling on returned rows, whatever the caller asks
D.WINDOWS={3600,86400}
local DAYS_IN_MONTH={31,28,31,30,31,30,31,31,30,31,30,31}

local function accessible(value)
 if issecretvalue and issecretvalue(value) then return nil end
 return value
end

local function zoneName(value)
 value=accessible(value)
 if type(value)~='string' then return nil end
 value=value:gsub('[%c|]',' '):match('^%s*(.-)%s*$')
 if value=='' or value=='?' then return nil end
 return value:sub(1,65)
end

-- Parse a K.Now() stamp into epoch seconds. Returns nil for anything else.
function D.ParseStamp(at)
 at=accessible(at)
 if type(at)~='string' or #at>16 then return nil end
 local y,mo,d,h,mi=at:match('^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d)$')
 if not y then return nil end
 y,mo,d,h,mi=tonumber(y),tonumber(mo),tonumber(d),tonumber(h),tonumber(mi)
 local days=DAYS_IN_MONTH[mo]
 if y==0 or not days or d<1 or h>23 or mi>59 then return nil end
 if mo==2 and y%4==0 and (y%100~=0 or y%400==0) then days=29 end
 if d>days then return nil end
 if type(time)~='function' then return nil end
 local ok,stamp=pcall(time,{year=y,month=mo,day=d,hour=h,min=mi,sec=0})
 if ok and type(stamp)=='number' then return stamp end
 return nil
end

local function confirmedKill(killer)
 killer=accessible(killer)
 return type(killer)=='string' and killer:find('^Killed by: ')~=nil
end

-- Summarize up to MAX_RECORDS records into at most `limit` zones that had a
-- death within `window` seconds of `now`. Sorted by count, then most recent,
-- then zone name, so equal inputs always produce equal output.
function D.Summarize(records,now,window,limit)
 if type(records)~='table' or type(now)~='number' or type(window)~='number' or window<=0 then return {} end
 limit=tonumber(accessible(limit))
 if not limit or limit~=limit or math.abs(limit)==math.huge then limit=5 end
 limit=math.max(1,math.min(D.MAX_ZONES,math.floor(limit)))
 local byZone,list={},{}
 for i=1,math.min(#records,D.MAX_RECORDS) do
  local record=records[i]
  if type(record)=='table' then
   local zone=zoneName(record.zone)
   local stamp=zone and D.ParseStamp(record.at)
   -- Minute-resolution stamps never exceed now; allow one minute of clock skew.
   if stamp and stamp<=now+60 and now-stamp<=window then
    local entry=byZone[zone]
    if not entry then
     entry={zone=zone,count=0,confirmed=0,last=stamp,lastAt=record.at}
     byZone[zone]=entry
     list[#list+1]=entry
    end
    entry.count=entry.count+1
    if confirmedKill(record.killer) then entry.confirmed=entry.confirmed+1 end
    if stamp>entry.last then entry.last,entry.lastAt=stamp,record.at end
   end
  end
 end
 table.sort(list,function(a,b)
  if a.count~=b.count then return a.count>b.count end
  if a.last~=b.last then return a.last>b.last end
  return a.zone<b.zone
 end)
 for i=#list,limit+1,-1 do list[i]=nil end
 return list
end

function D.WindowLabel(window)
 if window==3600 then return 'last 1 hour' end
 if window==86400 then return 'last 24 hours' end
 return 'last '..math.floor((tonumber(window) or 0)/60)..' minutes'
end

-- One display line per zone; plain ASCII so every client font can render it.
function D.FormatLine(entry)
 local deaths=entry.count==1 and '1 death' or (entry.count..' deaths')
 local line=entry.zone..'  |  '..deaths
 if entry.confirmed>0 then line=line..'  |  '..entry.confirmed..' confirmed kill'..(entry.confirmed==1 and '' or 's') end
 local clock=type(entry.lastAt)=='string' and entry.lastAt:match(' (%d%d:%d%d)$')
 if clock then line=line..'  |  last '..clock end
 return line
end
