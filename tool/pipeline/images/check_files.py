"""Checks Commons files exist and are public domain or CC0.

Usage: check_files.py <in.jsonl> <out.jsonl>
Input lines need "file" (e.g. "File:The Oath of the Horatii.jpg" or without
prefix). Output lines add "ok", "license", "artist", "title_meta", "date",
"url" (file page), "thumb_ok" and "width"/"height". Batched 40 per request.
"""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from common import get_json

PD = re.compile(r'^(public domain|pd\b|pd-|cc0|cc-zero|no restrictions)', re.I)

def clean(html):
    return re.sub(r'<[^>]+>', '', html or '').strip()

rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for r in rows:
    f = r['file'].strip()
    if not f.lower().startswith('file:'):
        f = 'File:' + f
    r['file'] = f.replace('_', ' ')
out = open(sys.argv[2], 'w')
for i in range(0, len(rows), 40):
    batch = rows[i:i + 40]
    res = get_json('https://commons.wikimedia.org/w/api.php', {
        'action': 'query', 'format': 'json', 'prop': 'imageinfo',
        'iiprop': 'extmetadata|size|url', 'titles': '|'.join(r['file'] for r in batch),
        'redirects': 1})
    q = res.get('query', {})
    norm = {n['from']: n['to'] for n in q.get('normalized', [])}
    redir = {n['from']: n['to'] for n in q.get('redirects', [])}
    pages = {p['title']: p for p in q.get('pages', {}).values()}
    for r in batch:
        t = norm.get(r['file'], r['file'])
        t = redir.get(t, t)
        p = pages.get(t, {})
        ii = (p.get('imageinfo') or [{}])[0]
        md = ii.get('extmetadata', {})
        lic = clean(md.get('LicenseShortName', {}).get('value'))
        r.update({
            'file': t,
            'exists': bool(ii),
            'license': lic,
            'ok': bool(ii) and bool(PD.match(lic)),
            'artist': clean(md.get('Artist', {}).get('value'))[:120],
            'date': clean(md.get('DateTimeOriginal', {}).get('value'))[:60],
            'title_meta': clean(md.get('ObjectName', {}).get('value'))[:160],
            'url': ii.get('descriptionurl', ''),
            'src': ii.get('url', ''),
            'width': ii.get('width', 0), 'height': ii.get('height', 0),
        })
        out.write(json.dumps(r) + '\n')
    out.flush()
    time.sleep(1)
print('checked', len(rows))
