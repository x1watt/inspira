import json, time, urllib.parse, urllib.request

UA = 'InspiraBuild/1.0 (offline quote app; maxbrito.x1@gmail.com)'

def get_json(url, params, tries=6):
    q = url + '?' + urllib.parse.urlencode(params)
    for i in range(tries):
        try:
            req = urllib.request.Request(q, headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except Exception as e:
            if i == tries - 1:
                raise
            wait = 30 * (i + 1) if '429' in str(e) else 2 * (i + 1)
            time.sleep(wait)

def download(url, path, tries=4):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=60) as r, open(path, 'wb') as f:
                f.write(r.read())
            return
        except Exception:
            if i == tries - 1:
                raise
            time.sleep(3 * (i + 1))
