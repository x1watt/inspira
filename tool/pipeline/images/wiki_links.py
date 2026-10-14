"""Adds English Wikipedia links for matched people to assets/images.json.

Usage: wiki_links.py <work dir> <project dir>
Reads work/picks_*.jsonl ({"name", "id"}), looks up the enwiki sitelink of
each Wikidata item and writes them under "wikipedia": {name: url}.
"""
import glob, json, os, sys, time, urllib.parse
sys.path.insert(0, os.path.dirname(__file__))
from common import get_json

work, proj = sys.argv[1:3]
picks = {}
for f in sorted(glob.glob(os.path.join(work, 'picks_*.jsonl'))):
    for l in open(f):
        if l.strip():
            p = json.loads(l)
            if p.get('id'):
                picks[p['name']] = p['id']
ids = sorted(set(picks.values()))
title = {}
for i in range(0, len(ids), 50):
    r = get_json('https://www.wikidata.org/w/api.php', {
        'action': 'wbgetentities', 'format': 'json', 'props': 'sitelinks',
        'sitefilter': 'enwiki', 'ids': '|'.join(ids[i:i + 50])})
    for qid, e in r.get('entities', {}).items():
        t = e.get('sitelinks', {}).get('enwiki', {}).get('title')
        if t:
            title[qid] = t
    time.sleep(1)
links = {
    n: 'https://en.wikipedia.org/wiki/' + urllib.parse.quote(title[q].replace(' ', '_'))
    for n, q in sorted(picks.items()) if q in title
}
path = os.path.join(proj, 'assets', 'images.json')
m = json.load(open(path))
m['wikipedia'] = links
with open(path, 'w') as fh:
    json.dump(m, fh, ensure_ascii=False, indent=0)
print(len(links), 'links of', len(picks), 'matched people')
