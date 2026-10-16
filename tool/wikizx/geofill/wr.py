# Turns compact answer lines into a JSONL part file.
#   python3 -I geofill/wr.py A 0001 1 <<'X'
#   qid|place|lat|lon|precision(s/c/r/n/k)|confidence(h/m/l)|note
#   X
# precision: s site, c city, r region, k country, n none. Empty place = null.
import json, sys
g, n, part = sys.argv[1:4]
P = {'s': 'site', 'c': 'city', 'r': 'region', 'k': 'country', 'n': 'none'}
C = {'h': 'high', 'm': 'medium', 'l': 'low'}
out = []
for l in sys.stdin:
    l = l.strip()
    if not l:
        continue
    q, place, lat, lon, pr, cf, *note = l.split('|')
    out.append(json.dumps({'qid': int(q), 'place': place or None,
        'lat': float(lat) if lat else None, 'lon': float(lon) if lon else None,
        'precision': P[pr], 'confidence': C[cf], 'note': '|'.join(note)},
        ensure_ascii=False, separators=(',', ':')))
import os
os.makedirs(f'geofill/out/{g}', exist_ok=True)
p = f'geofill/out/{g}/{n}.part{part}.jsonl'
assert not os.path.exists(p), p + ' exists'
open(p, 'w').write('\n'.join(out) + '\n')
print(len(out), 'lines ->', p)
