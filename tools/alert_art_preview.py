#!/usr/bin/env python3
"""Render an offline contact sheet of the alert plates as the War Room lays them out.

Reads the committed TGAs (round-trip check) and mirrors UI/AlertArt.lua geometry:
plate width = max(body_w*1.12, body_h/0.62*3), centred with the cy offset, scrim
behind live text, toast body unchanged. Fonts and spell icons are stand-ins; this
is a layout and readability preview, not an in-game capture.

    python3 tools/alert_art_preview.py out.png
"""
import json, struct, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ALERTS = ROOT / 'KeepersWarCommand' / 'Media' / 'Alerts'
MAN = json.loads((ROOT / 'docs' / 'ALERT_ART.json').read_text())
SCALE = 2
TROGDOR = dict(base='1A1517', text='FAEDDF', muted='DED0C3', faint='BDACA1', accent='EEA56E',
               accentText='FFC498', good='A2CF8F', danger='F18986', warn='EFC075')
FONT = 'C:/Windows/Fonts/segoeui.ttf' if sys.platform=='win32' else '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
FONTB = 'C:/Windows/Fonts/seguisb.ttf' if sys.platform=='win32' else '/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf'
LEVEL_W = {'Standard': 404, 'Heroic': 460, 'Legendary': 540}

SAMPLES = {
    'honorableKill': ('ENEMY SLAIN  |  WORLD PVP', 'good', 'Nez Dankdabs slew Alliance Rogue', 'Honorable kill', 'Hillsbrad Foothills', [], 'Standard'),
    'killingBlow': ('KILLING BLOW  |  WORLD PVP', 'good', 'Nez Dankdabs killed Brightblade-Stormrage', 'No honor awarded (enemy too low or recently killed)', 'Arathi Highlands', [], 'Heroic'),
    'killStreak': ('VERIFIED LOCAL STREAK', 'accent', 'Legendary Burninator', 'Nez Dankdabs  •  20 this session', 'Alterac Mountains', [], 'Legendary'),
    'fallen': ('GUILDMATE SLAIN  |  WORLD PVP', 'danger', 'Filibuster Fente was slain', 'Killed by: Brightblade-Stormrage', 'Tarren Mill  48.2, 61.7', ['Post bounty', 'Death log'], 'Standard'),
    'bountyPosted': ('BOUNTY POSTED', 'warn', 'Brightblade-Stormrage', 'Reward: 25g  •  camping Tarren Mill', 'Hillsbrad Foothills', ['Open'], 'Standard'),
    'bountySighting': ('BOUNTY TARGET SPOTTED', 'warn', 'Brightblade-Stormrage', 'Reward: 25g', 'Hillsbrad Foothills', ['Report sighting'], 'Standard'),
    'bountyClaimed': ('BOUNTY COMPLETED', 'accent', 'Brightblade-Stormrage', 'Completion confirmed by Nez Dankdabs', '', [], 'Heroic'),
    'callToArms': ('CALL TO ARMS', 'warn', '[HIGH] Hillsbrad Foothills  H:A 4:9', 'Defend Tarren Mill', '', ['Open'], 'Standard'),
    'ctaVictory': ('CALL TO ARMS', 'accent', 'Defend Tarren Mill', 'Victory confirmed by Nez Dankdabs', '', [], 'Heroic'),
    'commendation': ('KWC COMMENDATION', 'accent', 'Confirmed killing blows', 'Nez Dankdabs  •  25 observed killing blows', 'Ashenvale', [], 'Heroic'),
}


def hexc(h, a=255):
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def read_tga(path):
    d = path.read_bytes()
    w, h = struct.unpack('<HH', d[12:16])
    img = Image.frombytes('RGBA', (w, h), d[18:18 + w * h * 4]).transpose(Image.FLIP_TOP_BOTTOM)
    b, g, r, a = img.split()
    return Image.merge('RGBA', (r, g, b, a))


def toast(key, palette=TROGDOR, width=None):
    plate = MAN['plates'][key]
    kicker, tone, title, detail, meta, actions, level = SAMPLES[key]
    w = width or LEVEL_W[level]
    h = 106 + 30 * ((len(actions) + 1) // 2) if actions else 98
    pw = max(w * 1.12, h / 0.62 * (512 / 171))
    ph = pw / (512 / 171)
    dy = (plate['cy'] - 0.5) * ph
    pad = 6
    cw, ch = int(pw + 2 * pad), int(ph + 2 * pad)
    s = SCALE
    canvas = Image.new('RGBA', (cw * s, ch * s), (0, 0, 0, 0))
    tex = read_tga(ALERTS / (plate['file'] + '.tga')).crop((0, 0, 512, 171))
    canvas.alpha_composite(tex.resize((int(pw * s), int(ph * s)), Image.LANCZOS), (pad * s, pad * s))
    fx = pad + (pw - w) / 2
    fy = pad + (ph - h) / 2 + dy  # screen y grows downward; dy>0 moves plate up => frame lower in plate
    d = ImageDraw.Draw(canvas, 'RGBA')
    f12, f15 = ImageFont.truetype(FONTB, 11 * s), ImageFont.truetype(FONT, 14 * s)
    f12r = ImageFont.truetype(FONT, 11 * s)
    lines = [(kicker, f12), (title, f15), (detail, f12r), (meta, f12)]
    widest = max(d.textlength(t, font=f) / s for t, f in lines if t)
    solid = min(max(68 + widest + 14, w * 0.42), w - 28)
    fade = min(84, w - solid + 20)
    base = hexc(palette['base'])
    scrim = Image.new('RGBA', (int((solid + fade) * s), int((h - 8) * s)), (0, 0, 0, 0))
    sd = ImageDraw.Draw(scrim)
    for x in range(scrim.width):
        xx = x / s
        a = 0.6 if xx <= solid else 0.6 * (1 - (xx - solid) / fade) ** 1.6
        sd.line([(x, 0), (x, scrim.height)], fill=base[:3] + (int(a * 255),))
    canvas.alpha_composite(scrim, (int(fx * s), int((fy + 4) * s)))
    tc = palette['accentText'] if tone == 'accent' else palette[tone]
    ix, iy = fx + 16, fy + 14
    d.rectangle([ix * s, iy * s, (ix + 40) * s, (iy + 40) * s], fill=hexc('3A2A22'), outline=hexc(palette['accent'], 200), width=s)
    tx = ix + 52
    d.text((tx * s, (iy - 1) * s), kicker, font=f12, fill=hexc(tc))
    d.text((tx * s, (iy + 14) * s), title, font=f15, fill=hexc(palette['text']))
    d.text((tx * s, (iy + 34) * s), detail, font=f12r, fill=hexc(palette['muted']))
    if meta:
        d.text((tx * s, (iy + 62) * s), meta, font=f12, fill=hexc(palette['faint']))
    bx = fx + w - 12
    for i, label in enumerate(actions):
        bw = 130
        x0 = bx - bw - i * 138
        d.rectangle([x0 * s, (fy + h - 34) * s, (x0 + bw) * s, (fy + h - 10) * s],
                    fill=hexc(palette['accent'] if i == 0 else '2C2224'), outline=hexc(palette['accent']), width=s)
        d.text(((x0 + bw / 2) * s, (fy + h - 22) * s), label, font=f12, anchor='mm',
               fill=hexc('16121A' if i == 0 else palette['text']))
    # close control backing + timer
    cx, cy0 = fx + w - 28, fy + 6
    d.rectangle([(cx + 2) * s, (cy0 + 2) * s, (cx + 20) * s, (cy0 + 20) * s], fill=base[:3] + (178,))
    d.text(((cx + 11) * s, (cy0 + 11) * s), 'x', font=ImageFont.truetype(FONT, 14 * s), anchor='mm', fill=hexc(palette['faint']))
    d.line([((fx + 4) * s, (fy + h - 1) * s), ((fx + w * 0.62) * s, (fy + h - 1) * s)], fill=hexc(tc), width=2 * s)
    # dashed outline: the toast body = the only mouse-active area
    for x in range(int(fx * s), int((fx + w) * s), 10):
        d.line([(x, fy * s), (x + 5, fy * s)], fill=(120, 220, 255, 150))
        d.line([(x, (fy + h) * s), (x + 5, (fy + h) * s)], fill=(120, 220, 255, 150))
    return canvas, (w, level)


def sheet(out):
    tiles = []
    for key in MAN['plates']:
        img, (w, level) = toast(key)
        tiles.append((key, img, w, level))
    colw = max(t[1].width for t in tiles)
    gap, header = 28, 60
    rows = (len(tiles) + 1) // 2
    rowh = max(t[1].height for t in tiles) + 40
    W, H = colw * 2 + gap * 3, header + rows * rowh + 40
    bg = Image.new('RGBA', (W, H), (14, 12, 14, 255))
    d = ImageDraw.Draw(bg)
    d.text((gap, 18), 'KWC Alert Art Pack v1 — War Room toast layout (Trogdor skin, offline render, 2x)', font=ImageFont.truetype(FONTB, 26), fill=(240, 220, 200))
    for i, (key, img, w, level) in enumerate(tiles):
        r, c = divmod(i, 2)
        x, y = gap + c * (colw + gap), header + r * rowh
        d.text((x, y + 4), f"{key}  →  {MAN['plates'][key]['file']}.tga   ({level}, width {w}, height fits content; dashed = click area)",
               font=ImageFont.truetype(FONT, 18), fill=(190, 180, 170))
        bg.alpha_composite(img, (x, y + 30))
    bg.convert('RGB').save(out, quality=92)
    print('wrote', out, bg.size)


if __name__ == '__main__':
    sheet(sys.argv[1] if len(sys.argv) > 1 else 'alert_art_contact_sheet.png')
