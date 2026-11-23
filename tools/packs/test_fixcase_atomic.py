# SPDX-License-Identifier: AGPL-3.0-only
"""Keep edited translation JSON intact when the in-place correction write fails."""
import gzip
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("fixcase.py")


class FixCaseAtomicTests(unittest.TestCase):
    def test_json_dump_failure_does_not_destroy_previous_reviewed_translations(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            packs = root / "packs"
            packs.mkdir()
            with gzip.open(packs / "sample.json.gz", "wt", encoding="utf-8") as file:
                json.dump({"entries": {"abc": "istanbul istanbul"}, "segments": {}}, file)
            document = root / "reviewed.json"
            original = json.dumps([{"tr": ["Istanbul güzel."]}], ensure_ascii=False).encode("utf-8")
            document.write_bytes(original)
            hooks = root / "hooks"
            hooks.mkdir()
            (hooks / "sitecustomize.py").write_text(
                'import json\n'
                'def broken_dump(value, stream, **kwargs):\n'
                '    stream.write("{broken JSON")\n'
                '    raise OSError("disk full during JSON write")\n'
                'json.dump = broken_dump\n',
                encoding="utf-8")
            result = subprocess.run([sys.executable, "-B", str(SCRIPT), str(packs), str(document)],
                                    env={**os.environ, "PYTHONPATH": str(hooks)},
                                    capture_output=True, text=True, encoding="utf-8")
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(document.read_bytes(), original)
            self.assertEqual(sorted(p.name for p in root.iterdir() if p.name.startswith(".reviewed")), [])


if __name__ == "__main__":
    unittest.main()
