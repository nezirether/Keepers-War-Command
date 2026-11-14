local WIDTH, HEIGHT = 1188, 578
local ART = KWC.UITheme.warRoomArt
local cream, muted, bronze = {0.93,0.89,0.82}, {0.76,0.74,0.71}, {0.70,0.57,0.41}
local steel, charcoal = {0.39,0.37,0.34,1}, {0.075,0.075,0.078,1}
local frame, page, positionNote, mapMarker, moveButton
local selected, configured = 1, false
local reusable, used = {}, {}
local alerts = {
    {name="Guild Death", description="Alert when a guild member dies.", icon="Skull",
     module="WorldPvPDeaths", key="worldPvPDeath", enabled="worldPvPDeathAlerts",
     sound="worldPvPDeathSound", defaultY=0},
    {name="Bounty Spotted", description="Alert when a tracked bounty is spotted.", icon="Target",
     module="BountyAlerts", key="bountyAlert", enabled="bountyAlerts",
     sound="bountySound", defaultY=210},
}

local function locked()
    return InCombatLockdown and InCombatLockdown()
end

local function allocate(parent, kind, create)
    if parent~=page then return create() end
    local items=reusable[kind] or {}
    reusable[kind]=items
    local index=(used[kind] or 0)+1
    used[kind]=index
    local element=items[index]
    if not element then element=create();items[index]=element end
    element:ClearAllPoints()
    element:Show()
    return element
end

local function box(parent, alpha, x,y,w,h, file, color, layer, sublevel)
    local texture=allocate(parent,"texture",function() return parent:CreateTexture(nil,"ARTWORK") end)
    texture:SetDrawLayer(layer or "ARTWORK",sublevel or 0)
    texture:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    texture:SetSize(w,h)
    if file then texture:SetTexture(ART..file..".tga") else texture:SetColorTexture(unpack(color)) end
    texture:SetAlpha(alpha)
    return texture
end

local function label(parent, value, x,y,w,size, color, heading)
    local text=allocate(parent,"label",function() return parent:CreateFontString(nil,"OVERLAY") end)
    local font=heading and "Fonts\\FRIZQT__.TTF" or "Fonts\\ARIALN.TTF"
    if not text:SetFont(font,size,"") then text:SetFontObject(GameFontNormal) end
    text:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    text:SetWidth(w)
    text:SetJustifyH("LEFT")
    text:SetTextColor(unpack(color or cream))
    text:SetText(value)
    return text
end

local function panel(parent,x,y,w,h)
    box(parent,1,x,y,w,h,nil,steel,"BACKGROUND")
    box(parent,1,x+1,y+1,w-2,h-2,nil,charcoal,"BACKGROUND",1)
    box(parent,0.42,x+2,y+2,w-4,h-4,"Grain",nil,"BORDER")
end

local function button(parent, title,x,y,w,h, action, primary, icon)
    local b=allocate(parent,"button",function() return CreateFrame("Button",nil,parent) end)
    b:SetAlpha(1);b:Enable()
    b:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    b:SetSize(w,h)
    if not b.rim then
        local rim=b:CreateTexture(nil,"BACKGROUND")
        rim:SetAllPoints()
        local fill=b:CreateTexture(nil,"BORDER")
        fill:SetPoint("TOPLEFT",1,-1);fill:SetPoint("BOTTOMRIGHT",-1,1)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        local art=b:CreateTexture(nil,"ARTWORK")
        art:SetSize(23,23)
        b.rim,b.fill,b.art=rim,fill,art
        b.caption=label(b,"",0,0,w,18)
    end
    local edge=b.rim
    edge:SetAlpha(1)
    edge:SetColorTexture(unpack(primary and {0.70,0.24,0.27,1} or steel))
    b.fill:SetTexture(ART..(primary and "Crimson" or "Grain")..".tga")
    b.art:ClearAllPoints()
    b.art:SetPoint(title=="" and "CENTER" or "LEFT",b,title=="" and "CENTER" or "LEFT",title=="" and 0 or 13,0)
    b.art:SetShown(icon~=nil)
    if icon then b.art:SetTexture(ART..icon..".tga") end
    local caption=b.caption
    caption:ClearAllPoints()
    caption:SetPoint("CENTER",b,"CENTER",icon and 14 or 0,0)
    caption:SetWidth(w-(icon and 44 or 6))
    caption:SetJustifyH("CENTER")
    caption:SetText(title)
    b:SetScript("OnClick",action)
    b:SetScript("OnMouseDown",function() edge:SetAlpha(0.55) end)
    b:SetScript("OnMouseUp",function() edge:SetAlpha(1) end)
    return b
end

local function data()
    local row=alerts[selected]
    return row,KWC and KWC[row.module],KWCDB and KWCDB.settings
end

local function openPage(destination)
    if locked() or not (KWC and KWC.UI and KWC.UI.Toggle) then return end
    frame:Hide()
    KWC.UI.Toggle(destination)
end

local function updatePosition()
    if not mapMarker then return end
    local row,api,settings=data()
    if not settings or not api then
        positionNote:SetText("Alert settings are still loading.")
        moveButton:Disable()
        return
    end
    local point=settings[row.key.."Position"]
    local nx,ny=0.5,0.5+row.defaultY/math.max(UIParent:GetHeight(),1)
    if type(point)=="table" and type(point.nx)=="number" and type(point.ny)=="number" then
        nx,ny=point.nx,point.ny
    end
    nx,ny=math.max(0,math.min(1,nx)),math.max(0,math.min(1,ny))
    mapMarker:ClearAllPoints()
    mapMarker:SetPoint("TOPLEFT",page,"TOPLEFT",906+164*nx,-(276+103*(1-ny)))
    local moving=settings[row.key.."Unlocked"]
    moveButton:SetEnabled(not locked())
    moveButton.caption:SetText(moving and "Lock position" or "Move alert")
    positionNote:SetText(moving and "Drag the live alert, then lock its position." or "Set where this alert appears on screen.")
end

local function draw()
    if not page then
        page=CreateFrame("Frame",nil,frame)
        page:SetAllPoints(frame)
    end
    for kind,items in pairs(reusable) do
        for _,item in ipairs(items) do item:Hide() end
        used[kind]=0
    end
    mapMarker=nil
    label(page,"Alert Command Center",256,78,860,37,cream,true)
    label(page,"Manage guild alerts, triggers, and on-screen display.",256,132,850,21,muted)
    box(page,0.85,255,167,906,1,nil,steel)
    box(page,0.65,856,168,1,386,nil,steel)

    for i,row in ipairs(alerts) do
        local y=187+(i-1)*178
        local api=KWC and KWC[row.module]
        local settings=KWCDB and KWCDB.settings
        local enabled=api and settings and settings[row.enabled]~=false
        panel(page,257,y,584,160)
        box(page,1,276,y+18,102,102,row.icon)
        label(page,row.name,397,y+14,300,29,cream,true)
        label(page,row.description,397,y+54,417,19,muted)
        local state=enabled and "Enabled" or (api and settings and "Disabled" or "Unavailable")
        box(page,1,705,y+24,119,34,nil,enabled and {0.42,0.51,0.14,1} or steel)
        box(page,1,706,y+25,117,32,nil,enabled and {0.13,0.18,0.055,1} or charcoal,"ARTWORK",1)
        label(page,state,718,y+31,104,17,enabled and {0.90,0.94,0.75} or muted)
        local configure=button(page,"Configure",397,y+95,200,45,function()
            selected,configured=i,true
            draw()
        end,true,"Gear")
        local test=button(page,"Test alert",612,y+95,209,45,function()
            if locked() then return end
            local changed=selected~=i
            selected=i
            if changed then configured=false;draw() end
            api.Demo()
        end,false,"Play")
        configure:SetEnabled(not not (settings and api))
        test:SetEnabled(not not (settings and api and api.Demo))
        if not (settings and api) then configure:SetAlpha(0.48);test:SetAlpha(0.48) end
    end

    local row,api,settings=data()
    label(page,configured and row.name or "Position",885,191,278,28,cream,true)
    if configured and api and settings then
        label(page,"Change this alert's popup and sound.",885,228,270,18,muted)
        button(page,settings[row.enabled]==false and "Enable popup" or "Disable popup",885,265,268,37,function()
            if not locked() then api.SetEnabled(settings[row.enabled]==false);draw() end
        end,true)
        button(page,settings[row.sound]==false and "Enable sound" or "Disable sound",885,311,268,37,function()
            if locked() then return end
            if row.module=="WorldPvPDeaths" then api.SetSound(settings[row.sound]==false)
            elseif KWC.QOL then KWC.QOL.Toggle(row.sound) end
            draw()
        end)
        button(page,"Position",885,357,268,37,function() configured=false;draw() end)
        button(page,"Full alert settings",885,403,268,37,function() openPage("Alerts") end)
    else
        positionNote=label(page,"",885,226,276,17,muted)
        panel(page,889,259,266,145)
        box(page,0.5,1021,263,1,136,nil,steel)
        box(page,0.5,893,330,258,1,nil,steel)
        for _,x in ipairs({901,1132}) do
            for _,y in ipairs({271,385}) do
                box(page,1,x,y,11,2,nil,{0.83,0.76,0.62,1})
                box(page,1,x+(x==1132 and 9 or 0),y+(y==385 and -7 or 0),2,9,nil,{0.83,0.76,0.62,1})
            end
        end
        mapMarker=box(page,1,971,315,70,26,"Crimson")
        moveButton=button(page,"Move alert",889,426,266,43,function()
            if not api or not settings or locked() then return end
            api.SetUnlocked(not settings[row.key.."Unlocked"])
            updatePosition()
        end,true,"Move")
        local reset=button(page,"Reset position",889,483,266,41,function()
            if api and not locked() then api.ResetPosition();updatePosition() end
        end,false,"Reset")
        reset:SetEnabled(not not (api and settings))
        updatePosition()
    end
end

local function fit()
    local ratio=math.min(UIParent:GetWidth()/(WIDTH+24),UIParent:GetHeight()/(HEIGHT+36),1)
    frame:SetScale(ratio)
end

local function create()
    frame=CreateFrame("Frame","KWCWarRoomAlerts",UIParent)
    frame:SetSize(WIDTH,HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(90)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    panel(frame,0,0,WIDTH,HEIGHT)
    box(frame,1,9,8,1170,57,"Grain",nil,"BORDER")
    box(frame,0.62,10,65,221,502,"Grain",nil,"BACKGROUND")
    box(frame,0.58,231,66,1,501,nil,steel)
    box(frame,1,12,1,1164,9,"Steel")
    box(frame,1,12,568,1164,9,"Steel")
    for _,x in ipairs({1,1178}) do
        local rail=box(frame,1,x,10,9,558,"Steel")
        rail:SetTexCoord(0,1,1,1,0,0,1,0)
    end
    for i,corner in ipairs({{0,0},{1164,0},{0,554},{1164,554}}) do
        local cap=box(frame,1,corner[1],corner[2],24,24,"Corner",nil,"OVERLAY")
        cap:SetTexCoord(i%2==0 and 1 or 0,i%2==0 and 0 or 1,i>2 and 1 or 0,i>2 and 0 or 1)
    end
    box(frame,0.84,12,63,1164,3,"Steel")
    box(frame,0.75,65,429,126,143,"Insignia",nil,"BORDER")
    box(frame,1,39,11,54,54,"Logo",nil,"OVERLAY")
    box(frame,0.8,120,20,1,37,nil,bronze)
    label(frame,"Keepers War Command",142,22,773,27,cream,true)
    local drag=CreateFrame("Frame",nil,frame)
    drag:SetPoint("TOPLEFT",frame,"TOPLEFT",12,-10)
    drag:SetSize(1020,50)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart",function() frame:StartMoving() end)
    drag:SetScript("OnDragStop",function() frame:StopMovingOrSizing() end)
    local gear=button(frame,"",1068,20,41,36,function() openPage("Settings") end,false,"Gear")
    gear:SetScript("OnEnter",function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText("Settings");GameTooltip:Show()
        end
    end)
    gear:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
    gear:SetFrameLevel(drag:GetFrameLevel()+2)
    local close=button(frame,"×",1124,20,40,36,function() frame:Hide() end,true)
    close:SetFrameLevel(drag:GetFrameLevel()+2)
    local nav={
        {"Alerts","Horn",function() configured=false;draw() end},
        {"Bounties","Flag",function() openPage("Bounty Board") end},
        {"Guild","Guild",function() openPage("Guild Roster") end},
        {"Reports","Reports",function() openPage("Sync Health") end},
        {"Settings","Gear",function() openPage("Settings") end},
    }
    for i,item in ipairs(nav) do
        local y=96+(i-1)*61
        local tab=button(frame,item[1],13,y,216,55,item[3],i==1,item[2])
        tab.caption:ClearAllPoints();tab.caption:SetPoint("LEFT",tab,"LEFT",83,0)
        tab.caption:SetJustifyH("LEFT");tab.caption:SetWidth(128)
        tab.art:ClearAllPoints();tab.art:SetPoint("LEFT",tab,"LEFT",25,0);tab.art:SetSize(33,33)
        if i<5 then box(frame,0.45,27,y+57,189,1,nil,steel) end
    end
    button(frame,"Command Center",24,410,195,33,function() openPage("Home") end)
    local elapsed=0
    frame:SetScript("OnUpdate",function(_,delta)
        elapsed=elapsed+delta
        if elapsed>=0.2 then elapsed=0;updatePosition() end
    end)
    frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    frame:RegisterEvent("UI_SCALE_CHANGED")
    frame:SetScript("OnEvent",fit)
    if UISpecialFrames then table.insert(UISpecialFrames,"KWCWarRoomAlerts") end
end

KWC.AlertOverview={}
function KWC.AlertOverview.Toggle()
    if locked() then return end
    if frame and frame:IsShown() then frame:Hide();return end
    if not frame then create() end
    local host=KWC and KWC.UI and KWC.UI.GetHost and KWC.UI.GetHost()
    if host and host:IsShown() then KWC.UI.Toggle() end
    fit()
    draw()
    frame:Show()
end

function KWC.AlertOverview.Close()
    if frame then frame:Hide() end
end
