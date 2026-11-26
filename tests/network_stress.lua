-- Network stress on the shared impaired guild network (loss, reordering,
-- duplicates, throttling): backlogs, simultaneous updates, replay, offline and
-- deletion recovery, SOS priority and idle traffic. Set KWC_LEGACY_ADDON to an
-- older release folder to include older clients.
local network,packet,find=assert(loadfile("tests/guild_sync_audit.lua"))("fixtures")
local older=os.getenv("KWC_LEGACY_ADDON");if older=="" then older=nil end
local failures=0
local function check(name,ok,detail)
 print((ok and "PASS " or "FAIL ")..name..(detail and ("  ["..tostring(detail).."]") or ""))
 if not ok then failures=failures+1 end
end
local scoped={scoped=true}
local function guild(size,impaired)
 local n=network(size,impaired)
 for i=1,size do n.client(i,nil,{scoped=true,legacy=older and i>2 and i%5==0 or nil}) end
 for _,c in ipairs(n.clients) do c.event("PLAYER_ENTERING_WORLD");c.event("GUILD_ROSTER_UPDATE") end
 n.run(60)
 return n
end
local function queued(c) local q,_,_,dropped=c.e.KWC.Net.Status();return q,dropped end
local function ids(rows) local out,seen,dup={},{},false;for _,r in ipairs(rows or {}) do if seen[r.id] then dup=true end;seen[r.id]=true;out[#out+1]=r.id end;return seen,#out,dup end

-- 1. Large backlog: SOS goes first, the backlog still drains, queues stay bounded.
do
 local n=guild(10,true)
 local busy,peer=n.clients[3],n.clients[1]
 for j=1,200 do busy.e.KWC.Net.Send("KWC3","2;NOISE;"..j,"GUILD") end
 for j=1,100 do busy.e.KWCDB.ops[#busy.e.KWCDB.ops+1]={id="bulk-"..j,author=busy.name,text=string.rep("x",120),status="ACTIVE",revision=1,created=busy.e.time()} end
 busy.e.KWC.Sync.RequestAll(true)
 local peak=queued(busy)
 local ok=busy.e.KWC.Operations.RequestBackup()
 local id=busy.e.KWCDB.ops[1].id
 local arrived
 for s=1,120 do n.run(1);local q=queued(busy);peak=math.max(peak,q);if not arrived and find(peer.e.KWCDB.ops,id) then arrived=s end end
 check("SOS arrives within 15s behind a 200-message backlog",ok and arrived and arrived<=15,arrived)
 check("send queue stays within its limit (350 plus 65 replies)",peak<=415,peak)
 -- Periodic sync refills the queue later, so look for it reaching empty.
 local emptied
 for s=121,600 do n.run(1);if queued(busy)==0 then emptied=s;break end end
 local noise={}
 for _,p in ipairs(n.packets) do local k=p.from==busy.name and p.message:match("^2;NOISE;(%d+)$");if k then noise[k]=true end end
 local delivered=0;for _ in pairs(noise) do delivered=delivered+1 end
 local _,dropped=queued(busy)
 check("backlog empties and every backlog message is sent",emptied~=nil and delivered==200 and dropped==0,tostring(emptied).."s, "..delivered.."/200, "..dropped.." dropped")
 check("no Lua errors under backlog",#n.errors()==0,n.errors()[1])
end

-- 2. Simultaneous board updates converge without duplicates.
do
 local n=guild(10,true)
 local made={}
 for i=1,10 do
  local c=n.clients[i]
  c.e.KWC.Operations.AddBounty("Target "..i,{target="Target "..i,location="",reason="",reward=""})
  made[#made+1]={kind="bounties",id=c.e.KWCDB.bounties[1].id,owner=i}
  c.e.KWC.Operations.CreateCTA("[HIGH] Zone"..i.." - hold")
  made[#made+1]={kind="ops",id=c.e.KWCDB.ops[1].id,owner=i}
 end
 n.run(90)
 for round=1,4 do for _,c in ipairs(n.clients) do c.e.KWC.Sync.Request(true) end;n.run(95) end
 local officer=n.clients[2]
 local missing,dups=0,false
 for _,m in ipairs(made) do if not find(officer.e.KWCDB[m.kind],m.id) then missing=missing+1 end end
 for _,c in ipairs(n.clients) do for _,kind in ipairs({"ops","bounties"}) do local _,_,d=ids(c.e.KWCDB[kind]);dups=dups or d end end
 check("officer holds all 20 simultaneous records",missing==0,missing.." missing")
 check("no client holds a duplicate record",not dups)
 local worst=20
 for _,c in ipairs(n.clients) do if not c.legacy then local have=0;for _,m in ipairs(made) do if find(c.e.KWCDB[m.kind],m.id) then have=have+1 end end;worst=math.min(worst,have) end end
 check("every current client holds at least 18 of 20 after four recovery rounds",worst>=18,worst)
 -- Author and officer close and edit one call in the same second.
 local target=made[6]
 local author=n.clients[target.owner]
 author.e.KWC.Operations.Edit("CTA",target.id,"[HIGH] Zone3 - edited by author")
 officer.e.KWC.Operations.ChangeStatus("CTA",target.id,"RESOLVED")
 n.run(90)
 for round=1,4 do for _,c in ipairs(n.clients) do c.e.KWC.Sync.Request(true) end;n.run(95) end
 local states={}
 for _,c in ipairs(n.clients) do if not c.legacy then local e=find(c.e.KWCDB.ops,target.id);if e then states[e.status.."|"..e.text]=(states[e.status.."|"..e.text] or 0)+1 end end end
 local variants=0;for _ in pairs(states) do variants=variants+1 end
 local report={};for k,v in pairs(states) do report[#report+1]=v.."x "..k end
 check("conflicting same-second changes converge to one state",variants==1,table.concat(report," / "))
 check("no Lua errors under simultaneous updates",#n.errors()==0,n.errors()[1])
end

-- 3. Replay: every packet twice, newest first, changes nothing.
do
 local n=network(3,false)
 local a,b=n.client(1,nil,scoped),n.client(2,nil,scoped)
 a.e.KWC.Operations.AddBounty("Replay target",{target="Replay target",location="",reason="",reward=""})
 local bid=a.e.KWCDB.bounties[1].id
 a.e.KWC.Operations.CreateCTA("[HIGH] Zone - replay");local cid=a.e.KWCDB.ops[1].id
 a.e.KWC.Operations.CreateCTA("[HIGH] Zone - doomed");local gone=a.e.KWCDB.ops[1].id
 n.run(15)
 a.e.KWC.Operations.ChangeStatus("CTA",cid,"RESOLVED")
 a.e.KWC.Operations.Delete("CTA",gone)
 n.run(30)
 local function state(c) local out={};for _,kind in ipairs({"ops","bounties"}) do for _,e in ipairs(c.e.KWCDB[kind]) do out[#out+1]=e.id..e.status..(e.revision or 0)..#(e.sightings or {}) end end;table.sort(out);return table.concat(out,",") end
 local want=state(b)
 for round=1,2 do for i=#n.packets,1,-1 do local p=n.packets[i];if p.from==a.name and p.channel=="GUILD" then packet(b,p.prefix,p.message,a) end end;n.run(5) end
 check("reverse-order duplicate replay changes nothing",state(b)==want,state(b).." vs "..want)
 check("replay cannot resurrect the deleted call",not find(b.e.KWCDB.ops,gone))
 check("replay cannot reopen the resolved call",find(b.e.KWCDB.ops,cid).status=="RESOLVED")
 -- A client that only ever sees the replay, newest first.
 local late=n.client(3,nil,scoped)
 for i=#n.packets,1,-1 do local p=n.packets[i];if p.from==a.name and p.channel=="GUILD" then packet(late,p.prefix,p.message,a) end end
 n.run(10)
 check("out-of-order first delivery ends deleted and resolved",not find(late.e.KWCDB.ops,gone) and find(late.e.KWCDB.ops,cid) and find(late.e.KWCDB.ops,cid).status=="RESOLVED" and find(late.e.KWCDB.bounties,bid)~=nil)
 check("no Lua errors under replay",#n.errors()==0,n.errors()[1])
end

-- 4. Deletion reaches offline members on a lossy network and stays deleted.
for _,size in ipairs({5,25}) do
 local n=guild(size,true)
 local author,officer,away=n.clients[3],n.clients[2],n.clients[4]
 local made={}
 for j=1,10 do author.e.KWC.Operations.AddBounty("Gone "..j,{target="Gone "..j,location="",reason="",reward=""});made[j]=author.e.KWCDB.bounties[1].id;n.run(3) end
 n.run(60)
 away.online=false
 for j=1,10 do author.e.KWC.Operations.Delete("BOUNTY",made[j]);n.run(3) end
 n.run(60)
 for round=1,3 do officer.e.KWC.Sync.Request(true);n.run(95) end
 away.online=true;away.event("PLAYER_ENTERING_WORLD")
 for round=1,4 do away.e.KWC.Sync.Request(true);n.run(95) end
 local left,revived=0,0
 for j=1,10 do if find(away.e.KWCDB.bounties,made[j]) then left=left+1 end;if find(officer.e.KWCDB.bounties,made[j]) then revived=revived+1 end end
 check(size.." clients: returning member drops all 10 deleted records",left==0,left.." remain")
 check(size.." clients: officer never takes them back",revived==0,revived)
end

-- 5. Repeated SOS traffic cannot starve ordinary synchronization.
do
 local n=network(2,false)
 local a,b=n.client(1,nil,scoped),n.client(2,nil,scoped);n.run(40)
 for j=1,40 do a.e.KWC.Net.Send("KWC3","2;NOISE;"..j,"GUILD") end
 local mark=a.e.KWC.Net.Mark();for j=1,80 do a.e.KWC.Net.Send("KWC3","2;URGENT;"..j,"GUILD") end;a.e.KWC.Net.Expedite(mark)
 local from=#n.packets;n.run(60)
 local noise,urgent=0,0
 for i=from+1,#n.packets do local m=n.packets[i].message;if m:find("NOISE") then noise=noise+1 elseif m:find("URGENT") then urgent=urgent+1 end end
 check("ordinary messages keep at least one send in five",noise>=10 and urgent>=40 and noise*4>=urgent*0.9,noise.." ordinary, "..urgent.." priority")
end

-- 6. Idle guilds stay quiet.
for _,size in ipairs({10,25}) do
 local n=guild(size,false);n.run(120)
 local count,bytes=#n.packets,n.bytes;n.run(900)
 local per=(#n.packets-count)/size
 check(size.." clients: idle traffic under 120 messages per client in 15 minutes",per<120,("%.1f per client, %d bytes"):format(per,n.bytes-bytes))
end
print(("network_stress: %d failed%s"):format(failures,older and " (with older clients)" or ""))
os.exit(failures==0 and 0 or 1)
