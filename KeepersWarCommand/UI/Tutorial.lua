-- Local onboarding; uses existing preview and page controls, never posts events.
local K=KWC
local S,Kit=K.WarRoomSkin,K.Kit
local T={};K.Tutorial=T
local frame,index,active
local steps={
 {'Welcome to the War Room','Use /kt or the minimap button to open KWC. The Dashboard summarizes guild activity. This guide never posts a real event.','dashboard'},
 {'Position your alerts','All alert previews are unlocked. Drag each banner to a clear spot. Open Alerts to adjust individual size (50-200%) and opacity, or apply global values. Close previews individually if they overlap; Preview or Move can show them again.','alerts'},
 {'Alert preferences','Choose popup, sound and chat options where available. Kill alerts can include all killing blows or honorable kills only. Automatic alerts are suppressed in instances and while world state is uncertain. Manual previews remain available.','alerts'},
 {'Calls to Arms','Open the board to see active calls, location and priority. Use the response controls to tell the commander whether you can attend. Create a call only when you need real guild support.','cta'},
 {'Bounty Board','Browse targets and rewards. Use the board to post a bounty, report a sighting or claim a target. Only report real sightings and follow the guild rules for completion.','bounties'},
 {'World PvP','Review the guild activity feed and scouting information. Reports help guildmates understand where fighting is happening.','pvp'},
 {'Leaderboards','Review PvP rankings and honor statistics. Use the available tabs to distinguish different kinds of records.','leaderboards'},
 {'Deaths and guild records','Review open-world deaths separately from battleground records. Use available location details to help guildmates.','records'},
 {'Guild LFG','Browse guild groups and respond to listings. Create a listing when you need members for a real group.','lfg'},
 {'Guild services','Find guild professions and services. Review sharing preferences in Settings.','services'},
 {'Raid operations','Review raid schedules and sign-ups. Officer tools require the separate companion and appropriate rank.','raids'},
 {'Settings and addon checker','Adjust appearance, window size, sync and sharing. The Addon Checker shows versions reported by online guildmates.','settings'},
 {'Ready for battle','Finish to save your choices and lock all alert frames. Replay this guide with /kt tutorial or the Settings button.','dashboard'},
}
local function prefs() return KWCDB and KWCDB.settings end
local function unlock(on)
 for _,ch in ipairs(K.Toast.order) do ch:SetUnlocked(on) end
end
local function finish()
 if not active then return end
 active=false;unlock(false)
 if prefs() then prefs().tutorialSeen=true;prefs().tutorialFresh=nil end
 frame:Hide();if K.UI then K.UI.Refresh() end
end
local function render()
 local step=steps[index]
 frame.heading:SetText(step[1]);frame.body:SetText(step[2]);frame.count:SetText(('STEP %d / %d'):format(index,#steps))
 frame.next:SetLabel(index==#steps and 'Finish & lock' or 'Next')
 frame.back:SetShown(index>1)
end
local function build()
 frame=CreateFrame('Frame',nil,UIParent);frame:SetSize(440,230);frame:SetPoint('BOTTOM',UIParent,'BOTTOM',0,65)
 frame:SetFrameStrata('DIALOG');frame:SetClampedToScreen(true);frame:EnableMouse(true);frame:SetMovable(true);frame:RegisterForDrag('LeftButton')
 frame:SetScript('OnDragStart',function(self) self:StartMoving() end);frame:SetScript('OnDragStop',function(self) self:StopMovingOrSizing() end)
 Kit.Fill(frame,S.OWNER,'base','BACKGROUND');Kit.Border(frame,S.OWNER,'accent',1)
 frame.count=S.Text(frame,'kicker','accentText');frame.count:SetPoint('TOPLEFT',14,-12)
 frame.heading=S.Text(frame,'title','text');frame.heading:SetPoint('TOPLEFT',14,-34)
 frame.body=S.Para(frame,412,'text',13);frame.body:SetPoint('TOPLEFT',14,-65)
 frame.skip=S.Button(frame,'Skip & lock','secondary',finish,100,28);frame.skip:SetPoint('BOTTOMLEFT',14,12)
 frame.back=S.Button(frame,'Back','secondary',function() index=index-1;render() end,65,28);frame.back:SetPoint('LEFT',frame.skip,'RIGHT',6,0)
 frame.open=S.Button(frame,'Open page','secondary',function() K.UI.Open(steps[index][3]);frame:Raise() end,100,28);frame.open:SetPoint('LEFT',frame.back,'RIGHT',6,0)
 frame.next=S.Button(frame,'Next','primary',function() if index==#steps then finish() else index=index+1;render() end end,126,28);frame.next:SetPoint('BOTTOMRIGHT',-14,12)
 frame:Hide()
end
function T.Start()
 if not prefs() then return end
 if not frame then build() end
 if not active then index=1;active=true;unlock(true) end
 render();frame:Show();frame:Raise()
end
function T.Lock() if active then finish() else unlock(false) end end
function T.Unlock() if prefs() then unlock(true) end end
K.On('PLAYER_LOGIN',function()
 if prefs() and prefs().tutorialFresh and not prefs().tutorialSeen then
  T.Start()
 end
end)
