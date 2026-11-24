local H=dofile('tests/harness/wow.lua')
local w=H.World()
local chief='Grom Warcry'
local member='Ash Ember'
local chiefGUID='Player-1-0000000B'
local memberGUID='Player-1-0000000A'
w:AddMember({name=chief,rank=0,guid=chiefGUID})
w:AddMember({name=member,rank=3,guid=memberGUID})
local function boot(name,saved)
 local c=w:Client(name,{saved=saved})
 w:LoadAddon(c,'KeepersWarCommand');w:Login(c);w:Advance(6)
 return c
end
local a,b=boot(chief),boot(member)
local A,B=a.env.KWC.WarSpoils,b.env.KWC.WarSpoils
H.Check('rank zero and matching live GUID are required',A.CanWrite() and not B.CanWrite())
H.Check('unprivileged write fails',not B.Record('S',nil,nil,'Forgery'))
assert(A.Record('R',chief));assert(A.Record('R',member));assert(A.Record('S',nil,nil,'Ashen Citadel'))
H.Check('registered raiders start at five',A.View().raiders[memberGUID].points==5)
assert(A.Record('A',chief));assert(A.Record('A',member))
H.Check('same-session attendance duplicates fail',not A.Record('A',member))
for i=1,5 do assert(A.Record('B',member,'Boss '..i)) end
H.Check('boss credit caps at ten and records a zero delta at cap',
 A.View().raiders[memberGUID].points==10 and A.View().events[A.View().count].delta==0)
H.Check('boss occurrence identity is case-insensitive',not A.Record('B',member,'boss 1'))
assert(A.Record('L',member,'drop 1','Bronze Signet',chief))
H.Check('contested award costs exactly three and cannot repeat',
 A.View().raiders[memberGUID].points==7 and not A.Record('L',member,'DROP 1','Bronze Signet',chief))
H.Check('invalid corrections cannot bypass the cap',not A.Record('C',member,'4','Bad correction'))
assert(A.Record('C',member,'-1','Correct boss eligibility'))
H.Check('correction preserves original award and records reason',
 A.View().raiders[memberGUID].points==6 and A.View().events[A.View().count].note=='Correct boss eligibility')
assert(A.Record('E'))
w:Advance(30)
H.Check('peer applies complete authorized ledger',B.View().count==A.View().count and B.View().raiders[memberGUID].points==6)
local expected=B.View().count
local last=A.View().db.lines[expected]
w:Fire(b,'CHAT_MSG_ADDON','KWCWS1',A.View().guild..'|D|'..last,'GUILD',chief)
H.Check('duplicate replay leaves balance and event count unchanged',B.View().count==expected and not B.View().db.conflict)
w:Fire(a,'CHAT_MSG_ADDON','KWCWS1',A.View().guild..'|D|'..last:gsub('|E|','|S|'),'GUILD',member)
H.Check('ordinary guild messages cannot invalidate the ledger',not A.View().db.conflict)
b.online=false
assert(A.Record('C',member,'1','Manual verification'))
w:Advance(20)
b.online=true
B.Request();w:Advance(20)
H.Check('reconnecting peer requests and receives missing suffix',B.View().count==expected+1 and B.View().raiders[memberGUID].points==7)

local fresh=boot(member)
local F=fresh.env.KWC.WarSpoils
F.Request();w:Advance(45);F.Request();w:Advance(20)
H.Check('empty ledger recovers bounded pages without overwriting records',F.View().count==A.View().count)
local c=F.View().count
local altered=A.View().db.lines[c]:gsub('Manual verification','Alternate event')
w:Fire(fresh,'CHAT_MSG_ADDON','KWCWS1',A.View().guild..'|D|'..altered,'GUILD',chief)
H.Check('verified competing history is quarantined',F.View().db.conflict and F.View().count==c)

local saved=w:Saved(b,{'KWCDB'})
w:Drop(b)
b=boot(member,saved);B=b.env.KWC.WarSpoils
H.Check('log and derived balances survive reload',B.View().count==c and B.View().raiders[memberGUID].points==7)
w:Rename(member,'Ash Rekindled')
w:FireAll('GUILD_ROSTER_UPDATE')
w:Advance(2)
H.Check('roster rename retains the same WarSpoils identity',
 B.View().raiders[memberGUID].points==7 and b.env.KWC.Identity.RosterName(memberGUID):find('Ash Rekindled',1,true)~=nil)
w:Member(chief).rank=1
w:FireAll('GUILD_ROSTER_UPDATE')
H.Check('demotion removes local mutation authority immediately',not A.Record('C',chief,'1','Demoted writer'))
a.env.KWC.WarRoom2.Show('raids',{tab='spoils'})
local displayError=table.concat(a.printed,'\n'):find('Interface error',1,true)
H.Check('populated WarSpoils tab opens without layout errors',not displayError)
local preview=a.env.KWC.WarSpoilsPreview
H.Check('policy comparison shows different opening winners',
 preview.Compare('balance').raids[1].awards[1]=='Thane (-3)' and
 preview.Compare('lifetime').raids[1].awards[1]=='Ember (-3)')
H.Check('three proposals leave the real ledger untouched',preview.Compare('rotation').raiders[1].points<=10 and A.View().count==c)
local errors=table.concat(a.errors,' | ')..table.concat(b.errors,' | ')
H.Check('no player runtime errors',errors=='',errors)
os.exit(H.Summary('warspoils') and 0 or 1)
