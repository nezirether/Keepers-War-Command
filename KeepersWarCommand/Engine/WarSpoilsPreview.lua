-- Isolated in-memory comparisons. No guild ledger, gameplay actions or SavedVariables.
local K=KWC
local W={}
K.WarSpoilsPreview=W
W.policies={
 {id='rotation',label='Oldest award'},
 {id='lifetime',label='Fewest wins'},
 {id='balance',label='Highest balance'},
}
local baseline={
 {name='Thane',points=10,wins=6,last=-6},
 {name='Ember',points=5,wins=0,last=0},
 {name='Sable',points=5,wins=0,last=1},
}
local raids={
 {label='Opening raid',bosses=1,attend={1,2},claims={{1,2},{1,2}}},
 {label='Ember absent',bosses=2,attend={1},claims={{1}}},
 {label='Sable joins',bosses=1,attend={1,2,3},claims={{1,2,3},{1,3},{2,3}}},
 {label='Thane absent',bosses=0,attend={2,3},claims={{2,3},{2,3},{2}}},
 {label='Final raid',bosses=2,attend={1,2,3},claims={{1,2,3},{1,2,3}}},
}
local function score(policy,r)
 if policy=='rotation' then return r.last
 elseif policy=='lifetime' then return r.wins end
 return -r.points
end

function W.Compare(policy)
 assert(policy=='rotation' or policy=='lifetime' or policy=='balance','Unknown WarSpoils proposal')
 local results={raiders={},raids={},waste=0,spent=0}
 local order=2
 for i,r in ipairs(baseline) do
  results.raiders[i]={name=r.name,points=r.points,wins=r.wins,last=r.last,id=i,earned=0,contested=0,attended=0}
 end
 for _,raid in ipairs(raids) do
  local outcome={label=raid.label,awards={}}
  results.raids[#results.raids+1]=outcome
  for _,id in ipairs(raid.attend) do
   local r=results.raiders[id]
   local offered=1+raid.bosses
   local accepted=math.min(10-r.points,offered)
   r.points=r.points+accepted;r.earned=r.earned+accepted;r.attended=r.attended+1
   results.waste=results.waste+offered-accepted
  end
  for _,claims in ipairs(raid.claims) do
   local eligible={}
   for _,id in ipairs(claims) do
    local r=results.raiders[id]
    if r.points>=3 then eligible[#eligible+1]=r end
   end
   table.sort(eligible,function(a,b)
    local x,y=score(policy,a),score(policy,b)
    if x~=y then return x<y end
    if a.last~=b.last then return a.last<b.last end
    return a.id<b.id
   end)
   local winner=eligible[1]
   if winner then
    local cost=#eligible>1 and 3 or 0
    winner.points=winner.points-cost
    winner.contested=winner.contested+(cost>0 and 1 or 0)
    order=order+1;winner.last=order;winner.wins=winner.wins+1
    results.spent=results.spent+cost
    outcome.awards[#outcome.awards+1]=winner.name..(cost>0 and ' (-3)' or ' (free)')
   else outcome.awards[#outcome.awards+1]='Passed' end
  end
 end
 return results
end
