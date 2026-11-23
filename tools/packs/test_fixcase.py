# SPDX-License-Identifier: AGPL-3.0-only
"""Regression tests for the subtitle capitalization correction CLI."""
import gzip
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("fixcase.py")


class FixCaseTests(unittest.TestCase):
    def test_ignores_readme_and_subdirectories_while_using_real_pack_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            packs = root / "packs"
            packs.mkdir()
            (packs / "README.md").write_text("Packs are downloaded during builds.", encoding="utf-8")
            (packs / "notes").mkdir()
            (packs / "notes" / "index.txt").write_text("Not an archive.", encoding="utf-8")
            with gzip.open(packs / "sample.json.gz", "wt", encoding="utf-8") as target:
                json.dump({"entries": {"key": "istanbul istanbul"}, "segments": {}}, target)
            translations = root / "translated.json"
            translations.write_text(json.dumps([{"tr": ["Istanbul güzel."]}], ensure_ascii=False), encoding="utf-8")

            result = subprocess.run([sys.executable, "-B", str(SCRIPT), str(packs), str(translations)],
                                    capture_output=True, text=True, encoding="utf-8",
                                    env={**os.environ, "PYTHONIOENCODING": "cp1254"})
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(json.loads(translations.read_text(encoding="utf-8"))[0]["tr"],
                             ["İstanbul güzel."])

    def test_readme_only_directory_does_not_crash(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            packs = root / "packs"
            packs.mkdir()
            (packs / "README.md").write_text("No downloaded packs.", encoding="utf-8")
            translations = root / "translated.json"
            translations.write_text('[{"tr":["Istanbul güzel."]}]', encoding="utf-8")

            result = subprocess.run([sys.executable, "-B", str(SCRIPT), str(packs), str(translations)],
                                    capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(json.loads(translations.read_text(encoding="utf-8"))[0]["tr"], ["Istanbul güzel."])


if __name__ == "__main__":
    unittest.main()
