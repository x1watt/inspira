"""Checks the coordinates in out/*.jsonl against OpenStreetMap Nominatim.

For every `site` or `city` line the `query` is geocoded (one request per
second, as the Nominatim usage policy asks; results cached in
cache.json). Adds `osm` [lat, lon] and `km` (distance from the written
point) to each line and writes checked.jsonl. Far means more than 15 km
for a site and 30 km for a city; far and not found lines go to review.

Run: python3 -I tool/pipeline/places/verify.py
"""
import glob, json, math, os, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
UA = 'InspiraBuild/1.0 (https://github.com/x1watt/inspira)'
LIMIT = {'site': 15, 'city': 30}


def km(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = (math.sin((la2 - la1) / 2) ** 2
         + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2)
    return 6371 * 2 * math.asin(math.sqrt(h))


def geocode(q, cache):
    if q in cache:
        return cache[q]
    url = 'https://nominatim.openstreetmap.org/search?' + urllib.parse.urlencode(
        {'q': q, 'format': 'jsonv2', 'limit': 1})
    for i in range(4):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                hits = json.load(r)
            break
        except Exception:
            time.sleep(5 * (i + 1))
    else:
        hits = []
    time.sleep(1.1)
    cache[q] = [float(hits[0]['lat']), float(hits[0]['lon'])] if hits else None
    return cache[q]


def main():
    cache_path = os.path.join(HERE, 'cache.json')
    cache = json.load(open(cache_path)) if os.path.exists(cache_path) else {}
    rows = []
    for path in sorted(glob.glob(os.path.join(HERE, 'out', '*.jsonl'))):
        rows += [json.loads(l) for l in open(path, encoding='utf-8') if l.strip()]
    counts = {}
    for n, r in enumerate(rows):
        if r['precision'] in LIMIT:
            hit = geocode(r.get('query') or r['place'], cache) if (r.get('query') or r.get('place')) else None
            if hit is None:
                r['check'] = 'not_found'
            else:
                r['osm'] = hit
                r['km'] = round(km((r['lat'], r['lon']), hit), 1)
                r['check'] = 'ok' if r['km'] <= LIMIT[r['precision']] else 'far'
            counts[r['check']] = counts.get(r['check'], 0) + 1
            if n % 50 == 0:
                json.dump(cache, open(cache_path, 'w'))
    json.dump(cache, open(cache_path, 'w'))
    with open(os.path.join(HERE, 'checked.jsonl'), 'w', encoding='utf-8') as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + '\n')
    print(len(rows), 'rows', counts)


if __name__ == '__main__':
    main()
