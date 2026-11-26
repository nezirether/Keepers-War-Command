#!/usr/bin/env python3
"""Offline composite of the leaderboard page using the shipped textures and the
layout numbers from UI/Pages/Leaderboards.lua. This is a layout preview with
sample data and system fonts, not an in-game screenshot.

Usage: python tools/worldpvp_preview.py <output dir>
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, 'KeepersWarCommand', 'Media', 'WarRoomClassic', 'WorldPvP')
FONTS = r'C:\Windows\Fonts'
S = 2  # supersample for readable previews

def font(name, size): return ImageFont.truetype(os.path.join(FONTS, name), size * S)
def art(name): return Image.open(os.path.join(ART, name + '.tga')).convert('RGBA')
def rgb(c): return tuple(int(v * 255) for v in c)

def paste(canvas, im, x, y, w, h):
    canvas.alpha_composite(im.resize((max(1, round(w * S)), max(1, round(h * S))), Image.LANCZOS), (round(x * S), round(y * S)))

def slices(canvas, name, x, y, w, h, cap_l, cap_r, v):
    im = art(name); sw, sh = im.size; vh = round(v * sh)
    scale = h / sh
    left = cap_l * scale; right = min(cap_r * scale, w * 0.45)
    u2 = sw - right / scale
    paste(canvas, im.crop((0, 0, cap_l, vh)), x, y, left, h)
    paste(canvas, im.crop((cap_l, 0, sw - cap_r, vh)), x + left, y, w - left - right, h)
    paste(canvas, im.crop((round(u2), 0, sw, vh)), x + w - right, y, right, h)

def text(d, x, y, s, f, fill, width=None, anchor='lm', shadow=True):
    if width is not None and d.textlength(s, font=f) > width * S:
        while s and d.textlength(s + '...', font=f) > width * S: s = s[:-1]
        s += '...'
    if shadow: d.text(((x + 1) * S, (y + 1) * S), s, font=f, fill=(0, 0, 0), anchor=anchor)
    d.text((x * S, y * S), s, font=f, fill=fill, anchor=anchor)

TIERS = {1: ('Row_Legendary', 'Emblem_Legendary', 1, (1, .92, .62), (1, .78, .25)),
         2: ('Row_Epic', 'Emblem_Epic', 63 / 64, (.96, .86, 1), (.86, .62, 1)),
         3: ('Row_Epic', 'Emblem_Epic', 63 / 64, (.96, .86, 1), (.86, .62, 1)),
         4: ('Row_Elite', 'Emblem_Elite', 59 / 64, (.88, .95, 1), (.58, .82, 1)),
         5: ('Row_Elite', 'Emblem_Elite', 59 / 64, (.88, .95, 1), (.58, .82, 1))}
STANDARD = ('Row_Standard', None, 1, (.93, .89, .82), (.76, .62, .42))
SAMPLE = [('Sample Warlord', 1234567), ('Bartholomew Emberwardenstormcaller-Longrealm', 48210), ('Cinder Vale', 9120),
          ('Dorn Hollow', 4410), ('Ember Reach', 2875), ('Flint Marsh', 1930), ('Gale Thorne', 812),
          ('Hearth Oakes', 455), ('Iron Wick', 120), ('Juniper Sol', None), ('Kestrel Moor', None),
          ('Larkspur Dane', None), ('Mossy Quill', None), ('Nettle Crane', None), ('Orrin Vale', None),
          ('Pike Sorrel', None), ('Quarry Ash', None), ('Rook Bramble', None), ('Sedge Holt', None), ('Thistle Vane', None)]

def render(board, width, height, out):
    img = Image.new('RGBA', ((width + 40) * S, (height + 40) * S), (14, 12, 11, 255))
    layer = img
    d = ImageDraw.Draw(img)
    ox, oy = 20, 20
    display, narrow, body = 'georgiab.ttf', 'arialbd.ttf', 'arial.ttf'
    for i, (key, label, icon) in enumerate([('world', 'World PvP', 'Icon_WorldPvP'), ('battleground', 'Battlegrounds', 'Icon_Battlegrounds'), ('lifetime', 'Lifetime HKs', 'Icon_Lifetime')]):
        x = ox + i * 176; on = key == board
        slices(layer, 'Tab_Selected' if on else 'Tab_Inactive', x, oy, 170, 36, 32, 32, 62 / 64)
        ic = art(icon)
        if not on: ic.putalpha(ic.getchannel('A').point(lambda a: int(a * .7)))
        paste(layer, ic, x + 14, oy + 6, 24, 24)
        text(d, x + 44, oy + 18, label, font(display, 13), rgb((1, .92, .66) if on else (.72, .68, .61)), 116)
    y = oy + 42
    if board == 'world':
        tall = height >= 560
        h = min(150, int(height * .24)) if tall else 72
        h = min(h, width // 5)
        paste(layer, art('Warlords_Banner' if tall else 'WorldPvP_Header'), ox + (width - h * 5) / 2, y, h * 5, h)
    else:
        h = 52
        paste(layer, art('KWC_Crest'), ox, y, 200, 52)
        title = 'Battleground Kills' if board == 'battleground' else 'Lifetime Honorable Kills'
        note = 'Honorable kills earned in battlegrounds, kept separate from the world.' if board == 'battleground' else 'All-time honorable kills from each character.'
        text(d, ox + 214, y + 16, title, font(display, 21), (232, 222, 204), width - 214)
        text(d, ox + 214, y + 40, note, font(body, 12), (170, 160, 145), width - 214)
    y += h + 8
    d.rectangle([ox * S, y * S, (ox + 200) * S, (y + 28) * S], outline=(120, 96, 60), width=S)
    text(d, ox + 28, y + 14, 'Find a guildmate', font(body, 12), (130, 120, 108))
    d.rectangle([(ox + width - 160) * S, y * S, (ox + width) * S, (y + 30) * S], fill=(110, 22, 16), outline=(190, 140, 60), width=S)
    text(d, ox + width - 80, y + 15, 'Refresh my stats', font(body, 13), (245, 232, 205), anchor='mm')
    y += 40
    d.rectangle([ox * S, y * S, (ox + width) * S, (y + 29) * S], fill=(44, 34, 24))
    label = {'world': 'WORLD PVP HONORABLE KILLS', 'battleground': 'BATTLEGROUND HONORABLE KILLS', 'lifetime': 'LIFETIME HONORABLE KILLS'}[board]
    text(d, ox + 8, y + 15, label, font(narrow, 12), (224, 176, 96))
    y += 35
    row_h, gap = (44, 2) if board == 'world' else (30, 1)
    visible = int((oy + height - y + gap) // (row_h + gap))
    for i, (name, value) in enumerate(SAMPLE[:visible]):
        ry = y + i * (row_h + gap); w = width - 10; rank = i + 1
        shown = '{:,}'.format(value) if value is not None else 'Awaiting Stats'
        if board == 'world':
            warlord = rank <= 5 and value
            row, emblem, v, nc, ac = TIERS[rank] if warlord else STANDARD
            slices(layer, row, ox, ry, w, row_h, 48, 364, v)
            if emblem: paste(layer, art(emblem), ox + 8, ry + 5, 34, 34)
            value_w = int(min(130, max(84, w * .22))); text_w = w - 98 - value_w - 30
            text(d, ox + 70, ry + 22, '#%d' % rank if value is not None else '-', font(display, 17), rgb(ac), anchor='mm')
            text(d, ox + 98, ry + (15 if warlord else 22), name, font(display, 15), rgb(nc), text_w)
            if warlord: text(d, ox + 98, ry + 31, 'WARLORD OF TROGDOR', font(narrow, 11), rgb(ac), text_w)
            text(d, ox + w - 18, ry + 22, shown, font(narrow, 20 if value is not None else 12), rgb(nc if value is not None else STANDARD[4]), anchor='rm')
        else:
            d.rectangle([ox * S, ry * S, (ox + w) * S, (ry + row_h) * S], fill=(31, 27, 24) if rank % 2 else (39, 34, 30))
            value_w = int(min(130, max(84, w * .22)))
            text(d, ox + 10, ry + 15, '#%d' % rank if value is not None else '-', font(body, 13), (140, 128, 112), shadow=False)
            text(d, ox + 62, ry + 15, name, font(body, 13), (232, 222, 204), w - 62 - value_w - 76, shadow=False)
            text(d, ox + w - 14, ry + 15, shown, font(narrow, 15), (232, 222, 204) if value is not None else (140, 128, 112), anchor='rm', shadow=False)
    img.convert('RGB').save(out)

if __name__ == '__main__':
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    render('world', 656, 436, os.path.join(out, 'world_min_window.png'))
    render('world', 936, 636, os.path.join(out, 'world_default_window.png'))
    render('battleground', 936, 636, os.path.join(out, 'battleground_default_window.png'))
    render('lifetime', 656, 436, os.path.join(out, 'lifetime_min_window.png'))
    print('ok')
