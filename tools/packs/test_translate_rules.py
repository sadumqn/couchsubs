"""Offline regression tests for the shared manual subtitle translation/review rules."""
import json
import runpy
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from translate_rules import GLOSSARY, RULES
import poolpack


class TranslationRulesTests(unittest.TestCase):
    def test_shared_prompts_have_game_glossaries_and_translation_rules(self):
        self.assertIn("ds", GLOSSARY)
        self.assertIn("sm2", GLOSSARY)
        self.assertIn("Rules:", RULES)
        self.assertIn("Output only the requested JSON.", RULES)
        self.assertIn(RULES, poolpack.system_prompt(None))

    def test_translate_preserves_shared_system_prompt_without_api_call(self):
        fake_llm = types.ModuleType("llm")
        fake_llm.call = lambda *args, **kwargs: self.fail("No paid API call expected")
        fake_llm.spent = lambda: 0
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            empty_rows = root / "rows.jsonl"
            empty_rows.write_text("", encoding="utf-8")
            output = root / "translated.json"
            argv = ["translate.py", "ds", str(empty_rows), str(output)]
            with patch.dict(sys.modules, {"llm": fake_llm}), patch.object(sys, "argv", argv):
                context = runpy.run_path(str(HERE / "translate.py"), run_name="__main__")
            self.assertIn(GLOSSARY["ds"], context["SYSTEM"])
            self.assertIn(RULES, context["SYSTEM"])
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")), [])

    def test_manual_review_can_load_rules_and_write_output_offline(self):
        fake_llm = types.ModuleType("llm")
        fake_llm.call = lambda *args, **kwargs: {"fixes": []}
        fake_llm.spent = lambda: 0
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "translated.json"
            output = root / "reviewed.json"
            lines = [{
                "text": "Get in the car, Lucia.",
                "sents": ["Get in the car, Lucia."],
                "tr": ["Arabaya bin, Lucia."],
                "speaker": "Jason",
                "scene": "intro",
            }]
            source.write_text(json.dumps(lines), encoding="utf-8")
            argv = ["review.py", "gta-6", str(source), str(output)]
            with patch.dict(sys.modules, {"llm": fake_llm}), patch.object(sys, "argv", argv):
                context = runpy.run_path(str(HERE / "review.py"), run_name="__main__")
            self.assertIn("Game: gta-6.", context["SYSTEM"])
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")), lines)
            self.assertEqual(json.loads(Path(str(output) + ".log.json").read_text(encoding="utf-8")),
                             {"applied": [], "vetoed": []})


if __name__ == "__main__":
    unittest.main()
