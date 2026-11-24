local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Nez Dankdabs',rank=1,guid='Player-1-0000000A'})
local c=w:Client('Nez Dankdabs')
w:LoadAddon(c,'KeepersWarCommand');w:Login(c);w:Advance(15)
local K=c.env.KWC
local C=K.Celebrations
local p=C.Preferences()
H.Check('Balanced personal defaults and guild sharing off',p.intensity=='Balanced' and not p.guild and not p.guildAnnouncements)
local history=#C.History()
C.Preview('Legendary')
H.Check('preview creates no history',#C.History()==history)
K.Toast.channels.warCelebration:Hide()
C.Moment({eventID='a',title='First',level='Heroic',significant=true,evidence='fixture'})
C.Moment({eventID='a',title='First',level='Heroic',significant=true,evidence='fixture'})
H.Check('explicit retransmission is recorded once',#C.History()==history+1)
for i=1,40 do C.Moment({eventID='q'..i,title='Queued'}) end
H.Check('queue stays bounded',#C.queue<=12)
p.intensity='Off';w:Advance(1)
H.Check('Off drops queue and hides active automatic popup',#C.queue==0 and not K.Toast.channels.warCelebration:IsShown())
C.Preview('Standard')
H.Check('manual preview works in Off',K.Toast.channels.warCelebration:IsShown())
K.Toast.channels.warCelebration:Hide()
p.intensity='Balanced';p.streaks=true
C.KillingBlow('Player-2-000001')
C.KillingBlow('Player-2-000002')
C.KillingBlow('Player-2-000003')
H.Check('confirmed local streak reaches three',C.streak==3)
w:Fire(c,'PLAYER_DEAD')
H.Check('death resets streak',C.streak==0)
w:Fire(c,'PLAYER_ENTERING_WORLD')
H.Check('loading clears pending celebrations',#C.queue==0)
w:Advance(2)
c.env.KWCDB.bounties={{id='b1',status='ACTIVE',author='Nez Dankdabs',details={target='Enemy'}}}
C.ScanOperations();w:Advance(2)
local b=c.env.KWCDB.bounties[1]
local before=#C.History()
b.status='COMPLETED';b.revision=2;b.updatedBy='Nez Dankdabs'
C.ScanOperations();w:Advance(2);C.ScanOperations()
H.Check('completed bounty state celebrates once',#C.History()==before+1)
b.status='CANCELLED';w:Advance(2);C.ScanOperations()
H.Check('cancelled bounty has no victory',#C.History()==before+1)
local peer='Player-1-0000000B'
w:AddMember({name='Bo Pike',rank=3,guid=peer})
w:Fire(c,'GUILD_ROSTER_UPDATE')
K.Identity.Scan()
local observed=0
local old=K.EventEvidence.handlers.WORLDKILL
K.EventEvidence.handlers.WORLDKILL=function() observed=observed+1 end
local payload='Enemy;1;Ashenvale'
local legacy='2;WORLDKILL;'..payload
local function packet(n)
 return '2;EVENT1;WORLDKILL|'..peer..'|1-1|'..n..'|'..math.floor(w.now)..'|'..payload
end
w:Fire(c,'CHAT_MSG_ADDON','KWC3',legacy,'GUILD','Bo Pike')
w:Fire(c,'CHAT_MSG_ADDON','KWC3',packet(1),'GUILD','Bo Pike')
w:Fire(c,'CHAT_MSG_ADDON','KWC3',packet(1),'GUILD','Bo Pike');w:Advance(.6)
H.Check('legacy plus event envelope and replay are delivered once',observed==1)
w:Fire(c,'CHAT_MSG_ADDON','KWC3',packet(2),'GUILD','Bo Pike')
H.Check('second rapid event with identical target remains distinct',observed==2)
K.EventEvidence.handlers.WORLDKILL=old
c.env.KWCDB.ops={{id='cta-test',author='Nez Dankdabs',status='ACTIVE',text='Test campaign',created=w.now}}
local campaign=c.env.KWCDB.ops[1]
H.Check('authorized explicit victory records an outcome',C.CompleteCTA(campaign.id,'VICTORY') and C.Outcome(campaign.id).outcome=='VICTORY')
local prior=#C.History()
H.Check('replayed result cannot celebrate twice',not C.AcceptOutcome(campaign.id,'VICTORY',campaign.revision,math.floor(w.now),'Nez Dankdabs') and #C.History()==prior)
campaign.status='ACTIVE';campaign.revision=campaign.revision+1
H.Check('unauthorized peer cannot claim victory',not C.AcceptOutcome(campaign.id,'VICTORY',campaign.revision,math.floor(w.now),'Bo Pike'))
for _,id in ipairs(K.PublicThemes.order) do
 K.WarRoomSkin.Apply(id)
 C.Preferences().reducedMotion=true
 for _,level in ipairs({'Standard','Heroic','Legendary'}) do C.Preview(level) end
end
H.Check('all curated skins support each level with reduced motion',#c.errors==0 and C.Preferences().reducedMotion)
local beforeResolved=#C.History()
campaign.status='RESOLVED';campaign.revision=campaign.revision+1
H.Check('generic Resolve does not imply a victory',#C.History()==beforeResolved and not C.Outcome(campaign.id))
campaign.status='ACTIVE';campaign.revision=campaign.revision+1
H.Check('withdraw records an outcome without victory celebration',C.CompleteCTA(campaign.id,'WITHDRAWN') and C.Outcome(campaign.id).outcome=='WITHDRAWN' and #C.History()==beforeResolved)
local reads=0
c.env.GetPVPLifetimeStats=function() reads=reads+1;return reads<2 and nil or 166 end
w:Fire(c,'PLAYER_LOGIN');w:Fire(c,'PLAYER_ENTERING_WORLD');w:Advance(11)
H.Check('login retries delayed native honor',K.PvP.Rankings('lifetime')[1].value==166 and reads>=2)
local saved=w:Saved(c,{'KWCDB'});w:Drop(c)
local reload=w:Client('Nez Dankdabs',{saved=saved})
reload.env.GetPVPLifetimeStats=function()return 170 end
w:LoadAddon(reload,'KeepersWarCommand');w:Login(reload);w:Advance(11)
H.Check('reload refreshes honor before another kill',reload.env.KWC.PvP.Rankings('lifetime')[1].value==170)
H.Check('no runtime errors',#c.errors==0 and #reload.errors==0)
os.exit(H.Summary('celebrations') and 0 or 1)
