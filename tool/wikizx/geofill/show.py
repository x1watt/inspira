# Shows items START..END-1 of a batch in a compact form.
#   python3 -I geofill/show.py A 0002 0 50
import json, sys
g, n, a, b = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
ls = [json.loads(l) for l in open(f'geofill/in/{g}/{n}.jsonl')]
for o in ls[a:b]:
    ib = ' | '.join(f"{k}={v[:50]}" for k, v in o.get('infobox', {}).items())
    print(o['qid'], '#', o['title'], '#', o['lead'][:170].replace('\n', ' '), '#', ib)
