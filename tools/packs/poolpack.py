# Havuzdan hızlı paket: yeni çıkan bir oyunun (ör. GTA 6) oyuncuların ekranda okuduğu satırlarını oyuna göre alıp
# çeviriye hazırlar. Varsayılan KURU ÇALIŞTIRMADIR: hiçbir ağ isteği ve API harcaması yapılmaz.
#
#   poolpack.py titles                       Havuzda görülen oyun kimliklerini listeleyecek okuma komutunu yazar.
#   poolpack.py query --title PPSA12345      Bir oyunun satırlarını alacak okuma komutunu yazar (çalıştırmaz).
#   poolpack.py query --game "Grand Theft Auto VI"
#   poolpack.py plan pool-gta6.json --id gta-6 [--glossary glossary/gta6.json]
#                                            Temizler, sıklığa göre sıralar, rows.jsonl yazar, maliyeti tahmin eder.
#   poolpack.py plan pool-gta6.json --id gta-6 --translate --limit 500
#                                            YALNIZ bu bayraklarla: en sık 500 satır Claude ile çevrilir (harcama yapar).
#
# Sonra: review.py / fixcase.py (denetim) → build.py (paket) → coverage.py. Bkz. README.md "GTA 6 günü".
import argparse, json, re, shlex, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import common as c
from atomic_json import dump_atomic

ROOT = HERE.parents[1]
PACKS = ROOT / "core/Sources/CouchSubsCore/Resources/packs"
TITLE_ID = re.compile(r"^[A-Z]{4}\d{5}(_\d{2})?$")
LABEL = re.compile(r"^[-•\s]*([A-Z][A-Za-z .'’-]{1,28}?)\s*[•:]\s+(?=\S)")
TURKISH = re.compile(r"[ğĞşŞıİ]")
TURKISH_SHARED = re.compile(r"[üÜöÖçÇ]")
OCR_JUNK = re.compile(r"[$#@|\\{}<>~^_=]|\w[%&*]\w")
CHUNK = 40  # translate.py ile aynı parça boyu


def wrangler(sql):
    """Okuma sorgusunu çalıştıracak komut (yalnız SELECT; havuzda yazma yapmaz)."""
    assert sql.lstrip().upper().startswith("SELECT"), sql
    quoted = f'"{sql}"' if not re.search(r'["$`\\!]', sql) else shlex.quote(sql)
    return f"cd server/pool && npx wrangler d1 execute couchsubs-pool --remote --json --command {quoted}"


def sql_text(value):
    return "'" + value.replace("'", "''") + "'"


def titles_sql(limit=50):
    if limit <= 0:
        raise SystemExit("limit pozitif olmalı (SQLite LIMIT -1 sınırsız okur)")
    return ("SELECT title_id, game, COUNT(*) AS lines, SUM(installs) AS sightings FROM lines "
            f"WHERE title_id IS NOT NULL GROUP BY title_id, game ORDER BY lines DESC LIMIT {int(limit)}")


def query_sql(title=None, game=None, min_installs=2, limit=5000, include_exported=False):
    if limit <= 0 or min_installs <= 0:
        raise SystemExit("limit ve en az kurulum sayısı pozitif olmalı")
    where = [f"installs >= {int(min_installs)}"]
    if not include_exported:
        where.append("exported = 0")
    match = []
    if title:
        title = title.strip().upper()
        if not TITLE_ID.match(title):
            raise SystemExit(f"geçersiz oyun kimliği: {title} (beklenen: PPSA01234 ya da CUSA00419_00)")
        match.append(f"title_id = {sql_text(title)}")
    if game:
        game = re.sub(r"\s+", " ", game).strip()
        if not game or len(game) > 120:
            raise SystemExit("oyun adı boş ya da çok uzun")
        # Kaçış karakteri '^': kabukta tırnak içinde anlamı yok, komut okunur kalır.
        like = game.replace("^", "^^").replace("%", "^%").replace("_", "^_")
        match.append(f"game LIKE {sql_text('%' + like + '%')} ESCAPE '^'")
    if not match:
        raise SystemExit("--title ya da --game gerekli")
    where.append("(" + " OR ".join(match) + ")")
    return ("SELECT key, text, installs, first_seen, title_id, game FROM lines WHERE " + " AND ".join(where)
            + f" ORDER BY installs DESC LIMIT {int(limit)}")


def load_export(path):
    """wrangler --json çıktısı ([{results: [...]}]) ya da /v1/export yanıtı ({lines: [...]})."""
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if isinstance(data, dict) and "lines" in data:
        rows = data["lines"]
        if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
            raise SystemExit("invalid pool export lines array")
        return rows
    if isinstance(data, list):
        rows = []
        for part in data:
            if not isinstance(part, dict) or part.get("success") is False:
                raise SystemExit("failed D1 query or malformed export response")
            chunk = part.get("results")
            if not isinstance(chunk, list) or not all(isinstance(row, dict) for row in chunk):
                raise SystemExit("invalid D1 export results array")
            rows += chunk
        return rows
    raise SystemExit("unrecognized export file format")


def known_keys(directory=PACKS):
    """Uygulamayla gelen paketlerin anahtarları: bunlar zaten çevrili, yeniden çevrilmez."""
    import gzip, os
    keys = set()
    if directory.is_dir():
        for name in os.listdir(directory):
            if name.endswith(".json.gz"):
                p = json.load(gzip.open(directory / name))
                keys.update(k.lower() for k in p.get("entries", {}))
                keys.update(k.lower() for k in p.get("segments", {}))
    return keys


def clean(rows, known=frozenset()):
    """Satırları temizler ve aynı anahtardakileri birleştirir; (satırlar, atılanların sayısı) döner."""
    merged, dropped = {}, {"bozuk": 0, "türkçe": 0, "kısa": 0, "pakette": 0}
    for r in rows:
        raw = re.sub(r"\s+", " ", str(r.get("text", ""))).strip()
        speaker, body = "", raw
        m = LABEL.match(raw)
        if m:
            speaker, body = m.group(1).strip(), raw[m.end():].strip()
        letters = sum(ch.isalpha() for ch in body)
        # Mirror server/pool/src/filter.js: one shared accented letter may
        # occur in a foreign name, but multiple such letters signal Turkish.
        if TURKISH.search(body) or len(TURKISH_SHARED.findall(body)) >= 2:
            dropped["türkçe"] += 1
            continue
        if OCR_JUNK.search(body) or letters * 2 < len(body.replace(" ", "")):
            dropped["bozuk"] += 1
            continue
        if len([w for w in body.split() if any(ch.isalpha() for ch in w)]) < 2 or len(body) > 300:
            dropped["kısa"] += 1
            continue
        k = c.key(body)
        if not k:
            dropped["kısa"] += 1
            continue
        if k in known:
            dropped["pakette"] += 1
            continue
        installs = int(r.get("installs") or 1)
        pool_key = r.get("key")
        if k in merged:
            merged[k]["installs"] += installs
            if pool_key:
                merged[k]["pool_keys"].append(pool_key)
            continue
        merged[k] = {"speaker": speaker, "text": body, "scene": "pool", "raw": raw if raw != body else None,
                     "installs": installs, "key": k, "pool_keys": [pool_key] if pool_key else []}
    out = sorted(merged.values(), key=lambda x: (-x["installs"], x["text"]))
    return out, dropped


def llm_prices():
    """llm.py'deki model ve fiyat (anahtar okunmasın diye içe aktarılmaz, metinden okunur)."""
    text = (HERE / "llm.py").read_text(encoding="utf-8")
    model = re.search(r'MODEL = "([^"]+)"', text).group(1)
    p_in, p_out = re.search(r"PRICE_IN, PRICE_OUT = ([\d.]+) / 1e6, ([\d.]+) / 1e6", text).groups()
    return model, float(p_in) / 1e6, float(p_out) / 1e6


def estimate(rows, system_chars):
    """Kaba maliyet tahmini (USD): İngilizce ~4 karakter/jeton; çıktı Türkçe ve JSON, düşünme payıyla birlikte."""
    model, p_in, p_out = llm_prices()
    chars = sum(len(r["text"]) for r in rows)
    sentences = sum(max(1, len(c.sentences(r["text"]))) for r in rows)
    chunks = (len(rows) + CHUNK - 1) // CHUNK
    tokens_in = chunks * (system_chars / 4 + 4 * 30) + chars / 4 + sentences * 6
    low_out = chars / 4 * 1.5 + sentences * 12
    high_out = low_out * 2.5  # orta düzey düşünme jetonları
    return {"model": model, "lines": len(rows), "sentences": sentences, "chunks": chunks,
            "tokens_in": int(tokens_in), "tokens_out": (int(low_out), int(high_out)),
            "usd": (round(tokens_in * p_in + low_out * p_out, 4), round(tokens_in * p_in + high_out * p_out, 4))}


def system_prompt(glossary):
    from translate_rules import RULES
    head = "You translate video game subtitles from English into Turkish for CouchSubs, an app that shows Turkish\n" \
           "subtitles on the TV while people play."
    if glossary:
        import gta6glossary
        head += "\n" + gta6glossary.prompt_block(glossary)
    head += ("\nThese lines were read from the TV screen with OCR by players; if a line is clearly damaged, translate the "
             "most likely original.")
    return head + "\n\n" + RULES


def translate(rows, system, tag, out):
    """translate.py ile aynı biçimde çevirir ve yazar (review.py / build.py okur). Harcama yapar."""
    import llm  # anahtar burada okunur; kuru çalıştırmada hiç yüklenmez
    from concurrent.futures import ThreadPoolExecutor
    schema = {"type": "object", "properties": {"items": {"type": "array", "items": {"type": "object", "properties": {
        "id": {"type": "string"}, "tr": {"type": "string"}}, "required": ["id", "tr"], "additionalProperties": False}}},
        "required": ["items"], "additionalProperties": False}
    lines = [dict(r, sents=[s for s in c.sentences(r["text"]) if s.strip()] or [r["text"]]) for r in rows]

    def run(start):
        chunk = lines[start:start + CHUNK]
        parts = ["Translate each numbered sentence (id = line.sentence):"]
        for i, l in enumerate(chunk):
            parts.append(f"[{l['speaker'] or 'text'}]")
            parts += [f"  {start + i}.{j}\t{s}" for j, s in enumerate(l["sents"])]
        res = llm.call(system, "\n".join(parts), schema, tag, max_tokens=32000)
        # Ignore hallucinated IDs outside this prompt's chunk, or parallel
        # responses can silently overwrite an unrelated reviewed subtitle.
        valid = {f"{start + i}.{j}" for i, l in enumerate(chunk) for j in range(len(l["sents"]))}
        return {it["id"]: it["tr"].strip() for it in (res or {}).get("items", [])
                if it["id"] in valid and it["tr"].strip()}

    got = {}
    for attempt in range(2):
        todo = [s for s in range(0, len(lines), CHUNK)
                if any(f"{s + i}.{j}" not in got for i, l in enumerate(lines[s:s + CHUNK]) for j in range(len(l["sents"])))]
        if not todo:
            break
        with ThreadPoolExecutor(4) as ex:
            for items in ex.map(run, todo):
                got.update(items)
        print("deneme", attempt, "parça", len(todo), "toplam harcama $%.4f" % llm.spent())
    for i, l in enumerate(lines):
        l["tr"] = [got.get(f"{i}.{j}") for j in range(len(l["sents"]))]
    dump_atomic(lines, out, ensure_ascii=False, indent=0)
    print("çeviri:", out, "eksik cümle", sum(1 for l in lines for t in l["tr"] if not t))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    t = sub.add_parser("titles", help="havuzdaki oyun kimliklerini listeleyecek komut")
    t.add_argument("--limit", type=int, default=50)
    q = sub.add_parser("query", help="bir oyunun satırlarını alacak okuma komutu (çalıştırılmaz)")
    q.add_argument("--title")
    q.add_argument("--game")
    q.add_argument("--min", type=int, default=2, help="en az kaç kurulum görmüş (varsayılan 2)")
    q.add_argument("--limit", type=int, default=5000)
    q.add_argument("--all", action="store_true", help="çeviriye alınmış satırlar da")
    q.add_argument("--out", default="pool-export.json")
    p = sub.add_parser("plan", help="temizle, sırala, maliyeti tahmin et; --translate ile çevir")
    p.add_argument("export")
    p.add_argument("--id", required=True, help="paket kimliği (ör. gta-6)")
    p.add_argument("--glossary", default=str(HERE / "glossary/gta6.json"))
    p.add_argument("--out-dir", default=".")
    p.add_argument("--translate", action="store_true", help="çeviriyi gerçekten yap (API harcaması)")
    p.add_argument("--limit", type=int, help="çevrilecek en sık satır sayısı (--translate için zorunlu)")
    a = ap.parse_args(argv)

    if a.cmd == "titles":
        print(wrangler(titles_sql(a.limit)))
        return
    if a.cmd == "query":
        print(wrangler(query_sql(a.title, a.game, a.min, a.limit, a.all)) + f" > {shlex.quote(a.out)}")
        print("# Yalnız okur. D1'de okunan satır sayısı ücretlendirilir; title_id dizinlidir, --game tüm tabloyu tarar.",
              file=sys.stderr)
        return

    if a.translate and (not a.limit or a.limit <= 0):
        raise SystemExit("--translate yalnız --limit ile çalışır (ör. --limit 500)")
    rows = load_export(a.export)
    cleaned, dropped = clean(rows, known_keys())
    out_dir = Path(a.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    rows_file = out_dir / f"{a.id}.rows.jsonl"
    with rows_file.open("w", encoding="utf-8") as f:
        for r in cleaned:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    glossary = a.glossary if a.glossary and Path(a.glossary).is_file() else None
    system = system_prompt(glossary)
    print(f"havuzdan {len(rows)} satır; temiz {len(cleaned)}; atılan {dropped}")
    print(f"sıralı satırlar: {rows_file}")
    for r in cleaned[:10]:
        print(f"  {r['installs']:>5}  {r['text']}")
    chosen = cleaned[:a.limit] if a.limit else cleaned
    e = estimate(chosen, len(system))
    print(f"tahmin ({e['model']}): {e['lines']} satır, {e['sentences']} cümle, {e['chunks']} istek; "
          f"girdi ~{e['tokens_in']:,} jeton, çıktı ~{e['tokens_out'][0]:,}–{e['tokens_out'][1]:,} jeton; "
          f"~${e['usd'][0]:.2f}–${e['usd'][1]:.2f}")
    if not a.translate:
        print("KURU ÇALIŞTIRMA: çeviri yapılmadı. Çevirmek için: --translate --limit N")
        return
    translated_file = out_dir / f"{a.id}.tr.json"
    translate(chosen, system, f"{a.id}-poolpack", translated_file)
    # The exported-key list is later sent to /v1/exported. Never mark a pool
    # line when the model omitted one or more sentences: those lines must stay
    # available for the next translation attempt.
    translated_rows = json.loads(translated_file.read_text(encoding="utf-8"))
    completed = {
        row.get("key") for row in translated_rows if isinstance(row, dict)
        and isinstance(row.get("sents"), list) and row["sents"]
        and isinstance(row.get("tr"), list) and len(row["tr"]) == len(row["sents"])
        and all(isinstance(value, str) and value.strip() for value in row["tr"])
    }
    keys_file = out_dir / f"{a.id}.pool-keys.json"
    keys_file.write_text(json.dumps({"keys": [
        key for row in chosen if row["key"] in completed for key in row["pool_keys"]
    ]}), encoding="utf-8")
    print("havuz anahtarları:", keys_file)


if __name__ == "__main__":
    main()
