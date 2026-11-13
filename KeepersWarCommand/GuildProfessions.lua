local K,S=KWC,KWC.GuildServices
local professions={
 [164]='Blacksmithing',[165]='Leatherworking',[171]='Alchemy',[182]='Herbalism',
 [185]='Cooking',[186]='Mining',[197]='Tailoring',[202]='Engineering',
 [333]='Enchanting',[356]='Fishing',[393]='Skinning',[129]='First Aid',
}
local known={}
for _,name in pairs(professions) do known[name:lower()]=name end
local function accessible(v)
 if issecretvalue and issecretvalue(v) then return end
 return v
end
local function read(fn,...)
 if type(fn)~='function' then return end
 local ok,a,b,c,d,e,f,g,h=pcall(fn,...)
 if ok then return accessible(a),accessible(b),accessible(c),accessible(d),accessible(e),accessible(f),accessible(g),accessible(h) end
end
local function field(t,k)
 if type(t)=='table' then return accessible(t[k]) end
end
function S.ProfessionName(name,id)
 return professions[id] or (type(name)=='string' and known[name:lower()])
end
local function skill(value)
 if type(value)=='number' and value>=0 and value<=10000 and value%1==0 then return value end
end
function S.ReadSkills()
 local result={}
 local function add(name,id,rank)
  name=S.ProfessionName(name,id)
  if name then
   rank=skill(rank)
   if rank or result[name]==nil then result[name]=rank or false end
  end
 end
 local modern=C_SkillInfo
 local count=read(modern and modern.GetNumSkillLines)
 for i=1,math.min(skill(count) or 0,300) do
  local line=read(modern.GetSkillLineInfo,i)
  if not field(line,'isHeader') then
   add(field(line,'name') or field(line,'skillName'),field(line,'skillID') or field(line,'skillLineID'),
    field(line,'rank') or field(line,'skillRank') or field(line,'skillLineRank'))
  end
 end
 count=read(GetNumSkillLines)
 for i=1,math.min(skill(count) or 0,300) do
  local name,header,_,rank=read(GetSkillLineInfo,i)
  if not header then add(name,nil,rank) end
 end
 for _,index in pairs({read(GetProfessions)}) do
  if type(index)=='number' then
   local name,_,rank,_,_,_,id=read(GetProfessionInfo,index)
   add(name,id,rank)
  end
 end
 return result
end

-- Learn only from the player's own open book and explicit learned flags.
-- Recipe IDs and result item IDs are client data. No external catalog is needed.
function S.ReadRecipes()
 local t=C_TradeSkillUI
 if not t or type(t.IsTradeSkillLinked)~='function' or type(t.IsTradeSkillGuild)~='function' or type(t.IsNPCCrafting)~='function' then return end
 if read(t.IsTradeSkillLinked)~=false or read(t.IsTradeSkillGuild)~=false or read(t.IsNPCCrafting)~=false then return end
 local base=read(t.GetBaseProfessionInfo)
 local name=S.ProfessionName(field(base,'professionName'),field(base,'professionID'))
 local ids=read(t.GetAllRecipeIDs) or read(t.GetFilteredRecipeIDs)
 if not name or type(ids)~='table' or #ids==0 then return end
 local recipes,seen={},{}
 for i=1,math.min(#ids,2048) do
  local id=accessible(ids[i])
  if type(id)=='number' and id%1==0 and id>0 and id<100000000 and not seen[id] then
   local info=read(t.GetRecipeInfo,id)
   if field(info,'learned')==true then
    seen[id]=true
    local link=read(t.GetRecipeItemLink,id)
    local item=type(link)=='string' and tonumber(link:match('item:(%d+)')) or field(read(t.GetRecipeSchematic,id,false),'outputItemID')
    if type(item)~='number' or item%1~=0 or item<1 or item>=100000000 then item=nil end
    recipes[#recipes+1]={id=id,item=item}
   end
  end
 end
 if #recipes==0 then return end
 table.sort(recipes,function(a,b) return a.id<b.id end)
 while #recipes>64 do recipes[#recipes]=nil end
 return name,recipes,skill(field(base,'skillLevel'))
end

function S.RecipeNames(recipe)
 local name=read(C_Spell and C_Spell.GetSpellName,recipe.id) or read(GetSpellInfo,recipe.id)
 local item=recipe.item and (read(C_Item and C_Item.GetItemNameByID,recipe.item) or read(GetItemInfo,recipe.item))
 return type(name)=='string' and name or 'Recipe #'..recipe.id,type(item)=='string' and item or nil
end
