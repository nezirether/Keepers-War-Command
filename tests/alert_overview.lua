local frames={}
local methods={}
for _,key in ipairs({"SetPoint","ClearAllPoints","SetSize","SetScale","SetAllPoints","SetDrawLayer",
 "SetTexture","SetColorTexture","SetJustifyH","SetTextColor","SetWidth","SetAlpha",
 "SetHighlightTexture","SetFontObject","SetTexCoord","SetClampedToScreen","SetMovable",
 "EnableMouse","RegisterForDrag","RegisterEvent","SetFrameStrata"}) do methods[key]=function() end end
function methods:SetFont() return true end
function methods:SetFrameLevel(value) self.level=value end
function methods:GetFrameLevel() return self.level or 0 end
function methods:GetWidth() return 1600 end
function methods:GetHeight() return 900 end
function methods:SetText(value) self.text=value end
function methods:SetScript(key,value) self[key]=value end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:SetShown(value) self.shown=value end
function methods:IsShown() return self.shown end
function methods:SetEnabled(value) self.enabled=value end
function methods:Disable() self.enabled=false end
function methods:Enable() self.enabled=true end
local function object() return setmetatable({shown=true},{__index=methods}) end
methods.CreateTexture=object
methods.CreateFontString=object
UIParent=object()
UISpecialFrames={}
SlashCmdList={}
local combat=false
InCombatLockdown=function() return combat end
function CreateFrame(kind,name,parent)
    local f=object()
    f.parent=parent
    frames[#frames+1]=f
    if name then _G[name]=f end
    return f
end
local function visible(item)
    return item:IsShown() and (not item.parent or visible(item.parent))
end
local function click(text,index)
    local count=0
    for _,f in ipairs(frames) do
        if f.caption and f.caption.text==text and visible(f) then
            count=count+1
            if count==(index or 1) then
                assert(f.enabled,"button disabled: "..text)
                f:OnClick()
                return
            end
        end
    end
    error("button missing: "..text)
end
local settings={bountyAlerts=false}
KWCDB={settings=settings}
local opened={}
local tested={}
local function api(key,enabledKey)
    return {
        Demo=function() tested[#tested+1]=key end,
        SetEnabled=function(value) settings[enabledKey]=value end,
        SetUnlocked=function(value) settings[key.."Unlocked"]=value end,
        ResetPosition=function() settings[key.."Position"]=nil end,
        SetSound=function(value) settings[key.."Sound"]=value end,
    }
end
KWC={
    UITheme={warRoomArt="Interface\\\\AddOns\\\\KeepersWarCommand\\\\Textures\\\\WarRoom\\\\"},
    WorldPvPDeaths=api("worldPvPDeath","worldPvPDeathAlerts"),
    BountyAlerts=api("bountyAlert","bountyAlerts"),
    QOL={Toggle=function(key) settings[key]=settings[key]==false end},
    UI={Toggle=function(destination) opened[#opened+1]=destination end},
}
assert(loadfile("KeepersWarCommand/AlertOverview.lua"))()
KWC.AlertOverview.Toggle()
assert(KWCWarRoomAlerts:IsShown() and #UISpecialFrames==1)
click("Test alert")
assert(tested[1]=="worldPvPDeath")
click("Move alert")
assert(settings.worldPvPDeathUnlocked)
settings.worldPvPDeathPosition={nx=0.8,ny=0.7}
KWCWarRoomAlerts:OnUpdate(0.25)
click("Lock position")
assert(not settings.worldPvPDeathUnlocked)
click("Reset position")
assert(not settings.worldPvPDeathPosition)
click("Configure",2)
click("Enable popup")
assert(settings.bountyAlerts)
click("Disable sound")
assert(settings.bountySound==false)
click("Position")
click("Move alert")
assert(settings.bountyAlertUnlocked and not settings.worldPvPDeathUnlocked)
click("Lock position")
click("Test alert",2)
assert(tested[2]=="bountyAlert")
local count=#frames
for _=1,15 do
    click("Configure")
    click("Position")
end
assert(#frames==count,"redrawing should reuse frames")
for _,route in ipairs({{"Command Center","Home"},{"Bounties","Bounty Board"},{"Guild","Guild Roster"},{"Reports","Sync Health"},{"Settings","Settings"}}) do
    click(route[1])
    assert(opened[#opened]==route[2] and not KWCWarRoomAlerts:IsShown())
    KWC.AlertOverview.Toggle()
end
combat=true
click("Test alert")
assert(#tested==2)
combat=false
KWC.AlertOverview.Toggle()
assert(not KWCWarRoomAlerts:IsShown())
KWC.BountyAlerts=nil
KWC.AlertOverview.Toggle()
click("Test alert")
assert(#tested==3)
print("PASS: navigation, alert APIs, placement, missing module, combat guard, and widget reuse")
