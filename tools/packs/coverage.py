import argparse, sys, json, re
sys.path.insert(0, '.')
import common as c

parser = argparse.ArgumentParser(description="Estimate OCR coverage from synthetic or locally supplied rows")
parser.add_argument("rows", help="English rows.jsonl")
parser.add_argument("pool", help="OCR pool export.json")
parser.add_argument("pattern", help="OCR text filter regex, or - for all")
parser.add_argument("--title", default="", help="game title (enables GTA-specific short fuzzy estimate)")
args = parser.parse_args()
rows=[json.loads(l) for l in open(args.rows, encoding="utf-8")]
pat=args.pattern
fuzzy_min_len = c.fuzzy_min_len(args.title)
units={}
for r in rows:
    for s in [r['text']] + c.sentences(r['text']):
        k = c.key(s)
        if k:
            units[k] = s
grams={k:set(''.join(c.folded(v))[i:i+3] for i in range(len(c.folded(v))-2)) for k,v in units.items()}
pool=json.load(open(args.pool, encoding="utf-8"))['lines']
pool=[l for l in pool if re.search(pat,l['text'],re.I)] if pat!='-' else pool
exact=fz=0; misses=[]
def body(t):
    # Only strip plausible capitalized speaker names, not dialogue like
    # "Tell me: keep moving" where a colon belongs to the spoken sentence.
    m = re.match(r"^\s*[A-Z][A-Za-z.'’\-]*(?:\s+[A-Z][A-Za-z.'’\-]*){0,3}\s*[:•]\s+", t)
    return t[m.end():] if m else t
for l in pool:
    b=body(l['text'])
    k = c.key(b)
    parts = [p for p in c.sentences(b) if c.key(p)]
    if k and (k in units or (parts and all(c.key(p) in units for p in parts))):
        exact+=1; continue
    fq=''.join(c.folded(b)); g=set(fq[i:i+3] for i in range(len(fq)-2))
    if len(fq)<fuzzy_min_len or not g: misses.append(b); continue
    best=0;bt=None
    for k,gg in grams.items():
        if not gg or abs(len(gg)-len(g))>len(g)*0.4: continue
        s=min(len(g&gg)/len(g), len(g&gg)/len(gg))
        if s>best: best,bt=s,units[k]
    if best>=0.6: fz+=1
    else: misses.append(b)
print('pool lines',len(pool),'exact',exact,'fuzzy>=0.6',fz,'miss',len(misses))
for m in misses[:15]: print('  MISS',m[:120])
