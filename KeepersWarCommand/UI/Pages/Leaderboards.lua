-- War Room page: PvP leaderboards. World PvP first; battlegrounds and lifetime
-- honorable kills are separate boards. Values come only from each member's own
-- game Statistics, shared by their client; nothing is estimated or inferred.
local K=KWC
local Kit,S,P,W=K.Kit,K.WarRoomSkin,K.WarRoomPages,K.WarRoom2
local OWNER=S.OWNER

local page={id='leaderboards',title='Leaderboards',subtitle='Honorable kills by guildmate - world PvP first.',group='records'}
local state={board='world',query=''}
local BOARDS={
 world={'World PvP kills','Open-world honorable kills. Battlegrounds stay on their own board.'},
 battleground={'Battleground kills','Honorable kills earned in battlegrounds, kept separate from the world.'},
 lifetime={'Lifetime honorable kills','All-time honorable kills. The top five are recognized as Warlords of Trogdor.'},
}
local list,head,note,hero

local function rows()
 local out={}
 local data=K.PvP.Rankings(state.board) or {}
 local top=data[1] and data[1].value or 0
 for i,r in ipairs(data) do
  if P.Matches(r.name,state.query) then out[#out+1]={rank=r.value~=nil and i or nil,name=r.name,value=r.value,top=top,at=r.snapshot and r.snapshot.at,status=r.status} end
 end
 return out
end
local function fill(row,r)
 row.rank:SetText(r.rank and ('#'..r.rank) or '-')
 local me=K.PvP.PlayerName and K.PvP.PlayerName()
 local mine=me and P.Lower(r.name)==P.Lower(me)
 row.name:SetText(r.name..(mine and S.Code('accentText')..'  (you)|r' or ''))
 row.val:SetText(r.value~=nil and (tostring(r.value)..(r.status=='Stale' and ' (stale)' or '')) or 'Awaiting Stats')
 local warlord=state.board=='lifetime' and r.rank and r.rank<=5
 row:SetScoreLayout(false,r.value~=nil and r.top>0 and r.value/r.top or 0,warlord and 'WARLORD OF TROGDOR' or nil)
 row:SetWarlordInsignia(warlord and r.rank or nil)
 if not warlord then row:SetRankWreath(r.rank) end
 Kit.Paint(row.rank,OWNER,r.rank and r.rank<=5 and 'accentText' or 'faint','text')
 Kit.Paint(row.name,OWNER,warlord and 'accentText' or 'text','text')
 Kit.Paint(row.bg,OWNER,warlord and 'accentSoft' or 'surface','fill',r.rank==1 and 0.9 or warlord and 0.6 or 1)
end

function page.Build(self,host)
 hero=CreateFrame('Frame',nil,host);hero:SetPoint('TOPLEFT');hero:SetPoint('TOPRIGHT');hero:SetHeight(76)
 Kit.Fill(hero,OWNER,'header');S.Art(hero,'banner','BACKGROUND');S.Art(hero,'material','BORDER')
 local sigil=CreateFrame('Frame',nil,hero);sigil:SetSize(46,46);sigil:SetPoint('LEFT',14,0);sigil:EnableMouse(false);S.Art(sigil,'crest','ARTWORK')
 local trophy=S.ThemedTexture(sigil,'iconTrophy',30,'OVERLAY',4);trophy:SetPoint('CENTER')
 local title=S.Text(hero,'display','text');title:SetPoint('TOPLEFT',sigil,'TOPRIGHT',14,-9);title:SetText('Warlords of Trogdor')
 local caption=S.Text(hero,'small','muted');caption:SetPoint('TOPLEFT',title,'BOTTOMLEFT',0,-5);caption:SetText('Guild pride  ·  World PvP  ·  Lifetime honors')
 local leftLaurel=S.ThemedTexture(hero,'laurelLeft',28,'ARTWORK',3);leftLaurel:SetPoint('RIGHT',title,'LEFT',-7,0)
 local rightLaurel=S.ThemedTexture(hero,'laurelRight',28,'ARTWORK',3);rightLaurel:SetPoint('LEFT',title,'RIGHT',7,0)
 local bar=P.Toolbar(host,{search=function(t) state.query=t;if list then list:ScrollTo(1) end;self:Update() end,searchHint='Find a guildmate',
  segments={{'world','World PvP'},{'battleground','Battlegrounds'},{'lifetime','Lifetime HKs'}},get=function() return state.board end,
  set=function(v) state.board=v;self:Update() end,segWidth=120,action='Refresh my stats',onAction=function() K.PvP.RefreshMyStats();self:Update() end,actionWidth=160})
 bar:ClearAllPoints();bar:SetPoint('TOPLEFT',hero,'BOTTOMLEFT',0,-12);bar:SetPoint('TOPRIGHT',host,'TOPRIGHT')
 self.bar=bar
 head=S.Text(host,'section','text');head:SetPoint('TOPLEFT',bar,'BOTTOMLEFT',0,-18)
 note=S.Para(host,600,'faint',12);note:SetPoint('TOPLEFT',head,'BOTTOMLEFT',0,-4)
 note:SetPoint('RIGHT',host,'RIGHT',-4,0)
 list=Kit.List(host,46,3,S.RankBuild,fill)
 P.ListHeading(host,list,note,'Rankings')
 Kit.Paint(list.thumb,OWNER,'line','fill')
 list.empty=S.Empty(list,'No scores shared yet','Guildmates appear after their client shares a valid honor total.',480)
 list.empty:SetPoint('TOPLEFT',4,-6)
end
function page.Update(self)
 if not list then return end
 self.bar.seg:Update()
 head:SetText(BOARDS[state.board][1]);note:SetText(BOARDS[state.board][2])
 list:SetData(rows())
end
W.Register(page)
