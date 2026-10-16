# Repairs answer files of one batch: an answer with an unknown qid is moved to
# the unanswered item in the same position (when the numbers of unknown
# answers and unanswered items are equal), otherwise dropped.
#   python3 -I geofill/repair.py A 0033
import glob, json, sys
g, n = sys.argv[1:3]
want = [json.loads(l)['qid'] for l in open(f'geofill/in/{g}/{n}.jsonl') if l.strip()]
files = sorted(glob.glob(f'geofill/out/{g}/{n}.part*.jsonl') + glob.glob(f'geofill/out/{g}/{n}.jsonl'))
rows = []  # (file, line index, obj)
for f in files:
    for i, l in enumerate(open(f)):
        if l.strip():
            rows.append((f, i, json.loads(l)))
known = set(want)
got = {r[2]['qid'] for r in rows if r[2]['qid'] in known}
missing = [q for q in want if q not in got]
unknown = [r for r in rows if r[2]['qid'] not in known]
print(f'{g}/{n}: {len(unknown)} unknown, {len(missing)} unanswered')
if not unknown:
    sys.exit()
fix = {}
if len(unknown) == len(missing):
    # match by position in the input: nearest preceding answered qid
    pos = {q: i for i, q in enumerate(want)}
    for r, q in zip(unknown, missing):
        fix[id(r)] = q
for f in files:
    keep = []
    for i, l in enumerate(open(f)):
        if not l.strip():
            continue
        o = json.loads(l)
        if o['qid'] not in known:
            r = next(r for r in unknown if r[0] == f and r[1] == i)
            if id(r) in fix:
                o['qid'] = fix[id(r)]
            else:
                continue
        keep.append(json.dumps(o, ensure_ascii=False, separators=(',', ':')))
    open(f, 'w').write('\n'.join(keep) + '\n')
print('repaired' if len(unknown) == len(missing) else 'dropped, redo the missing items')
