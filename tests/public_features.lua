-- Public engine flows through real addon modules and two simulated clients.
local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})
w:AddMember({name='Ash Ember',rank=3,guid='Player-1-0000000A'})
local folder=arg and arg[1] or 'KeepersWarCommand'
local function client(name)
 local c=w:Client(name)
 w:LoadAddon(c,folder);w:Login(c);w:Advance(6)
 return c
end
local a,b=client('Grom Warcry'),client('Ash Ember')
local A,B=a.env.KWC,b.env.KWC
a.lifetimeHK=231
A.PvP.RefreshHonor()
A.PvP.RequestGuildHonor(false)
w:Advance(10)
local ranked=A.PvP.Rankings('lifetime')
H.Check('lifetime honorable kills populate the ranking',ranked[1] and ranked[1].value==231)

a.env.C_SkillInfo={
 GetNumSkillLines=function() return 1 end,
 GetSkillLineInfo=function() return {skillID=171,rank=143} end,
}
a.env.C_TradeSkillUI={
 IsTradeSkillLinked=function() return false end,
 IsTradeSkillGuild=function() return false end,
 IsNPCCrafting=function() return false end,
 GetBaseProfessionInfo=function() return {professionID=171,skillLevel=143} end,
 GetAllRecipeIDs=function() return {1234,1235} end,
 GetRecipeInfo=function(id) return {learned=id==1234} end,
 GetRecipeItemLink=function() return '|Hitem:99|h[Elixir]|h' end,
}
assert(A.GuildServices.SetSharing(true))
local outgoing
local send=A.Net.Send
A.Net.Send=function(prefix,payload,...)
 if prefix=='KWPRO1' and payload:find('|P|',1,true) then outgoing=payload end
 return send(prefix,payload,...)
end
local publication=A.GuildServices.Refresh(true,true)
A.Net.Send=send
H.Check('manual publishing reports scan and queue evidence',publication.scanned=='Alchemy' and publication.queued==1)
w:Advance(10)
local _,_,actor=A.GuildServices.Context()
local record=B.GuildServices.Context().characters[actor]
local craft=record and record.professions.Alchemy
H.Check('learned recipe and skill propagate through Guild Services',craft and craft.rank==143 and #craft.recipes==1 and craft.recipes[1].id==1234)
B.WarRoom2.Show('services')
local viewError=table.concat(b.printed,'\n'):find('Interface error',1,true)
H.Check('received professions render in Guild Services',not viewError)
local function clickText(client,text)
 for _,widget in ipairs(client.allWidgets) do
  if widget.kind=='Button' and type(widget.text)=='table' and widget.text:GetText()==text and widget:IsVisible() then
   local callback=widget:GetScript('OnClick')
   if callback then callback(widget);return true end
  end
 end
 return false
end
H.Check('recipe mode is accessible from the public page',clickText(b,'Recipes'))
local recipe=false
for _,widget in ipairs(b.allWidgets) do
 if widget.kind=='FontString' and type(widget.text)=='string' and widget.text:find('Spell 1234',1,true) and widget:IsVisible() then recipe=true end
end
H.Check('populated recipe mode renders the received spell',recipe)
assert(A.GuildServices.SetSharing(false))
w:Advance(12)
record=B.GuildServices.Context().characters[actor]
H.Check('turning sharing off withdraws the listing from the peer',record and not next(record.professions))
assert(outgoing,'expected an actual profession packet')
w:Fire(b,'CHAT_MSG_ADDON','KWPRO1',outgoing,'GUILD',a.name)
H.Check('a stale legitimate profession packet cannot resurrect a withdrawn listing',not next(record.professions))
local saved=w:Saved(a,{'KWCDB'})
w:Drop(a)
a=w:Client('Grom Warcry',{saved=saved})
w:LoadAddon(a,folder);w:Login(a);w:Advance(6)
A=a.env.KWC
H.Check('existing opt-out survives a reload and profession migration',not A.GuildServices.IsSharing())

local id,err=A.GuildLFG.Create({activity='Dungeon',name='Public test group',description='One healer',roles={Healer=true},
 minLevel=1,maxLevel=60,needed=1,groupSize=5,lifetimeMinutes=45})
assert(id,err)
w:Advance(10)
local function browse()
 for _,listing in ipairs(B.GuildLFG.Browse({})) do if listing.id==id then return listing end end
end
H.Check('Guild LFG listing reaches a peer',browse()~=nil)
H.Check('peer can mark interest',B.GuildLFG.Interest(id,true))
w:Advance(10)
local own
for _,listing in ipairs(A.GuildLFG.Browse({mine=true})) do if listing.id==id then own=listing end end
H.Check('Guild LFG owner sees the listing',own and own.name=='Public test group')

A.WarRoomSkin.Apply('classic')
A.UI.SetScale(0.9)
H.Check('skin and scale write to SavedVariables',
 A.WarRoomSkin.Current()=='classic' and a.env.KWCDB.settings.ui2Scale==0.9)
local errorText=table.concat(a.errors,' | ')..table.concat(b.errors,' | ')
H.Check('no simulated client runtime errors',errorText=='',errorText)
os.exit(H.Summary('public_features') and 0 or 1)
