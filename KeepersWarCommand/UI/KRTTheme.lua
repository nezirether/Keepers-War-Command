-- Keepers Raid Tools reads KWC.UITheme at load. 2.0 supplies the War Room
-- palette under KRT's key names, and points its two texture lookups at new
-- 2.0 media (Media/Grain.tga, Media/Crimson.tga). No legacy texture is used.
local K=KWC
local H=K.Kit.Hex
local function c(hex) local t=H(hex);return {t[1],t[2],t[3],1} end
KWC.UITheme={
 font='Fonts\\FRIZQT__.TTF',fallbackFont='Fonts\\FRIZQT__.TTF',headingFont='Fonts\\FRIZQT__.TTF',
 size={title=20,section=15,body=13,field=13,nav=13},
 gold=c('F3A06F'),cream=c('ECE6DA'),muted=c('A9A398'),
 bronze=c('34383F'),steel=c('24272C'),graphite=c('1C1E22'),charcoal=c('101113'),
 panel={0.07,0.075,0.085,1},hover=c('2C3036'),crimson=c('C94A43'),accent=c('E0733A'),
 sidebar=c('16171A'),molten=c('E0733A'),card=c('1C1E22'),buttonEdge=c('34383F'),
 metal=K.Kit.MEDIA..'Grain.tga',
 warRoomArt=K.Kit.MEDIA,
}
