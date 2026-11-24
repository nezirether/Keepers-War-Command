-- WoW Forever compatibility: do not write to Blizzard global C_Spell.
-- The v0.1.3 global C_Spell shims tainted protected Blizzard UI at startup.
-- Future compatibility helpers must be addon-local, never inserted into C_Spell.
local addonName, addon = ...
if type(addon) == "table" then
    addon.ForeverCompat = addon.ForeverCompat or {}
end
