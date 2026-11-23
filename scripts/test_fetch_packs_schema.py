# SPDX-License-Identifier: AGPL-3.0-only
"""Reject archive entries clients cannot decode before replacing bundled game packs."""
import gzip
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("fetch-packs.py")
SPEC = importlib.util.spec_from_file_location("fetch_packs_schema", SCRIPT)
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


class PackageSchemaTests(unittest.TestCase):
    def test_entry_values_must_be_nonempty_strings(self):
        for invalid in ({"a": 42}, {"a": None}, {"a": "   "}):
            with self.subTest(invalid=invalid):
                with tempfile.TemporaryDirectory() as tmp:
                    folder = Path(tmp)
                    target = folder / "example.json.gz"
                    old = gzip.compress(json.dumps({"format": 2, "entries": {"a": "Old working"}}).encode())
                    target.write_bytes(old)
                    new = gzip.compress(json.dumps({"format": 2, "id": "example", "entries": invalid}).encode())
                    cfg = {k: "test" for k in mod.KEYS}
                    with (patch.object(mod, "ROOT", folder),
                          patch.object(mod, "TARGETS", {"bundled/": folder}),
                          patch.object(mod, "config", return_value=cfg),
                          patch.object(mod, "list_keys", return_value=[("bundled/example.json.gz", len(new))]),
                          patch.object(mod, "request", return_value=new)):
                        result = mod.main(["--require"])
                    self.assertEqual(result, 1)
                    self.assertEqual(target.read_bytes(), old)
                    self.assertFalse((folder / ".example.json.gz.download").exists())


if __name__ == "__main__":
    unittest.main()
