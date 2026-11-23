# SPDX-License-Identifier: AGPL-3.0-only
"""Release-notes links must survive Markdown-to-HTML conversion."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("surum-notlari-html.py")


class AppcastLinkTests(unittest.TestCase):
    def render(self, item):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "notes.md"
            file.write_text("**Bu sürümde yeni**\n- " + item + "\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, "-X", "utf8", str(SCRIPT), str(file)],
                capture_output=True, text=True, encoding="utf-8",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout

    def test_link_query_separator_is_escaped_only_once(self):
        html = self.render("[Detaylar](https://example.org/notes?a=1&b=2)")
        self.assertIn('<a href="https://example.org/notes?a=1&amp;b=2">Detaylar</a>', html)
        self.assertNotIn("&amp;amp;", html)

    def test_quotes_remain_escaped_and_link_label_is_safe(self):
        html = self.render('[<Detaylar>](https://example.org/?q="quoted"&lang=tr)')
        self.assertIn(
            '<a href="https://example.org/?q=&quot;quoted&quot;&amp;lang=tr">&lt;Detaylar&gt;</a>',
            html,
        )


if __name__ == "__main__":
    unittest.main()
