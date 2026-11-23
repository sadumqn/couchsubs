# SPDX-License-Identifier: AGPL-3.0-only
"""A failed localization catalog update must preserve the previous valid xcstrings."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("metinler-katalog.py")


class CatalogAtomicTests(unittest.TestCase):
    def run_update(self, fail_replace=False, empty_catalog=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            shutil.copyfile(SCRIPT, root / "scripts/metinler-katalog.py")
            doc = root / "design/yeni-arayuz/METINLER.md"
            doc.parent.mkdir(parents=True)
            doc.write_text("| EN | TR |\n| --- | --- |\n| Start game | Oyunu baslat|\n", encoding="utf-8")
            catalog = root / "mac/CouchSubs/Resources/Localizable.xcstrings"
            catalog.parent.mkdir(parents=True)
            original = ('{\n  "strings": {\n  },\n  "version": "1.0"\n}\n'
                        if empty_catalog else
                        '{\n  "strings": {\n    "Existing": {"localizations": {"tr": {"stringUnit": {"value": "Mevcut"}}}}\n  },\n  "version": "1.0"\n}\n')
            catalog.write_text(original, encoding="utf-8")
            env = {**os.environ, "PYTHONIOENCODING": "utf-8"}
            if fail_replace:
                hooks = root / "hooks"
                hooks.mkdir()
                (hooks / "sitecustomize.py").write_text(
                    'import os\n'
                    '_orig = os.replace\n'
                    'def fail(src, dst):\n'
                    '    if str(dst).endswith("Localizable.xcstrings"):\n'
                    '        raise OSError("simulated atomic replace failure")\n'
                    '    return _orig(src, dst)\n'
                    'os.replace = fail\n', encoding="utf-8")
                env["PYTHONPATH"] = str(hooks)
            result = subprocess.run([sys.executable, "-B", str(root / "scripts/metinler-katalog.py")],
                                    capture_output=True, text=True, encoding="utf-8", env=env)
            staged = list(catalog.parent.glob("*.tmp"))
            return result, original, catalog.read_text(encoding="utf-8"), staged

    def test_failed_catalog_replacement_preserves_previous_complete_catalog(self):
        result, original, current, staged = self.run_update(fail_replace=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(current, original, "a failed update must not alter the previous catalog")
        self.assertEqual(staged, [], "temporary catalog file must be cleaned on failure")

    def test_first_localization_can_be_inserted_into_an_empty_catalog(self):
        result, original, current, staged = self.run_update(empty_catalog=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(current)["strings"]["Start game"]["localizations"]["tr"]["stringUnit"]["value"],
                         "Oyunu baslat")
        self.assertEqual(staged, [])

    def test_successful_update_still_adds_missing_localization(self):
        result, original, current, staged = self.run_update()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(current)["strings"]["Start game"]["localizations"]["tr"]["stringUnit"]["value"],
                         "Oyunu baslat")
        self.assertEqual(staged, [])


if __name__ == "__main__":
    unittest.main()
