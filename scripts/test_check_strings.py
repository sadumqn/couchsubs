# SPDX-License-Identifier: AGPL-3.0-only
"""Translations must exist and have a usable Turkish string-unit value."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("check-strings.py")


class CheckStringsTests(unittest.TestCase):
    def check(self, translation, extra=""):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            script = root / "scripts/check-strings.py"
            script.parent.mkdir(parents=True)
            shutil.copyfile(SCRIPT, script)
            sources = root / "mac/CouchSubs"
            (sources / "Resources").mkdir(parents=True)
            (sources / "UI.swift").write_text('import SwiftUI\nlet action = Text("Start game")\n' + extra, encoding="utf-8")
            catalog = {"strings": {"Start game": {"localizations": {"tr": translation}}}}
            (sources / "Resources/Localizable.xcstrings").write_text(json.dumps(catalog), encoding="utf-8")
            result = subprocess.run([sys.executable, "-B", str(script)], capture_output=True, text=True,
                                    encoding="utf-8", env={**os.environ, "PYTHONIOENCODING": "utf-8"})
            return result

    def test_missing_string_unit_is_reported(self):
        result = self.check({})
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Start game", result.stdout)

    def test_blank_turkish_translation_is_reported(self):
        result = self.check({"stringUnit": {"state": "translated", "value": "  "}})
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)

    def test_nonempty_turkish_translation_passes(self):
        result = self.check({"stringUnit": {"state": "translated", "value": "Oyunu başlat"}})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_verbatim_and_badge_ternaries_are_not_ui_keys(self):
        extra = ('let a = Text(verbatim: on ? "Alt Bölge" : "Tam Ekran")\n'
                 'let b = Tile(badge: xbox ? "XB" : "PS5", title: name)\n')
        result = self.check({"stringUnit": {"state": "translated", "value": "Oyunu başlat"}}, extra)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
