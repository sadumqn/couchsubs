# SPDX-License-Identifier: AGPL-3.0-only
"""Manual paid-AI tools must preserve earlier reviewed output if serialization fails."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent


class ManualOutputAtomicTests(unittest.TestCase):
    def invoke(self, tool, fail=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in (tool + ".py", "common.py", "atomic_json.py"):
                shutil.copyfile(HERE / name, root / name)
            (root / "llm.py").write_text(
                "def call(*args, **kwargs): return {'fixes': [], 'items': []}\n"
                "def spent(): return 0.0\n", encoding="utf-8")
            (root / "translate_rules.py").write_text(
                "GLOSSARY = {'ds': ''}\nRULES = ''\n", encoding="utf-8")
            source = root / "source.json"
            if tool == "translate":
                source = root / "source.jsonl"
                source.write_text(json.dumps({
                    "speaker": "", "scene": "", "text": "Keep moving now.",
                }) + "\n", encoding="utf-8")
            else:
                source.write_text(json.dumps([{
                    "speaker": "", "text": "Keep moving now.",
                    "sents": ["Keep moving now."], "tr": ["Devam et."],
                }]), encoding="utf-8")
            output = root / "last-good.json"
            original = b'{"previous": "saved translation"}\n'
            output.write_bytes(original)
            env = {**os.environ, "PYTHONIOENCODING": "utf-8"}
            if fail:
                hooks = root / "hooks"
                hooks.mkdir()
                (hooks / "sitecustomize.py").write_text(
                    "import json\n"
                    "def fail_json_dump(value, target, **kwargs):\n"
                    "    target.write('partial data')\n"
                    "    raise OSError('simulated disk write failure')\n"
                    "json.dump = fail_json_dump\n", encoding="utf-8")
                env["PYTHONPATH"] = str(hooks)
            proc = subprocess.run([sys.executable, "-B", str(root / (tool + ".py")),
                                   "ds", str(source), str(output)],
                                  cwd=root, env=env, capture_output=True, text=True,
                                  encoding="utf-8", errors="replace")
            return proc, original, output.read_bytes(), list(root.glob(".last-good*.tmp"))

    def test_failed_translate_dump_keeps_last_good_paid_translation(self):
        proc, old, new, staged = self.invoke("translate", fail=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual(new, old, "a failed output must not corrupt earlier AI translations")
        self.assertEqual(staged, [], "incomplete staging data must be removed")

    def test_failed_review_dump_keeps_last_good_human_review_output(self):
        proc, old, new, staged = self.invoke("review", fail=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual(new, old, "a failed review must not corrupt previous reviewed source")
        self.assertEqual(staged, [])

    def test_successful_translation_still_writes_structured_json(self):
        proc, old, new, staged = self.invoke("translate")
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertEqual(len(json.loads(new)), 1)
        self.assertEqual(staged, [])

    def test_successful_review_still_writes_structured_json(self):
        proc, old, new, staged = self.invoke("review")
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertEqual(json.loads(new)[0]["tr"], ["Devam et."])
        self.assertEqual(staged, [])


if __name__ == "__main__":
    unittest.main()
