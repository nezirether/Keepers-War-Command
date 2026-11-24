-- War Room page: World PvP. Guild kill and guildmate death feeds with honest
-- evidence labels, danger zones, local scout reports and manual death reports.
local K=KWC
local Kit,S,P,W=K.Kit,K.WarRoomSkin,K.WarRoomPages,K.WarRoom2
local OWNER=S.OWNER

local page={id='pvp',title='World PvP',subtitle='Open-world kills, guildmate deaths and enemy scouting.',group='ops'}
local state={feed='ALL',query=''}
local list,side

-- Evidence wording: confirmed (death recap named the killer), suspected
-- (recap evidence without a confirmed name), reported (victim's manual report),
-- unidentified. Never upgrades a suspicion to a confirmation.
local function evidence(r)
 local k=tostring(r.killer or '')
 local c=k:match('^Killed by: (.+)');if c then return 'Confirmed killer: '..c,'danger',c end
 local s=k:match('^Suspected: (.+)');if s then return 'Suspected attacker: '..s,'warn',s end
 if k=='Unknown Alliance attacker' or k=='Unidentified Alliance attacker' or k=='' then return 'Attacker unidentified','faint' end
 return 'Reported by victim: '..k,'warn',k
end

local function rows()
 local out={}
 if state.feed~='DEATHS' then
  for _,r in ipairs(KWCDB.worldPvPKills or {}) do
   local t=Kit.StampEpoch(r.at) or 0
   local count=r.count or 1
   local credit=count==0 and 'Killing blow (no honor)' or count>1 and (count..' honorable kills') or 'Honorable kill'
   local text=P.Short(r.killer)..(r.victim and (' killed '..r.victim) or ' reported a PvP kill')
   if P.Matches(text..' '..tostring(r.zone),state.query) then
    out[#out+1]={at=t,kind='kill',title=text,sub=tostring(r.zone or '?')..'   '..S.Code('faint')..credit..(r.method and count>0 and (' / '..r.method) or '')..(r.victim and '' or ' - victim not identified')..'|r',tone='good'}
   end
  end
 end
 if state.feed~='KILLS' then
  for _,r in ipairs(KWCDB.worldPvPDeaths or {}) do
   local t=r.epoch or Kit.StampEpoch(r.at) or 0
   local ev,tone=evidence(r)
   local text=P.Short(r.victim)..' was slain'
   if P.Matches(text..' '..tostring(r.zone)..' '..tostring(r.killer),state.query) then
    out[#out+1]={at=t,kind='death',title=text,sub=tostring(r.zone or '?')..'   '..S.Code(tone)..ev..'|r',tone='danger',record=r}
   end
  end
 end
 table.sort(out,function(a,b) return a.at>b.at end)
 return out
end

local function fill(row,it)
 row:Tone(it.tone);row.title:SetText(it.title);row.sub:SetText(it.sub)
 row.meta:SetText(Kit.Age(it.at));row.meta2:SetText(it.kind=='kill' and 'KILL' or 'DEATH')
 row:Select(false)
end

function page.Build(self,host)
 local left,right=P.Split(host,380)
 local bar=P.Toolbar(left,{search=function(t) state.query=t;if list then list:ScrollTo(1) end;self:Update() end,searchHint='Search names or zones',
  segments={{'ALL','Everything'},{'KILLS','Guild kills'},{'DEATHS','Guild deaths'}},get=function() return state.feed end,
  set=function(v) state.feed=v;self:Update() end,segWidth=96})
 list=Kit.List(left,52,6,function(row) S.RowBuild(row) end,fill)
 P.ListHeading(left,list,bar,'Activity')
 Kit.Paint(list.thumb,OWNER,'line','fill')
 list.empty=S.Empty(list,'No world PvP recorded yet','Guild kills appear when a guildmate earns an honorable kill in the open world; deaths when a guildmate running KWC dies to a player outside instances.',440)
 list.empty:SetPoint('TOPLEFT',4,-6)
 -- side panel
 local _,c=P.DrawerBody(right)
 side={stack=P.Stack(c,330)}
 side.zones=P.Section(c,'Danger zones - last 24 hours',330)
 side.scoutHead=S.Text(c,'kicker','faint');side.scoutHead:SetText('FILE A SCOUT REPORT')
 side.zone=S.Field(c,'Zone',330,55,'Where are they?')
 side.enemy=S.Field(c,'Enemy force',330,60,'Rogue group, raid, gankers...')
 side.cnt=CreateFrame('Frame',nil,c);side.cnt:SetSize(330,52)
 side.count=S.Field(side.cnt,'Count',100,3,'0');side.count:SetPoint('TOPLEFT')
 side.notes=S.Field(side.cnt,'Notes',220,100,'optional');side.notes:SetPoint('TOPRIGHT')
 side.zone.next,side.enemy.next,side.count.next=side.enemy,side.count,side.notes
 side.file=S.Button(c,'Save scout report','primary',function()
  local n=tonumber(side.count:Get())
  if side.zone:Get()=='' then side.zone:Error('Zone is required.');return end
  if side.enemy:Get()=='' then side.enemy:Error('Describe the enemy.');return end
  if not n or n<0 or n>999 or n~=math.floor(n) then side.count:Error('0-999');return end
  if K.WarRoom.ReportScout(side.zone:Get(),side.enemy:Get(),n,side.notes:Get()) then side.enemy:Set('');side.count:Set('');side.notes:Set('');self:Update() end
 end,170,30);side.file.keepWidth=true
 side.scoutNote=S.Para(c,330,'faint',12);side.scoutNote:SetText('Scout reports are saved on this character only. Guild-wide scout sync is not part of this build.')
 side.reports=P.Section(c,'Your recent scout reports',330)
 side.deathHead=S.Text(c,'kicker','faint');side.deathHead:SetText('REPORT YOUR OWN DEATH')
 side.killer=S.Field(c,'Who killed you?',330,48,'Enemy player name')
 side.report=S.Button(c,'Report to guild','secondary',function()
  local n=side.killer:Get();if n=='' then side.killer:Error('Enter the attacker name.');return end
  K.WorldPvPDeaths.Report(n);side.killer:Set('');self:Update()
 end,150,30);side.report.keepWidth=true
 side.zone:Set(P.HereZone())
end

function page.Update(self)
 if not list then return end
 list:SetData(rows())
 local st=side.stack;st:Reset()
 local z=K.DangerZones.Summarize(KWCDB.worldPvPDeaths or {},time(),86400,5)
 local lines={}
 for _,e in ipairs(z) do lines[#lines+1]=K.DangerZones.FormatLine(e) end
 side.zones:Set(#lines>0 and table.concat(lines,'\n') or S.Code('faint')..'No guildmate deaths in the last day.|r');st:Place(side.zones,nil,18)
 st:Place(side.scoutHead,14,8);st:Place(side.zone,52,8);st:Place(side.enemy,52,8);st:Place(side.cnt,52,12);st:Place(side.file,30,8)
 st:Place(side.scoutNote,nil,14)
 local r={}
 for i,x in ipairs(KWCDB.scoutReports or {}) do if i>4 then break end;r[#r+1]=x.zone..': '..x.enemy..' x'..x.count..S.Code('faint')..'  '..Kit.Age(x.created)..'|r' end
 side.reports:Set(#r>0 and table.concat(r,'\n') or S.Code('faint')..'None yet.|r');st:Place(side.reports,nil,18)
 local dead=UnitIsDeadOrGhost and UnitIsDeadOrGhost('player')
 st:Place(side.deathHead,14,8);st:Place(side.killer,52,8);st:Place(side.report,30,10)
 side.report:SetEnabledState(dead and true or false,'Available only while you are dead or a ghost in the open world, if the automatic death recap could not name the attacker.')
end
W.Register(page)
