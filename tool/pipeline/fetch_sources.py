import sys, json, os, re, urllib.request, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from manifest import SOURCES
out = sys.argv[1]
for s in SOURCES:
    p = os.path.join(out, s["key"] + ".txt")
    if os.path.exists(p) and os.path.getsize(p) > 1000: continue
    url = f"https://www.gutenberg.org/cache/epub/{s['pg']}/pg{s['pg']}.txt"
    raw = urllib.request.urlopen(url, timeout=120).read().decode("utf-8", "replace").replace("\r\n", "\n")
    m1 = re.search(r"\*\*\* ?START OF.*?\*\*\*", raw); m2 = re.search(r"\*\*\* ?END OF", raw)
    body = raw[m1.end() if m1 else 0 : m2.start() if m2 else len(raw)]
    open(p, "w", encoding="utf-8").write(body)
    print(s["key"], len(body)); time.sleep(1)
json.dump(SOURCES, open(os.path.join(out, "manifest.json"), "w"), indent=1)
