-- War Room page: PvP leaderboards. World PvP first; battlegrounds and lifetime
-- honorable kills are separate boards. Values come only from each member's own
-- game Statistics, shared by their client; nothing is estimated or inferred.
local K=KWC
local Kit,S,P,W=K.Kit,K.WarRoomSkin,K.WarRoomPages,K.WarRoom2
local OWNER=S.OWNER

local page={id='leaderboards',title='Leaderboards',subtitle='Honorable kills by guildmate - world PvP first.',group='records'}
local state={board='world',query=''}
local BOARDS={
 world={'World PvP kills','Honorable kills earned in world zones (game Statistics, category World). Battlegrounds are excluded.'},
 battleground={'Battleground kills','Honorable kills earned in battlegrounds (game Statistics). Shown separately from world PvP.'},
 lifetime={'Lifetime honorable kills','All-time honorable kills from the game. Only members whose client could read the value are listed.'},
}
local list,head,note

local function rows()
 local out={}
 local data=K.PvP.Rankings(state.board) or {}
 local top=data[1] and data[1].value or 0
 for i,r in ipairs(data) do
  if P.Matches(r.name,state.query) then out[#out+1]={rank=i,name=r.name,value=r.value,top=top,at=r.snapshot and r.snapshot.at} end
 end
 return out
end
local function fill(row,r)
 row.rank:SetText('#'..r.rank)
 local me=K.PvP.PlayerName and K.PvP.PlayerName()
 local mine=me and P.Lower(r.name)==P.Lower(me)
 row.name:SetText(r.name..(mine and S.Code('accentText')..'  (you)|r' or ''))
 row.val:SetText(tostring(r.value))
 row:SetScoreLayout(false,r.top>0 and r.value/r.top or 0)
 Kit.Paint(row.rank,OWNER,r.rank<=3 and 'accentText' or 'faint','text')
end

function page.Build(self,host)
 local bar=P.Toolbar(host,{search=function(t) state.query=t;if list then list:ScrollTo(1) end;self:Update() end,searchHint='Find a guildmate',
  segments={{'world','World PvP'},{'battleground','Battlegrounds'},{'lifetime','Lifetime HKs'}},get=function() return state.board end,
  set=function(v) state.board=v;self:Update() end,segWidth=120,action='Refresh my stats',onAction=function() K.PvP.RefreshHonor();K.PvP.RequestGuildHonor(false);self:Update() end,actionWidth=160})
 self.bar=bar
 head=S.Text(host,'section','text');head:SetPoint('TOPLEFT',bar,'BOTTOMLEFT',0,-18)
 note=S.Para(host,600,'faint',12);note:SetPoint('TOPLEFT',head,'BOTTOMLEFT',0,-4)
 note:SetPoint('RIGHT',host,'RIGHT',-4,0)
 list=Kit.List(host,34,3,S.RankBuild,fill)
 P.ListHeading(host,list,note,'Rankings')
 Kit.Paint(list.thumb,OWNER,'line','fill')
 list.empty=S.Empty(list,'No values shared yet','Members appear once their client reads their Statistics and shares them. Ask guildmates to log in with KWC; "Refresh my stats" re-reads yours.',480)
 list.empty:SetPoint('TOPLEFT',4,-6)
end
function page.Update(self)
 if not list then return end
 self.bar.seg:Update()
 head:SetText(BOARDS[state.board][1]);note:SetText(BOARDS[state.board][2])
 list:SetData(rows())
end
W.Register(page)
