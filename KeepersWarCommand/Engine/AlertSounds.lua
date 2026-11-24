-- Existing alert sound preferences.
local K=KWC
local Q={};K.QOL=Q
function Q.Enabled(name)
 return not KWCDB or not KWCDB.settings or KWCDB.settings[name]~=false
end
function Q.Toggle(name)
 if not KWCDB then return end
 KWCDB.settings[name]=not Q.Enabled(name)
 K.Say(name..': '..(Q.Enabled(name) and 'ON' or 'OFF'))
end
