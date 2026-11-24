-- One pooled preview list inside Settings; the existing War Room is the full-size preview.
local K=KWC
local Kit,S,P,T=K.Kit,K.WarRoomSkin,K.WarRoomPages,K.PublicThemes
local OWNER=S.OWNER
local shelves={{'all','All themes'},{'favorites','Favorites'},{'recent','Recently used'},{'current','Current theme'}}
local collections={{'any','All collections'}}
for _,name in ipairs(T.collections) do collections[#collections+1]={name} end

function P.AppearanceGallery(card)
 local body=card.body
 local query,shelf,collection,selected='','all','any',nil
 local gallery={};local update
 local search=S.Field(body,'Search skins',320,40,'Name or collection')
 search.edit:HookScript('OnTextChanged',function(self) query=self:GetText();update(true) end)
 local tabs=S.Segmented(body,shelves,function() return shelf end,function(value) shelf=value;update(true) end,104)
 local groups=S.Segmented(body,collections,function() return collection end,function(value) collection=value;update(true) end)
 local resultCount=S.Text(body,'kicker','accentText')
 local function tint(texture,color) texture:SetColorTexture(color[1],color[2],color[3],color[4] or 1) end
 local list=Kit.List(body,48,4,function(row)
  S.RowBuild(row)
  local thumb=CreateFrame('Frame',nil,row);thumb:SetSize(62,36);thumb:SetPoint('LEFT',11,0)
  row.swatches={}
  row.swatches[1]=thumb:CreateTexture(nil,'ARTWORK');row.swatches[1]:SetAllPoints(thumb)
  row.swatches[2]=thumb:CreateTexture(nil,'ARTWORK',nil,1);row.swatches[2]:SetPoint('TOPLEFT',0,0);row.swatches[2]:SetPoint('TOPRIGHT');row.swatches[2]:SetHeight(8)
  row.art=thumb:CreateTexture(nil,'ARTWORK',nil,2);row.art:SetAllPoints(thumb)
  row.trimPreview=thumb:CreateTexture(nil,'ARTWORK',nil,3);row.trimPreview:SetAllPoints(thumb)
  row.swatches[3]=thumb:CreateTexture(nil,'ARTWORK',nil,3);row.swatches[3]:SetSize(22,5);row.swatches[3]:SetPoint('BOTTOMRIGHT',-5,5)
  row.title:SetPoint('TOPLEFT',row,'TOPLEFT',84,-7)
  row:SetScript('OnClick',function(self)
   selected=self.item.id;S.Preview(selected);update()
  end)
 end,function(row,skin)
  row.title:SetText(skin.label)
  row.sub:SetText(skin.collection..' · '..skin.description)
  row.meta:SetText(skin.id==S.Current() and 'Applied' or skin.id==S.Active() and 'Preview' or '')
  local prefs=T.Preferences()
  row.meta2:SetText(T.IsFavorite(skin.id,prefs) and 'Favorite' or '')
  tint(row.swatches[1],skin.colors.base);tint(row.swatches[2],skin.colors.header);tint(row.swatches[3],skin.colors.accent)
  S.DrawArt(row.art,skin.id,'thumbnail',62,36)
  S.DrawArt(row.trimPreview,skin.id,'trim')
  row:Select(skin.id==(selected or S.Active()))
 end)
 list:SetHeight(204)
 list.empty=S.Empty(list,'No skins match','Clear the search or choose a different collection.',300)
 list.empty:SetPoint('TOPLEFT',4,-5)
 Kit.Paint(list.thumb,OWNER,'accent','fill')
 local prev=S.Button(body,'Previous','secondary',function() list:Page(-1) end,92,32)
 local next=S.Button(body,'Next','secondary',function() list:Page(1) end,84,32)
 list.header={SetRange=function(_,offset,n,total)
  resultCount:SetText(n>0 and ('%d–%d of %d matches'):format(offset+1,offset+n,total) or ('%d matches'):format(total))
  prev:SetEnabledState(offset>0,'First page')
  next:SetEnabledState(offset+n<total,'Last page')
 end}
 local summary=S.Para(body,400,'text',13)
 local swatch=CreateFrame('Frame',nil,body);swatch:SetHeight(74);swatch:EnableMouse(false)
 Kit.Fill(swatch,OWNER,'header');Kit.Border(swatch,OWNER,'lineSoft')
 local image=CreateFrame('Frame',nil,swatch)
 image:SetPoint('TOPLEFT',swatch,'TOP',0,0);image:SetPoint('BOTTOMRIGHT',swatch,'BOTTOMRIGHT',-1,1)
 image:EnableMouse(false);S.Art(image,'banner');S.Art(image,'material','ARTWORK')
 S.Art(swatch,'trim','BORDER')
 local badge=CreateFrame('Frame',nil,swatch);badge:SetSize(40,40);badge:SetPoint('LEFT',12,0)
 badge:EnableMouse(false);S.Art(badge,'crest','ARTWORK');S.Art(badge,'sigil','OVERLAY')
 local previewLabel=S.Text(swatch,'section','text')
 previewLabel:SetPoint('LEFT',badge,'RIGHT',10,0);previewLabel:SetPoint('RIGHT',swatch,'CENTER',-5,0)
 previewLabel:SetJustifyH('LEFT')
 local save=S.Button(body,'Apply preview','primary',function() S.Apply(S.Active());update() end,125,36)
 local cancel=S.Button(body,'Cancel preview','secondary',function() S.CancelPreview();selected=nil;update() end,130,36)
 local star=S.Button(body,'Toggle favorite','secondary',function() T.ToggleFavorite(selected or S.Active());update() end,132,36)
 local reset=S.Button(body,'Reset theme','secondary',function() S.Reset();selected=nil;update() end,112,36)

 update=function(scrollTop)
  if scrollTop then list:ScrollTo(1) end
  local prefs=T.Preferences()
  local source=shelf=='recent' and T.Recent(prefs) or shelf=='current' and {S.Current()} or T.order
  local rows={}
  for _,id in ipairs(source) do
   local theme=T.Get(id)
   local favorite=T.IsFavorite(id,prefs)
   if theme and (shelf~='favorites' or favorite) and (collection=='any' or collection==theme.collection)
    and P.Matches(theme.label..' '..theme.collection,query) then rows[#rows+1]=theme end
  end
  list:SetData(rows)
  tabs:Update();groups:Update()
  local preview=S.IsPreviewing()
  local theme=T.Get(S.Active())
  if previewLabel:GetText()~=theme.label then previewLabel:SetText(theme.label) end
  summary:SetText((preview and 'Previewing ' or 'Applied: ')..theme.label..' · '..theme.description)
  save:SetEnabledState(preview,'Select a skin to preview it.')
  cancel:SetEnabledState(preview,'No preview is active.')
 end

 function gallery:Layout(stack)
  stack:Place(search,52,4)
  tabs:SetHeight(P.SegmentWidth(tabs,stack.width))
  stack:Place(tabs,nil,8)
  P.SegmentWidth(groups,stack.width)
  stack:Place(groups,nil,8)
  stack:Place(resultCount,nil,6)
  stack:Place(list,204,8)
  stack:Actions({prev,next},8)
  stack:Place(swatch,74,8)
  stack:Place(summary,nil,9)
  stack:Actions({save,cancel,star,reset},4)
 end
 function gallery:Update() update() end
 update()
 return gallery
end
