-- Run from the repository root with Lua 5.1 or LuaJIT.
local epoch = 1794592800
local roster = {
    alpha={name="Alpha One"},
    bravo={name="Bravo Two"},
    charlie={name="Charlie Three",online=false},
    delta={name="Delta Four"},
}

local function client(player, saved)
    local handlers, packets, timers = {}, {}, {}
    local c = {now=epoch, world="--", bg="--", lifetime=123, refreshes=0, slots={381,382,399}}
    local env = setmetatable({
        KWCDB=saved or {pvp={},roster=roster},
        date=os.date, time=function() return c.now end,
        UnitFullName=function() return player end,
        IsInGuild=function() return true end,
        GetPVPLifetimeStats=function() return c.lifetime end,
        GetStatisticsCategoryList=function() return {[2]=18} end,
        GetCategoryNumAchievements=function() return #c.slots end,
        GetStatistic=function(category,index)
            assert(category==18)
            local id=c.slots[index]
            if id==381 then return c.world,c.skipWorld,id end
            if id==382 then return c.bg,false,id end
            return "90000",false,id
        end,
        C_Timer={After=function(_,callback) timers[#timers+1]=callback end},
        KWC={
            On=function(event,fn)
                handlers[event]=handlers[event] or {}
                table.insert(handlers[event],fn)
            end,
            Send=function(kind,payload)
                packets[#packets+1]={kind=kind,message="2;"..kind..";"..payload}
                return true
            end,
            IsMember=function(sender) return roster[sender:lower():match("^%w+")]~=nil end,
            UI={Refresh=function() c.refreshes=c.refreshes+1 end},
        }
    }, {__index=_G})
    c.db,c.env,c.packets=env.KWCDB,env,packets
    setfenv(assert(loadfile("KeepersWarCommand/PvP.lua")),env)()
    c.pvp=env.KWC.PvP
    function c.fire(event,...)
        for _, fn in ipairs(handlers[event] or {}) do fn(...) end
    end
    function c.receive(sender,message)
        c.fire("CHAT_MSG_ADDON","KWC3",message,"GUILD",sender)
    end
    function c.flush()
        local pending=timers
        timers={}
        for _, fn in ipairs(pending) do fn() end
    end
    function c.last(kind)
        for i=#packets,1,-1 do if packets[i].kind==kind then return packets[i].message end end
    end
    function c.count(kind)
        local n=0
        for _,p in ipairs(packets) do if p.kind==kind then n=n+1 end end
        return n
    end
    function c.score(name,metric)
        for _,r in ipairs(c.pvp.Rankings(metric)) do if r.name==name then return r.value end end
    end
    return c
end

local alpha=client("Alpha One")
alpha.fire("PLAYER_ENTERING_WORLD")
assert(alpha.score("Alpha One","lifetime")==123)
assert(#alpha.pvp.Rankings("world")==0 and #alpha.pvp.Rankings("battleground")==0)
assert(not alpha.last("HKAREA"))
alpha.world,alpha.bg="19","0"
alpha.fire("PLAYER_PVP_KILLS_CHANGED")
assert(alpha.score("Alpha One","world")==19 and alpha.score("Alpha One","battleground")==0)
local sent=alpha.count("HKAREA")
alpha.fire("COMBAT_LOG_EVENT_UNFILTERED","UNIT_DIED")
alpha.fire("PLAYER_PVP_KILLS_CHANGED")
alpha.fire("HONOR_XP_UPDATE")
alpha.fire("PLAYER_ENTERING_WORLD","arena")
assert(alpha.count("HKAREA")==sent and alpha.score("Alpha One","world")==19)
alpha.now=epoch+10
alpha.world,alpha.bg="19","41"
alpha.slots={382,399,381}
alpha.fire("CRITERIA_UPDATE")
alpha.fire("CRITERIA_UPDATE")
alpha.flush()
assert(alpha.count("HKAREA")==sent+1 and alpha.score("Alpha One","battleground")==41)
local newest=alpha.last("HKAREA")
alpha.bg,alpha.skipWorld="--",true
alpha.fire("PLAYER_ENTERING_WORLD","pvp")
assert(alpha.score("Alpha One","world")==19 and alpha.score("Alpha One","battleground")==41)
alpha.env.GetStatistic=function() error("unavailable") end
alpha.fire("PLAYER_PVP_KILLS_CHANGED")
assert(alpha.score("Alpha One","battleground")==41)

local bravo=client("Bravo Two")
bravo.now=epoch+20
bravo.receive("Alpha-Realm",newest)
assert(bravo.score("Alpha One","world")==19 and bravo.score("Alpha One","battleground")==41)
local refreshed=bravo.refreshes
bravo.receive("Alpha One-Realm",newest)
bravo.receive("Alpha One",("2;HKAREA;700;%d;950;%d"):format(epoch,epoch))
bravo.receive("Stranger",("2;HKAREACACHE;Alpha One;800;%d;800;%d"):format(epoch+12,epoch+12))
bravo.receive("Alpha One",("2;HKAREA;999;%d;5;%d"):format(epoch+5000,epoch+5000))
assert(bravo.score("Alpha One","world")==19 and bravo.refreshes==refreshed)
bravo.receive("Alpha One","2;HONOR;875")
assert(bravo.score("Alpha One","lifetime")==875 and bravo.score("Alpha One","battleground")==41)
bravo.receive("Charlie Three","2;HONOR;1234")
assert(bravo.score("Charlie Three","world")==nil)
bravo.receive("Charlie Three",("2;HKAREA;9;%d;55;%d"):format(epoch,epoch))
bravo.receive("Charlie Three",("2;HKAREA;100;%d;-1;0"):format(epoch+1))
bravo.receive("Delta Four",("2;HKAREA;19;%d;-1;0"):format(epoch))
bravo.receive("delta four",("2;HKAREA;18;%d;-1;0"):format(epoch))
local ranked=bravo.pvp.Rankings("world")
assert(#ranked==3 and ranked[1].name=="Charlie Three" and ranked[1].value==100)
assert(ranked[2].name=="Alpha One" and ranked[3].name=="Delta Four")
assert(bravo.score("Charlie Three","battleground")==55)

-- A third client can catch up on an offline member without creating a second row.
local delta=client("Delta Four")
bravo.receive("Delta Four","2;PVPREQ;1")
bravo.flush()
for _, p in ipairs(bravo.packets) do
    if p.kind=="HKAREACACHE" then delta.receive("Bravo Two",p.message) end
end
assert(delta.score("Charlie Three","world")==100 and delta.score("Charlie Three","battleground")==55)
assert(delta.score("Delta Four","world")==nil and #delta.pvp.Rankings("world")==2)
delta.receive("Bravo Two",("2;HKAREACACHE;Unknown Person;999;%d;-1;0"):format(epoch))
assert(#delta.pvp.Rankings("world")==2)

-- Saved snapshots and legacy lifetime/daily/weekly records survive a new Lua session.
alpha.db.pvp["Alpha One"].weekly.legacy=12
alpha.db.pvp["Alpha One"].achievementPoints=45
local relog=client("Alpha One",alpha.db)
relog.now=epoch+30
relog.env.GetStatisticsCategoryList=nil
relog.fire("PLAYER_ENTERING_WORLD")
assert(relog.score("Alpha One","world")==19 and relog.score("Alpha One","battleground")==41)
assert(relog.score("Alpha One","lifetime")==123)
assert(relog.db.pvp["Alpha One"].weekly.legacy==12 and relog.db.pvp["Alpha One"].achievementPoints==45)
assert(not relog.last("HKAREA"))
print("PASS: native PvP split, missing data, zone changes, replay, guild catch-up, ties and relog")
