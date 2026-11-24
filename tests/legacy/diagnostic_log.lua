-- K.Log (Core.lua) diagnostic logging: missing history table, nil/dirty categories,
-- secret values, and the unchanged text cap, entry cap, and newest-first order.
-- Run from the repository root with Lua 5.1 or LuaJIT.
local network=assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
local n=network(2,false)
local client=n.client(1,nil,{scoped=true})
local e=client.e
local K=e.KWC

-- 1. No KWCDB: no error and nothing written.
local saved=e.KWCDB
e.KWCDB=nil
assert(pcall(K.Log,"X","no database"),"K.Log must not throw without KWCDB")
assert(e.KWCDB==nil,"K.Log must not create KWCDB")

-- 2. KWCDB present but history not yet created: the logger creates it.
e.KWCDB={}
local ok,err=pcall(K.Log,"X","before init")
assert(ok,"K.Log must not throw when KWCDB.history is missing: "..tostring(err))
assert(type(e.KWCDB.history)=="table" and #e.KWCDB.history==1)
assert(e.KWCDB.history[1].category=="X" and e.KWCDB.history[1].text=="before init")

-- 3. A non-table history is replaced instead of crashing.
e.KWCDB={history="corrupt"}
assert(pcall(K.Log,"X","replaced"))
assert(type(e.KWCDB.history)=="table" and #e.KWCDB.history==1)
e.KWCDB=saved

-- 4. Nil, empty, and whitespace categories fall back to GENERAL so the Activity
-- view's '['..e.category..']' concatenation cannot fail.
assert(pcall(K.Log,nil,"nil category"),"nil category must not throw")
local h=e.KWCDB.history
assert(h[1].category=="GENERAL" and h[1].text=="nil category")
K.Log("","empty category")
assert(h[1].category=="GENERAL")
K.Log("\n|","control-only category")
assert(h[1].category=="GENERAL")
assert(pcall(function() return h[1].time.." ["..h[1].category.."] "..h[1].text end))

-- 5. Categories are cleaned (no pipes or newlines) and capped at 24 bytes;
-- existing short categories are stored unchanged.
K.Log("BAD|cat\nname"..string.rep("Z",40),"dirty category")
assert(not h[1].category:find("[\r\n|]"),"category must be cleaned")
assert(#h[1].category==24,"category must be capped at 24")
K.Log("RECRUIT","existing caller")
assert(h[1].category=="RECRUIT")
K.Log(42,"numeric category")
assert(h[1].category=="42")

-- 6. Secret values are never stringified.
local stringified=false
local secret=setmetatable({},{__tostring=function() stringified=true;return "LEAK" end})
e.issecretvalue=function(v) return v==secret end
K.Log("SCOUT",secret)
assert(h[1].text=="[secret]" and h[1].category=="SCOUT")
K.Log(secret,"secret category")
assert(h[1].category=="[secret]" and h[1].text=="secret category")
assert(not stringified,"secret values must not reach tostring")
e.issecretvalue=nil

-- 7. Unchanged behavior: text cleaned and capped at 230, newest first, 350 entries max.
K.Log("CTA","a|b\nc"..string.rep("x",400))
assert(#h[1].text==230 and not h[1].text:find("[\r\n|]"))
K.Log("CTA","older");K.Log("CTA","newer")
assert(h[1].text=="newer" and h[2].text=="older")
assert(type(h[1].time)=="string" and h[1].time~="")
for i=1,400 do K.Log("BULK","entry "..i) end
assert(#h==350,"history must stay capped at 350, got "..#h)
assert(h[1].text=="entry 400" and h[350].text=="entry 51")

print("PASS: K.Log tolerates missing history, nil/dirty categories, and secret values; caps and order unchanged")
