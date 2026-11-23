# Çok cümleli satırların cümlelerini pakete parça (segment) olarak ekler; çeviri (API) gerekmez.
# Satırın Türkçesi İngilizcesiyle aynı sayıda cümleye bölünüyorsa cümleler sırayla eşlenir (soru/ünlem işareti ve
# uzunluk oranı tutmalı). Ekranda cümlesi ayrı okunan, iki satırın birleştiği ya da yarım okunan altyazılar böylece
# paketten bulunur. Var olan imzalar korunur, yeni parçaların imzası İngilizcesinden hesaplanır.
# Kullanım: sentences.py <paket.json.gz> <english.json: ["English line", ...]> <çıktı.json.gz>
import base64, collections, gzip, json, sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
import common as c

src, english_path, out = sys.argv[1:4]
pack = json.load(gzip.open(src))
entries, segments = pack["entries"], pack.get("segments", {})
have = set(entries) | set(segments)
CLOSE = "\"'”’)]"


def ender(s):
    s = s.rstrip(CLOSE)
    return s[-1:] if s[-1:] in "?!" else ""


candidates = collections.defaultdict(collections.Counter)
stats = collections.Counter()
for en in json.load(open(english_path, encoding="utf-8")):
    parts = c.sentences(en)
    if len(parts) < 2:
        continue
    k = c.key(en)
    turkish = entries.get(k) or segments.get(k)
    if not turkish or all(c.key(p) in have for p in parts):
        continue
    stats["multi"] += 1
    tr = c.sentences(turkish)
    if len(tr) != len(parts):
        stats["count"] += 1
        continue
    if any(ender(a) != ender(b) or not 0.4 <= len(b) / max(len(a), 1) <= 2.5 for a, b in zip(parts, tr)):
        stats["sanity"] += 1
        continue
    stats["aligned"] += 1
    for a, b in zip(parts, tr):
        ka = c.key(a)
        if ka and ka not in have and b.strip():
            candidates[ka][(a, b.strip())] += 1

added = {}
english = {}
for ka, counter in candidates.items():
    (a, b), _ = counter.most_common(1)[0]
    added[ka] = b
    english[ka] = a
stats["added"] = len(added)

# Var olan imzalar: dosyadaki sıra (bütün anahtarlar sayı sırasıyla), imzalı olanların uzunluk ve Bloom'u.
old_order = sorted({int(k, 16) for k in have})
fz = pack["fuzzy"]
mask, lengths, blooms = (base64.b64decode(fz[n]) for n in ("mask", "lengths", "blooms"))
assert fz["count"] == len(old_order)
kept, pos, signed = {}, 0, 0
for i, k in enumerate(old_order):
    if mask[i >> 3] >> (i & 7) & 1:
        n = c.bits_for(lengths[signed]) // 8
        kept[k] = (lengths[signed], blooms[pos:pos + n])
        pos += n
        signed += 1
assert signed == len(lengths) and pos == len(blooms)
for ka, a in english.items():
    # Match the pack builder's GTA-specific short fuzzy signature threshold.
    sig = c.signature(a, c.fuzzy_min_len(pack.get("title")))
    if sig:
        kept[int(ka, 16)] = sig

segments = dict(segments)
segments.update(added)
order = sorted({int(k, 16) for k in list(entries) + list(segments)})
new_mask = bytearray((len(order) + 7) // 8)
new_lengths, new_blooms = bytearray(), bytearray()
for i, k in enumerate(order):
    if k in kept:
        new_mask[i >> 3] |= 1 << (i & 7)
        new_lengths.append(kept[k][0])
        new_blooms += kept[k][1]
b64 = lambda b: base64.b64encode(bytes(b)).decode()
pack["segments"] = dict(sorted(segments.items()))
pack["entries"] = dict(sorted(entries.items()))
pack["fuzzy"] = {"version": 1, "count": len(order), "mask": b64(new_mask), "lengths": b64(new_lengths), "blooms": b64(new_blooms)}
data = json.dumps(pack, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
with gzip.GzipFile(out, "wb", compresslevel=9, mtime=0) as f:
    f.write(data)
print(pack["id"], dict(stats), "segments", len(segments), "signed", len(new_lengths))
