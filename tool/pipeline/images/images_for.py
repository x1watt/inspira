"""Adds P18 images to search hits. Usage: images_for.py search.jsonl out.jsonl"""
import json, os, sys, time, urllib.parse
sys.path.insert(0, os.path.dirname(__file__))
from common import get_json
rows = [json.loads(l) for l in open(sys.argv[1])]
ids = sorted({h['id'] for r in rows for h in r['hits']})
img = {}
for i in range(0, len(ids), 250):
    vals = ' '.join('wd:' + x for x in ids[i:i + 250])
    q = ('SELECT ?item ?img WHERE { VALUES ?item { %s } ?item wdt:P18 ?img }' % vals)
    res = get_json('https://query.wikidata.org/sparql', {'query': q, 'format': 'json'})
    for b in res['results']['bindings']:
        qid = b['item']['value'].rsplit('/', 1)[1]
        f = urllib.parse.unquote(b['img']['value'].rsplit('/', 1)[1])
        img.setdefault(qid, 'File:' + f.replace('_', ' '))
    time.sleep(1)
with open(sys.argv[2], 'w') as out:
    for r in rows:
        hits = [dict(h, file=img[h['id']]) for h in r['hits'] if h['id'] in img]
        if hits:
            out.write(json.dumps({'name': r['name'], 'context': r['context'], 'hits': hits}) + '\n')
print(len(ids), 'ids,', len(img), 'with image')
