# SPDX-License-Identifier: AGPL-3.0-only
"""UTF-8 BOM must not silently drop the first transcript line or reject JSON input."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent


class ExtractBomTests(unittest.TestCase):
    def run_extract(self, game, root):
        output = root / "output.jsonl"
        result = subprocess.run(
            [sys.executable, "-I", str(HERE / "extract.py"), game, str(root), str(output)],
            capture_output=True, text=True, encoding="utf-8",
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return [json.loads(line) for line in output.read_text(encoding="utf-8").splitlines()]

    def test_ds_keeps_first_dialogue_with_utf8_bom(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "lines.txt").write_text(
                "Sam: We need to move.\nFragile: Don't look back.\n", encoding="utf-8-sig"
            )
            rows = self.run_extract("ds", root)
            self.assertEqual([row["speaker"] for row in rows], ["Sam", "Fragile"])
            self.assertEqual(rows[0]["text"], "We need to move.")

    def test_sm2_accepts_bom_prefixed_script_json(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            content = {"parse": {"wikitext": {"*": "'''Peter''': We have to go."}}}
            (root / "script.json").write_text(json.dumps(content), encoding="utf-8-sig")
            (root / "menu.json").write_text(json.dumps({"parse": {"wikitext": {"*": ""}}}), encoding="utf-8")
            rows = self.run_extract("sm2", root)
            self.assertEqual(rows, [{"speaker": "Peter", "text": "We have to go.", "scene": ""}])


if __name__ == "__main__":
    unittest.main()
