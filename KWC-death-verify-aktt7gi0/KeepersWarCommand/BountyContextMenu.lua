-- Extend the tagged Forever unit menus without replacing protected handlers.
local K=KWC
local tags={'MENU_UNIT_PLAYER','MENU_UNIT_ENEMY_PLAYER','MENU_UNIT_PARTY','MENU_UNIT_RAID','MENU_UNIT_RAID_PLAYER'}
local registered={}
local populated=setmetatable({}, {__mode='k'})

local function addBounty(_,root,context)
 if not root or populated[root] or type(root.CreateButton)~='function' then return end
 local name=K.UI.GetBountyPlayerName(context and context.unit)
 if not name then return end
 root:CreateButton('KWC: Add Bounty',function() K.UI.OpenBountyForName(name) end)
 populated[root]=true
end

local function install()
 if not Menu or type(Menu.ModifyMenu)~='function' then return end
 for _,tag in ipairs(tags) do
  if not registered[tag] then
   registered[tag]=pcall(Menu.ModifyMenu,tag,addBounty)
  end
 end
end

K.On('PLAYER_LOGIN',install)
K.On('PLAYER_ENTERING_WORLD',install)
K.On('ADDON_LOADED',function(name)
 if name=='Blizzard_Menu' or name=='Blizzard_UnitPopupShared' then install() end
end)
