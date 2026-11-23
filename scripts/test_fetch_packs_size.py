# SPDX-License-Identifier: AGPL-3.0-only
"""Reject truncated or mismatched R2 downloads before replacing packaged game data."""
import gzip
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("fetch-packs.py")
SPEC = importlib.util.spec_from_file_location("fetch_packs_size", SCRIPT)
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


class ObjectSizeTests(unittest.TestCase):
    def test_wrong_r2_size_does_not_replace_last_good_pack(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            original = gzip.compress(json.dumps({"format": 2, "entries": {"a": "Last good"}}).encode())
            replacement = gzip.compress(json.dumps({"format": 2, "entries": {"b": "New working"}}).encode())
            target = folder / "example.json.gz"
            target.write_bytes(original)
            cfg = {k: "test" for k in mod.KEYS}
            with (patch.object(mod, "ROOT", folder),
                  patch.object(mod, "TARGETS", {"bundled/": folder}),
                  patch.object(mod, "config", return_value=cfg),
                  patch.object(mod, "list_keys", return_value=[("bundled/example.json.gz", len(replacement) + 5)]),
                  patch.object(mod, "request", return_value=replacement)):
                result = mod.main(["--require"])
            self.assertEqual(result, 1)
            self.assertEqual(target.read_bytes(), original)
            self.assertFalse((folder / ".example.json.gz.download").exists())


if __name__ == "__main__":
    unittest.main()
