# SPDX-License-Identifier: AGPL-3.0-only
"""New short GTA fragments must retain the game's 8-character fuzzy threshold."""
import base64
import gzip
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import common as c


class ShortSegmentTests(unittest.TestCase):
    def run_case(self, title):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            src, english, out = (root / "before.json.gz", root / "english.json", root / "after.json.gz")
            en, tr = "Keep moving! Stay hidden!", "Hareket et! Gizli kal!"
            k = c.key(en)
            c.write_pack(src, "test-pack", title, "test", {k: tr}, {}, {k: en})
            english.write_text(json.dumps([en]), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, "-B", str(HERE / "sentences.py"), str(src), str(english), str(out)],
                capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            with gzip.open(out, "rt", encoding="utf-8") as input_file:
                pack = json.load(input_file)
            self.assertEqual(len(pack["segments"]), 2)
            return sum(byte.bit_count() for byte in base64.b64decode(pack["fuzzy"]["mask"]))

    def test_gta_short_segments_receive_fuzzy_signatures(self):
        self.assertEqual(self.run_case("Grand Theft Auto VI"), 3)

    def test_other_games_keep_existing_minimum_length(self):
        self.assertEqual(self.run_case("Test Game"), 1)


if __name__ == "__main__":
    unittest.main()
