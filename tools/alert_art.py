#!/usr/bin/env python3
"""Convert the KWC Alert Art Pack PNGs into Forever-ready TGA alert plates.

    python3 tools/alert_art.py --src <assets dir> --write   # convert + write TGAs
    python3 tools/alert_art.py --check                       # validate committed TGAs + Lua registry

Output: KeepersWarCommand/Media/Alerts/<file>.tga (512x256, 32-bit BGRA, straight
alpha, bottom-left origin, uncompressed, same as Media/Art) plus ScrimFade.tga.
Masters stay outside the add-on. Requires Pillow.
"""
import argparse, json, re, struct, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'docs' / 'ALERT_ART.json'
OUT = ROOT / 'KeepersWarCommand' / 'Media' / 'Alerts'
REGISTRY = ROOT / 'KeepersWarCommand' / 'UI' / 'AlertArt.lua'


def tga_bytes(img):
    """Uncompressed 32-bit BGRA, bottom-left origin, 8 alpha bits (descriptor 0x08)."""
    w, h = img.size
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    r, g, b, a = img.split()
    from PIL import Image
    bgra = Image.merge('RGBA', (b, g, r, a)).transpose(Image.FLIP_TOP_BOTTOM)
    return header + bgra.tobytes()


def to_srgb(img):
    from PIL import Image, ImageCms
    icc = img.info.get('icc_profile')
    if icc:
        import io
        src = ImageCms.ImageCmsProfile(io.BytesIO(icc))
        dst = ImageCms.createProfile('sRGB')
        mode = img.mode
        img = ImageCms.profileToProfile(img.convert('RGBA'), src, dst, outputMode='RGBA')
    return img.convert('RGBA')


def resize_premultiplied(img, size):
    """Resize in premultiplied space so transparent edges do not halo."""
    import numpy as np
    from PIL import Image
    a = np.asarray(img).astype(np.float32) / 255.0
    rgb, al = a[..., :3], a[..., 3:4]
    pre = np.concatenate([rgb * al, al], axis=2)
    chans = [Image.fromarray(pre[..., i]).resize(size, Image.LANCZOS) for i in range(4)]
    out = np.stack([np.asarray(c) for c in chans], axis=2)
    out = np.clip(out, 0.0, 1.0)
    alpha = out[..., 3:4]
    rgb = np.where(alpha > 1e-4, out[..., :3] / np.maximum(alpha, 1e-4), 0.0)
    res = np.concatenate([np.clip(rgb, 0, 1), alpha], axis=2)
    return Image.fromarray((res * 255.0 + 0.5).astype(np.uint8), 'RGBA')


def convert(src_dir, manifest):
    from PIL import Image, ImageFilter
    OUT.mkdir(parents=True, exist_ok=True)
    cw, ch = manifest['canvas']
    pw, ph = manifest['content']
    written = []
    for key, plate in manifest['plates'].items():
        src = Path(src_dir) / plate['source']
        img = to_srgb(Image.open(src))
        if abs(img.width / img.height - pw / ph) > 0.02:
            raise SystemExit(f'{src.name}: expected ~3:1 master, got {img.size}')
        small = resize_premultiplied(img, (pw, ph))
        # Mild sharpening restores painted detail lost in the 4.2x reduction.
        rgb = small.convert('RGB').filter(ImageFilter.UnsharpMask(radius=0.8, percent=45, threshold=2))
        small = Image.merge('RGBA', (*rgb.split(), small.getchannel('A')))
        canvas = Image.new('RGBA', (cw, ch), (0, 0, 0, 0))
        canvas.paste(small, (0, 0))
        path = OUT / (plate['file'] + '.tga')
        path.write_bytes(tga_bytes(canvas))
        written.append(path)
    sw, sh = manifest['scrim']['size']
    ramp = Image.new('RGBA', (sw, sh))
    for x in range(sw):
        t = x / (sw - 1)
        a = int(round(255 * (1 - t) ** 1.6))  # eased fade: dense under text, soft tail
        for y in range(sh):
            ramp.putpixel((x, y), (255, 255, 255, a))
    path = OUT / (manifest['scrim']['file'] + '.tga')
    path.write_bytes(tga_bytes(ramp))
    written.append(path)
    return written


def read_tga(path, reader=None):
    data = reader(path.relative_to(ROOT).as_posix()) if reader else path.read_bytes()
    if len(data) < 18:
        raise ValueError(f"{path.name}: truncated TGA header")
    ident, cmap, mode, _, _, _, _, _, w, h, bits, flags = struct.unpack('<BBBHHBHHHHBB', data[:18])
    if cmap or mode != 2 or bits != 32 or flags != 8 or len(data) != 18 + ident + w * h * 4:
        raise ValueError(f'{path.name}: not an uncompressed 32-bit bottom-left TGA')
    alpha = data[18 + ident + 3::4]
    if min(alpha) == 255 or max(alpha) == 0:
        raise ValueError(f'{path.name}: expected meaningful transparency')
    return w, h


def check(manifest, reader=None, paths=None):
    problems = []
    lua = reader(REGISTRY.relative_to(ROOT).as_posix()).decode() if reader else REGISTRY.read_text(encoding='utf-8')
    registered = dict(re.findall(r"(\w+)=\{file='Alerts\\\\(\w+)'", lua))
    total = 0
    for key, plate in manifest['plates'].items():
        path = OUT / (plate['file'] + '.tga')
        try:
            w, h = read_tga(path, reader)
            if (w, h) != tuple(manifest['canvas']):
                problems.append(f'{path.name}: {w}x{h}, expected {manifest["canvas"]}')
            total += len(reader(path.relative_to(ROOT).as_posix())) if reader else path.stat().st_size
        except (OSError, ValueError) as e:
            problems.append(str(e))
        if registered.get(key) != plate['file']:
            problems.append(f'{key}: Lua registry entry missing or points elsewhere ({registered.get(key)})')
    extra = set(registered) - set(manifest['plates'])
    if extra:
        problems.append(f'Lua registry has unmanifested plates: {sorted(extra)}')
    scrim = OUT / (manifest['scrim']['file'] + '.tga')
    try:
        if read_tga(scrim, reader) != tuple(manifest['scrim']['size']):
            problems.append('ScrimFade.tga has the wrong size')
    except (OSError, ValueError) as e:
        problems.append(str(e))
    actual = {Path(p).name for p in paths if p.startswith('KeepersWarCommand/Media/Alerts/')} if paths is not None else {p.name for p in OUT.glob('*')}
    stray = actual - {pl['file'] + '.tga' for pl in manifest['plates'].values()} - {scrim.name}
    if stray:
        problems.append(f'unexpected files in Media/Alerts: {sorted(stray)}')
    return problems, total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', help='directory holding the pack PNGs')
    ap.add_argument('--write', action='store_true')
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    if args.write:
        if not args.src:
            ap.error('--write needs --src')
        for p in convert(args.src, manifest):
            print('wrote', p.relative_to(ROOT))
    problems, total = check(manifest)
    for p in problems:
        print('FAIL', p)
    print(f'alert plates: {len(manifest["plates"])} manifested, {total/1048576:.2f} MiB on disk, '
          f'{"OK" if not problems else str(len(problems)) + " problem(s)"}')
    sys.exit(1 if problems else 0)


if __name__ == '__main__':
    main()
