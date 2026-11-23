#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Mac ve iPhone/iPad uygulamalarındaki ekran metinlerini bulur ve Localizable.xcstrings'te Türkçesi olup olmadığını kontrol eder.
# Kullanım: python3 scripts/check-strings.py [--list]
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "mac" / "CouchSubs"
# iPhone/iPad uygulaması aynı katalogu kullanır (couchsubs-ios/project.yml).
SOURCE_DIRS = [SOURCES, ROOT / "couchsubs-ios" / "CouchSubs"]
CATALOG = SOURCES / "Resources" / "Localizable.xcstrings"

# Yerelleştirilen çağrılar: Text("…"), Button("…"), Label("…"), String(localized: "…"), title:/message:/text: "…" vb.
PATTERNS = [
    r'(?:Text|TextField|Button|Label|Link|Toggle|Section|Picker|GroupBox|confirmationDialog)\(\s*"((?:[^"\\]|\\.)*)"',
    r'String\(localized:\s*"((?:[^"\\]|\\.)*)"',
    r'(?:title|message|text):\s*"((?:[^"\\]|\\.)*)"',
    r'\?\s*"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"',
]

def keys():
    found = set()
    for path in (p for d in SOURCE_DIRS for p in d.rglob("*.swift")):
        source = path.read_text()
        for pattern in PATTERNS:
            for match in re.findall(pattern, source):
                for key in (match if isinstance(match, tuple) else (match,)):
                    # SF Symbol adları (ör. "play.fill") ekran metni değildir.
                    if key and not re.fullmatch(r"[a-z0-9.]+", key) and "\\(" not in key:
                        key = key.replace('\\"', '"').replace("\\n", "\n")
                        if not not_ui(key):
                            found.add(key)
    return found

# Desenlere takılan ama ekran metni olmayan dizgiler: günlük satırları (Türkçe yazılır), protokol/XML değerleri, tarih
# biçimleri, renk kodları, adresler.
NOT_UI = {"Xbox (Beta)", "Bad Request", "Not Found", "TLS", "The TV closed the connection", "Remote Play penceresi", "Kurulum tamam.",
          "düz", "açık", "kapalı", "geçerli", "onaylandı", "seçilen pencere", "Seçilen pencere"}

def not_ui(key):
    return (key in NOT_UI
            or re.match(r"https?://", key) is not None
            or key.startswith("<")
            or re.fullmatch(r"#[0-9A-Fa-f]{6}", key) is not None
            or re.fullmatch(r"[yMdHmsZ']+", key) is not None
            or not re.search(r"[A-Za-zÇĞİÖŞÜçğıöşü]", key)
            # Türkçe günlük metinleri (ekran metinleri İngilizce anahtarla yazılır).
            or (re.search(r"[çğışöüÇĞİŞÖÜ]", key) is not None and not re.search(r"[A-Z]{2}", key) and key[:1].islower())
            # Günlük satırlarına eklenen parantezli Türkçe notlar (" (dinlenmede)").
            or key.startswith(" (")
            or key in {"TV'de CouchSubs görünmüyor; kuruluyor.", "tam paket SHA-512", "yalın paket SHA-256"})

def main():
    found = keys()
    if "--list" in sys.argv:
        print("\n".join(sorted(found)))
        return
    catalog = json.loads(CATALOG.read_text())["strings"]
    def has_turkish(key):
        entry = catalog.get(key, {})
        localization = entry.get("localizations", {}).get("tr", {})
        text = localization.get("stringUnit", {}).get("value")
        return isinstance(text, str) and bool(text.strip())

    # An empty or incomplete tr record is not a usable translation.
    missing = sorted(k for k in found if not has_turkish(k))
    if missing:
        print("Türkçesi eksik metinler:")
        print("\n".join("  " + k for k in missing))
        sys.exit(1)
    print(f"Tamam: {len(found)} metnin hepsinin Türkçesi var.")

main()
