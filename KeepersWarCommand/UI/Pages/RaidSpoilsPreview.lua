local K=KWC
local Kit,S,P=K.Kit,K.WarRoomSkin,K.WarRoomPages
local Preview=K.WarSpoilsPreview
function P.BuildSpoilsPreview(host)
 local scroll,body=Kit.Scroll(host);scroll:SetAllPoints(host)
 local cards={}
 local function card(title,text)
  local frame=S.Card(body,title);frame.fullWidth=true
  frame.text=S.Para(frame.body,450,'text',13);frame.text:SetText(text or '')
  function frame:LayoutBody(stack) stack:Place(self.text,nil,0) end
  cards[#cards+1]=frame
  return frame
 end
 card('WarSpoils proposal comparison','Fictional five-raid replay. Thane starts at 10 with six prior wins. Ember starts at 5. Sable joins later. The proposals use identical attendance, kills, and claims.')
 for _,proposal in ipairs(Preview.policies) do
  local result=Preview.Compare(proposal.id)
  local lines={('%d points spent   |   %d points lost at cap'):format(result.spent,result.waste)}
  for _,r in ipairs(result.raiders) do
   lines[#lines+1]=('%s: %d WarSpoils, %d raids attended, %d contested wins'):format(r.name,r.points,r.attended,r.contested)
  end
  lines[#lines+1]=''
  for _,raid in ipairs(result.raids) do lines[#lines+1]=raid.label..': '..table.concat(raid.awards,', ') end
  card(proposal.label,table.concat(lines,'\n'))
 end
 local function layout()
  local width=host:GetWidth()
  P.CardGrid(body,width>0 and width or 650,cards,320)
 end
 host:HookScript('OnSizeChanged',layout)
 layout()
end
