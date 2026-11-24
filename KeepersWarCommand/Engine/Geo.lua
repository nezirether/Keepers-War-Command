-- KWC 2.0 location helpers (nonvisual). Coordinates are read only for the local
-- player, only from public map APIs, and never when values are secret.
-- Returns mapID, x, y (0..1) or nil.
local K=KWC
local G={};K.Geo=G
local function readable(v) return not (issecretvalue and issecretvalue(v)) end
function G.PlayerPosition()
 if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return nil end
 local ok,map=pcall(C_Map.GetBestMapForUnit,'player')
 if not ok or not readable(map) or type(map)~='number' then return nil end
 local ok2,pos=pcall(C_Map.GetPlayerMapPosition,map,'player')
 if not ok2 or not pos or not readable(pos) then return nil end
 local x,y
 if type(pos.GetXY)=='function' then
  local ok3,a,b=pcall(pos.GetXY,pos);if ok3 then x,y=a,b end
 else x,y=pos.x,pos.y end
 if not readable(x) or not readable(y) or type(x)~='number' or type(y)~='number' then return nil end
 if x<=0 or y<=0 or x>=1 or y>=1 then return nil end
 return map,x,y
end
function G.Format(x,y) return string.format('%.1f, %.1f',x*100,y*100) end
-- Sets the user waypoint (the player's own map pin). Returns true on success.
function G.DropPin(map,x,y)
 if type(map)~='number' or type(x)~='number' or type(y)~='number' then return false end
 if not C_Map or not C_Map.SetUserWaypoint or not UiMapPoint or not UiMapPoint.CreateFromCoordinates then return false end
 local ok=pcall(function()
  C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map,x,y))
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
 end)
 return ok
end
function G.CanDropPin() return C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates and true or false end
