-- Sidebar grouping, order, officer visibility, selection highlight and spacing.
local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})
local c=w:Client('Grom Warcry')
w:LoadAddon(c,'KeepersWarCommand');w:Login(c);w:Advance(6)
local W=c.env.KWC.WarRoom2
-- Stand-in for the officer companion's page, registered the way it registers.
local officer=true
W.Register({id='officer-command',title='War Council',group='guild',CanShow=function() return officer end,Build=function() end})
W.Show('dashboard')

local function buttons()
 local out={}
 for _,b in ipairs(c.allWidgets) do if rawget(b,'page') and rawget(b,'bar') and b:IsShown() then out[#out+1]=b end end
 table.sort(out,function(a,b) return a.contentTop<b.contentTop end)
 return out
end
local function headers()
 local out={}
 for _,t in ipairs(c.allWidgets) do
  local text=t.kind=='FontString' and t:GetText()
  if (text=='WAR ROOM' or text=='GUILD SUPPORT' or text=='ADVANCED' or text=='HONORS' or text=='GUILD') and t:IsShown() and t:GetNumPoints()==1 then
   local point,_,_,x,y=t:GetPoint();if point=='TOPLEFT' and x==18 then out[#out+1]={text=text,top=-y} end
  end
 end
 return out
end
local function listing()
 local rows=headers()
 for _,b in ipairs(buttons()) do rows[#rows+1]={text=b.text:GetText(),top=b.contentTop} end
 table.sort(rows,function(a,b) return a.top<b.top end)
 local out={};for _,r in ipairs(rows) do out[#out+1]=r.text end
 return table.concat(out,' | ')
end
local expected='WAR ROOM | Dashboard | Leaderboards | World PvP | Bounty Board | Calls to Arms | Guild Records | '..
 'GUILD SUPPORT | Guild Hall | War Council | ADVANCED | Alerts | Settings'
H.Check('officer sees the three groups in order',listing()==expected,listing())

local function spacing(label)
 local list,previous,clean=buttons(),0,true
 for _,b in ipairs(list) do
  if b.contentTop<previous then clean=false end
  previous=b.contentTop+b:GetHeight()
 end
 H.Check(label..' buttons do not overlap',clean)
 local headed=true
 for _,h in ipairs(headers()) do for _,b in ipairs(list) do
  if h.top>=b.contentTop and h.top<b.contentTop+b:GetHeight() then headed=false end
 end end
 H.Check(label..' headings are clear of buttons',headed)
 -- 560 minimum window height less the 72 brand block and 32 footer.
 H.Check(label..' rail fits the minimum window',previous<=560-72-32,previous)
end
spacing('officer')
for _,b in ipairs(buttons()) do
 local id=b.page.id
 if b.hall then W.Show('raids');id='raids' end
 W.Show(id)
 local selected={}
 for _,other in ipairs(buttons()) do if other.bar:IsShown() then selected[#selected+1]=other.hall and 'raids' or other.page.id end end
 if b.hall then W.Show(id) end
 H.Check('navigating to '..id..' highlights only it',W.Current().id==id and table.concat(selected,',')==id,table.concat(selected,','))
end
local function hall() for _,b in ipairs(buttons()) do if b.hall then return b end end end
local function tab(id) for _,s in ipairs(W.hallTabs.segs) do if s.value==id then return s end end end
local function marked() local out={};for _,s in ipairs(W.hallTabs.segs) do if s.mark:IsShown() then out[#out+1]=s.value end end;return table.concat(out,',') end
for _,id in ipairs({'raids','services','lfg','services'}) do
 tab(id):Click()
 H.Check('Guild Hall tab '..id..' opens its page and highlights',W.Current().id==id and marked()==id and hall().bar:IsShown()
  and W.hallTabs:IsShown() and not W.pageSub:IsShown() and W.pageTitle:GetText()=='Guild Hall')
 local only=true
 for other,page in pairs(W.pages) do if page.host and page.host:IsShown()~=(other==id) then only=false end end
 H.Check(id..' is the only visible page',only)
end
hall():GetScript('OnEnter')(hall());hall():GetScript('OnLeave')(hall())
H.Check('hover keeps the Guild Hall highlight',hall().selected and hall().bar:IsShown())
W.Show('dashboard')
H.Check('tabs leave with the Guild Hall',not W.hallTabs:IsShown() and W.pageSub:IsShown() and not hall().bar:IsShown())
hall():Click()
H.Check('Guild Hall returns to the last section',W.Current().id=='services')
for command,id in pairs({lfg='lfg',raids='raids',raid='raids',services='services',professions='services'}) do
 W.Show('dashboard');c.env.SlashCmdList.KEEPERSWARCOMMAND(command)
 H.Check('/kt '..command..' still opens its section',W.Current().id==id and marked()==id)
end
for label,id in pairs({['Guild LFG']='lfg',['Guild Services']='services',['Raids']='raids'}) do
 c.env.KWC.UI.Open(label);H.Check('direct link '..label..' still opens',W.Current().id==id)
end
-- Signup and group indicators: per section on the tabs, combined on the rail.
W.pages.raids.Badge=function() return 2 end;W.pages.lfg.Badge=function() return 3 end
W.Show('raids')
H.Check('indicators show on tabs and rail',tab('raids').text:GetText()=='Raid Operations (2)' and tab('lfg').text:GetText()=='Guild LFG (3)'
 and tab('services').text:GetText()=='Guild Services' and hall().badge:GetText()=='5')
W.pages.raids.Badge=function() return 0 end;W.pages.lfg.Badge=function() return 0 end;W.Show('raids')
H.Check('indicators clear',hall().badge:GetText()=='' and tab('raids').text:GetText()=='Raid Operations')
-- Strip tabs clear the close button at the minimum window and never move content.
local last=W.hallTabs.segs[3];local p={last:GetPoint()}
H.Check('tabs fit the minimum window strip',24+p[4]+last:GetWidth()<=900-212-58 and 43+28<=72)
H.Check('page heading uses the new group name',(function() W.Show('lfg');return W.pageGroup:GetText()=='GUILD SUPPORT' end)())
H.Check('Guild Records sits in the War Room group',(function() W.Show('records');return W.pageGroup:GetText()=='WAR ROOM' end)())

officer=false
W.Show('officer-command')
H.Check('a non-officer cannot open War Council',W.Current().id=='dashboard')
H.Check('non-officer list omits only War Council',listing()==expected:gsub(' | War Council',''),listing())
spacing('member')
H.Check('no Lua errors',#c.errors==0 and not table.concat(c.printed,'\n'):find('Interface error',1,true),c.errors[1])
os.exit(H.Summary('nav_groups') and 0 or 1)
