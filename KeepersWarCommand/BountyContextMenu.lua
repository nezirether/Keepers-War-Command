-- Optional native player context menu integration. Never override protected nameplate clicks.
local K=KWC
local function install()
 if not Menu or type(Menu.ModifyMenu)~='function' or not Enum or not Enum.UnitPopupType then
  K.Say('Native player menu extension unavailable; use /kt bounty addtarget.')
  return
 end
 local seen={}
 for _,kind in ipairs({'Target','Player','Focus'}) do
  local menuType=Enum.UnitPopupType[kind]
  if menuType and not seen[menuType] then
   seen[menuType]=true
   local ok=pcall(Menu.ModifyMenu,menuType,function(owner,root,context)
    if not root or type(root.CreateButton)~='function' then return end
    local unit=(context and context.unit) or (kind=='Focus' and 'focus' or 'target')
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    root:CreateButton('Add to Bounty Board',function()
     K.UI.OpenBountyForUnit(unit)
    end)
   end)
   if not ok then K.Say('Player menu extension unsupported; use /kt bounty addtarget.') end
  end
 end
end
K.On('PLAYER_LOGIN',install)
