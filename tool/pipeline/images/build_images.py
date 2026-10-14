"""Downloads, converts and writes bundled images plus assets/images.json.

Usage: build_images.py <work dir> <download dir> <project dir>
Reads work/picks_*.jsonl + work/candidates.jsonl (portraits),
work/pools.jsonl and work/events.jsonl (art). Only files whose Commons
license is public domain or CC0 are kept.
"""
import glob, hashlib, json, os, re, subprocess, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from common import get_json, download

work, dl, proj = sys.argv[1:4]
PD = re.compile(r'^(public domain|pd\b|pd-|cc0|cc-zero|no restrictions)', re.I)
clean = lambda h: re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', '', h or '')).strip()

def slug(s):
    return re.sub(r'[^a-z0-9]+', '-', s.lower()).strip('-')[:50] + '-' + \
        hashlib.md5(s.encode()).hexdigest()[:6]

def info(files, width):
    """file title -> metadata with a thumb url, for licensed files only."""
    out = {}
    files = sorted(set(files))
    for i in range(0, len(files), 40):
        res = get_json('https://commons.wikimedia.org/w/api.php', {
            'action': 'query', 'format': 'json', 'prop': 'imageinfo',
            'iiprop': 'extmetadata|url|size', 'iiurlwidth': width,
            'titles': '|'.join(files[i:i + 40]), 'redirects': 1})
        q = res.get('query', {})
        back = {}
        for n in q.get('normalized', []) + q.get('redirects', []):
            back[n['to']] = back.get(n['from'], n['from'])
        for p in q.get('pages', {}).values():
            ii = (p.get('imageinfo') or [None])[0]
            if not ii:
                continue
            md = ii.get('extmetadata', {})
            lic = clean(md.get('LicenseShortName', {}).get('value'))
            if not PD.match(lic):
                continue
            out[back.get(p['title'], p['title'])] = {
                'thumb': ii.get('thumburl') or ii['url'],
                'url': ii.get('descriptionurl', ''),
                'license': lic,
                'artist': clean(md.get('Artist', {}).get('value'))[:100],
                'title': clean(md.get('ObjectName', {}).get('value'))[:140],
                'date': clean(md.get('DateTimeOriginal', {}).get('value'))[:40],
            }
        time.sleep(1)
    return out

def fetch(meta, name, kind):
    src = os.path.join(dl, kind, name + os.path.splitext(meta['thumb'])[1][:5])
    os.makedirs(os.path.dirname(src), exist_ok=True)
    if not os.path.exists(src):
        download(meta['thumb'], src)
        time.sleep(0.5)
    dst_dir = os.path.join(proj, 'assets', 'images', kind)
    os.makedirs(dst_dir, exist_ok=True)
    dst = os.path.join(dst_dir, name + '.webp')
    if kind == 'avatars':
        args = ['-resize', '256x256^', '-gravity', 'north', '-extent', '256x256',
                '-quality', '78']
    else:
        args = ['-resize', '640x1138>', '-quality', '58']
    subprocess.run(['convert', src + '[0]', '-strip', *args, dst], check=True)
    return f'{kind}/{name}.webp'

def norm(f):
    f = f.strip().replace('_', ' ')
    return f if f.lower().startswith('file:') else 'File:' + f

# Portraits.
files_by_qid = {}
for l in open(os.path.join(work, 'candidates.jsonl')):
    r = json.loads(l)
    for h in r['hits']:
        files_by_qid[h['id']] = h['file']
picks = {}
for f in sorted(glob.glob(os.path.join(work, 'picks_*.jsonl'))):
    for l in open(f):
        if l.strip():
            p = json.loads(l)
            if p.get('id') and p['id'] in files_by_qid:
                picks[p['name']] = norm(files_by_qid[p['id']])
pmeta = info(picks.values(), 330)
avatars = {}
for name, f in sorted(picks.items()):
    m = pmeta.get(f)
    if m:
        try:
            avatars[name] = fetch(m, slug(f), 'avatars')
        except Exception as e:
            print('avatar failed', name, e)
print('avatars', len(avatars), 'of', len(picks))

# Art.
art_rows = []
for fn in ('pools.jsonl', 'events.jsonl'):
    p = os.path.join(work, fn)
    if os.path.exists(p):
        art_rows += [json.loads(l) for l in open(p) if l.strip()]
ameta = info([norm(r['file']) for r in art_rows], 960)
art = {}
for r in art_rows:
    f = norm(r['file'])
    m = ameta.get(f)
    if not m:
        print('art not free or missing', f)
        continue
    if f not in art:
        try:
            path = fetch(m, slug(f), 'art')
        except Exception as e:
            print('art failed', f, e)
            continue
        art[f] = {'file': path, 'title': r.get('title') or m['title'],
                  'artist': r.get('artist') or m['artist'],
                  'year': str(r.get('year') or m['date']),
                  'url': m['url'], 'license': m['license'], 'pools': []}
    a = art[f]
    if r.get('pool') and r['pool'] != 'event' and r['pool'] not in a['pools']:
        a['pools'].append(r['pool'])
    if r.get('story_id') and r['story_id'] not in a.setdefault('stories', []):
        a['stories'].append(r['story_id'])
manifest = {'avatars': avatars, 'art': list(art.values())}
with open(os.path.join(proj, 'assets', 'images.json'), 'w') as fh:
    json.dump(manifest, fh, ensure_ascii=False, indent=0)
pools = {}
for a in art.values():
    for p in a['pools'] or ['event']:
        pools[p] = pools.get(p, 0) + 1
print('art', len(art), pools)
