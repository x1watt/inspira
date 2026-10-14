"""Checks every event in raw/*.jsonl against Wikidata.

For each event the English Wikipedia title is resolved to its Wikidata
item. The item's date (P585 point in time, else P580 start time) is
compared with the event's day, converting between Julian and Gregorian
when the calendars differ. Coordinates come from the item (P625) or from
its location (P276). Writes checked.jsonl next to this file, one line per
event with `qid` and a `check` object, and prints a summary.

Run: python3 -I tool/pipeline/events/verify.py
"""
import glob, json, math, os, sys, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
API = 'https://www.wikidata.org/w/api.php'
UA = 'InspiraBuild/1.0 (https://github.com/x1watt/inspira)'
GREGORIAN = 'http://www.wikidata.org/entity/Q1985727'
JULIAN = 'http://www.wikidata.org/entity/Q1985786'


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


def astro(year):
    """Historical year (no year 0) to astronomical (1 BC = 0)."""
    return year + 1 if year < 0 else year


def jdn(y, m, d, julian):
    y = astro(y)
    a = (14 - m) // 12
    yy, mm = y + 4800 - a, m + 12 * a - 3
    n = d + (153 * mm + 2) // 5 + 365 * yy + yy // 4
    return n - 32083 if julian else n - yy // 100 + yy // 400 - 32045


def entities(ids=None, titles=None):
    out = {}
    keys = ids or titles
    for i in range(0, len(keys), 50):
        chunk = keys[i:i + 50]
        p = {'action': 'wbgetentities', 'format': 'json',
             'props': 'claims|sitelinks'}
        if ids:
            p['ids'] = '|'.join(chunk)
        else:
            p.update(sites='enwiki', titles='|'.join(chunk), redirects='yes',
                     sitefilter='enwiki')
        data = get_json(p)
        for qid, e in data.get('entities', {}).items():
            if 'missing' in e:
                continue
            out[qid] = e
        time.sleep(0.4)
    return out


def claim_values(e, prop):
    vals = []
    for c in e.get('claims', {}).get(prop, []):
        dv = c.get('mainsnak', {}).get('datavalue')
        if dv:
            vals.append(dv['value'])
    return vals


def wd_dates(e):
    """(year, month, day, calendar url) of day precision dates."""
    out = []
    # Point in time, start, end (battles known by the last day), founding,
    # publication, official opening, launch, first performance, discovery,
    # first flight, service entry.
    for prop in ('P585', 'P580', 'P582', 'P571', 'P577', 'P1619', 'P619',
                 'P1191', 'P575', 'P606', 'P729'):
        for v in claim_values(e, prop):
            if v.get('precision') != 11:
                continue
            t = v['time']
            sign = -1 if t[0] == '-' else 1
            y, m, d = t[1:].split('T')[0].split('-')
            out.append((sign * int(y), int(m), int(d), v['calendarmodel']))
    return out


def km(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = (math.sin((la2 - la1) / 2) ** 2
         + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2)
    return 6371 * 2 * math.asin(math.sqrt(h))


def main():
    events = []
    for path in sorted(glob.glob(os.path.join(HERE, 'raw', '*.jsonl'))):
        for line in open(path, encoding='utf-8'):
            if line.strip():
                ev = json.loads(line)
                ev['slice'] = os.path.basename(path)[:-6]
                events.append(ev)
    titles = sorted({e['wikipedia'] for e in events})
    items = entities(titles=titles)
    by_title = {}
    for qid, e in items.items():
        link = e.get('sitelinks', {}).get('enwiki', {}).get('title')
        if link:
            by_title[link] = qid
    # Redirected titles: ask once more one by one for the ones not matched.
    for t in titles:
        if t in by_title:
            continue
        data = get_json({'action': 'wbgetentities', 'format': 'json',
                         'sites': 'enwiki', 'titles': t, 'redirects': 'yes',
                         'props': 'info'})
        for qid, e in data.get('entities', {}).items():
            if 'missing' not in e:
                by_title[t] = qid
        time.sleep(0.4)
    missing_items = sorted({q for q in by_title.values()} - set(items))
    items.update(entities(ids=missing_items) if missing_items else {})
    locations = sorted({
        v['id'] for e in items.values() for v in claim_values(e, 'P276')
        if isinstance(v, dict) and 'id' in v})
    loc_items = entities(ids=locations) if locations else {}

    summary = {}
    with open(os.path.join(HERE, 'checked.jsonl'), 'w', encoding='utf-8') as f:
        for ev in events:
            qid = by_title.get(ev['wikipedia'])
            check = {}
            if not qid:
                check['date'] = 'no_item'
            else:
                ev['qid'] = qid
                item = items[qid]
                dates = wd_dates(item)
                mine_jul = ev['calendar'] == 'julian'
                mine = jdn(ev['year'], ev['month'], ev['day'], mine_jul)
                if not dates:
                    check['date'] = 'no_date'
                else:
                    ok = False
                    for y, m, d, cal in dates:
                        if jdn(y, m, d, cal == JULIAN) == mine:
                            ok = True
                        # Same digits in the other calendar: a calendar mixup,
                        # the day itself is what Wikipedia shows.
                        elif (y, m, d) == (ev['year'], ev['month'], ev['day']):
                            ok = True
                    check['date'] = 'match' if ok else 'mismatch'
                    if not ok:
                        check['wikidata_dates'] = [
                            f'{y}-{m:02d}-{d:02d} '
                            f'{"julian" if c == JULIAN else "gregorian"}'
                            for y, m, d, c in dates]
                coords = [(v['latitude'], v['longitude'])
                          for v in claim_values(item, 'P625')
                          if isinstance(v, dict) and 'latitude' in v
                          and v.get('globe', '').endswith('Q2')]
                if not coords:
                    for v in claim_values(item, 'P276'):
                        loc = loc_items.get(v.get('id', '')) if isinstance(v, dict) else None
                        if loc:
                            coords += [(c['latitude'], c['longitude'])
                                       for c in claim_values(loc, 'P625')
                                       if isinstance(c, dict) and 'latitude' in c]
                        if coords:
                            break
                if coords:
                    wd = coords[0]
                    if ev.get('lat') is None:
                        check['coords'] = 'wikidata_only'
                    else:
                        dist = km((ev['lat'], ev['lon']), wd)
                        check['coords'] = 'match' if dist <= 100 else 'far'
                        check['km'] = round(dist)
                    check['wikidata_coords'] = [round(wd[0], 4), round(wd[1], 4)]
                else:
                    check['coords'] = 'none' if ev.get('lat') is None else 'unchecked'
            ev['check'] = check
            for k in ('date', 'coords'):
                key = f'{k}:{check.get(k, "-")}'
                summary[key] = summary.get(key, 0) + 1
            f.write(json.dumps(ev, ensure_ascii=False) + '\n')
    print(len(events), 'events')
    for k in sorted(summary):
        print(f'  {k}: {summary[k]}')


if __name__ == '__main__':
    sys.exit(main())
