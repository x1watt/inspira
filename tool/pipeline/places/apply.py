"""Writes `place`, `lat` and `lon` into stories/<category>/*.json.

Takes checked.jsonl (from verify.py) plus review.jsonl (one line per far
or not found point: {"id", "action": "keep" | "fix" | "drop", "lat",
"lon", "place"}). Points that are `ok`, kept or fixed get written;
regions, unplaced stories, drops and unreviewed points get none (and lose
any earlier one).

Run: python3 -I tool/pipeline/places/apply.py, then
dart run tool/bundle_quotes.dart
"""
import glob, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))


def main():
    rows = {}
    for l in open(os.path.join(HERE, 'checked.jsonl'), encoding='utf-8'):
        if l.strip():
            r = json.loads(l)
            rows[r['id']] = r
    review = {}
    rp = os.path.join(HERE, 'review.jsonl')
    if os.path.exists(rp):
        for l in open(rp, encoding='utf-8'):
            if l.strip():
                r = json.loads(l)
                review[r['id']] = r
    counts = {}
    for path in sorted(glob.glob(os.path.join(ROOT, 'stories', '*', '*.json'))):
        story = json.load(open(path, encoding='utf-8'))
        r = rows.get(story['id'])
        point = None
        if r and r.get('check') == 'ok':
            point = (r['place'], r['lat'], r['lon'])
            why = 'ok'
        elif r and r.get('check') in ('far', 'not_found'):
            v = review.get(story['id'])
            why = v['action'] if v else 'unreviewed'
            if v and v['action'] == 'keep':
                point = (r['place'], r['lat'], r['lon'])
            elif v and v['action'] == 'fix':
                point = (v.get('place') or r['place'], v['lat'], v['lon'])
        else:
            why = r['precision'] if r else 'missing'
        counts[why] = counts.get(why, 0) + 1
        for k in ('place', 'lat', 'lon'):
            story.pop(k, None)
        if point:
            story['place'], story['lat'], story['lon'] = point
        with open(path, 'w', encoding='utf-8') as f:
            f.write(json.dumps(story, ensure_ascii=False, indent=2) + '\n')
    print(counts, 'placed:', sum(counts.get(k, 0) for k in ('ok', 'keep', 'fix')))


if __name__ == '__main__':
    main()
