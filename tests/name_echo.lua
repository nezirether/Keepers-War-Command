local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Nez Dankdabs',rank=3,guid='Player-1-0000000A'})
w:AddMember({name='Nez Other',rank=3,guid='Player-1-0000000B'})
local c=w:Client('Nez Dankdabs')
w:LoadAddon(c,'KeepersWarCommand');w:Login(c);w:Advance(15)
local K=c.env.KWC
local original=c.env.UnitName
c.env.UnitName=function(unit) if unit=='player' then return 'Nez' end;return original(unit) end
H.Check('local GUID resolves full name despite abbreviated unit API',K.CharacterDisplayName('Nez',true)=='Nez Dankdabs')
H.Check('first name alone stays unresolved with two unrelated members',K.CurrentGuildMember('Nez')==nil and K.CharacterDisplayName('Nez')=='Nez')
H.Check('only verified local sender is a self echo',K.IsLocalSender('Nez Dankdabs') and not K.IsLocalSender('Nez Other'))
local toast=K.Toast.channels.pvpKill
local shown=0
local present=toast.Present
toast.Present=function(self,...) shown=shown+1;return present(self,...) end
w:Fire(c,'CHAT_MSG_ADDON','KWC3','2;WORLDKILL;Filibuster Fente;1;Ashenvale','GUILD','Nez Dankdabs')
H.Check('full-name self echo causes zero extra kill popups',shown==0)
c.sessionHK=(c.sessionHK or 0)+1
w:Fire(c,'PLAYER_PVP_KILLS_CHANGED','player');w:Advance(4)
H.Check('local kill popup uses verified full name',shown==1 and toast.frame.title:GetText():find('Nez Dankdabs',1,true))
w:Fire(c,'CHAT_MSG_ADDON','KWC3','2;WORLDKILL;Filibuster Fente;1;Ashenvale','GUILD','Nez Dankdabs')
H.Check('local kill and its full-name retransmission display once',shown==1)
c.sessionHK=c.sessionHK+1;w:Fire(c,'PLAYER_PVP_KILLS_CHANGED','player');w:Advance(4)
H.Check('second real kill displays again',shown==2)
H.Check('explicit event identity suppresses only its retransmission',K.Toast.Claim('kill','event-one') and not K.Toast.Claim('kill','event-one') and K.Toast.Claim('kill','event-two') and K.Toast.Claim('death','event-one'))
w:Advance(1)
for i=1,600 do K.Toast.Claim('bounded',i) end
H.Check('deduplication cache evicts old entries',K.Toast.Claim('kill','event-one'))
w:Advance(601)
H.Check('deduplication entry expires',K.Toast.Claim('kill','event-one'))
H.Check('no Lua errors',#c.errors==0)
os.exit(H.Summary('name_echo') and 0 or 1)
