import json, os, re, unicodedata
SCRIPTS = os.path.dirname(os.path.abspath(__file__))
WORK = os.environ.get("INSPIRA_WORK", os.path.dirname(SCRIPTS))
SOURCES_DIR = os.path.join(WORK, "sources")
CATEGORIES = ["relations", "leadership", "team", "family", "strategy"]
_FOOT = re.compile(r"\[[^\]]{0,12}\]")

def letters(s):
    s = unicodedata.normalize("NFKD", s)
    s = _FOOT.sub(" ", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", "", s.lower())

_cache = {}
def source_letters(key):
    if key not in _cache:
        _cache[key] = letters(open(os.path.join(SOURCES_DIR, key + ".txt"), encoding="utf-8").read())
    return _cache[key]

def manifest():
    return {s["key"]: s for s in json.load(open(os.path.join(SOURCES_DIR, "manifest.json")))}

def found_in_source(key, text):
    src = source_letters(key)
    pos = 0
    for part in re.split(r"\.\.\.|…", text):
        p = letters(part)
        if not p: continue
        i = src.find(p, pos)
        if i < 0: return False
        pos = i + len(p)
    return True

def tidy(text):
    t = text.replace("‘", "'").replace("’", "'").replace("“", '"').replace("”", '"')
    t = t.replace("…", "...").replace("_", "")
    for a, b in (("\u00e6", "ae"), ("\u00c6", "Ae"), ("\u0153", "oe"), ("\u0152", "Oe")): t = t.replace(a, b)
    t = re.sub(r"\s*(—|–|--)\s*", ", ", t)
    t = _FOOT.sub("", t)
    t = re.sub(r"\s+", " ", t).strip()
    t = re.sub(r"\s+([,.;:!?])", r"\1", t)
    t = re.sub(r",\s*,", ",", t)
    return t

_LEAD = re.compile(r"^(?:(?:But|And|Moreover|Besides|Nay|Wherefore|Accordingly|However|Furthermore|Therefore|Hence|Thus),?\s+|For(?:,\s*|\s+(?=(?:it|if|as|when|there|we|they|he|she|this|these|those|such|no|all|nothing|men|man|what|who|whoever|whatever)\b)))+", re.I)
def strip_lead(t):
    """Drop leading connectors ('But', 'And for') so the quote starts where the thought starts."""
    m = _LEAD.match(t)
    if not m: return t
    rest = t[m.end():].lstrip(", ")
    if len(rest) < 25 or not rest[0].isalpha(): return t
    return rest[0].upper() + rest[1:]
