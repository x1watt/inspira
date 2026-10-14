"""Wikidata search for each name; top 5 hits. Usage: search.py names.json out.jsonl"""
import json, sys, os
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.dirname(__file__))
from common import get_json
names = json.load(open(sys.argv[1]))
done = set()
if os.path.exists(sys.argv[2]):
    done = {json.loads(l)['name'] for l in open(sys.argv[2])}
def one(n):
    r = get_json('https://www.wikidata.org/w/api.php', {
        'action': 'wbsearchentities', 'search': n, 'language': 'en',
        'format': 'json', 'limit': 5, 'type': 'item'})
    return {'name': n, 'context': names[n], 'hits': [
        {'id': h['id'], 'label': h.get('label', ''), 'desc': h.get('description', '')}
        for h in r.get('search', [])]}
todo = [n for n in names if n not in done]
import time
with open(sys.argv[2], 'a') as f:
    for n in todo:
        f.write(json.dumps(one(n)) + '\n')
        f.flush()
        time.sleep(0.4)
print('searched', len(todo))
