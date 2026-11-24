-- Run after: mkdir /tmp/AddOns && unzip dist/KWC-2.0-public-private-test.zip -d /tmp/AddOns && unzip dist/KWCC-2.0-officer-private-test.zip -d /tmp/AddOns
local H=dofile('tests/harness/wow.lua')
local w=H.World()
w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})
w:AddMember({name='Ash Ember',rank=3,guid='Player-1-0000000A'})
local o=w:Client('Grom Warcry');w:LoadAddon(o,'/tmp/AddOns/KeepersWarCommand');w:LoadAddon(o,'/tmp/AddOns/KeepersWarCommand_Command');w:Login(o)
local m=w:Client('Ash Ember');w:LoadAddon(m,'/tmp/AddOns/KeepersWarCommand');w:Login(m);w:Advance(8)
for _,p in ipairs({'dashboard','cta','bounties','pvp','leaderboards','records','lfg','services','raids','alerts','settings'}) do o.env.SlashCmdList.KEEPERSWARCOMMAND(p);m.env.SlashCmdList.KEEPERSWARCOMMAND(p);w:Advance(0.3) end
o.env.SlashCmdList.KEEPERSWARCOMMAND('command');w:Advance(0.5)
o.env.KWC.Operations.DetailedCTA('Hillsbrad','Zip test',1,2,'HIGH','','');w:Advance(8)
local got=false;for _,e in ipairs(m.env.KWCDB.ops) do if e.text:find('Zip test') then got=true end end
H.Check('extracted ZIPs load (officer: KWC+KWCC, member: KWC) with no Lua errors',#o.errors==0 and #m.errors==0,table.concat(o.errors,'|')..table.concat(m.errors,'|'))
H.Check('Command Table opens from the extracted officer package',o.env.KWCC_CommandTable and o.env.KWCC_CommandTable:IsShown() and not o.env.KWCC.UI.IsLocked())
H.Check('CTA syncs between clients running the extracted packages',got)
local miss
for p in pairs(o.textures) do local f=p:match('^Interface\\AddOns\\(.+)$');if f then local q='/tmp/AddOns/'..f:gsub('\\','/');if not q:match('%.tga$') then q=q..'.tga' end;local h=io.open(q,'rb');if h then h:close() else miss=q end end end
H.Check('every texture requested at runtime exists in the extracted packages',miss==nil,miss)
os.exit(H.Summary('zip_install') and 0 or 1)
