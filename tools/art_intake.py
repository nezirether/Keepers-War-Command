"""Check or stage one approved-ID artwork pack outside the public checkout."""
import argparse
import hashlib
import io
import json
import os
import tempfile
from pathlib import Path

from art_contract import CATALOG, SLOTS, THEMES, catalog_ids, export_path, focal
from theme_art import MANIFEST, MEDIA, REGISTRY, ROOT, validate

LIMIT = 64 * 1024 * 1024


def json_bytes(value):
    return (json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n").encode()


def safe_read(root, relative):
    path = (root / relative).resolve(strict=True)
    if not path.is_relative_to(root) or not path.is_file():
        raise ValueError(f"Expected a regular file inside the art pack: {relative}")
    if path.stat().st_size > LIMIT:
        raise ValueError(f"{relative}: exceeds the 64 MiB intake limit")
    return path.read_bytes()


def unique_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def export_png(data, slot, point):
    from PIL import Image, ImageCms

    master, size, rgba, _, _ = SLOTS[slot]
    with Image.open(io.BytesIO(data), formats=["PNG"]) as file:
        w, h = file.size
        if file.is_animated:
            raise ValueError("Animated PNGs are unsupported")
        if master and file.size != master:
            raise ValueError(f"Expected master {master[0]}×{master[1]}, got {w}×{h}")
        if not master and (w * size[1] != h * size[0] or not size[0] <= w <= 4096 or h < size[1]):
            raise ValueError(f"Tile must match {size[0]}:{size[1]} at export size or larger, up to 4096 px")
        file.verify()
    with Image.open(io.BytesIO(data), formats=["PNG"]) as file:
        image = file.convert("RGBA")
        alpha = image.getchannel("A")
        if alpha.getextrema()[1] == 0:
            raise ValueError("Artwork is fully transparent")
        icc = file.info.get("icc_profile")
        if icc:
            source = ImageCms.ImageCmsProfile(io.BytesIO(icc))
            rgb = ImageCms.profileToProfile(file.convert("RGB"), source, ImageCms.createProfile("sRGB"))
            rgb.putalpha(alpha)
            image = rgb
        if not rgba and alpha.getextrema() != (255, 255):
            raise ValueError("Thumbnail must be flattened onto an opaque background")
        if slot == "thumbnail":
            height = w * size[1] // size[0]
            top = round(max(0, min(h - height, point[1] * h - height / 2)))
            image = image.crop((0, top, w, top + height))
            point = [point[0], max(0, min(1, (point[1] * h - top) / height))]
        image = image.resize(size, Image.Resampling.LANCZOS)
        output = io.BytesIO()
        image.convert("RGBA" if rgba else "RGB").save(output, format="TGA")
        return output.getvalue(), point


def prepare(pack, repo):
    source = json.loads(safe_read(pack, "manifest.json"), object_pairs_hook=unique_keys)
    if (not isinstance(source, dict) or set(source) != {"schema", "skin_id", "slots"}
            or type(source["schema"]) is not int or source["schema"] != 1):
        raise ValueError("Expected schema 1 with skin_id and slots")
    catalog = (repo / CATALOG).read_text(encoding="utf-8")
    skin_id = source["skin_id"]
    if skin_id not in catalog_ids(catalog):
        raise ValueError(f"Unknown theme ID: {skin_id}")
    slots = source["slots"]
    if not isinstance(slots, dict) or set(slots) != set(SLOTS):
        raise ValueError("Expected eight slots: " + ", ".join(SLOTS))
    original = (repo / MANIFEST).read_bytes()
    manifest = json.loads(original)
    production = manifest.setdefault("production", {})
    if skin_id in production:
        raise ValueError(f"{skin_id} is already approved. Review the existing revision before replacement.")
    files = {}
    for slot in SLOTS:
        entry = slots[slot]
        try:
            if (not isinstance(entry, dict) or set(entry) != {"source", "license", "focal"}
                    or any(not isinstance(entry[k], str) or not entry[k].strip() for k in ("source", "license"))):
                raise ValueError("Expected non-empty source and license, and normalized focal coordinates")
            point = focal(entry["focal"])
            path = MEDIA + export_path(skin_id, slot)
            if (repo / path).exists():
                raise ValueError(f"Public texture already exists at {path}")
            data, point = export_png(safe_read(pack, f"source/{slot}.png"), slot, point)
            files[path] = data
            entry["focal"] = point
        except (OSError, ValueError) as error:
            raise ValueError(f"{skin_id}/{slot}: {error}") from error
    production[skin_id] = source

    def read(relative):
        if relative in files:
            return files[relative]
        return (repo / relative).read_bytes()

    files[REGISTRY] = validate(read, manifest, catalog, read(THEMES).decode()).encode("ascii")
    files[MANIFEST] = json_bytes(manifest)
    files["STAGING_REPORT.json"] = json_bytes({
        "skin_id": skin_id,
        "baseline_manifest_sha256": hashlib.sha256(original).hexdigest(),
        "candidate_files": {path: hashlib.sha256(data).hexdigest() for path, data in files.items()},
    })
    return files


def stage(files, output, pack, repo):
    if output.exists() or output.is_relative_to(pack) or output.is_relative_to(repo):
        raise ValueError("Stage to a new directory outside the input pack and the public checkout")
    with tempfile.TemporaryDirectory(dir=output.parent, prefix=".kwc-art-") as temp:
        payload = Path(temp) / "candidate"
        for path, data in files.items():
            target = payload / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        os.rename(payload, output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pack", type=Path, help="One incoming delivery folder containing manifest.json")
    parser.add_argument("--repo", type=Path, default=ROOT, help="Verified public checkout")
    parser.add_argument("--stage", type=Path, help="Create a new candidate directory outside the checkout")
    args = parser.parse_args()
    try:
        pack, repo = args.pack.resolve(strict=True), args.repo.resolve(strict=True)
        files = prepare(pack, repo)
        if args.stage:
            stage(files, args.stage.resolve(), pack, repo)
    except (OSError, ValueError, ImportError, KeyError, TypeError) as error:
        parser.exit(1, f"Artwork intake failed: {error}\n")
    print("Validated eight exported textures and the candidate public registration.")
    if args.stage:
        print(f"Candidate created at {args.stage.resolve()}")


if __name__ == "__main__":
    main()
