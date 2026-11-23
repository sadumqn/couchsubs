# SPDX-License-Identifier: AGPL-3.0-only
"""Pool AI translations must not destroy previously generated output on disk errors."""
import json
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import poolpack as pp


class PoolPackAtomicOutputTests(unittest.TestCase):
    def test_failed_pool_translation_write_preserves_previous_output(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "reviewed-pool.json"
            old = b'{"last_good": "paid translations"}\n'
            target.write_bytes(old)
            fake = types.SimpleNamespace(
                call=lambda *args, **kw: {"items": [{"id": "0.0", "tr": "Devam et."}]},
                spent=lambda: 0.0)
            def partial_dump(value, stream, **kw):
                stream.write("partial data")
                raise OSError("disk full during JSON output")
            with patch.dict(sys.modules, {"llm": fake}), patch.object(json, "dump", side_effect=partial_dump):
                with self.assertRaises(OSError):
                    pp.translate([{"speaker": "", "text": "Keep moving now."}],
                                 "Offline system", "test", target)
            self.assertEqual(target.read_bytes(), old)
            self.assertEqual(list(Path(directory).glob(".reviewed-pool.json.*.tmp")), [])

    def test_successful_pool_translation_still_writes_expected_json(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "translated.json"
            fake = types.SimpleNamespace(
                call=lambda *args, **kw: {"items": [{"id": "0.0", "tr": "Devam et."}]},
                spent=lambda: 0.0)
            with patch.dict(sys.modules, {"llm": fake}):
                pp.translate([{"speaker": "", "text": "Keep moving now."}],
                             "Offline system", "test", target)
            result = json.loads(target.read_text(encoding="utf-8"))
            self.assertEqual(result[0]["tr"], ["Devam et."])


if __name__ == "__main__":
    unittest.main()
