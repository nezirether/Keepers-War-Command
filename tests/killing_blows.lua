-- 2.0 killing-blow path (Forever PARTY_KILL(attackerGUID, targetGUID)), simulated.
-- Covers: own KB with no honor -> WORLDKB shared + popup in "all" mode only;
-- own KB that earns honor -> honor path owns it (no duplicate); party member's
-- KB, secret GUIDs, non-player and guildmate targets ignored; instance kills not
-- shared; receiver validates sender, dedupes, and ignores self echoes.
local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Ash Ember',rank=3,guid='Player-1-0000000A'})
w:AddMember({name='Bo Pike',rank=3,guid='Player-1-0000000B'})
w.guidNames={['Player-2-0000E001']='Evil Rogue',['Player-2-0000E002']='Low Gnome',['Player-2-0000E003']='Other Guy'}
local a=w:Client('Ash Ember');w:LoadAddon(a,'KeepersWarCommand');w:Login(a)
local b=w:Client('Bo Pike');w:LoadAddon(b,'KeepersWarCommand');w:Login(b)
w:Advance(15);w:Pump()
local KA,KB=a.env.KWC,b.env.KWC
local TB=KB.Toast.channels.pvpKill
local function kbMsgs() local n=0;for _,m in ipairs(w.log or {}) do end;return n end
local sentBefore=w.sentCount or 0
local function sends(fn) local seen={};local orig=a.env.C_ChatInfo.SendAddonMessage
 a.env.C_ChatInfo.SendAddonMessage=function(p,m,ch,t) seen[#seen+1]=m;return orig(p,m,ch,t) end
 fn();a.env.C_ChatInfo.SendAddonMessage=orig;return seen end
local function has(list,pat) for _,m in ipairs(list) do if m:find(pat) then return true end end;return false end

H.Check('default kill mode is honor-only',KB.WorldPvPKills.KillMode()=='honor')
-- 1) Own killing blow, no honor.
local out=sends(function() w:Fire(a,'PARTY_KILL','Player-1-0000000A','Player-2-0000E002');w:Advance(4) end)
H.Check('own no-honor killing blow is shared as WORLDKB',has(out,'^2;WORLDKB;Low Gnome;'),table.concat(out,' / '))
w:Pump()
H.Check('honor-only mode: receiver records but shows no popup',not TB.frame:IsShown() and (b.env.KWCDB.worldPvPKills or {})[1] and b.env.KWCDB.worldPvPKills[1].victim=='Low Gnome')
KB.WorldPvPKills.SetKillMode('all')
w:Advance(10)
out=sends(function() w:Fire(a,'PARTY_KILL','Player-1-0000000A','Player-2-0000E003');w:Advance(4) end);w:Pump()
H.Check('all mode: receiver shows a killing-blow popup',TB.frame:IsShown() and (TB.frame.title:GetText() or ''):find('Other Guy')~=nil,TB.frame.title:GetText())
H.Check('popup states no honor was awarded',(TB.frame.detail:GetText() or ''):find('No honor')~=nil)
TB.frame:Hide()
-- duplicate delivery
w:Fire(b,'CHAT_MSG_ADDON','KWC3','2;WORLDKB;Other Guy;Ashenvale','GUILD','Ash Ember')
H.Check('duplicate WORLDKB within 8s is ignored',not TB.frame:IsShown())
-- 2) Own KB that earns honor -> honor path only.
w:Advance(10)
out=sends(function()
 w:Fire(a,'PARTY_KILL','Player-1-0000000A','Player-2-0000E001')
 a.sessionHK=(a.sessionHK or 0)+1
 w:Fire(a,'PLAYER_PVP_KILLS_CHANGED','player');w:Advance(4) end)
H.Check('honorable killing blow is reported once, via WORLDKILL',has(out,'WORLDKILL;Evil Rogue;1;') and not has(out,'WORLDKB'),table.concat(out,' / '))
-- 3) Ignored inputs.
w:Advance(10)
out=sends(function()
 w:Fire(a,'PARTY_KILL','Player-1-0000000B','Player-2-0000E002') -- someone else's KB
 w:Fire(a,'PARTY_KILL','Player-1-0000000A','Creature-0-1-2-3-4') -- NPC
 w:Fire(a,'PARTY_KILL','Player-1-0000000A','Player-1-0000000B') -- guildmate (duel)
 w:Fire(a,'PARTY_KILL',nil,nil) -- unreadable
 w:Advance(4) end)
H.Check('party KB, NPC, guildmate and unreadable GUIDs are not shared',not has(out,'WORLDKB'),table.concat(out,' / '))
H.Check('unreadable PARTY_KILL counted as skipped',KA.WorldPvPKills.KillingBlowStats().secret>=1)
-- 4) Instance kill is not shared.
a.instance='pvp';w:Fire(a,'PLAYER_ENTERING_WORLD',false,false);w:Advance(2)
out=sends(function() w:Fire(a,'PARTY_KILL','Player-1-0000000A','Player-2-0000E003');w:Advance(4) end)
H.Check('killing blow inside a battleground is not shared',not has(out,'WORLDKB'))
a.instance=nil;w:Fire(a,'PLAYER_ENTERING_WORLD',false,false);w:Advance(2)
-- 5) Receiver validation.
TB.frame:Hide();w:Advance(10)
w:Fire(b,'CHAT_MSG_ADDON','KWC3','2;WORLDKB;Fake;Ashenvale','GUILD','Stranger')
H.Check('WORLDKB from a non-member is rejected',not TB.frame:IsShown())
w:Fire(b,'CHAT_MSG_ADDON','KWC3','2;WORLDKB;Bad|cffName;Ashenvale','GUILD','Ash Ember')
H.Check('WORLDKB with escape codes is rejected',not TB.frame:IsShown())
w:Fire(b,'CHAT_MSG_ADDON','KWC3','2;WORLDKB;Echo;Ashenvale','GUILD','Bo Pike')
H.Check('own WORLDKB echo is ignored',not TB.frame:IsShown())
w:Fire(b,'CHAT_MSG_ADDON','KWC3','2;WORLDKB;Echo;Ashenvale','WHISPER','Ash Ember')
H.Check('WORLDKB outside GUILD channel is rejected',not TB.frame:IsShown())
local errs=table.concat(a.errors,' | ')..table.concat(b.errors,' | ')
H.Check('no Lua errors',#a.errors==0 and #b.errors==0,errs:sub(1,500))
os.exit(H.Summary('killing_blows') and 0 or 1)
