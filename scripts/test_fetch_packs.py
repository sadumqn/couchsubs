# SPDX-License-Identifier: AGPL-3.0-only
"""Validate private R2 package downloads without network access or credentials."""
import gzip
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("fetch-packs.py")
SPEC = importlib.util.spec_from_file_location("fetch_packs", SCRIPT)
fetch_packs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fetch_packs)


def archive(value):
    return gzip.compress(json.dumps(value).encode("utf-8"))


class FetchPacksTests(unittest.TestCase):
    def download(self, data):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / "packs"
            target.mkdir()
            existing = target / "example.json.gz"
            original = archive({"format": 2, "entries": {"a": "Original"}, "segments": {}})
            existing.write_bytes(original)
            cfg = {key: "test" for key in fetch_packs.KEYS}

            with (patch.object(fetch_packs, "TARGETS", {"bundled/": target}),
                  patch.object(fetch_packs, "ROOT", root),
                  patch.object(fetch_packs, "config", return_value=cfg),
                  patch.object(fetch_packs, "list_keys", return_value=[("bundled/example.json.gz", len(data))]),
                  patch.object(fetch_packs, "request", return_value=data)):
                result = fetch_packs.main(["--require"])
            return result, existing.read_bytes(), original, list(target.iterdir())

    def test_require_contrib_must_download_a_bundled_game_pack(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            targets = {"bundled/": root / "bundled", "contrib/": root / "contrib"}
            cfg = {key: "test" for key in fetch_packs.KEYS}
            def list_for(_cfg, prefix):
                return [("contrib/example.json", 3)] if prefix == "contrib/" else []
            with (patch.object(fetch_packs, "TARGETS", targets),
                  patch.object(fetch_packs, "ROOT", root),
                  patch.object(fetch_packs, "config", return_value=cfg),
                  patch.object(fetch_packs, "list_keys", side_effect=list_for),
                  patch.object(fetch_packs, "request", return_value=b"abc")):
                result = fetch_packs.main(["--require", "--contrib"])
            self.assertEqual(result, 1, "contribution downloads cannot satisfy a required game-pack release")
            self.assertEqual((targets["contrib/"] / "example.json").read_bytes(), b"abc")

    def test_require_does_not_count_unusable_bundled_metadata_as_a_game_pack(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / "bundled"
            cfg = {key: "test" for key in fetch_packs.KEYS}
            with (patch.object(fetch_packs, "TARGETS", {"bundled/": target}),
                  patch.object(fetch_packs, "ROOT", root),
                  patch.object(fetch_packs, "config", return_value=cfg),
                  patch.object(fetch_packs, "list_keys", return_value=[("bundled/notes.txt", 3)]),
                  patch.object(fetch_packs, "request", return_value=b"abc")):
                result = fetch_packs.main(["--require"])
            self.assertEqual(result, 1, "only verified game archives satisfy --require")

    def test_corrupt_gzip_does_not_replace_working_pack(self):
        result, saved, original, files = self.download(b"broken archive")
        self.assertEqual(result, 1)
        self.assertEqual(saved, original)
        self.assertEqual(len(files), 1, "no partial download file should remain")

    def test_invalid_json_inside_gzip_does_not_replace_working_pack(self):
        result, saved, original, files = self.download(gzip.compress(b"{broken json"))
        self.assertEqual(result, 1)
        self.assertEqual(saved, original)
        self.assertEqual(len(files), 1)

    def test_invalid_pack_schema_does_not_replace_working_pack(self):
        result, saved, original, _ = self.download(archive({"not_a_pack": True}))
        self.assertEqual(result, 1)
        self.assertEqual(saved, original)

    def test_wrong_embedded_id_cannot_replace_another_games_pack(self):
        value = {"format": 2, "id": "different-game", "entries": {"b": "Wrong game"}, "segments": {}}
        result, saved, original, files = self.download(archive(value))
        self.assertEqual(result, 1)
        self.assertEqual(saved, original)
        self.assertEqual(len(files), 1)

    def test_zero_entry_pack_cannot_replace_a_working_pack(self):
        value = {"format": 2, "id": "example", "entries": {}, "segments": {"b": "Only fragment"}}
        result, saved, original, files = self.download(archive(value))
        self.assertEqual(result, 1)
        self.assertEqual(saved, original)
        self.assertEqual(len(files), 1)

    def test_valid_pack_replaces_existing_archive(self):
        valid = archive({"format": 2, "entries": {"b": "Replacement"}, "segments": {}})
        result, saved, _, files = self.download(valid)
        self.assertEqual(result, 0)
        self.assertEqual(saved, valid)
        self.assertEqual(len(files), 1)


if __name__ == "__main__":
    unittest.main()
