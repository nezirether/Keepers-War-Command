from pathlib import Path
import math, random, sys
from PIL import Image, ImageDraw

# Generate small monochrome repeatable treatments. Runtime supplies the tint.
out = Path(__file__).resolve().parent.parent / 'KeepersWarCommand' / 'Media' / 'Themes'
out.mkdir(parents=True, exist_ok=True)
white = (255,255,255,210)

def material(name):
    im = Image.new('RGBA',(256,64))
    d = ImageDraw.Draw(im)
    rng = random.Random(name)
    def line(points, alpha=195, width=1):
        d.line(points,fill=(255,255,255,alpha),width=width)
    if name in ('embers','dust','stars','snow'):
        density = {'embers':60,'dust':115,'stars':30,'snow':32}[name]
        for _ in range(density):
            x,y = rng.randrange(256),rng.randrange(64)
            r = rng.choice([1,1,2,3])
            a = rng.randrange(60,236)
            if name=='embers':
                line([(x,y),(x+3*r,y-2*r)],a,r)
            elif name=='dust':
                d.ellipse((x,y,x+r,y+r),fill=(255,255,255,a))
            else:
                for i in range(2 if name=='stars' else 3):
                    o = i*math.pi/(2 if name=='stars' else 3)
                    dx,dy = math.cos(o)*r*1.5,math.sin(o)*r*1.5
                    line([(x-dx,y-dy),(x+dx,y+dy)],a)
    elif name in ('scales','arch','eclipse'):
        for y in range(-10,65,13):
            for x in range(-8,261,21):
                xx=x+(y%2)*10
                if name=='scales': d.arc((xx,y-4,xx+20,y+15),0,180,fill=white,width=1)
                elif name=='arch': d.arc((xx,y,xx+18,y+18),180,360,fill=white,width=1)
                else: d.arc((xx,y,xx+13,y+13),25,310,fill=white,width=1)
    elif name in ('chevron','facet','runes','herald','checker','filigree'):
        for y in range(-4,67,16):
            for x in range(-4,261,20):
                if name=='chevron': line([(x,y),(x+9,y+9),(x+18,y)],215,2)
                elif name=='facet':
                    line([(x,y+8),(x+9,y),(x+18,y+8),(x+9,y+16),(x,y+8)],180)
                    line([(x,y+8),(x+18,y+8)],110)
                elif name=='runes':
                    line([(x+4,y+13),(x+4,y+3),(x+13,y+11),(x+13,y+2)],215,2)
                elif name=='herald':
                    line([(x+2,y+2),(x+17,y+2),(x+15,y+10),(x+9,y+15),(x+4,y+10),(x+2,y+2)],210)
                elif name=='checker':
                    d.rectangle((x+(y//16%2)*10,y+2,x+8+(y//16%2)*10,y+9),fill=(255,255,255,145))
                else:
                    d.arc((x+1,y+1,x+15,y+11),25,310,fill=white)
                    d.ellipse((x+7,y+6,x+9,y+8),fill=white)
    elif name in ('grate','grid','stone','rivet','line'):
        for y in range(2,63,7 if name=='line' else 12):
            line([(0,y),(255,y)],172 if name!='line' else 125)
            for x in range(4,255,17):
                xx=x+(y//12%2)*8
                if name=='grid': line([(x,y),(x,y+12)],155)
                elif name=='stone': line([(xx,y),(xx,y+12)],150)
                elif name=='rivet': d.ellipse((xx,y+4,xx+3,y+7),outline=white,width=1)
                elif name=='grate': d.rounded_rectangle((x,y+3,x+10,y+9),radius=1,outline=white,width=1)
    elif name in ('leaf','vine','root','waves','dune','flame','crack','weave'):
        for phase in range(3,68,10):
            pts=[]
            for x in range(0,257,3):
                freq={'waves':17,'dune':29,'flame':9,'crack':6,'weave':5}.get(name,15)
                amount={'flame':5,'crack':3,'weave':2}.get(name,4)
                swing=amount*math.sin(x/freq+phase*.17)
                if name=='crack': swing+=rng.choice([-2,2])
                pts.append((x,phase+swing))
            line(pts,210 if name in ('waves','flame') else 160,1)
            if name in ('leaf','vine','root'):
                for x,y in pts[2::8]:
                    if name=='root': line([(x,y),(x+6,y+5),(x+14,y+7)],180)
                    else: d.ellipse((x,y-3,x+6,y+1),outline=white)
    elif name in ('sigils','chain','gear','forge','petals','rays','circuit'):
        for y in range(8,66,20):
            for x in range(8,260,25):
                if name in ('chain','sigils','gear','petals'):
                    if name=='chain': d.ellipse((x-8,y-4,x+7,y+4),outline=white)
                    if name=='petals':
                        for dx,dy in ((3,0),(-3,0),(0,3),(0,-3)):
                            d.ellipse((x+dx-3,y+dy-3,x+dx+3,y+dy+3),outline=white)
                    if name=='sigils':
                        d.ellipse((x-7,y-7,x+7,y+7),outline=white)
                        line([(x,y-5),(x+5,y+4),(x-5,y+4),(x,y-5)],240)
                    if name=='gear':
                        d.ellipse((x-6,y-6,x+6,y+6),outline=white,width=1)
                        for a in range(0,360,60):
                            a=math.radians(a);line([(x+6*math.cos(a),y+6*math.sin(a)),(x+9*math.cos(a),y+9*math.sin(a))],230,2)
                elif name=='forge':
                    d.rectangle((x-9,y-5,x+9,y+5),outline=white,width=1)
                    line([(x-5,y),(x+5,y)],235,2)
                elif name=='rays': line([(x-8,y+6),(x+8,y-6)],230,2)
                else:
                    line([(x-8,y+3),(x,y+3),(x,y-4),(x+10,y-4)],205)
                    d.ellipse((x+8,y-6,x+12,y-2),outline=white)
    else:
        assert name=='blank',name
    return im

def trim(name):
    im=Image.new('RGBA',(256,32));d=ImageDraw.Draw(im)
    def line(points,a=230,w=1): d.line(points,fill=(255,255,255,a),width=w)
    if name=='edge':
        line([(0,29),(255,29)],210,2)
    elif name=='double':
        for y in (24,29): line([(4,y),(251,y)],220,1)
    elif name=='forged':
        line([(0,26),(255,26)],170,4);line([(0,22),(255,22)],125)
        for x in (12,52,204,244):d.ellipse((x,24,x+4,28),fill=white)
    elif name=='standard':
        for x in (20,214):
            line([(x,0),(x,23),(x+11,30),(x+22,23),(x+22,0)],235,2)
    elif name=='split':
        d.rectangle((0,25,103,29),fill=white);d.rectangle((151,25,255,29),fill=white)
    elif name=='cut':
        line([(0,29),(82,29),(91,22),(165,22),(174,29),(255,29)],235,2)
    elif name=='brackets':
        line([(6,13),(6,27),(48,27)],240,3);line([(249,13),(249,27),(205,27)],240,3)
    elif name=='inset':
        line([(4,17),(4,27),(251,27),(251,17)],160,1)
        line([(10,30),(245,30)],140)
    elif name=='crown':
        line([(0,29),(89,29),(108,25),(122,15),(128,20),(134,15),(148,25),(166,29),(255,29)],255,2)
    elif name=='monolith':
        for x in (1,246):d.rectangle((x,8,x+8,31),fill=(255,255,255,195))
        line([(10,29),(245,29)],150,2)
    else:raise ValueError(name)
    return im

if __name__=='__main__':
    import re
    catalog=(out.parent.parent/'UI'/'ThemeCatalog.lua').read_text()
    recipes=re.findall(r"'[0-9A-F]{6}','[0-9A-F]{6}','[0-9A-F]{6}','[0-9A-F]{6}','(\w+)','(\w+)'",catalog)
    assert len(recipes)==100
    for name in sorted({a for a,_ in recipes}): material(name).save(out/('M_'+name+'.tga'))
    for name in sorted({b for _,b in recipes}): trim(name).save(out/('T_'+name+'.tga'))
