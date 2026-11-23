# SPDX-License-Identifier: AGPL-3.0-only
"""Only completed pool translations may be marked exported for the next D1 update."""
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import poolpack as pp


class ExportedPoolKeysTests(unittest.TestCase):
    def test_exported_keys_only_include_fully_translated_pool_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            export = root / "pool.json"
            export.write_text(json.dumps({"lines": [
                {"key": "fully-done", "text": "Keep your head down, Jason.", "installs": 30},
                {"key": "partial-line", "text": "Come here. Leave now.", "installs": 20},
                {"key": "no-output", "text": "Stop the engine now.", "installs": 10},
            ]}), encoding="utf-8")

            def translate_stub(rows, system, tag, out):
                translated = []
                for row in rows:
                    parts = pp.c.sentences(row["text"])
                    if row["pool_keys"] == ["fully-done"]:
                        tr = ["Basini eg, Jason."]
                    elif row["pool_keys"] == ["partial-line"]:
                        tr = ["Buraya gel.", None]
                    else:
                        tr = [None] * len(parts)
                    translated.append(dict(row, sents=parts, tr=tr))
                Path(out).write_text(json.dumps(translated, ensure_ascii=False), encoding="utf-8")

            with patch.object(pp, "known_keys", return_value=set()), patch.object(pp, "translate", side_effect=translate_stub):
                pp.main(["plan", str(export), "--id", "sample", "--out-dir", directory,
                         "--translate", "--limit", "3"])
            marked = json.loads((root / "sample.pool-keys.json").read_text(encoding="utf-8"))["keys"]
            self.assertEqual(marked, ["fully-done"],
                             "partial and missing AI translations must stay available for future export")


if __name__ == "__main__":
    unittest.main()
