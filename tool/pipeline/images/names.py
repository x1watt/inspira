"""Collects person names with context. Usage: names.py <project> <out.json>"""
import json, sys
proj, out = sys.argv[1], sys.argv[2]
q = json.load(open(f'{proj}/assets/quotes.json'))
s = json.load(open(f'{proj}/assets/stories.json'))
names = {}
def add(n, ctx):
    n = n.strip()
    if n and n not in names:
        names[n] = ctx
for x in q:
    add(x['author'], f"author of {x['reference']}, {x.get('author_lifespan','')}")
for x in q:
    if x.get('speaker'):
        add(x['speaker'], f"speaker in {x['author']}, {x['reference']}")
for x in s:
    if x['kind'] == 'story':
        continue
    p = x.get('people', '').split(',')[0].split(' and ')[0].strip()
    add(p, f"{x['kind']}: {x['title']} ({x.get('date','')})")
json.dump(names, open(out, 'w'), indent=0)
print(len(names))
