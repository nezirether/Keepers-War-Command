-- Quality of Life: local milestones and opt-in notification settings.
-- No new addon messages, no alteration to guild sync, PvP totals or shared records.
local K=KWC
local Q={};K.QOL=Q
local function state()
 if not KWCDB then return nil end
 KWCDB.qol=KWCDB.qol or {achievements={},counts={}}
 KWCDB.qol.achievements=KWCDB.qol.achievements or {}
 KWCDB.qol.counts=KWCDB.qol.counts or {}
 return KWCDB.qol
end
-- 500 deterministic, locally tracked achievements: 10 tracks x 50 milestones.
-- The client records five kinds of user actions; these are not verified combat feats.
local tracks={
 {key='cta',kind='CTA',title='Warcaller',category='Calls to Arms',step=1,verb='CTAs posted'},
 {key='ctaLegend',kind='CTA',title='Battle Marshal',category='Calls to Arms',step=5,verb='CTAs posted'},
 {key='bounty',kind='BOUNTY',title='Bounty Broker',category='Bounty Board',step=1,verb='bounties posted'},
 {key='bountyLegend',kind='BOUNTY',title='Gold on Their Heads',category='Bounty Board',step=5,verb='bounties posted'},
 {key='claim',kind='CLAIM',title='Skull Collector',category='Bounty Claims',step=1,verb='claims submitted'},
 {key='claimLegend',kind='CLAIM',title='Trogdor\'s Executioner',category='Bounty Claims',step=5,verb='claims submitted'},
 {key='sighting',kind='SIGHTING',title='Eyes of Trogdor',category='Scouting',step=1,verb='sightings reported'},
 {key='sightingLegend',kind='SIGHTING',title='Shadow Watcher',category='Scouting',step=5,verb='sightings reported'},
 {key='response',kind='RESPONSE',title='First to the Fight',category='Reinforcements',step=1,verb='Coming responses'},
 {key='responseLegend',kind='RESPONSE',title='Shield of the Horde',category='Reinforcements',step=5,verb='Coming responses'},
}
local numerals={'I','II','III','IV','V','VI','VII','VIII','IX','X'}
local function numeral(n)
 local a=math.floor((n-1)/10);return (a>0 and string.rep('X',a) or '')..numerals[((n-1)%10)+1]
end
local catalog={}
for _,track in ipairs(tracks) do
 for level=1,50 do
  catalog[#catalog+1]={id=track.key..'_'..level,title=track.title..' '..numeral(level),category=track.category,kind=track.kind,required=level*track.step,description='Record '..(level*track.step)..' '..track.verb}
 end
end
-- Lifetime honorable-kill achievements, sourced from the player's own PvP API snapshot.
-- Existing 500 local-action achievements are retained unchanged.
local killMilestones={1,5,10,25,50,75,100,150,200,250,300,350,400,450,500,600,750,1000,1250,1500,1750,2000,2500,3000,4000,5000,7500,10000,15000,20000,25000,30000,40000,50000,75000,100000}
for _,n in ipairs(killMilestones) do
 catalog[#catalog+1]={id='honor_'..n,title='Blood of Trogdor - '..n..' HKs',category='PvP Kills',kind='HONOR',required=n,description='Reach '..n..' lifetime honorable kills',points=10}
end
function Q.HonorTotal()
 if not KWCDB or not KWCDB.pvp or not K.PvP then return 0 end
 local name=K.PvP.PlayerName()
 local p=KWCDB.pvp[name]
 return (p and p.honor and tonumber(p.honor.lifetime)) or 0
end
function Q.UpdateHonor()
 local d=state();if not d then return end
 local current=Q.HonorTotal()
 for _,a in ipairs(catalog) do
  if a.kind=='HONOR' and current>=a.required and not d.achievements[a.id] then
   d.achievements[a.id]={date=K.Now(),label=a.title}
   K.Say('Achievement unlocked: '..a.title)
  end
 end
end
function Q.Points()
 local d=state();if not d then return 0 end
 local points=0
 for _,a in ipairs(catalog) do if d.achievements[a.id] then points=points+(a.points or 5) end end
 return points
end
function Q.BroadcastPoints(force)
 if not KWCDB or not K.Send then return end
 Q.UpdateHonor()
 local points=Q.Points()
 local now=time()
 if force or Q.lastPoints~=points or not Q.lastSent or now-Q.lastSent>600 then
  if K.Send('ACHPTS',tostring(points)) then Q.lastPoints=points;Q.lastSent=now end
 end
end
K.On('PLAYER_PVP_KILLS_CHANGED',function() Q.BroadcastPoints() end)
K.On('HONOR_XP_UPDATE',function() Q.BroadcastPoints() end)
K.On('PLAYER_ENTERING_WORLD',function()
 if C_Timer and C_Timer.After then C_Timer.After(4,function() Q.BroadcastPoints(true) end)
 else Q.BroadcastPoints(true) end
end)
K.On('CHAT_MSG_ADDON',function(prefix,msg,channel,sender)
 if prefix~='KWC3' or channel~='GUILD' or type(msg)~='string' or not K.IsMember(sender) then return end
 local value=msg:match('^2;ACHPTS;(%d+)$')
 if not value then return end
 local points=tonumber(value)
 if not points or points>100000 or not KWCDB or not KWCDB.pvp then return end
 local name=sender:match('^[^-]+')
 if not name or (K.PvP and name:lower()==K.PvP.PlayerName():lower()) then return end
 local p=KWCDB.pvp[name] or {}
 p.achievementPoints=points
 KWCDB.pvp[name]=p
 if K.UI and K.UI.Refresh then K.UI.Refresh() end
end)
function Q.Catalog() return catalog end
function Q.Count(kind)
 if kind=='HONOR' then return Q.HonorTotal() end
 local d=state();return (d and tonumber(d.counts[kind])) or 0
end
function Q.Unlocked(id)
 local d=state();return d and d.achievements[id] or nil
end
function Q.Record(kind)
 local d=state();if not d then return end
 d.counts[kind]=(d.counts[kind] or 0)+1
 for _,a in ipairs(catalog) do
  if a.kind==kind and d.counts[kind]>=a.required and not d.achievements[a.id] then
   d.achievements[a.id]={date=K.Now(),label=a.title}
   K.Say('Achievement unlocked: '..a.title)
  end
 end
 Q.BroadcastPoints()
end
function Q.List()
 local out={}
 for _,a in ipairs(catalog) do if Q.Unlocked(a.id) then out[#out+1]=a end end
 return out
end
function Q.Summary()
 local n=0;for _,a in ipairs(catalog) do if Q.Unlocked(a.id) then n=n+1 end end
 return n,#catalog
end
function Q.Enabled(name)
 return not KWCDB or not KWCDB.settings or KWCDB.settings[name]~=false
end
function Q.Toggle(name)
 if not KWCDB then return end
 KWCDB.settings[name]=not Q.Enabled(name)
 K.Say(name..': '..(Q.Enabled(name) and 'ON' or 'OFF'))
end
-- Wrap user-initiated operations, recording only successful local state changes.
-- This is intentionally local fun progression, not a guild-wide verified score.
local O=K.Operations
local function wrap(method,kind)
 local original=O[method];if type(original)~='function' then return end
 O[method]=function(...)
  local before=kind=='CTA' and #(KWCDB.ops or {}) or kind=='BOUNTY' and #(KWCDB.bounties or {})
  local result=original(...)
  if before and ((kind=='CTA' and #(KWCDB.ops or {})>before) or (kind=='BOUNTY' and #(KWCDB.bounties or {})>before)) then Q.Record(kind) end
  return result
 end
end
wrap('CreateCTA','CTA');wrap('DetailedCTA','CTA');wrap('AddBounty','BOUNTY');wrap('QuickBounty','BOUNTY')
local originalClaim=O.ClaimBounty
if originalClaim then O.ClaimBounty=function(id,...)
 local before;for _,b in ipairs(KWCDB.bounties or {}) do if b.id==id then before=(function() local n=0;for _ in pairs(b.claims or {}) do n=n+1 end;return n end)() end end
 local result=originalClaim(id,...)
 for _,b in ipairs(KWCDB.bounties or {}) do if b.id==id and before and (function() local n=0;for _ in pairs(b.claims or {}) do n=n+1 end;return n end)()>before then Q.Record('CLAIM') end end
 return result
end end
local originalSighting=O.AddSighting
if originalSighting then O.AddSighting=function(id,...)
 local before;for _,b in ipairs(KWCDB.bounties or {}) do if b.id==id then before=#(b.sightings or {}) end end
 local result=originalSighting(id,...)
 for _,b in ipairs(KWCDB.bounties or {}) do if b.id==id and before and #(b.sightings or {})>before then Q.Record('SIGHTING') end end
 return result
end end
local originalRespond=O.Respond
if originalRespond then O.Respond=function(id,status,...)
 local me=UnitName('player') or '';local before=(KWCDB.responses or {})[id] and KWCDB.responses[id][me]
 local result=originalRespond(id,status,...)
 local after=(KWCDB.responses or {})[id] and KWCDB.responses[id][me]
 if after and after~=before and after=='Coming' then Q.Record('RESPONSE') end
 return result
end end
