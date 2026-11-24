-- Regression coverage for responsive host geometry and preserved public data.
local H=dofile('tests/harness/wow.lua')
local world=H.World()
local chief='Grom Warcry'
world:AddMember({name=chief,rank=0,guid='Player-1-0000000B'})
local function boot(saved)
 local c=world:Client(chief,{saved=saved})
 world:LoadAddon(c,'KeepersWarCommand');world:Login(c);world:Advance(6)
 return c
end
local c=boot()
local K=c.env.KWC
local frame=c.env.CreateFrame('Frame',nil,c.env.UIParent)
frame:SetSize(280,100)
local list=K.Kit.List(frame,30,4,function() end,function() end)
list:SetSize(280,100)
local rows={}
for i=1,34 do rows[i]={id=i} end
list:SetData(rows)
H.Check('pooled list allocates only complete visible rows',#list.rows==3)
list:Page(1)
H.Check('page forward advances through populated data',list.offset==2 and list.rows[1].item.id==3)
list:ScrollTo(34)
H.Check('final list page is clamped to the final records',list.rows[3].item.id==34)
list:SetHeight(12)
H.Check('short viewport hides rather than clipping pooled rows',not list.rows[1]:IsShown() and not list.track:IsShown())
list:SetHeight(100);list:SetData({{id=1}})
H.Check('filtering a scrolled list clamps selection back into range',list.offset==0 and list.rows[1].item.id==1)

local _,content=K.Kit.Scroll(frame)
local scroll=content:GetParent()
scroll:SetVerticalScroll(95)
scroll:GetScript('OnScrollRangeChanged')(scroll,0,40)
H.Check('shrinking scroll range clamps the current position',scroll:GetVerticalScroll()==40)

H.Check('embedded Raid Tools mounts in the public host',K.RaidTools.Mount(frame,'Attendance'))
local inner
for _,child in ipairs(c.allWidgets) do
 local _,anchor=child:GetPoint(2)
 if child:GetParent()==frame and anchor==frame then
  local p1=child:GetPoint(1);local p2=child:GetPoint(2)
  if p1=='TOPLEFT' and p2=='BOTTOMRIGHT' then inner=child;break end
 end
end
H.Check('mounted Raid Tools has opposing anchors on its host',inner~=nil)
K.RaidTools.Close()
H.Check('closing the tool unmounts its shared content',inner and inner:GetParent()~=frame and not inner:IsShown())

local comm=c.env.KeepersRaidTools.Comms
local decoded,handled=0,0
local decode,groupUnit=comm.Decode,comm.GroupUnit
comm.Decode=function()
 decoded=decoded+1
 return true,{type='regression',data={}}
end
comm.GroupUnit=function(_,sender) return sender=='Group Peer' and 'party1' or nil end
comm:RegisterHandler('regression',function() handled=handled+1 end)
comm:Dispatch('test','Outside Group','WHISPER')
comm:Dispatch('test','Group Peer','GUILD')
H.Check('irrelevant channels and non-group peers do not reach the codec',decoded==0 and handled==0)
comm:Dispatch('test','Group Peer','PARTY')
H.Check('verified group peer still reaches the registered handler',decoded==1 and handled==1)
comm:RegisterHandler('regression',function() error('synthetic handler failure') end)
comm.streamStarts['group peer']=c.env.time()
local ok=pcall(comm.Dispatch,comm,string.rep('a',256),'Group Peer','WHISPER')
H.Check('a failed handler cannot leave receive state behind',ok and comm.dispatchStarted==nil)
comm.Decode,comm.GroupUnit=decode,groupUnit

local ws=K.WarSpoils
assert(ws.Record('R',chief))
assert(ws.Record('S',nil,nil,'Persistence test'))
assert(ws.Record('A',chief))
local saved=world:Saved(c,{'KWCDB'})
local lines=saved.KWCDB.warSpoils.lines
local suffix=lines[3]
lines[2]=nil
world:Drop(c)
c=boot(saved);ws=c.env.KWC.WarSpoils
local state=ws.View()
H.Check('a gap quarantines the restored ledger without deleting the suffix',
 state.db.conflict and state.count==1 and state.db.lines[3]==suffix and not ws.CanWrite())
H.Check('a quarantined ledger cannot overwrite the missing sequence',not ws.Record('S',nil,nil,'Do not overwrite'))

saved=world:Saved(c,{'KWCDB'})
saved.KWCDB.warSpoils={version=98,lines={'future schema'}}
world:Drop(c)
c=boot(saved);ws=c.env.KWC.WarSpoils
local view,problem=ws.View()
H.Check('future ledger schema is preserved and mutations remain unavailable',
 not view and problem and c.env.KWCDB.warSpoils.lines[1]=='future schema' and not ws.CanWrite())
H.Check('no public startup errors',#c.errors==0,table.concat(c.errors,' | '))
os.exit(H.Summary('phoenix_integration') and 0 or 1)
