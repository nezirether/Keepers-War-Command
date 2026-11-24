"""Mastercraft art contract shared by intake and committed-package validation."""
import re

# (master size, export size, alpha required on export, opacity, crop to cover)
SLOTS = {
    "dashboard": ((2048, 1024), (512, 256), True, .78, True),
    "header": ((2048, 256), (512, 64), True, .55, False),
    "crest": ((512, 512), (128, 128), True, 1, True),
    "thumbnail": ((512, 288), (256, 128), False, 1, True),
    "alert": ((1024, 256), (512, 128), True, .22, False),
    "ornament": ((256, 256), (64, 64), True, .82, True),
    "material": (None, (256, 64), True, .16, False),
    "trim": (None, (256, 32), True, .82, False),
}

CATALOG = "KeepersWarCommand/UI/ThemeCatalog.lua"
THEMES = "KeepersWarCommand/UI/PublicThemes.lua"


def catalog_ids(source):
    names = re.findall(r"\{'([^']+)','[0-9A-F]{6}','[0-9A-F]{6}','[0-9A-F]{6}','[0-9A-F]{6}',", source)
    ids = [re.sub(r"[^a-z0-9]+", "-", name.lower().replace("&", "")).rstrip("-") for name in names]
    if len(ids) != 100 or len(set(ids)) != 100:
        raise ValueError("Expected 100 unique public theme IDs")
    return ids


def focal(point):
    if (not isinstance(point, list) or len(point) != 2
            or any(type(v) not in (int, float) or not 0 <= v <= 1 for v in point)):
        raise ValueError("Focal must be [x, y] with each coordinate within [0, 1]")
    return point


def export_path(skin_id, slot):
    return f"Art/{skin_id}/{slot}.tga"
