"""Protect the last valid game package if the gzip writer fails mid-stream."""
import gzip
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
import common


class AtomicPackWriterTests(unittest.TestCase):
    def test_failed_gzip_write_preserves_existing_archive_and_cleans_staging(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "existing.json.gz"
            original = gzip.compress(b'{"original":true}')
            path.write_bytes(original)
            with patch.object(common.gzip.GzipFile, "write", side_effect=OSError("disk full")):
                with self.assertRaises(OSError):
                    common.write_pack(path, "existing", "Existing", "test",
                                      {"0000000000000001": "A translation"}, {}, {})
            self.assertEqual(path.read_bytes(), original, "failed update must never overwrite installed archive")
            self.assertEqual([p.name for p in Path(folder).iterdir()], ["existing.json.gz"])

    def test_failed_final_replace_also_preserves_last_good_archive(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "existing.json.gz"
            original = gzip.compress(b'{"original":true}')
            path.write_bytes(original)
            with patch.object(common.os, "replace", side_effect=OSError("locked file")):
                with self.assertRaises(OSError):
                    common.write_pack(path, "existing", "Existing", "test",
                                      {"0000000000000001": "Translation"}, {}, {})
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual([p.name for p in Path(folder).iterdir()], ["existing.json.gz"])

    def test_successful_write_still_creates_loadable_gzip(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "new.json.gz"
            common.write_pack(path, "new", "New Game", "test",
                              {"0000000000000001": "A translation"}, {}, {})
            obj = json.loads(gzip.decompress(path.read_bytes()))
            self.assertEqual(obj["id"], "new")
            self.assertEqual(obj["entries"]["0000000000000001"], "A translation")


if __name__ == "__main__":
    unittest.main()
