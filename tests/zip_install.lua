-- Loads extracted packages, not the source tree. Set KWC_PACKAGE_DIR to a folder
-- holding the extracted KeepersWarCommand and KeepersWarCommand_Command add-ons.
local H=dofile('tests/harness/wow.lua')
local ROOT=(os.getenv('KWC_PACKAGE_DIR') or '/tmp/AddOns')
assert(io.open(ROOT..'/KeepersWarCommand/KeepersWarCommand.toc','r'),'Set KWC_PACKAGE_DIR to the extracted add-on folder; not found: '..ROOT)
local w=H.World()
w:AddMember({name='Grom Warcry',rank=1,guid='Player-1-0000000B'})
w:AddMember({name='Ash Ember',rank=3,guid='Player-1-0000000A'})
local o=w:Client('Grom Warcry');w:LoadAddon(o,ROOT..'/KeepersWarCommand');w:LoadAddon(o,ROOT..'/KeepersWarCommand_Command');w:Login(o)
local m=w:Client('Ash Ember');w:LoadAddon(m,ROOT..'/KeepersWarCommand');w:Login(m);w:Advance(8)
for _,p in ipairs({'dashboard','cta','bounties','pvp','leaderboards','records','lfg','services','raids','alerts','settings'}) do o.env.SlashCmdList.KEEPERSWARCOMMAND(p);m.env.SlashCmdList.KEEPERSWARCOMMAND(p);w:Advance(0.3) end
w:Advance(8);o.env.SlashCmdList.KEEPERSWARCOMMAND('command');w:Advance(0.5)
o.env.KWC.Operations.DetailedCTA('Hillsbrad','Zip test',1,2,'HIGH','','');w:Advance(8)
local got=false;for _,e in ipairs(m.env.KWCDB.ops) do if e.text:find('Zip test') then got=true end end
H.Check('extracted ZIPs load (officer: KWC+KWCC, member: KWC) with no Lua errors',#o.errors==0 and #m.errors==0,table.concat(o.errors,'|')..table.concat(m.errors,'|'))
H.Check('War Council opens from the extracted officer package',o.env.KWC.WarRoom2.Current().id=='officer-command' or o.env.KWC.Officer.Open()==true)
H.Check('CTA syncs between clients running the extracted packages',got)
local miss
for p in pairs(o.textures) do local f=p:match('^Interface\\AddOns\\(.+)$');if f then local q=ROOT..'/'..f:gsub('\\','/');if not q:match('%.tga$') then q=q..'.tga' end;local h=io.open(q,'rb');if h then h:close() else miss=q end end end
H.Check('every texture requested at runtime exists in the extracted packages',miss==nil,miss)
os.exit(H.Summary('zip_install') and 0 or 1)
