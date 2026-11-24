"""Verify representative accept and reject cases for the public art build gate."""
import copy
import json
import unittest

import theme_art as art


class ArtworkValidation(unittest.TestCase):
    def setUp(self):
        self.read = lambda path: (art.ROOT / path).read_bytes()
        self.manifest = json.loads(self.read(art.MANIFEST))
        self.catalog = self.read("KeepersWarCommand/UI/ThemeCatalog.lua").decode()
        self.themes = self.read("KeepersWarCommand/UI/PublicThemes.lua").decode()
        self.asset = art.MEDIA + "TrogdorHeader.tga"

    def validate(self, manifest=None, read=None):
        return art.validate(read or self.read, manifest or self.manifest, self.catalog, self.themes)

    def test_shipped_pack(self):
        self.assertEqual(self.validate(), self.read(art.REGISTRY).decode().replace("\r\n", "\n"))

    def test_bad_paths(self):
        for path in ("../fallback.tga", "C:/invalid.tga", "TrogdorHeader.png"):
            pack = copy.deepcopy(self.manifest)
            pack["skins"]["trogdor"]["header"]["path"] = path
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "Invalid media-relative"):
                self.validate(pack)

    def test_wrong_dimensions(self):
        def wrong_size(path):
            return self.read(art.MEDIA + "TrogdorCrest.tga") if path == self.asset else self.read(path)
        with self.assertRaisesRegex(ValueError, "expected 512"):
            self.validate(read=wrong_size)

    def test_truncated_data(self):
        def truncate(path):
            return self.read(path)[:42] if path == self.asset else self.read(path)
        with self.assertRaisesRegex(ValueError, "unreadable"):
            self.validate(read=truncate)

    def test_missing_fallback_file(self):
        def missing(path):
            if path == art.MEDIA + "Emblem.tga":
                raise FileNotFoundError(path)
            return self.read(path)
        with self.assertRaisesRegex(FileNotFoundError, "Emblem"):
            self.validate(read=missing)

    def test_missing_fallback_declaration(self):
        self.manifest["skins"]["trogdor"]["crest"]["fallback"] = "surface"
        with self.assertRaisesRegex(ValueError, "expected fallback Emblem"):
            self.validate()

    def test_unregistered_runtime_art_blocks_packaging(self):
        with self.assertRaisesRegex(ValueError, "Unregistered"):
            art.check(self.read, paths=[art.MEDIA + "Art/classic/header.tga"])

    def test_stale_registry(self):
        def stale(path):
            return b"stale" if path == art.REGISTRY else self.read(path)
        with self.assertRaisesRegex(ValueError, "stale"):
            art.check(stale)


if __name__ == "__main__":
    unittest.main()
