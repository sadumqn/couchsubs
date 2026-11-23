# poolpack.py denemeleri: ağ ve API yok. Çalıştırma: python3 -m unittest tools/packs/test_poolpack.py
import json, re, sys, tempfile, types, unittest
from unittest.mock import patch
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import poolpack as pp


class PoolPackTests(unittest.TestCase):
    def test_translation_chunks_reject_hallucinated_ids_from_other_chunks(self):
        rows = [{"speaker": "", "scene": "pool", "text": f"Number {i} is speaking now."}
                for i in range(pp.CHUNK + 1)]
        def fake_call(system, prompt, schema, tag, max_tokens):
            ids = [line.split(chr(9), 1)[0].strip() for line in prompt.splitlines()
                   if line.startswith("  ") and chr(9) in line]
            items = [{"id": iid, "tr": "Correct " + iid} for iid in ids]
            if f"{pp.CHUNK}.0" in ids:
                items.append({"id": "0.0", "tr": "WRONG OTHER CHUNK"})
            return {"items": items}
        fake_llm = types.SimpleNamespace(call=fake_call, spent=lambda: 0.0)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "translated.json"
            with patch.dict(sys.modules, {"llm": fake_llm}):
                pp.translate(rows, "Synthetic offline system", "test", output)
            actual = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(len(actual), pp.CHUNK + 1)
        self.assertEqual(actual[0]["tr"], ["Correct 0.0"],
                         "other chunks cannot replace already translated subtitles")
        self.assertEqual(actual[pp.CHUNK]["tr"], [f"Correct {pp.CHUNK}.0"])

    def test_query_is_read_only_and_escaped(self):
        sql = pp.query_sql(title="ppsa12345", game="Grand Theft_Auto's 100%")
        self.assertTrue(sql.startswith("SELECT"))
        self.assertIn("title_id = 'PPSA12345'", sql)
        self.assertIn("'%Grand Theft^_Auto''s 100^%%' ESCAPE '^'", sql)
        self.assertIn("exported = 0", sql)
        command = pp.wrangler(sql)
        self.assertIn('--remote --json --command "SELECT', command)
        self.assertIn("'", pp.wrangler('SELECT "x"').split("--command ")[1][0])
        with self.assertRaises(SystemExit):
            pp.query_sql(title="x'; DELETE FROM lines; --")
        with self.assertRaises(SystemExit):
            pp.query_sql()
        with self.assertRaises(AssertionError):
            pp.wrangler("DELETE FROM lines")

    def test_generated_read_queries_reject_unbounded_or_invalid_limits(self):
        for n in (0, -1, -100):
            with self.subTest(value=n):
                with self.assertRaises(SystemExit):
                    pp.titles_sql(limit=n)
                with self.assertRaises(SystemExit):
                    pp.query_sql(title="PPSA12345", limit=n)
                with self.assertRaises(SystemExit):
                    pp.query_sql(title="PPSA12345", min_installs=n)
        self.assertIn("LIMIT 50", pp.titles_sql(50))
        self.assertIn("LIMIT 5000", pp.query_sql(title="PPSA12345"))

    def test_clean_merges_sorts_and_drops_noise(self):
        rows = [
            {"text": "LUCIA: Get in the car, Jason.", "installs": 3},
            {"text": "Get in the car, Jason!", "installs": 4},
            {"text": "Keep your head down.", "installs": 9},
            {"text": "Oturum Açtı şimdi", "installs": 50},
            {"text": "We need ou$3e now", "installs": 50},
            {"text": "Hold", "installs": 50},
            {"text": "Already in a pack.", "installs": 50},
        ]
        known = {pp.c.key("Already in a pack.")}
        out, dropped = pp.clean(rows, known)
        self.assertEqual([r["text"] for r in out], ["Keep your head down.", "Get in the car, Jason."])
        self.assertEqual(out[1]["installs"], 7)
        self.assertEqual(out[1]["speaker"], "LUCIA")
        self.assertEqual(out[1]["raw"], "LUCIA: Get in the car, Jason.")
        self.assertEqual(dropped, {"bozuk": 1, "türkçe": 1, "kısa": 1, "pakette": 1})

    def test_clean_discards_turkish_lines_with_shared_accents(self):
        # ü/ö/ç alone can appear in foreign names, but multiple such letters
        # are already considered Turkish by the server's pool filter.
        rows = [
            {"text": "Çözümleri kontrol et.", "installs": 5},
            {"text": "Bölümü tekrar dene.", "installs": 4},
            {"text": "Herr Müller will see you now.", "installs": 2},
            {"text": "Please get in the car.", "installs": 3},
        ]
        cleaned, dropped = pp.clean(rows)
        self.assertEqual([r["text"] for r in cleaned],
                         ["Please get in the car.", "Herr Müller will see you now."])
        self.assertEqual(dropped["türkçe"], 2)

    def test_reads_wrangler_and_export_formats(self):
        with tempfile.TemporaryDirectory() as d:
            a, b = Path(d) / "a.json", Path(d) / "b.json"
            a.write_text(json.dumps([{"results": [{"text": "One two.", "installs": 2}], "success": True}]))
            b.write_text(json.dumps({"lines": [{"text": "One two.", "installs": 2}]}))
            self.assertEqual(pp.load_export(a), pp.load_export(b))

    def test_rejects_failed_d1_exports_and_invalid_line_collections(self):
        bad = [
            [{"success": False, "error": "remote D1 query failed", "results": []}],
            [{"success": False, "results": [{"text": "We need to leave."}]}],
            {"lines": None},
            {"lines": "not a line array"},
            [{"success": True, "results": None}],
        ]
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "export.json"
            for result in bad:
                with self.subTest(payload=result):
                    path.write_text(json.dumps(result), encoding="utf-8")
                    with self.assertRaises(SystemExit):
                        pp.load_export(path)

    def test_dry_run_never_translates(self):
        with tempfile.TemporaryDirectory() as d:
            export = Path(d) / "pool.json"
            export.write_text(json.dumps({"lines": [{"text": "Keep your head down, Jason.", "installs": 5}]}))
            pp.main(["plan", str(export), "--id", "gta-6", "--out-dir", d])
            self.assertTrue((Path(d) / "gta-6.rows.jsonl").is_file())
            self.assertFalse((Path(d) / "gta-6.tr.json").exists())
            self.assertNotIn("llm", sys.modules)
            with self.assertRaises(SystemExit):
                pp.main(["plan", str(export), "--id", "gta-6", "--out-dir", d, "--translate"])
            self.assertNotIn("llm", sys.modules)

    def test_estimate_and_prompt(self):
        e = pp.estimate([{"text": "Keep your head down. Get in the car."}] * 80, 3000)
        self.assertEqual(e["chunks"], 2)
        self.assertEqual(e["sentences"], 160)
        self.assertLess(e["usd"][0], e["usd"][1])
        prompt = pp.system_prompt(str(Path(pp.HERE) / "glossary/gta6.json"))
        self.assertIn("Vice City", prompt)
        self.assertIn("dude = ahbap", prompt)
        self.assertIn("Output only the requested JSON.", prompt)


if __name__ == "__main__":
    unittest.main()
