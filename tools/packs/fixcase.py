# Sentence-initial "I..." where Turkish needs "İ" (model lowercased/uppercased with ASCII rules).
# Decides per word from word frequencies in the existing Turkish packs. Usage: fixcase.py <packs dir> <file.json>...
import collections, gzip, json, os, re, sys, tempfile
# Legacy Windows terminal encodings (e.g. cp1254) cannot print the correction arrow.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, ValueError):
    pass
freq = collections.Counter()
for f in os.listdir(sys.argv[1]):
    path = os.path.join(sys.argv[1], f)
    if not f.endswith(".json.gz") or not os.path.isfile(path):
        continue
    d = json.load(gzip.open(path))
    for v in list(d["entries"].values()) + list(d.get("segments", {}).values()):
        for w in re.findall(r"\b[\wçğıöşü]+", v):
            if w[:1].islower():
                freq[w] += 1
TR_LOWER = lambda s: s.replace("I", "ı").replace("İ", "i").lower()
changed = collections.Counter()
def fix(m):
    w = m.group(0)
    rest = TR_LOWER(w[1:])
    dotted, dotless = "i" + rest, "ı" + rest
    if freq[dotted] > freq[dotless]:
        changed[w + "→İ" + w[1:]] += 1
        return "İ" + w[1:]
    return w
for path in sys.argv[2:]:
    L = json.load(open(path, encoding="utf-8"))
    for l in L:
        l["tr"] = [re.sub(r"\bI[a-zçğıöşü]+", fix, t) if t else t for t in l["tr"]]
    # This edits the reviewed source in place. A disk-full or failed JSON
    # serialization must not truncate the last valid translations.
    staged = None
    try:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=os.path.dirname(os.path.abspath(path)),
                                         prefix="." + os.path.basename(path) + ".", suffix=".tmp",
                                         delete=False) as output:
            staged = output.name
            json.dump(L, output, ensure_ascii=False, indent=0)
        os.replace(staged, path)
    finally:
        if staged and os.path.exists(staged):
            os.unlink(staged)
print(sum(changed.values()), changed.most_common(40))
