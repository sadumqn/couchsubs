# SPDX-License-Identifier: AGPL-3.0-only
"""docs/surum-notlari.md'nin yalnız "Bu sürümde yeni" bölümünü Sparkle appcast'inin <description>'ı için HTML yapar.

Notlar geçmiş sürümlerin özetini de taşır ("beta.65'te gelenler" ...); güncelleme penceresi yalnız yeni sürümü
anlatsın diye bölüm, bir sonraki eski sürüm paragrafında biter. Windows kartı aynı kuralı GitHubReleaseNotes'ta uygular.
Bölüm yoksa hiçbir şey yazmaz (appcast'e <description> girmez).
"""
import html
import re
import sys

OLDER = re.compile(r"^\*\*(beta\.\d+\S*\s+gelenler\b|Daha önce\b|Önceki sürüm)")


def inline(text: str) -> str:
    out = html.escape(text, quote=False)
    out = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", out)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    # The text is HTML-escaped already; escaping the whole URL again would turn
    # '&amp;' into '&amp;amp;' and break links with multiple query parameters.
    def link(match):
        href = match.group(2).replace('"', '&quot;').replace("'", '&#x27;')
        return f'<a href="{href}">{match.group(1)}</a>'

    return re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", link, out)


def main(path: str) -> None:
    lines = open(path, encoding="utf-8").read().splitlines()
    start = next((i for i, line in enumerate(lines) if line.startswith("**Bu sürümde yeni")), None)
    if start is None:
        return
    parts, items = [], []

    def flush() -> None:
        if items:
            parts.append("<ul>" + "".join(f"<li>{item}</li>" for item in items) + "</ul>")
            items.clear()

    for index, line in enumerate(lines[start:]):
        if index > 0 and OLDER.match(line):
            break
        stripped = line.strip()
        if stripped.startswith(("- ", "* ")):
            items.append(inline(stripped[2:]))
        elif stripped:
            flush()
            parts.append(f"<p>{inline(stripped)}</p>")
    flush()
    # CDATA içinde kapanış dizisi bulunamaz.
    sys.stdout.write("".join(parts).replace("]]>", "]]&gt;"))


if __name__ == "__main__":
    main(sys.argv[1])
