-- Public directory and recipe browser. Records retain the existing KWPRO1 schema.
local K=KWC
local Kit,S,P,W=K.Kit,K.WarRoomSkin,K.WarRoomPages,K.WarRoom2
local G,OWNER=K.GuildServices,S.OWNER
local categories={{'ALL','All'},{'Alchemy'},{'Blacksmithing','Smithing'},{'Cooking'},{'Enchanting'},
 {'Engineering'},{'First Aid'},{'Fishing'},{'Herbalism'},{'Leatherworking','Leather'},{'Mining'},{'Skinning'},{'Tailoring'}}
local state={profession='ALL',query='',mode='CRAFT',sort='NAME'}
local page={id='services',title='Guild Services',subtitle='Find a guild crafter or search shared recipes.',group='guild'}
local list,side

local sorts={
 NAME=function(a,b) return a.actor,b.actor end,
 SKILL=function(a,b) return -(a.rank or -1),-(b.rank or -1) end,
 ONLINE=function(a,b) return a.online and 0 or 1,b.online and 0 or 1 end,
 RECENT=function(a,b) return -(a.at or 0),-(b.at or 0) end,
}
local function directory()
 local db=G.Context()
 local out,labels={},{}
 if not db then return out end
 for actor,record in pairs(db.characters) do
  local member,_,online=K.CurrentGuildMember(actor)
  if member and (not state.crafter or state.crafter==actor) then
   for prof,p in pairs(record.professions or {}) do
    if state.profession=='ALL' or state.profession==prof then
     local recipes={}
     for _,recipe in ipairs(p.recipes or {}) do
      local key=recipe.id..':'..(recipe.item or 0)
      local label=labels[key]
      if not label then
       local name,item=G.RecipeNames(recipe)
       label=item and item~=name and (name..' / '..item) or name
       labels[key]=label
      end
      recipes[#recipes+1]=label
     end
     local row={actor=actor,prof=prof,rank=p.rank,at=p.at,online=online,recipes=recipes}
     local base=P.Short(actor)..' '..actor..' '..prof
     if state.mode=='CRAFT' and P.Matches(base..' '..table.concat(recipes,' '),state.query) then
      out[#out+1]=row
     elseif state.mode=='RECIPE' then
      for _,label in ipairs(recipes) do
       if P.Matches(base..' '..label,state.query) then
        out[#out+1]={actor=actor,prof=prof,rank=p.rank,at=p.at,online=online,recipes=recipes,recipe=label}
       end
      end
     end
    end
   end
  end
 end
 table.sort(out,function(a,b)
  local x,y=sorts[state.sort](a,b)
  if x~=y then return x<y end
  if a.actor~=b.actor then return a.actor<b.actor end
  if a.prof~=b.prof then return a.prof<b.prof end
  return (a.recipe or '')<(b.recipe or '')
 end)
 return out
end

local function fill(row,r)
 row:Tone(r.online and 'good' or 'accent')
 row.title:SetText(r.recipe or (P.Short(r.actor)..'  -  '..r.prof))
 row.sub:SetText(r.recipe and (P.Short(r.actor)..'  -  '..r.prof)
  or (#r.recipes>0 and (r.recipes[1]..(#r.recipes>1 and ('  +'..(#r.recipes-1)) or '')) or 'No recipes shared'))
 row.meta:SetText(r.rank and r.rank>=0 and ('Skill '..r.rank) or 'Skill unknown')
 row.meta2:SetText(r.online==true and 'Online' or r.online==false and 'Offline' or 'Status unknown')
 row:Select(state.selected==r.actor..'/'..r.prof)
end

local function filter(page)
 state.selected=nil
 list:ScrollTo(1)
 page:Update()
end

function page.Build(self,host)
 local left,right=P.Split(host,340)
 local bar=P.Toolbar(left,{search=function(t) state.query=t;filter(self) end,
  searchHint='Search crafters or recipes',searchWidth=220,
  segments={{'CRAFT','Crafters'},{'RECIPE','Recipes'}},get=function() return state.mode end,
  set=function(v) state.mode=v;if v=='CRAFT' then state.crafter=nil end;filter(self) end,segWidth=80})
 local tabs=S.Segmented(left,categories,function() return state.profession end,function(v)
  state.profession=v;filter(self)
 end)
 tabs:SetPoint('TOPLEFT',bar,'BOTTOMLEFT',0,-6)
 local sort=S.Segmented(left,{{'NAME','Name'},{'SKILL','Skill'},{'ONLINE','Online'},{'RECENT','Recent'}},
  function() return state.sort end,function(v) state.sort=v;filter(self) end,66)
 sort:SetPoint('TOPLEFT',tabs,'BOTTOMLEFT',0,-8)
 local function layout(_,width)
  if width>0 then P.SegmentWidth(tabs,width);P.SegmentWidth(sort,width) end
 end
 left:HookScript('OnSizeChanged',layout);layout(left,left:GetWidth()>0 and left:GetWidth() or 300)
 list=Kit.List(left,51,4,function(row)
  S.RowBuild(row)
  row:SetScript('OnClick',function(r) state.selected=r.item.actor..'/'..r.item.prof;self:Update() end)
 end,fill)
 P.ListHeading(left,list,sort,'Results')
 Kit.Paint(list.thumb,OWNER,'line','fill')
 list.empty=S.Empty(list,'No matching records','Try another profession or clear the search. Recipes appear after a guildmate shares them.',290)
 list.empty:SetPoint('TOPLEFT',4,-6)
 local _,body=P.DrawerBody(right)
 side={stack=P.Stack(body,300)}
 side.head=P.DrawerHead(body,300)
 side.details=P.Section(body,'Shared record',300)
 side.book=P.Section(body,'Shared recipes',300)
 side.share=S.Switch(body,'Share my professions',G.IsSharing,function(v) G.SetSharing(v);self:Update() end,300)
 side.publish=S.Button(body,'Publish open profession','primary',function()
  side.publishResult=G.Refresh(true,true)
  self:Update()
 end,186,30)
 side.whisper=S.Button(body,'Prepare whisper','primary',function()
  if side.actor then Kit.CopyBox(OWNER,'Whisper this crafter','/w '..(side.target or P.Short(side.actor))..' ') end
 end,136,30)
 side.crafter=S.Button(body,'Crafter recipes','secondary',function()
  if state.crafter then state.crafter=nil else state.crafter=side.actor end
  state.mode='RECIPE';bar.seg:Update();filter(self)
 end,132,30)
 side.status=P.Section(body,'Publishing status',300)
 side.tabs=tabs
end

local function publishText()
 local result=side.publishResult
 if not result then return 'Open a learned profession window, then publish to refresh its shared recipes.' end
 if result.guild~=K.GuildScope() then return 'Open a profession window in the current guild to publish.' end
 if result.detected==0 then return 'No professions detected. Open your own profession window and try again.' end
 local scan=result.scanned and ('Book scanned: '..result.scanned..'. ') or 'No open learned recipe book was read. '
 return scan..('%d queued, %d not queued. Queueing does not confirm another client received the update.'):format(result.queued,result.failed)
end

function page.Update()
 if not list then return end
 local data=directory()
 local selected
 for _,r in ipairs(data) do if state.selected==r.actor..'/'..r.prof then selected=r;break end end
 list:SetData(data)
 local st=side.stack;st:Reset()
 for _,key in ipairs({'details','book','whisper','crafter'}) do side[key]:Hide() end
 if selected then
  local roster=K.RosterRecord(selected.actor)
  side.actor=selected.actor
  side.target=roster and roster.name
  side.head:Set(selected.prof,P.Short(selected.actor))
  st:Place(side.head,nil,10)
  side.details:Set((selected.rank and selected.rank>=0 and ('Skill '..selected.rank) or 'Skill unavailable')..
   '\nUpdated '..Kit.Age(selected.at)..'\n'..(selected.online==true and 'Online' or selected.online==false and 'Offline' or 'Online status unavailable'))
  st:Place(side.details,nil,10)
  side.crafter:SetLabel(state.crafter and 'All crafters' or 'Crafter recipes')
  st:Actions({side.whisper,side.crafter})
  side.book:Set(#selected.recipes>0 and table.concat(selected.recipes,'\n') or 'No recipes have been shared for this profession.')
  st:Place(side.book,nil,16)
 else
  side.actor=nil
  side.head:Set('Crafting directory',state.crafter and P.Short(state.crafter) or 'Your professions')
  st:Place(side.head,nil,10)
  if state.crafter then side.crafter:SetLabel('All crafters');st:Actions({side.crafter}) end
 end
 side.share:Update();st:Place(side.share,nil,8)
 side.publish.keepWidth=true
 side.publish:SetEnabledState(K.GuildReadiness()=='Ready' and G.IsSharing(),'Requires verified guild membership and sharing enabled.')
 st:Place(side.publish,30,12)
 local names={}
 for name in pairs(G.localSkills or {}) do names[#names+1]=name end
 table.sort(names)
 local db,_,actor=G.Context()
 local record=db and db.characters[actor]
 local updated=0
 for _,prof in pairs(record and record.professions or {}) do updated=math.max(updated,prof.at or 0) end
 side.status:Set('Detected: '..(#names>0 and table.concat(names,', ') or 'none')..
  '\nLocal record: '..(updated>0 and Kit.Age(updated) or 'no publication recorded')..'\n'..publishText())
 st:Place(side.status,nil,8)
end
W.Register(page)
