"""Builds Media/WinterVeil from the supplied KWC_WinterVeil_TexturePack.

The pack is only read. The addon copies have stray fragments of neighbouring atlas
art cleared; nothing else changes. Usage: winterveil_art.py <pack.zip>
"""
import io, os, sys, zipfile, struct
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'KeepersWarCommand', 'Media', 'WinterVeil')
# name: (size, [rectangles to clear as x0, y0, x1, y1])
ASSETS = {
    'FestiveTrogdor': ((1024, 256), [(0, 238, 1024, 256)]),
    'HeaderGarland': ((1024, 128), []),
    'FrostCornerLeft': ((256, 256), [(128, 200, 256, 256)]),
    'FrostCornerRight': ((256, 256), [(0, 200, 128, 256)]),
    'WinterVeilEmblem': ((512, 512), [(0, 405, 70, 512), (450, 405, 512, 512), (0, 0, 80, 95), (440, 0, 512, 95)]),
}


def main(pack):
    os.makedirs(OUT, exist_ok=True)
    with zipfile.ZipFile(pack) as z:
        for name, (size, clear) in ASSETS.items():
            im = Image.open(io.BytesIO(z.read('Textures/%s.tga' % name))).convert('RGBA')
            assert im.size == size, (name, im.size)
            for box in clear:
                im.paste((0, 0, 0, 0), box)
            path = os.path.join(OUT, name + '.tga')
            im.save(path, compression=None, orientation=-1)
            head = open(path, 'rb').read(18)
            assert head[2] == 2 and head[16] == 32 and head[17] & 0x0f == 8, (name, head)
            assert struct.unpack('<HH', head[12:16]) == size
            print(name, size, 'cleared', len(clear), os.path.getsize(path))


if __name__ == '__main__':
    main(sys.argv[1])
