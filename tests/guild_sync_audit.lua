-- Shared multi-client guild network for the synchronization tests. Run from the
-- repository root with Lua 5.1 or LuaJIT. Each client loads the real add-on in TOC
-- order; time, timers, roster and addon-message transport are simulated here.
--
--   local network,packet,find=assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
--
-- Clients created with {legacy=true} load an older release instead when the
-- environment variable KWC_LEGACY_ADDON names its add-on folder.
--
-- Run without arguments, this file runs the release gate. The 1.x "baseline"
-- audit it once held replayed commits that are not in this repository; its
-- still-relevant scenarios live in tests/network_stress.lua and
-- tests/trust_boundaries.lua.
local H=dofile("tests/harness/wow.lua")
local epoch=1794592800
local current="KeepersWarCommand"
local older=os.getenv("KWC_LEGACY_ADDON")
if older=="" then older=nil end

local function guid(i) return ("Player-1-%08X"):format(i) end

local function network(size,impaired)
    local n={now=0,clients={},jobs={},sequence=0,packets={},bytes=0,loss=0,duplicates=0,throttles=0}
    local roster={}
    for i=1,size do
        local name=("Player%02d Example"):format(i)
        roster[name:lower()]={name=name,rankIndex=i<=2 and 1 or 3,scannedAt=epoch,online=true}
    end
    n.roster=roster
    function n.schedule(delay,callback)
        local tick=n.now+math.max(1,math.ceil(delay*10-0.0001))
        local q=n.jobs[tick] or {}
        n.jobs[tick]=q
        q[#q+1]=callback
    end
    function n.run(seconds)
        for tick=n.now+1,n.now+seconds*10 do
            n.now=tick
            for _,fn in ipairs(n.jobs[tick] or {}) do fn() end
            n.jobs[tick]=nil
            for _,c in ipairs(n.clients) do
                if c.online then
                    for _,f in ipairs(c.host.allWidgets) do
                        local update=f.scripts.OnUpdate
                        if update then
                            local ok,err=pcall(update,f,0.1)
                            if not ok then c.errors[#c.errors+1]="OnUpdate: "..tostring(err) end
                        end
                    end
                end
            end
        end
    end
    -- Every Lua error raised on any client, for tests to assert on.
    function n.errors()
        local out={}
        for _,c in ipairs(n.clients) do
            for _,e in ipairs(c.errors) do out[#out+1]=c.name..": "..e end
            for _,line in ipairs(c.logs) do
                if line:find("Interface error",1,true) then out[#out+1]=c.name..": "..line end
            end
        end
        return out
    end
    function n.client(i,saved,options)
        options=options or {}
        local world=H.World()
        local host=world:Client(("Player%02d Example"):format(i))
        local c={name=host.name,online=true,guild=true,guildID=1,logs={},honor=100+i,world=20+i,bg=30+i,
            host=host,errors=host.errors,noLFG=options.noLFG,legacy=options.legacy}
        local e=host.env
        -- The client's own name can be changed by a test, so read it late.
        local function me() return c.name end
        e.math=setmetatable({random=function(a,b)
            c.seed=((c.seed or i)*16807)%2147483647
            if not a then return c.seed/2147483647 end
            if not b then return 1+c.seed%a end
            return a+c.seed%(b-a+1)
        end},{__index=math})
        e.time=function(t) if t then return os.time(t) end;return epoch+math.floor(n.now/10) end
        e.GetServerTime=e.time
        e.GetTime=function() return n.now/10 end
        e.date=function(format,t) return os.date(format,t or e.time()) end
        e.print=function(...)
            local parts={}
            for k=1,select("#",...) do parts[#parts+1]=tostring((select(k,...))) end
            c.logs[#c.logs+1]=table.concat(parts," ")
        end
        e.IsInGuild=function() return c.guild end
        if options.scoped~=false then
            e.C_Club={GetGuildClubId=function() if c.guild then return c.guildID end end,GetMemberInfoForSelf=function() end}
        else e.C_Club=nil end
        e.GetNormalizedRealmName=function() return "Realm" end
        e.GetNumGuildMembers=function() return size,size end
        e.GetGuildRosterInfo=function(index)
            local name=("Player%02d Example"):format(index)
            local record=roster[name:lower()]
            if not record then return nil end
            local online=record.online
            if options.scoped then
                for _,peer in ipairs(n.clients) do
                    if peer.name==name then online=online and peer.online and peer.guildID==c.guildID end
                end
            end
            return record.name,"Rank",record.rankIndex,60,"Warrior","Zone","","",online,0,"WARRIOR",0,0,false,false,0,guid(index)
        end
        e.GetGuildInfo=function() return "Guild","Rank",i<=2 and 1 or 3 end
        e.UnitName=function(unit) if unit=="player" then return me() end end
        e.UnitFullName=e.UnitName
        e.GetUnitName=e.UnitName
        e.UnitGUID=function(unit) if unit=="player" then return guid(i) end end
        e.GetZoneText=function() return c.zone or "Audit Zone" end
        e.GetRealZoneText=e.GetZoneText
        e.GetPVPLifetimeStats=function() return c.honor end
        e.GetStatisticsCategoryList=function() return {18} end
        e.GetCategoryNumAchievements=function() return 2 end
        e.GetStatistic=function(_,index) return index==1 and c.world or c.bg,false,380+index end
        e.C_GuildInfo={GuildRoster=function() end}
        e.C_Timer={After=function(delay,fn)
            n.schedule(delay,function() if c.online then fn() end end)
        end}
        e.C_Timer.NewTimer=function(delay,fn)
            local timer={}
            function timer:Cancel() self.cancelled=true end
            e.C_Timer.After(delay,function() if not timer.cancelled then fn(timer) end end)
            return timer
        end
        e.C_Timer.NewTicker=function(delay,fn)
            local ticker={}
            function ticker:Cancel() self.cancelled=true end
            local function tick() if not ticker.cancelled then fn(ticker);e.C_Timer.After(delay,tick) end end
            e.C_Timer.After(delay,tick)
            return ticker
        end
        e.C_ChatInfo={RegisterAddonMessagePrefix=function() return true end}
        e.C_ChatInfo.SendChatMessage=function() error("unexpected player chat send") end
        e.SendChatMessage=e.C_ChatInfo.SendChatMessage
        e.C_ChatInfo.SendAddonMessage=function(prefix,message,channel,target)
            assert(#message<=255,"addon message over 255 bytes: "..prefix)
            n.sequence=n.sequence+1
            local seq=n.sequence
            -- 3 is the client's addon-message throttle result.
            if impaired and seq%83==0 then n.throttles=n.throttles+1;return 3 end
            n.packets[#n.packets+1]={prefix=prefix,message=message,from=c.name,tick=n.now,target=target,channel=channel}
            n.bytes=n.bytes+#prefix+#message
            for j,peer in ipairs(n.clients) do
                if peer.online and c.guildID==peer.guildID and not (peer.noLFG and prefix=="KWL1")
                    and (channel=="GUILD" or (channel=="WHISPER" and (peer.name==target or peer.name.."-Realm"==target))) then
                    if impaired and (seq+j*7)%41==0 then n.loss=n.loss+1
                    else
                        local function deliver()
                            if peer.online and c.guildID==peer.guildID then
                                peer.event("CHAT_MSG_ADDON",prefix,message,channel,c.name.."-Realm")
                            end
                        end
                        n.schedule(impaired and (0.1+((seq*17+j*11)%30)/10) or 0.1,deliver)
                        if impaired and (seq+j)%47==0 then
                            n.duplicates=n.duplicates+1
                            n.schedule(4.1,deliver)
                        end
                    end
                end
            end
            return 0
        end
        e.KWCDB=saved or {roster={},settings={autoGuildSync=true,autoScout=true,dev6AutoDefaultsApplied=true}}
        e.KWCDB.roster=e.KWCDB.roster or {}
        for key,record in pairs(roster) do
            e.KWCDB.roster[key]={name=record.name,rankIndex=record.rankIndex,scannedAt=e.time(),online=true}
        end
        c.e=e
        c.event=function(event,...) world:Fire(host,event,...) end
        world:LoadAddon(host,options.legacy and older or current)
        n.clients[#n.clients+1]=c
        return c
    end
    return n
end

local function packet(c,prefix,message,sender,channel)
    c.event("CHAT_MSG_ADDON",prefix,message,channel or "GUILD",sender.name.."-Realm")
end
local function find(rows,id)
    for _,row in ipairs(rows) do if row.id==id then return row end end
end

if ... == "fixtures" then return network,packet,find end
return assert(loadfile("tests/guild_sync_release_gate.lua"))()
