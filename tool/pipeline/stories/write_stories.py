"""Writes reviewed story entries to <project>/stories/<category>/<key>.json.

Usage: python3 -I write_stories.py <work dir> <project dir>
Reads <work>/raw/*.jsonl and applies <work>/review/*.jsonl, where each
review line is {"key": ..., "action": "keep" | "drop" | "fix", "fields":
{...}, "why": ...}. "fix" overwrites the given fields.
"""
import glob, json, os, re, sys

work, project = sys.argv[1], sys.argv[2]
CATS = {'relations', 'leadership', 'team', 'family', 'strategy'}
KINDS = {'story': {'fable', 'parable', 'folktale', 'literature'},
         'history': {'documented', 'anecdote', 'legend'},
         'study': {'study'}}
REPL = {'—': ', ', '–': ', ', '‘': "'", '’': "'",
        '“': '"', '”': '"', '…': '...', '→': 'to',
        ' ': ' '}

def tidy(s):
    for a, b in REPL.items():
        s = s.replace(a, b)
    s = re.sub(r' -- | - ', ', ', s)
    s = re.sub(r'[ \t]+', ' ', s)
    s = re.sub(r' ,', ',', s).replace(',,', ',')
    return s.strip()

reviews = {}
for f in sorted(glob.glob(os.path.join(work, 'review', '*.jsonl'))):
    for line in open(f, encoding='utf-8'):
        if line.strip():
            r = json.loads(line)
            reviews[r['key']] = r

items, seen_keys, seen_titles, problems = [], set(), set(), []
stats = {'dropped': 0, 'fixed': 0, 'unreviewed': 0}
for f in sorted(glob.glob(os.path.join(work, 'raw', '*.jsonl'))):
    for n, line in enumerate(open(f, encoding='utf-8'), 1):
        if not line.strip():
            continue
        try:
            e = json.loads(line)
        except ValueError as ex:
            problems.append(f'{f}:{n} bad json {ex}')
            continue
        r = reviews.get(e.get('key'))
        if r is None:
            stats['unreviewed'] += 1
        elif r['action'] == 'drop':
            stats['dropped'] += 1
            continue
        elif r['action'] == 'fix':
            e.update(r.get('fields') or {})
            stats['fixed'] += 1
        for k, v in list(e.items()):
            if isinstance(v, str):
                e[k] = tidy(v) if k != 'text' else '\n\n'.join(
                    tidy(p) for p in re.split(r'\n\s*\n', v) if p.strip())
        key = re.sub(r'[^a-z0-9-]+', '-', e.get('key', '').lower()).strip('-')
        title_norm = re.sub(r'[^a-z0-9]', '', e.get('title', '').lower())
        miss = [k for k in ('category', 'kind', 'title', 'text', 'lesson',
                            'source', 'basis') if not e.get(k)]
        if not key or miss:
            problems.append(f'{f}:{n} {key} missing {miss}')
            continue
        if e['category'] not in CATS or e['basis'] not in KINDS.get(e['kind'], ()):
            problems.append(f"{f}:{n} {key} bad category/kind/basis "
                            f"{e['category']}/{e['kind']}/{e['basis']}")
            continue
        words = len(e['text'].split())
        if not 90 <= words <= 360:
            problems.append(f'{f}:{n} {key} text {words} words')
        if key in seen_keys or title_norm in seen_titles:
            problems.append(f'{f}:{n} {key} duplicate, skipped')
            continue
        seen_keys.add(key)
        seen_titles.add(title_norm)
        year = e.get('year')
        out = {
            'id': f'story-{key}',
            'category': e['category'],
            'kind': e['kind'],
            'title': e['title'],
            'text': e['text'],
            'lesson': e['lesson'],
            'people': e.get('people', ''),
            'date': e.get('date', ''),
            'year': year if isinstance(year, int) else None,
            'location': e.get('location', ''),
            'source': e['source'],
            'basis': e['basis'],
        }
        if e.get('source_url'):
            out['source_url'] = e['source_url']
        if e.get('caveat'):
            out['caveat'] = e['caveat']
        if out['year'] is None:
            del out['year']
        items.append(out)

root = os.path.join(project, 'stories')
for old in glob.glob(os.path.join(root, '*', '*.json')):
    os.remove(old)
counts = {}
for it in items:
    d = os.path.join(root, it['category'])
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, it['id'][6:] + '.json'), 'w', encoding='utf-8') as fh:
        json.dump(it, fh, ensure_ascii=False, indent=2)
        fh.write('\n')
    c = counts.setdefault(it['category'], {})
    c[it['kind']] = c.get(it['kind'], 0) + 1
print('\n'.join(problems[:80]))
print(len(problems), 'problems;', stats)
for c in sorted(counts):
    print(c, sum(counts[c].values()), counts[c])
print('total', len(items))
