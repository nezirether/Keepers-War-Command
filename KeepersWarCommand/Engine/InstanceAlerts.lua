-- Central policy for automatic, player-facing KWC alerts.
-- Automatic alerts (popups, banners, alert sounds, automatic chat and screen
-- notices) are allowed only when the client positively confirms the open world:
--   * IsInInstance() returns a readable boolean false and the readable type 'none';
--   * GetInstanceInfo() is available and confirms the readable type 'none'.
-- Anything else suppresses alerts: instances (dungeons, raids, battlegrounds and
-- other instance types), unavailable or throwing APIs, secret, nil or unexpected
-- values, contradictory results, and loading screens.
-- Suppressed alerts are dropped, never queued for later.
-- This policy only decides whether to notify. Data collection, guild sync,
-- statistics, manual commands, previews and the addon UI never consult it.
local K=KWC
local P={};K.InstanceAlerts=P
-- The epoch changes on every loading screen and whenever eligibility changes.
-- A delayed alert takes a token at its trigger; the token is false when the
-- trigger itself was not eligible, and a stale epoch drops it at emission.
local epoch,lastAllowed,loading=0,nil,false
local listeners={}
local function secret(value)
 if not issecretvalue then return false end
 local ok,result=pcall(issecretvalue,value)
 return not ok or result==true
end
-- Returns 'open', 'instance' or 'unknown'. Never raises.
local function evaluate()
 if type(IsInInstance)~='function' then return 'unknown' end
 local ok,inside,kind=pcall(IsInInstance)
 if not ok or secret(inside) or secret(kind) then return 'unknown' end
 if inside==true then return 'instance' end
 if inside~=false or kind~='none' then return 'unknown' end
 -- The cross-check is required: missing, throwing, secret or any type other
 -- than 'none' means the open world is not confirmed.
 if type(GetInstanceInfo)~='function' then return 'unknown' end
 local okInfo,_,instanceType=pcall(GetInstanceInfo)
 if not okInfo or secret(instanceType) or instanceType~='none' then return 'unknown' end
 return 'open'
end
-- Banners and other visible automatic alerts register here so they can be
-- dismissed the moment suppression begins.
local function notifySuppressed()
 for _,fn in ipairs(listeners) do pcall(fn) end
end
local function refresh()
 local state=loading and 'loading' or evaluate()
 local allowed=state=='open'
 if lastAllowed~=nil and allowed~=lastAllowed then epoch=epoch+1 end
 local began=lastAllowed==true and not allowed
 lastAllowed=allowed
 if began then notifySuppressed() end
 return state
end
-- Current state: 'open', 'instance', 'unknown' or 'loading'.
function P.State() return refresh() end
-- Token for an alert whose emission may be delayed. False when the trigger is
-- not eligible, so the alert can never be emitted later.
function P.Token()
 if refresh()~='open' then return false end
 return epoch
end
-- True only in the confirmed open world, outside a loading screen, and, when a
-- token is given, only if that token was eligible and no transition has
-- happened since. Call this immediately before emitting an automatic alert.
function P.Allowed(token)
 if token==false then return false end
 if refresh()~='open' then return false end
 return token==nil or token==epoch
end
-- fn() runs (protected) when automatic alerts stop being allowed.
function P.OnSuppressed(fn)
 if type(fn)=='function' then listeners[#listeners+1]=fn end
end
-- Diagnostics and tests.
function P.Status() return {state=refresh(),epoch=epoch,loading=loading} end
-- A loading screen suppresses immediately and invalidates every earlier token.
K.On('PLAYER_LEAVING_WORLD',function()
 loading=true
 epoch=epoch+1
 lastAllowed=false
 notifySuppressed()
end)
-- Alerts resume only once the client confirms the open world again.
K.On('PLAYER_ENTERING_WORLD',function()
 loading=false
 epoch=epoch+1
 refresh()
end)
K.On('ZONE_CHANGED_NEW_AREA',refresh)
