"""Regression checks for reviewed sentence alignment when building packs."""
import gzip
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("build.py")

class BuildPackTests(unittest.TestCase):
    def run_build(self, translations):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            source = base / "reviewed.json"
            output = base / "built.json.gz"
            source.write_text(json.dumps([{
                "text": "We should leave now. Stay behind.",
                "sents": ["We should leave now.", "Stay behind."],
                "tr": translations,
            }], ensure_ascii=False), encoding="utf-8")
            proc = subprocess.run([sys.executable, str(SCRIPT), str(source), str(output),
                                   "test-pack", "Regression test", "Source"],
                                  capture_output=True, text=True, encoding="utf-8")
            return proc, (json.loads(gzip.decompress(output.read_bytes())) if output.exists() else None)

    def test_incomplete_or_extra_sentence_translation_is_rejected(self):
        for translations in ([], ["Now we leave."],
                             ["Now we leave.", "Wait here.", "Another line."]):
            with self.subTest(translations=translations):
                proc, pack = self.run_build(translations)
                self.assertNotEqual(proc.returncode, 0, "misaligned translations must stop package generation")
                self.assertIsNone(pack, "do not write a pack with wrong sentence alignment")

    def test_no_valid_translations_cannot_publish_an_unusable_pack(self):
        for translations in (["", ""], ["We should leave now.", "Stay behind."]):
            with self.subTest(translations=translations):
                proc, pack = self.run_build(translations)
                self.assertNotEqual(proc.returncode, 0, "a pack without full translations is rejected by clients")
                self.assertIsNone(pack, "do not emit a zero-entry package")

    def test_valid_aligned_subtitles_still_build(self):
        proc, pack = self.run_build(["Now we leave.", "Wait here."])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(pack["id"], "test-pack")
        self.assertEqual(len(pack["entries"]), 1)
        self.assertEqual(len(pack["segments"]), 2)

if __name__ == "__main__":
    unittest.main()
