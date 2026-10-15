# Run: python3 -I tool/wikizx/scripts/wdcheck.py events
"""Estimate Wikidata coordinate coverage for the verified events by tier:
own P625, location P276 -> P625, area P131 -> P625, country P17 -> P625."""
import glob, json, math, sys, time, urllib.parse, urllib.request
UA = 'InspiraBuild/1.0 (https://github.com/x1watt/inspira)'
def get(ids):
    out = {}
    for i in range(0, len(ids), 50):
        q = 'https://www.wikidata.org/w/api.php?' + urllib.parse.urlencode({
            'action': 'wbgetentities', 'format': 'json', 'props': 'claims',
            'ids': '|'.join(ids[i:i + 50])})
        for t in range(5):
            try:
                with urllib.request.urlopen(urllib.request.Request(q, headers={'User-Agent': UA}), timeout=60) as r:
                    out.update(json.load(r).get('entities', {})); break
            except Exception:
                time.sleep(5 * (t + 1))
        time.sleep(0.3)
    return out
def vals(e, p):
    return [c['mainsnak'].get('datavalue', {}).get('value') for c in e.get('claims', {}).get(p, [])
            if c.get('rank') != 'deprecated' and c['mainsnak'].get('datavalue')]
def coord(e):
    for v in vals(e, 'P625'):
        if isinstance(v, dict) and v.get('globe', '').endswith('Q2'):
            return v['latitude'], v['longitude']
def km(a, b, c, d):
    r = math.radians
    h = math.sin(r(c - a) / 2) ** 2 + math.cos(r(a)) * math.cos(r(c)) * math.sin(r(d - b) / 2) ** 2
    return 12742 * math.asin(math.sqrt(h))
ev = {}
for f in glob.glob(sys.argv[1] + '/*/*.json'):
    e = json.load(open(f))
    if e.get('wikidata') and e.get('lat') is not None:
        ev[e['wikidata']] = e
items = get(list(ev))
refs = set()
for e in items.values():
    for p in ('P276', 'P131', 'P17'):
        refs |= {v['id'] for v in vals(e, p) if isinstance(v, dict) and 'id' in v}
places = get(sorted(refs))
tiers = {}; ok = {}; ok5 = {}
for q, e in ev.items():
    it = items.get(q, {}); got = None
    c = coord(it)
    if c: got = ('own P625', c)
    else:
        for p, name in (('P276', 'location P276'), ('P131', 'area P131'), ('P17', 'country P17')):
            for v in vals(it, p):
                pc = coord(places.get(v.get('id'), {})) if isinstance(v, dict) else None
                if pc: got = (name, pc); break
            if got: break
    name = got[0] if got else 'none'
    tiers[name] = tiers.get(name, 0) + 1
    if got:
        d = km(e['lat'], e['lon'], *got[1])
        ok[name] = ok.get(name, 0) + (d < 50); ok5[name] = ok5.get(name, 0) + (d < 5)
n = len(ev)
print(f'{n} verified events with coordinates and a Wikidata id')
cum = 0
for name in ('own P625', 'location P276', 'area P131', 'country P17', 'none'):
    k = tiers.get(name, 0); cum += k if name != 'none' else 0
    extra = f', within 50 km {ok.get(name,0)}/{k}, within 5 km {ok5.get(name,0)}/{k}' if k and name != 'none' else ''
    print(f'  {name:14s} {k:4d} ({100*k/n:.1f}%){extra}')
print(f'  any tier above country: {sum(tiers.get(t,0) for t in ("own P625","location P276","area P131"))}/{n}')
