"""Tests use temporary validation fixtures and never produce runtime art."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

import art_intake as intake
from art_contract import SLOTS


class IntakeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = Path(cls.temp.name).resolve()
        cls.pack = cls.root / "input"
        cls.pack.mkdir()
        (cls.pack / "source").mkdir()
        cls.base = {"schema": 1, "skin_id": "classic", "slots": {}}
        for slot, (master, size, rgba, _, _) in SLOTS.items():
            cls.base["slots"][slot] = {"source": "validation fixture", "license": "test", "focal": [.5, .5]}
            with Image.new("RGBA" if rgba else "RGB", master or size, "#9f7a52") as image:
                if rgba and slot != "dashboard":
                    image.paste((0, 0, 0, 0), (0, 0, image.width // 2, image.height))
                image.save(cls.pack / "source" / f"{slot}.png")

    def write_manifest(self, **change):
        path = self.pack / "manifest.json"
        path.write_bytes(intake.json_bytes(dict(self.base, **change)))
        return path

    def test_valid_pack_and_stage_are_non_destructive(self):
        path = self.write_manifest()
        before = {f: hashlib.sha256(f.read_bytes()).digest() for f in self.pack.rglob("*") if f.is_file()}
        files = intake.prepare(self.pack, intake.ROOT)
        output = self.root / "staged"
        intake.stage(files, output, self.pack, intake.ROOT)
        self.assertEqual(len(files), 11)
        self.assertIn(b"ProductionThemeArtwork", (output / intake.REGISTRY).read_bytes())
        self.assertIn("classic", json.loads((output / intake.MANIFEST).read_bytes())["production"])
        self.assertEqual(before, {f: hashlib.sha256(f.read_bytes()).digest()
                                  for f in self.pack.rglob("*") if f.is_file()})
        with self.assertRaisesRegex(ValueError, "new directory"):
            intake.stage(files, output, self.pack, intake.ROOT)
        self.assertEqual(path.read_bytes(), intake.json_bytes(self.base))

    def test_bad_focal_is_rejected(self):
        slots = dict(self.base["slots"])
        slots["header"] = dict(slots["header"], focal=[2, 0])
        self.write_manifest(slots=slots)
        with self.assertRaisesRegex(ValueError, "classic/header: Focal"):
            intake.prepare(self.pack, intake.ROOT)

    def test_wrong_master_dimensions(self):
        self.write_manifest()
        wrong = self.pack / "source/header.png"
        original = wrong.read_bytes()
        try:
            wrong.write_bytes((self.pack / "source/crest.png").read_bytes())
            with self.assertRaisesRegex(ValueError, "Expected master 2048"):
                intake.prepare(self.pack, intake.ROOT)
        finally:
            wrong.write_bytes(original)

    def test_unknown_id_rejected(self):
        self.write_manifest(skin_id="../unknown")
        with self.assertRaisesRegex(ValueError, "Unknown theme ID"):
            intake.prepare(self.pack, intake.ROOT)

    def test_duplicate_json_rejected(self):
        path = self.write_manifest()
        path.write_text('{"schema":1,"schema":1}')
        with self.assertRaisesRegex(ValueError, "Duplicate JSON key"):
            intake.prepare(self.pack, intake.ROOT)

    def test_stage_inside_source_or_repo_rejected(self):
        for path in (self.pack / "candidate", intake.ROOT / "candidate"):
            with self.assertRaisesRegex(ValueError, "outside"):
                intake.stage({}, path, self.pack, intake.ROOT)


if __name__ == "__main__":
    unittest.main()
