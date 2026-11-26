-- Officer companion integration contract. Companions check K.integrationVersion,
-- not the release version. If a change here would break a companion (a member below
-- removed, renamed or given different behaviour), raise K.integrationVersion and
-- update this list. Release version changes alone never require that.
--
-- Contract 1 also includes: the KWCDB.ops and KWCDB.bounties record lists, and
-- K.Officer, where a companion attaches Open, Refresh, version and IsAuthorized.
-- IsAuthorized returns allowed, reason, {actor,guild,rank,guid}.
local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})
local c=w:Client('Grom Warcry');w:LoadAddon(c,'KeepersWarCommand')
-- A companion reads these while its files load, before login.
local K=c.env.KWC
local contract={
 [1]={
  ['function']={'CurrentGuildMember','GuildReadiness','GuildScope','IsSenderOfficer','LocalGuildMember','On','SameGuildMember','Say',
   'AddonChecker.ForRoster','Celebrations.CompleteCTA','Celebrations.Outcome','Identity.RosterGUID','Identity.RosterName',
   'Kit.Border','Kit.EditBox','Kit.Fill','Kit.List','Kit.Paint','Kit.Scroll','Kit.Tooltip','Net.Send','Net.SendParts',
   'OfficerBroadcast.Preview','OfficerBroadcast.Receive',
   'Operations.AddSighting','Operations.AssignLieutenant','Operations.AssumeCommand','Operations.CanDelete','Operations.CTALeadership',
   'Operations.ChangeStatus','Operations.ClaimBounty','Operations.Commanders','Operations.CreateCTA','Operations.Delete',
   'Operations.RestoreCommander','Operations.UpdateBounty','Operations.UpdateCTA',
   'WarRoom2.Refresh','WarRoom2.Register','WarRoom2.Show',
   'WarRoomPages.CardGrid','WarRoomPages.Flow','WarRoomPages.SegmentWidth','WarRoomPages.Stack',
   'WarRoomSkin.AssetPath','WarRoomSkin.Button','WarRoomSkin.Card','WarRoomSkin.Confirm','WarRoomSkin.Field','WarRoomSkin.Kick',
   'WarRoomSkin.OnThemeChange','WarRoomSkin.Para','WarRoomSkin.Segmented','WarRoomSkin.Text','WarRoomSkin.ThemedTexture'},
  ['table']={'Officer'},
  ['boolean']={'Net.GuardSupported','WarRoom2.PrivatePageSupported'},
  ['string']={'version'},
 },
}
H.Check('public KWC declares an integer integration version',type(K.integrationVersion)=='number' and K.integrationVersion%1==0 and K.integrationVersion>=1,tostring(K.integrationVersion))
local expected=contract[K.integrationVersion]
H.Check('the declared version has a recorded interface list',expected~=nil,tostring(K.integrationVersion))
for kind,names in pairs(expected or {}) do
 local wrong={}
 for _,path in ipairs(names) do
  local v=K
  for part in path:gmatch('[^.]+') do v=type(v)=='table' and v[part] or nil end
  if type(v)~=kind then wrong[#wrong+1]=path..'='..type(v) end
 end
 H.Check('contract '..kind..' members are present ('..#names..')',#wrong==0,table.concat(wrong,', '))
end
w:Login(c);w:Advance(5)
H.Check('operation record lists exist',type(c.env.KWCDB.ops)=='table' and type(c.env.KWCDB.bounties)=='table')
H.Check('no Lua errors',#c.errors==0,c.errors[1])
os.exit(H.Summary('integration_contract') and 0 or 1)
