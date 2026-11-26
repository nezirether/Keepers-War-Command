#!/usr/bin/env python3
"""Build the World PvP leaderboard textures from KWC_WorldPvP_TexturePack_v1.zip.

Usage: python tools/worldpvp_art.py <pack.zip> [--previews DIR]
Writes uncompressed 32-bit TGA files to Media/WarRoomClassic/WorldPvP/ and an
inventory to design/WorldPvP/INVENTORY.json. The source pack is never modified.
Adaptations: leftover laurel/crown fragments are removed from the three tier
rows, and the dark backing of emblems and icons becomes transparent.
"""
import hashlib, io, json, os, sys, zipfile
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'KeepersWarCommand', 'Media', 'WarRoomClassic', 'WorldPvP')
SKIP = {'Icon_Deaths': 'no deaths board on the leaderboard page'}
REPAIR = {'Row_Legendary', 'Row_Epic', 'Row_Elite'}
KEYED = ('Emblem_', 'Icon_')
# The shield's dark red field sits close to the backing, so it needs a tighter key.
THRESHOLD = {'Icon_WorldPvP': 16}

def repair_row(im):
    """Cover columns 36-219 (label-removal leftovers) with clean columns from
    further right, feathered so the frame rails stay continuous."""
    left, width = 36, 184
    patch = im.crop((300, 0, 300 + width, im.height))
    mask = Image.new('L', patch.size, 255)
    draw = ImageDraw.Draw(mask)
    for i in range(14):
        v = int(255 * (i + 1) / 15)
        draw.line([(i, 0), (i, im.height)], fill=v)
        draw.line([(width - 1 - i, 0), (width - 1 - i, im.height)], fill=v)
    out = im.copy()
    out.paste(patch, (left, 0), mask)
    return out

def key_backing(im, threshold=34):
    """Flood the dark backing from the border to transparent; art is untouched."""
    rgb = im.convert('RGB')
    dark = rgb.convert('L').point(lambda v: 255 if v <= threshold else 0)
    w, h = dark.size
    framed = Image.new('L', (w + 2, h + 2), 255)
    framed.paste(dark, (1, 1))
    ImageDraw.floodfill(framed, (0, 0), 128)
    alpha = framed.crop((1, 1, w + 1, h + 1)).point(lambda v: 0 if v == 128 else 255)
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.6))
    out = rgb.convert('RGBA')
    out.putalpha(alpha)
    return out

def main():
    pack = sys.argv[1]
    previews = sys.argv[3] if len(sys.argv) > 3 and sys.argv[2] == '--previews' else None
    os.makedirs(OUT, exist_ok=True)
    inventory = []
    with zipfile.ZipFile(pack) as z:
        manifest = json.loads(z.read('manifest.json'))
        for entry in manifest:
            name, data = entry['name'], z.read(entry['file'])
            im = Image.open(io.BytesIO(data)).convert('RGBA')
            assert im.size == (entry['width'], entry['height']), name
            assert all(n & (n - 1) == 0 for n in im.size), name
            record = {'name': name, 'width': im.width, 'height': im.height,
                      'sourceSha256': hashlib.sha256(data).hexdigest()}
            if name in SKIP:
                record.update(shipped=False, reason=SKIP[name])
            else:
                change = 'none (byte-identical)'
                if name in REPAIR:
                    im, change = repair_row(im), 'removed leftover laurel/crown fragments (x 36-219)'
                elif name.startswith(KEYED):
                    im, change = key_backing(im, THRESHOLD.get(name, 34)), 'dark backing keyed to transparency'
                path = os.path.join(OUT, name + '.tga')
                if change.startswith('none'):
                    open(path, 'wb').write(data)
                else:
                    im.save(path, format='TGA', compression=None, orientation=-1)
                out = open(path, 'rb').read()
                assert out[2] == 2 and out[16] == 32 and out[17] == 8, (name, out[:18])
                record.update(shipped=True, adaptation=change,
                              path='Media/WarRoomClassic/WorldPvP/%s.tga' % name,
                              sha256=hashlib.sha256(out).hexdigest())
                if previews:
                    os.makedirs(previews, exist_ok=True)
                    Image.open(path).save(os.path.join(previews, name + '.png'))
            inventory.append(record)
    os.makedirs(os.path.join(ROOT, 'design', 'WorldPvP'), exist_ok=True)
    with open(os.path.join(ROOT, 'design', 'WorldPvP', 'INVENTORY.json'), 'w', newline='\n') as f:
        json.dump(inventory, f, indent=1)
    print('shipped', sum(r['shipped'] for r in inventory), 'of', len(inventory))

if __name__ == '__main__':
    main()
