"""Second check for events Wikidata could not confirm: is the day written
in the English Wikipedia article?

For every event in checked.jsonl whose date is not a Wikidata `match`, the
title is resolved (redirects followed; a title that does not exist is
replaced by the top search hit, recorded as `resolved_title`), the plain
text of the article is fetched and searched for the day in the usual
spellings ("20 July 1969", "July 20, 1969", "15 March 44 BC"). For
Gregorian dates before 1918 the Julian equivalent is searched too (Old
Style dates in British and Russian articles). Adds `text` (found or
not_found) to each event's check and rewrites checked.jsonl.

Run after verify.py: python3 -I tool/pipeline/events/check_text.py
"""
import json, os, re, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
API = 'https://en.wikipedia.org/w/api.php'
UA = 'InspiraBuild/1.0 (https://github.com/x1watt/inspira)'
MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
          'August', 'September', 'October', 'November', 'December']


def get_json(params, tries=6):
    q = API + '?' + urllib.parse.urlencode(params)
    for i in range(tries):
        try:
            req = urllib.request.Request(q, headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except Exception as e:
            if i == tries - 1:
                raise
            time.sleep(30 * (i + 1) if '429' in str(e) else 3 * (i + 1))


def jdn_gregorian(y, m, d):
    a = (14 - m) // 12
    yy, mm = y + 4800 - a, m + 12 * a - 3
    return d + (153 * mm + 2) // 5 + 365 * yy + yy // 4 - yy // 100 + yy // 400 - 32045


def julian_from_jdn(j):
    c = j + 32082
    d = (4 * c + 3) // 1461
    e = c - 1461 * d // 4
    m = (5 * e + 2) // 153
    day = e - (153 * m + 2) // 5 + 1
    month = m + 3 - 12 * (m // 10)
    year = d - 4800 + m // 10
    return year, month, day


def patterns(y, m, d):
    name = MONTHS[m - 1]
    yr = f'{-y} BC' if y < 0 else str(y)
    yr_re = re.escape(yr) if y < 0 else rf'(?:AD )?{yr}'
    return [
        rf'\b{d}(?:st|nd|rd|th)? {name},? {yr_re}\b',
        rf'\b{name} {d}(?:st|nd|rd|th)?,? {yr_re}\b',
        # "on 20 July" with the year nearby (same sentence)
        rf'\b{d} {name}[^.]{{0,80}}\b{re.escape(yr)}\b',
        rf'\b{re.escape(yr)}\b[^.]{{0,80}}\b{d} {name}\b',
        rf'\b{name} {d}\b[^.]{{0,80}}\b{re.escape(yr)}\b',
        rf'\b{re.escape(yr)}\b[^.]{{0,80}}\b{name} {d}\b',
    ]


def article(title):
    """(resolved title, plain text) or (None, '')."""
    data = get_json({'action': 'query', 'format': 'json', 'redirects': 1,
                     'prop': 'extracts', 'explaintext': 1, 'titles': title})
    for page in data.get('query', {}).get('pages', {}).values():
        if 'missing' not in page and 'extract' in page:
            return page['title'], page['extract']
    hits = get_json({'action': 'query', 'format': 'json', 'list': 'search',
                     'srsearch': title, 'srlimit': 1})
    hits = hits.get('query', {}).get('search', [])
    if not hits:
        return None, ''
    time.sleep(0.3)
    return article(hits[0]['title']) if hits[0]['title'] != title else (None, '')


def main():
    path = os.path.join(HERE, 'checked.jsonl')
    events = [json.loads(l) for l in open(path, encoding='utf-8') if l.strip()]
    counts = {}
    for ev in events:
        c = ev['check']
        if c.get('date') == 'match':
            continue
        title, text = article(ev['wikipedia'])
        time.sleep(0.3)
        if title and title != ev['wikipedia']:
            c['resolved_title'] = title
        dates = [(ev['year'], ev['month'], ev['day'])]
        if ev['calendar'] == 'gregorian' and 1582 <= ev['year'] < 1918:
            dates.append(julian_from_jdn(jdn_gregorian(*dates[0])))
        found = any(re.search(p, text) for dt in dates for p in patterns(*dt))
        c['text'] = 'found' if found else ('not_found' if title else 'no_article')
        counts[c['text']] = counts.get(c['text'], 0) + 1
    with open(path, 'w', encoding='utf-8') as f:
        for ev in events:
            f.write(json.dumps(ev, ensure_ascii=False) + '\n')
    print(counts)


if __name__ == '__main__':
    main()
