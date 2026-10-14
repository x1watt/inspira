"""Usage: python3 -I write_quotes.py <project_dir>
Reads SCRATCH/candidates/*/*.jsonl (verified, from sources) and SCRATCH/attributed/*.jsonl,
verifies, dedups, and writes <project_dir>/quotes/<category>/<id>.json (folder is regenerated)."""
import sys, os, json, glob, hashlib, re, unicodedata, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import CATEGORIES, found_in_source, manifest, letters, tidy, strip_lead
SCRATCH = os.environ.get("INSPIRA_WORK", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
M = manifest()
FIELDS = ["id","category","text","author","author_lifespan","speaker","reference","locator","date","year",
          "location","original_language","translation","source_url","confidence"]
ATTR_REQ = ["category","text","author","reference","date","location"]

def slug(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")[:32].strip("-")

def no_dash(v):
    return re.sub(r"\s*(—|–|--)\s*", ", ", v) if isinstance(v, str) else v

stats = collections.Counter(); out = []
for f in sorted(glob.glob(os.path.join(SCRATCH, "candidates", "*", "*.jsonl"))):
    for line in open(f, encoding="utf-8"):
        if not line.strip(): continue
        try: c = json.loads(line)
        except Exception: stats["bad_json"] += 1; continue
        s = M.get(c.get("source"))
        t = c.get("text", "")
        if not s or c.get("category") not in CATEGORIES or not (25 <= len(t) <= 600) or not found_in_source(s["key"], t):
            stats["rejected_verified"] += 1; continue
        q = {k: s.get(k) for k in ["author","author_lifespan","reference","date","year","location","original_language","translation","source_url"]}
        for k in ["author","author_lifespan","speaker","date","year","location","locator"]:
            if c.get(k) not in (None, ""): q[k] = c[k]
        q.update(category=c["category"], text=strip_lead(tidy(t)), confidence="verified")
        out.append(q)
for f in sorted(glob.glob(os.path.join(SCRATCH, "attributed", "*.jsonl"))):
    for line in open(f, encoding="utf-8"):
        if not line.strip(): continue
        try: c = json.loads(line)
        except Exception: stats["bad_json"] += 1; continue
        if c.get("category") not in CATEGORIES or any(not c.get(k) for k in ATTR_REQ) or not (20 <= len(c["text"]) <= 600):
            stats["rejected_attributed"] += 1; continue
        q = {k: c.get(k) for k in FIELDS if k not in ("id", "confidence")}
        q["text"] = tidy(c["text"]); q["confidence"] = "attributed"
        out.append(q)

# dedup: verified first, then longer first; drop exact dups and texts contained in a kept text of same author
out.sort(key=lambda q: (q["confidence"] != "verified", -len(q["text"])))
kept = []; keys_by_author = collections.defaultdict(list); seen = set()
for q in out:
    k = letters(q["text"])
    if k in seen: stats["dup"] += 1; continue
    a = slug(q["author"])
    if len(k) > 40 and any(k in o for o in keys_by_author[a]): stats["contained"] += 1; continue
    seen.add(k); keys_by_author[a].append(k); kept.append(q)

base = os.path.join(sys.argv[1], "quotes")
for cat in CATEGORIES:
    d = os.path.join(base, cat); os.makedirs(d, exist_ok=True)
    for f in glob.glob(os.path.join(d, "*.json")): os.remove(f)
# review decisions: DROP<TAB>id<TAB>reason / RECAT<TAB>id<TAB>category
drop, recat = set(), {}
for f in glob.glob(os.path.join(SCRATCH, "review", "decisions*.tsv")):
    for line in open(f, encoding="utf-8"):
        p = line.rstrip("\n").split("\t")
        if len(p) >= 2 and p[0] == "DROP": drop.add(p[1].strip())
        elif len(p) >= 3 and p[0] == "RECAT" and p[2].strip() in CATEGORIES: recat[p[1].strip()] = p[2].strip()
counts = collections.Counter()
for q in kept:
    if q.get("original_language") == "English": q["translation"] = None
    q["id"] = slug(q["author"]) + "-" + hashlib.sha1(letters(q["text"]).encode()).hexdigest()[:8]
    if q["id"] in drop: stats["review_drop"] += 1; continue
    if q["id"] in recat: q["category"] = recat[q["id"]]; stats["review_recat"] += 1
    rec = {k: no_dash(q.get(k)) if k != "text" else q["text"] for k in FIELDS if q.get(k) not in (None, "")}
    if not rec.get("locator"): rec["locator"] = ""
    with open(os.path.join(base, q["category"], q["id"] + ".json"), "w", encoding="utf-8") as fh:
        json.dump(rec, fh, ensure_ascii=False, indent=2); fh.write("\n")
    counts[(q["category"], q["confidence"])] += 1
print("stats", dict(stats))
for cat in CATEGORIES:
    v, a = counts[(cat, "verified")], counts[(cat, "attributed")]
    print(f"{cat:11s} verified {v:5d} attributed {a:5d} total {v+a:5d}")
print("total", sum(counts.values()))
