-- War Command 1.4.0 DEV2: independent, opt-in guild scouting.
-- WE uses OV for objective context, not as a player-sighting feed.
local K=KWC
local A={};K.AutoScout=A
local PREFIX='KWCS1'
local seen={};local lastSend=0
local function enabled() return KWCDB and KWCDB.settings and KWCDB.settings.autoScout==true end
local function safe(s,n) return K.Clean(s,n):gsub(';',' '):gsub('%%',' ') end
local function record(name,zone,source,author,stamp,remote)
 if not KWCDB or not name or name=='' or not zone or zone=='' then return end
 local key=name:lower()..'@'..zone:lower()
 local now=time()
 if seen[key] and now-seen[key]<45 then return end
 seen[key]=now
 local t=KWCDB.scoutReports
 table.insert(t,1,{zone=zone,enemy=name,count=1,notes=(remote and 'Guild sighting' or 'Auto detected')..' ('..source..')',author=author,created=stamp or now,when=date('%Y-%m-%d %H:%M',stamp or now),auto=true})
 while #t>75 do table.remove(t) end
 if K.UI and K.UI.Refresh then K.UI.Refresh() end
end
local function observe(unit)
 if not enabled() or not UnitExists(unit) or not UnitIsPlayer(unit) or not UnitIsEnemy('player',unit) then return end
 if UnitIsDead(unit) then return end
 local name=UnitName(unit)
 local zone=GetZoneText and GetZoneText() or ''
 if not name or name=='' or zone=='' then return end
 local now=time();local key=name:lower()..'@'..zone:lower()
 if seen[key] and now-seen[key]<45 then return end
 record(name,zone,'local',UnitName('player'),now,false)
 if now-lastSend<3 or not IsInGuild() then return end
 lastSend=now
 if C_ChatInfo and C_ChatInfo.SendAddonMessage then
  local msg='S;'..safe(name,55)..';'..safe(zone,55)..';'..tostring(now)
  if #msg<=225 then pcall(C_ChatInfo.SendAddonMessage,PREFIX,msg,'GUILD') end
 end
end
K.On('PLAYER_TARGET_CHANGED',function() observe('target') end)
K.On('UPDATE_MOUSEOVER_UNIT',function() observe('mouseover') end)
K.On('NAME_PLATE_UNIT_ADDED',function(unit) if type(unit)=='string' then observe(unit) end end)
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~=PREFIX or channel~='GUILD' or not enabled() then return end
 if type(sender)~='string' or not K.IsMember(sender) then return end
 if type(msg)~='string' or #msg>225 then return end
 local name,zone,stamp=msg:match('^S;([^;]+);([^;]+);(%d+)$')
 stamp=tonumber(stamp)
 if not name or #name>55 or #zone>55 or not stamp or math.abs(time()-stamp)>120 then return end
 if not name:match('^[%w%-]+$') then return end
 record(name,zone,'guild',sender,stamp,true)
end)
function A.SetEnabled(on)
 if not KWCDB then return end
 KWCDB.settings.autoScout=on==true
 K.Say('Automatic guild scouting '..(on and 'ON' or 'OFF')..'.')
end
function A.Status() return enabled() end
function A.Info()
 local o=rawget(_G,'Overlord')
 local registry=type(o)=='table' and type(rawget(o,'Fronts'))=='table' and rawget(rawget(o,'Fronts'),'Registry')
 return 'OV objective registry: '..(type(registry)=='table' and 'available' or 'unavailable')..'; WE: '..(C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded('WarEffortScout') and 'loaded' or 'not loaded')
end
