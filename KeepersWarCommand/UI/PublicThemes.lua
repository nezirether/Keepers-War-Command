-- One public visual identity shared by the War Room and its officer workspace.
local K=KWC
local T={default='war-room-classic',entries={},order={'war-room-classic'}}
K.PublicThemes=T
T.entries[T.default]={id=T.default,label='War Room Classic',colors={},fonts={display='display'},art={}}
function T.Get() return T.entries[T.default] end

-- Migrate the old account selection and existing character selections only.
-- A character with no appearance profile inherits the official theme.
function T.Saved()
 local settings=KWCDB and KWCDB.settings
 if settings then
  settings.ui2Skin=T.default
  if type(settings.ui2Appearance)=='table' then
   for _,profile in pairs(settings.ui2Appearance) do
    if type(profile)=='table' and profile.skin~=nil then profile.skin=T.default end
   end
  end
 end
 return T.default
end
