local K,S=KWC,KWC.GuildServices
local tabs={'Overview','Professions','Recipes'}
local tab='Overview'
local query,character,profession='','',''
local sortBy='Character'
local lastGuild
local function contains(hay,needle)
 return needle=='' or hay:lower():find(needle:lower(),1,true)~=nil
end
local function stamp(at)
 return at and date('%Y-%m-%d %H:%M',at) or 'Waiting for roster refresh'
end
local function collect(db,actor)
 local rows={}
 for name,record in pairs(db.characters) do
  if K.CurrentGuildMember(name)==name then
   for job,p in pairs(record.professions) do
    rows[#rows+1]={name=name,job=job,rank=p.rank,at=p.at,recipes=p.recipes}
   end
  end
 end
 if not S.IsSharing() then
  for name,rank in pairs(S.localSkills or {}) do
   rows[#rows+1]={name=actor,job=name,rank=rank or -1,at=nil,recipes={},private=true}
  end
 end
 table.sort(rows,function(a,b)
  if sortBy=='Profession' and a.job~=b.job then return a.job<b.job end
  if sortBy=='Skill' and a.rank~=b.rank then return a.rank>b.rank end
  if a.name~=b.name then return a.name<b.name end
  return a.job<b.job
 end)
 return rows
end
local function field(parent,label,edit,caption,value,x,y,w,set)
 label(parent,caption,x,y,w)
 local box=edit(parent,value,x,y-23,w)
 box:SetScript('OnTextChanged',function(self) set(self:GetText()) end)
 return box
end
function S.Draw(parent,label,button,edit,surface,redraw)
 K.RefreshGuildScope()
 local db,guild,actor=S.Context()
 if lastGuild~=guild then
  tab='Overview';query,character,profession='','','';lastGuild=guild
  if db then S.Refresh() end
 end
 label(parent,'Guild Services',18,-12,520,'GameFontNormalLarge')
 if not db then
  local state=K.GuildReadiness()
  if state=='Ready' then label(parent,'Guild Services data format is unsupported.',18,-62,520)
  else K.GuildLFG.DrawWaiting(parent,label,button,redraw,state) end
  return
 end
 local makeButton=button
 button=function(p,caption,x,y,w,action,help,selectedTab)
  return makeButton(p,caption,x,y,w,function()
   if guild==K.GuildScope() then action() else redraw() end
  end,help,selectedTab)
 end
 for i,name in ipairs(tabs) do
  button(parent,(tab==name and '> ' or '')..name,18+(i-1)*180,-60,169,function() tab=name;redraw() end,nil,tab==name)
 end
 local rows=collect(db,actor)
 if tab=='Overview' then
  local roster,at=S.Roster()
  local shared,latest=0,nil
  for _,r in ipairs(rows) do
   if not r.private then shared=shared+1;if r.at and (not latest or r.at>latest) then latest=r.at end end
  end
  surface(parent,18,-114,529,152,0.10)
  label(parent,('%d guild characters  /  %d shared profession entries'):format(#roster,shared),31,-130,504,'GameFontNormal')
  label(parent,'Roster refreshed: '..stamp(at),31,-161,504)
  label(parent,'Latest shared update: '..(latest and stamp(latest) or 'None'),31,-187,504)
  label(parent,'Share my profession information with guildmates',18,-292,530,'GameFontNormal')
  label(parent,'Shares this character’s profession skills and observed learned recipes with this guild.',18,-319,530)
  button(parent,S.IsSharing() and 'Sharing On' or 'Sharing Off',18,-360,155,function()
   S.SetSharing(not S.IsSharing());redraw()
  end,'Share this character’s profession skills and observed learned recipes with this guild.')
  button(parent,'Refresh Directory',190,-360,165,function()
   S.Refresh(true);K.Sync.Request(true);redraw()
  end)
  label(parent,'Open your profession window to collect learned recipes.',18,-409,520)
  label(parent,'Guild roster',18,-452,520,'GameFontNormal')
  local y=-486
  for _,r in ipairs(roster) do
   if y < -3650 then break end
   surface(parent,18,y+6,529,27,0.085)
   label(parent,r.name,18,y,198)
   label(parent,(r.rank or 'Unknown rank')..' / '..(r.level or '?')..' '..(r.class or ''),220,y,232)
   label(parent,r.online==true and 'Online' or r.online==false and 'Offline' or 'Unknown',455,y,92)
   y=y-30
  end
  return
 end
 field(parent,label,edit,'Character',character,18,-112,160,function(v) character=v end)
 field(parent,label,edit,'Profession',profession,190,-112,160,function(v) profession=v end)
 field(parent,label,edit,'Recipe or crafted item',query,362,-112,185,function(v) query=v end)
 button(parent,'Apply Filters',18,-174,155,redraw)
 button(parent,'Sort: '..sortBy,190,-174,160,function()
  sortBy=sortBy=='Character' and 'Profession' or sortBy=='Profession' and 'Skill' or 'Character'
  redraw()
 end)
 button(parent,'Refresh',362,-174,185,function() S.Refresh(true);K.Sync.Request(true);redraw() end)
 local y,found=-232,0
 for _,r in ipairs(rows) do
  if y < -3610 then label(parent,'Narrow the search to see more results.',18,y,520);break end
  if contains(r.name,character) and contains(r.job,profession) then
   local recipes={}
   for _,recipe in ipairs(r.recipes) do
    local name,item=S.RecipeNames(recipe)
    if contains(name,query) or (item and contains(item,query)) then
     recipes[#recipes+1]=name..(item and item~=name and ' / '..item or '')
    end
   end
   if tab=='Professions' and (query=='' or #recipes>0) then
    local rank=r.rank>=0 and tostring(r.rank) or 'Unknown'
    label(parent,r.name..'  /  '..r.job..'  /  '..rank,18,y,530,'GameFontNormal')
    label(parent,r.private and 'Local only' or 'Updated '..stamp(r.at),18,y-25,530)
    y=y-63;found=found+1
   elseif tab=='Recipes' then
    for _,name in ipairs(recipes) do
     if y < -3610 then break end
     label(parent,name,18,y,530,'GameFontNormal')
     label(parent,r.name..'  /  '..r.job..'  /  '..stamp(r.at),18,y-25,530)
     y=y-63;found=found+1
    end
   end
  end
 end
 if found==0 then
  label(parent,tab=='Recipes' and 'No known shared recipes match. Open your own profession window to collect recipes.' or
   'No profession entries match this view.',18,y,520)
 end
end
