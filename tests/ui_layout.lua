-- Headless public War Room geometry. The harness estimates text and does not
-- resolve WoW's anchors, so check offsets produced by the layout helpers.
local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})
for i=1,30 do
 w:AddMember({name='Quartermaster '..string.char(65+math.floor((i-1)/26))..string.char(65+(i-1)%26)..' Emberward',
  rank=3,guid=('Player-1-%08X'):format(100+i)})
end
local c=w:Client('Grom Warcry')
w:LoadAddon(c,'KeepersWarCommand');w:Login(c);w:Advance(6)
local K=c.env.KWC
local W=K.WarRoom2
local shared=assert(K.GuildServices.Context())
local recipes={}
for i=1,16 do recipes[i]={id=10000+i,item=45000+i} end
for _,member in ipairs(w.roster) do
 local id=K.CurrentGuildMember(member.name)
 if id then shared.characters[id]={professions={Alchemy={rank=300,at=c.env.time(),recipes=recipes}}} end
end
local objective='Hold the eastern bridge while the last group returns to the guild rendezvous'
K.Operations.DetailedCTA('Hillsbrad Foothills',objective,12,18,'HIGH','57.5, 44.0',string.rep(' Bring healers.',8))
K.Operations.AddBounty('A lengthy wanted notice',{target='Aurelius Emberwarden',location='Hillsbrad Foothills',reason=objective,reward='25 gold'})
assert(K.GuildLFG.Create({activity='Dungeon',name='Reserve healer for the last group',description=objective,
 roles={Healer=true},minLevel=40,maxLevel=60,needed=1,groupSize=5,lifetimeMinutes=45}))
assert(K.RaidSignup.Create('Garrison of the Ashen Watch','Saturday 20:00'))
c.lifetimeHK=98765
K.PvP.RefreshHonor()
w:Fire(c,'CHAT_MSG_ADDON','KWC3','2;WORLDKB;Aurelius Emberwarden;Hillsbrad Foothills','GUILD',w.roster[2].name)
w:Fire(c,'CHAT_MSG_ADDON','KWC3','2;WORLDDEATH;Killed by: Aurelius Emberwarden;Hillsbrad Foothills','GUILD',w.roster[3].name)
local pages={'dashboard','cta','bounties','pvp','leaderboards','records','lfg','services','raids','alerts','settings'}
local cases={{1024,768,920,580,1.35},{1366,768,1100,700,1},{1920,1080,1480,940,0.9}}
local function inside(parent,widget)
 local point,_,_,x,y=widget:GetPoint()
 local bw,bh=widget:GetSize()
 if point=='TOPRIGHT' then x=parent:GetWidth()+x-bw end
 if widget.kind=='FontString' then bh=widget:GetStringHeight() end
 return {x=x,y=-y,w=bw,h=bh}
end
local function verify(label,rects,width,height)
 for i,a in ipairs(rects) do
  if a.x<0 or a.y<0 or a.x+a.w>width+0.1 or a.y+a.h>height+0.1 then
   H.Check(label,false,('control %d at %.1f,%.1f, size %.1fx%.1f in %.1fx%.1f'):format(i,a.x,a.y,a.w,a.h,width,height))
   return
  end
  for j,b in ipairs(rects) do
   if j>i and a.x<b.x+b.w and b.x<a.x+a.w and a.y<b.y+b.h and b.y<a.y+a.h then
    H.Check(label,false,'controls '..i..' and '..j..' overlap')
    return
   end
  end
 end
 H.Check(label,true)
end

for _,case in ipairs(cases) do
 local screenW,screenH,initialW,initialH,scale=unpack(case)
 c.env.UIParent:SetSize(screenW,screenH)
 local settings=c.env.KWCDB.settings
 settings.ui2Window={point='CENTER',x=0,y=0,w=initialW,h=initialH}
 settings.ui2Scale=scale
 W.Show('dashboard')
 local frame=W.Frame()
 frame:SetSize(initialW,initialH);W.FitWindow()
 local width=frame:GetWidth()-198-24-22
 local height=frame:GetHeight()-86-18-20
 local effective=frame:GetScale()
 H.Check(screenW..' window fits at requested scale '..scale,
  frame:GetWidth()*effective<=screenW-31 and frame:GetHeight()*effective<=screenH-47)
 W.content:SetSize(width,height)
 for _,id in ipairs(pages) do
  W.Show(id)
  local page=W.Current()
  page.host:SetSize(width,height)
  c.printed={}
  if id=='cta' then W.Show(id,{select=c.env.KWCDB.ops[1].id})
  elseif id=='bounties' then W.Show(id,{select=c.env.KWCDB.bounties[1].id})
  else W.Show(id) end
  w:Advance(0.4)
  local detailWidths={cta=380,bounties=380,pvp=380,records=350,lfg=380,services=340}
  for _,widget in ipairs(c.allWidgets) do
   if rawget(widget,'Layout') and (widget.search or widget.action) and widget:IsVisible() then
    -- The harness cannot infer split-pane widths from left/right anchors.
    local detail=detailWidths[id]
    local toolbarW=detail and width-detail-18 or width
    if id=='raids' then toolbarW=width-380-18 end
    widget:SetWidth(toolbarW);widget:Layout(toolbarW)
    if id=='services' then
     local column=widget:GetParent()
     column:SetWidth(toolbarW)
     for _,group in ipairs(column.children) do
      if group.segs then
       local filters={}
       for _,button in ipairs(group.segs) do filters[#filters+1]=inside(group,button) end
       verify(screenW..' populated service filter group fits',filters,toolbarW,group:GetHeight())
      end
     end
    end
    local bounds={}
    if widget.search then bounds[#bounds+1]=inside(widget,widget.search:GetParent()) end
    if widget.action then bounds[#bounds+1]=inside(widget,widget.action) end
    if widget.secondary then bounds[#bounds+1]=inside(widget,widget.secondary) end
    if widget.seg then
     local filter=inside(widget,widget.seg)
     for _,button in ipairs(widget.seg.segs) do
      local r=inside(widget.seg,button);r.y=r.y+filter.y
      bounds[#bounds+1]=r
     end
    end
    verify(screenW..' '..id..' toolbar fits without overlap',bounds,toolbarW,widget:GetHeight())
   end
  end
  if page.cards then
   local bounds={}
   for _,card in ipairs(page.cards) do bounds[#bounds+1]=inside(page.content,card) end
   verify(screenW..' '..id..' measured cards fit without overlap',bounds,width,page.content:GetHeight())
  end
  H.Check(screenW..' '..id..' updates without Lua errors',
   #c.errors==0 and not table.concat(c.printed,'\n'):find('Interface error',1,true))
  c.errors={}
 end
end
K.UI.SetScale(3)
H.Check('requested scale is still capped to 135%',c.env.KWCDB.settings.ui2Scale==1.35)
os.exit(H.Summary('ui_layout') and 0 or 1)
