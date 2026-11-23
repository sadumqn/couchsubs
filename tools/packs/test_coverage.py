# SPDX-License-Identifier: AGPL-3.0-only
"""Coverage reports cannot count blank readings or subtitle punctuation as a pack match."""
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("coverage.py")


class CoverageTests(unittest.TestCase):
    def check(self, pool):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            rows = root / "rows.jsonl"
            rows.write_text(json.dumps({"text": "Keep moving now."}) + "\n", encoding="utf-8")
            export = root / "pool.json"
            export.write_text(json.dumps({"lines": [{"text": s} for s in pool]}), encoding="utf-8")
            result = subprocess.run([sys.executable, "-B", str(SCRIPT), str(rows), str(export), "-"],
                                    capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            summary = re.search(r"pool lines (\d+) exact (\d+)", result.stdout)
            self.assertIsNotNone(summary, result.stdout)
            return int(summary.group(2))

    def test_empty_ocr_text_is_not_reported_as_exact(self):
        self.assertEqual(self.check(["", "Keep moving now."]), 1)

    def test_dialogue_with_colon_is_not_mistaken_for_speaker_label(self):
        self.assertEqual(self.check(["Tell me: Keep moving now.", "Keep moving now."]), 1)

    def test_speaker_label_still_matches(self):
        self.assertEqual(self.check(["Jason: Keep moving now.", "JASON: Keep moving now."]), 2)


if __name__ == "__main__":
    unittest.main()
