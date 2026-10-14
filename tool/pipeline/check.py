"""Usage: python3 -I check.py <candidates.jsonl>  -> reports lines whose text is not found verbatim in its source."""
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import CATEGORIES, found_in_source, manifest, letters
M = manifest()
bad = 0; ok = 0; seen = set(); counts = {}
for n, line in enumerate(open(sys.argv[1], encoding="utf-8"), 1):
    line = line.strip()
    if not line: continue
    try: q = json.loads(line)
    except Exception as e: print(f"line {n}: bad json: {e}"); bad += 1; continue
    errs = []
    if q.get("source") not in M: errs.append(f"unknown source {q.get('source')}")
    if q.get("category") not in CATEGORIES: errs.append(f"bad category {q.get('category')}")
    t = q.get("text", "")
    if not (25 <= len(t) <= 600): errs.append(f"text length {len(t)} (25-600)")
    if not q.get("locator"): errs.append("missing locator")
    if not errs and not found_in_source(q["source"], t): errs.append("text NOT found verbatim in source")
    k = letters(t)
    if k in seen: errs.append("duplicate")
    seen.add(k)
    if errs: bad += 1; print(f"line {n}: {'; '.join(errs)} :: {t[:80]}")
    else:
        ok += 1; counts[q["category"]] = counts.get(q["category"], 0) + 1
print(f"OK {ok}  BAD {bad}  by category {counts}")
