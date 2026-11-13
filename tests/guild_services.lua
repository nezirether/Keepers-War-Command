local network,packet=assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
local function setup(c)
 local e=c.e
 e.C_SkillInfo={GetNumSkillLines=function() return 2 end,GetSkillLineInfo=function(i)
  return i==1 and {skillID=171,name="Alchemy",rank=143} or {name="Skills",isHeader=true}
 end}
 e.C_TradeSkillUI={
  IsTradeSkillLinked=function() return false end,IsTradeSkillGuild=function() return false end,IsNPCCrafting=function() return false end,
  GetBaseProfessionInfo=function() return {professionID=171,professionName="Alchemy",skillLevel=143} end,
  GetAllRecipeIDs=function() return {1234,1235,1234} end,
  GetRecipeInfo=function(id) return {learned=id==1234} end,
  GetRecipeItemLink=function() return "|Hitem:99|h[Elixir]|h" end,
 }
 return e.KWC.GuildServices
end
for _,size in ipairs({2,5,10,25,50}) do
 local n=network(math.max(3,size),true)
 local a,b,c
 for i=1,math.max(3,size) do
  local client=n.client(i,nil,{scoped=true,legacy=i>2 and i%5==0})
  if i==1 then a=client elseif i==2 then b=client else c=client end
 end
 c.online=false
 local A,B,C=setup(a),setup(b),setup(c)
 assert(A.ReadSkills().Alchemy==143)
 local name,recipes=A.ReadRecipes()
 assert(name=="Alchemy" and #recipes==1 and recipes[1].item==99)
 a.e.C_TradeSkillUI.IsTradeSkillLinked=function() return true end
 assert(not A.ReadRecipes())
 a.e.C_TradeSkillUI.IsTradeSkillLinked=function() return false end
 assert(not A.IsSharing())
 A.Refresh(true)
 n.run(2)
 for _,p in ipairs(n.packets) do assert(p.prefix~="KWPRO1") end
 assert(A.SetSharing(true))
 n.run(12)
 local db=B.Context()
 assert(db.characters[a.name:lower()].professions.Alchemy.recipes[1].id==1234)
 local prior
 for _,p in ipairs(n.packets) do if p.prefix=="KWPRO1" then prior=p.message end end
 assert(prior)
 a.online=false;c.online=true
 local start,bytes=#n.packets,n.bytes
 assert(c.e.KWC.Sync.Request(true))
 n.run(20)
 local recovered=C.Context()
 assert(recovered.characters[a.name:lower()].professions.Alchemy.rank==143)
 local sent,amount=#n.packets-start,n.bytes-bytes
 assert(sent<=20 and amount<3000)
 local drops=0
 for _,client in ipairs(n.clients) do
  local _,_,_,d=client.e.KWC.Net.Status();drops=drops+d
  for _,message in ipairs(client.logs) do assert(not message:find("error:",1,true),message) end
 end
 assert(drops==0)
 print(("%d clients | %d recovery packets | %d bytes | %d drops"):format(size,sent,amount,drops))
 a.online=true
 assert(A.SetSharing(false))
 n.run(10)
 assert(not next(db.characters[a.name:lower()].professions))
 packet(b,"KWPRO1",prior,a)
 assert(not next(db.characters[a.name:lower()].professions))
 packet(b,"KWPRO1",prior,c)
 assert(not next(db.characters[a.name:lower()].professions))
 b.online=false
 local reload=n.client(2,b.e.KWCDB,{scoped=true})
 local stored=reload.e.KWC.GuildServices.Context()
 assert(stored.characters[a.name:lower()].withdrawn>0)
 packet(reload,"KWPRO1",prior,a)
 assert(not next(stored.characters[a.name:lower()].professions))
 reload.guildID=2;reload.event("PLAYER_GUILD_UPDATE")
 packet(reload,"KWPRO1",prior,a)
 assert(not next(reload.e.KWC.GuildServices.Context().characters))
 a.guildID=2;a.event("PLAYER_GUILD_UPDATE")
 assert(not A.IsSharing(),"sharing consent followed the character into another guild")
end
print("PASS: profession APIs, private defaults, scoped consent, stale/forged packets, withdrawal, reload and offline recovery")

local n=network(2,false)
local c=n.client(1)
local e=c.e
local function dispatch(alias,args)
 for i=1,3 do
  if e["SLASH_KEEPERSWARCOMMAND"..i]==alias then return e.SlashCmdList.KEEPERSWARCOMMAND(args) end
 end
 error("missing alias "..alias)
end
local toggles=0
e.KWC.UI.Toggle=function() toggles=toggles+1 end
local sync,scout,death=0,0,0
e.KWC.Sync.RequestAll=function() sync=sync+1 end
e.KWC.AutoScout.SetEnabled=function(v) assert(v);scout=scout+1 end
e.KWC.WorldPvPDeaths={Demo=function() death=death+1 end}
for _,alias in ipairs({"/kwc","/kt","/keepers"}) do
 dispatch(alias,"");dispatch(alias,"help");dispatch(alias,"sync");dispatch(alias,"autoscout on")
 dispatch(alias,"deathalert test");dispatch(alias,"unknown")
end
assert(toggles==3 and sync==3 and scout==3 and death==3)
local reload=n.client(1,e.KWCDB)
assert(reload.e.SLASH_KEEPERSWARCOMMAND1=="/kwc" and reload.e.SLASH_KEEPERSWARCOMMAND2=="/kt")
print("PASS: slash aliases, shared handler, subcommands, help and reload registration")
