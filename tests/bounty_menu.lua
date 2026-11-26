-- Run from the repository root with Lua 5.1 or LuaJIT.
local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})
local c=w:Client('Grom Warcry')
local env=c.env
local tags,picked,target={},nil,'Enemy'
w:LoadAddon(c,'KeepersWarCommand')
env.UnitExists=function(unit) return unit~='missing' end
env.UnitIsPlayer=function(unit) return unit~='npc' end
env.UnitFullName=function(unit)
 if unit=='target' then return target,'Realm' end
 if unit=='focus' then return 'Focus','Realm' end
 if unit=='player' then return 'Grom Warcry' end
end
env.UnitName=env.UnitFullName
w:Login(c);w:Advance(6)
local K=env.KWC
assert(next(tags)==nil)
K.UI.OpenBountyForName=function(name) picked=name end
env.SlashCmdList.KEEPERSWARCOMMAND('bounty addtarget')
assert(picked=='Enemy-Realm',tostring(picked))
env.Menu={ModifyMenu=function(tag,callback)
 assert(not tags[tag],'duplicate registration');tags[tag]=callback
end}
w:Fire(c,'ADDON_LOADED','Blizzard_Menu')
w:Fire(c,'PLAYER_ENTERING_WORLD')
w:Fire(c,'PLAYER_LOGIN')
assert(tags.MENU_UNIT_PLAYER and tags.MENU_UNIT_RAID and tags.MENU_UNIT_ENEMY_PLAYER and tags.MENU_UNIT_PARTY)
local options={}
local root={CreateButton=function(_,text,callback)
 assert(text=='KWC: Add Bounty');table.insert(options,callback)
end}
local callback=tags.MENU_UNIT_ENEMY_PLAYER
callback(nil,root,{unit='npc'})
callback(nil,root,{})
assert(#options==0)
callback(nil,root,{unit='target'})
callback(nil,root,{unit='target'})
assert(#options==1)
target='Different'
options[1]()
assert(picked=='Enemy-Realm')
K.UI.OpenBountyForUnit('focus')
assert(picked=='Focus-Realm',tostring(picked))
local said=#c.printed
K.UI.OpenBountyForUnit('missing')
assert(c.printed[said+1]:find('Target a player first.',1,true))
assert(#c.errors==0,c.errors[1])
print('PASS: Forever tagged menus, delayed and duplicate registration, captured full name and target fallback')
