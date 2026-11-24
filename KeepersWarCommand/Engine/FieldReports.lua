-- v1.4.0 development module. Scout reports and AARs are local-only until a
-- separate, tested guild sync protocol is implemented. Existing CTA sync is unchanged.
local K=KWC
local W={}
K.WarRoom=W
local function clean(s,n) return K.Clean(s,n) end
function W.Active()
 local out={}
 for _,e in ipairs(KWCDB.ops or {}) do
  if (e.status or 'ACTIVE')=='ACTIVE' then out[#out+1]=e end
 end
 table.sort(out,function(a,b)return (a.created or 0)>(b.created or 0) end)
 return out
end
function W.Roster(e)
 local coming,maybe,busy=0,0,0
 for _,r in pairs((KWCDB.responses or {})[e.id] or e.responses or {}) do
  local status=type(r)=='table' and (r.status or r.response) or r
  if status=='Coming' then coming=coming+1 elseif status=='Maybe' then maybe=maybe+1 elseif status=='Busy' then busy=busy+1 end
 end
 return coming,maybe,busy
end
function W.ReportScout(zone,enemy,count,notes)
 zone=clean(zone,55);enemy=clean(enemy,60);notes=clean(notes,100)
 count=tonumber(count)
 if zone=='' or enemy=='' or not count or count<0 or count>999 or count~=math.floor(count) then
  K.Say('Scout report needs zone, enemy description and a count (0-999).');return false
 end
 local t=KWCDB.scoutReports
 table.insert(t,1,{zone=zone,enemy=enemy,count=count,notes=notes,author=UnitName('player'),created=time(),when=K.Now()})
 while #t>75 do table.remove(t) end
 K.Log('SCOUT',zone..' - '..enemy..' x'..count)
 K.Say('Scout report saved locally (not yet guild-synced).')
 K.UI.Refresh();return true
end
function W.SaveAAR(ctaId,result,kills,notes)
 result=clean(result,35);notes=clean(notes,140)
 kills=tonumber(kills)
 if ctaId=='' or result=='' or not kills or kills<0 or kills>99999 or kills~=math.floor(kills) then
  K.Say('Select an operation, outcome and valid estimated kills.');return false
 end
 local entry
 for _,e in ipairs(KWCDB.ops or {}) do if e.id==ctaId then entry=e;break end end
 if not entry then K.Say('CTA not found.');return false end
 local t=KWCDB.afterAction
 table.insert(t,1,{ctaId=ctaId,title=clean(entry.text,125),result=result,kills=kills,notes=notes,author=UnitName('player'),created=time(),when=K.Now()})
 while #t>75 do table.remove(t) end
 K.Log('AAR',result..' - '..entry.text)
 K.Say('After-action report saved locally (not yet guild-synced).')
 K.UI.Refresh();return true
end
