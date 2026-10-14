"""Writes events/<mm>/<key>.json from checked.jsonl and review_out/*.jsonl.

review_out/*.jsonl (written by the review pass) has one line per event that the
Wikidata check flagged: {"key": ..., "action": "keep" | "fix" | "drop",
"fields": {...}} where `fields` replaces fields of the event on "fix".
Flagged events without a review line are dropped.

Also: fills lat/lon from Wikidata when the writer gave none, drops
duplicates (same Wikidata item or same title), and keeps at most --max
events, highest weight first.

Run: python3 -I tool/pipeline/events/write_events.py [--max 1000]
"""
import argparse, glob, json, os, re, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
FIELDS = ['title', 'year', 'month', 'day', 'calendar', 'summary', 'reason',
          'significance', 'participants', 'countries', 'place', 'lat', 'lon',
          'tags', 'weight', 'wikipedia']
BAD_CHARS = re.compile('[\u2012-\u2015\u2190-\u21ff\u2018\u2019\u201c\u201d]')


def flagged(ev):
    """Needs a review line: Wikidata disagrees on the day, or neither
    Wikidata nor the article text confirms it, or the coordinates are far
    from Wikidata's."""
    c = ev.get('check', {})
    return (c.get('date') == 'mismatch'
            or (c.get('date') != 'match' and c.get('text') != 'found')
            or c.get('coords') == 'far')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--max', type=int, default=1000)
    args = ap.parse_args()
    events = [json.loads(l) for l in open(os.path.join(HERE, 'checked.jsonl'),
                                          encoding='utf-8') if l.strip()]
    reviews = {}
    for path in sorted(glob.glob(os.path.join(HERE, 'review_out', '*.jsonl'))):
        for l in open(path, encoding='utf-8'):
            if l.strip():
                r = json.loads(l)
                reviews[r['key']] = r
    kept, dropped = [], {}
    for ev in events:
        if flagged(ev):
            r = reviews.get(ev['key'])
            action = r['action'] if r else 'unreviewed'
            if action == 'fix':
                ev.update(r.get('fields', {}))
            elif action != 'keep':
                dropped[action] = dropped.get(action, 0) + 1
                continue
        c = ev.get('check', {})
        # A redirect target with an en dash stays as the plain title,
        # which redirects to it.
        if c.get('resolved_title') and not BAD_CHARS.search(
                c['resolved_title']) and 'wikipedia' not in (
                reviews.get(ev['key'], {}).get('fields', {})):
            ev['wikipedia'] = c['resolved_title']
        if ev.get('lat') is None and c.get('coords') == 'wikidata_only':
            ev['lat'], ev['lon'] = c['wikidata_coords']
        kept.append(ev)

    kept.sort(key=lambda e: -e['weight'])
    seen_q, seen_t, out = set(), set(), []
    for ev in kept:
        t = re.sub(r'[^a-z0-9]', '', ev['title'].lower())
        q = ev.get('qid')
        if t in seen_t or (q and q in seen_q):
            dropped['duplicate'] = dropped.get('duplicate', 0) + 1
            continue
        seen_t.add(t)
        if q:
            seen_q.add(q)
        out.append(ev)
    if len(out) > args.max:
        dropped['over max'] = len(out) - args.max
        out = out[:args.max]

    target = os.path.join(ROOT, 'events')
    if os.path.isdir(target):
        shutil.rmtree(target)
    for ev in out:
        rec = {'id': 'event-' + ev['key']}
        rec.update({k: ev.get(k) for k in FIELDS})
        if ev.get('qid'):
            rec['wikidata'] = ev['qid']
        text = json.dumps(rec, ensure_ascii=False, indent=2)
        if BAD_CHARS.search(text):
            text = (text.replace('\u2019', "'").replace('\u2018', "'")
                    .replace('\u201c', '\\"').replace('\u201d', '\\"'))
            text = re.sub('[\u2012-\u2015]', ', ', text)
        d = os.path.join(target, f'{ev["month"]:02d}')
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, ev['key'] + '.json'), 'w', encoding='utf-8') as f:
            f.write(text + '\n')
    print(f'wrote {len(out)} events; dropped {dropped}')


if __name__ == '__main__':
    main()
