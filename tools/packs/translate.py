# Translate transcript rows sentence by sentence with Claude Haiku 5.5.
# Usage: translate.py <game> <rows.jsonl>[,<rows2.jsonl>] <out tr.json>
# Output: {sentence key: {"en": ..., "tr": ...}} plus line structure in <out>.lines.json
import json, re, sys
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, __file__.rsplit("/", 1)[0])
import common as c, llm
from atomic_json import dump_atomic

game, srcs, out = sys.argv[1], sys.argv[2].split(","), sys.argv[3]

from translate_rules import GLOSSARY, RULES

SYSTEM = f"""You translate video game subtitles from English into Turkish for CouchSubs, an app that shows Turkish
subtitles on the TV while people play.
{GLOSSARY[game]}

{RULES}"""

SCHEMA = {"type": "object", "properties": {"items": {"type": "array", "items": {"type": "object", "properties": {
    "id": {"type": "string"}, "tr": {"type": "string"}}, "required": ["id", "tr"], "additionalProperties": False}}},
    "required": ["items"], "additionalProperties": False}

rows = []
for s in srcs:
    rows += [json.loads(l) for l in open(s, encoding="utf-8")]

# Unique lines by key, in order; each line split into sentences.
lines, seen = [], set()
for r in rows:
    k = c.key(r["text"])
    if not k or k in seen:
        continue
    seen.add(k)
    sents = [x for x in c.sentences(r["text"]) if x.strip()]
    lines.append({"key": k, "speaker": r["speaker"], "scene": r["scene"], "text": r["text"], "sents": sents,
                  "raw": r.get("raw")})
print(game, "lines", len(lines), "sentences", sum(len(l["sents"]) for l in lines))

CH = 40


def run(start):
    ctx = lines[max(0, start - 4):start]
    chunk = lines[start:start + CH]
    parts = []
    if ctx:
        parts.append("Previous lines for context (do not translate):")
        parts += [f"  {l['speaker'] or '-'}: {l['text']}" for l in ctx]
    parts.append(f"Scene: {chunk[0]['scene'] or '-'}\nTranslate each numbered sentence (id = line.sentence):")
    for i, l in enumerate(chunk):
        parts.append(f"[{l['speaker'] or 'text'}]")
        for j, s in enumerate(l["sents"]):
            parts.append(f"  {start + i}.{j}\t{s}")
    res = llm.call(SYSTEM, "\n".join(parts), SCHEMA, f"{game}-translate", max_tokens=32000)
    # LLM responses may contain hallucinated IDs from the preceding context
    # or other chunks. Only allow this chunk's requested sentence IDs to
    # update translations, or a later chunk could overwrite an earlier one.
    valid = {f"{start + i}.{j}" for i, l in enumerate(chunk) for j in range(len(l["sents"]))}
    return start, {it["id"]: it["tr"].strip() for it in (res or {}).get("items", [])
                   if it["id"] in valid and it["tr"].strip()}


got = {}
for attempt in range(3):
    todo = [s for s in range(0, len(lines), CH)
            if any(f"{s + i}.{j}" not in got for i, l in enumerate(lines[s:s + CH]) for j in range(len(l["sents"])))]
    if not todo:
        break
    with ThreadPoolExecutor(4) as ex:
        for start, items in ex.map(run, todo):
            got.update(items)
    print("attempt", attempt, "chunks", len(todo), "spent $%.4f" % llm.spent())

for i, l in enumerate(lines):
    l["tr"] = [got.get(f"{i}.{j}") for j in range(len(l["sents"]))]
missing = sum(1 for l in lines for t in l["tr"] if not t)
print("missing sentences", missing)
dump_atomic(lines, out, ensure_ascii=False, indent=0)
