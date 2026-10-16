# Plan: zx in Inspira and an offline Wikipedia as a zx database

Status: phase 0 done with the mini ZIM (section 8); nothing in the app
yet. Written 2026-10-15.

Goal: read Wikipedia offline inside Inspira, without images, and ask it
questions fast: what happened on a date, what is near a place, what a
person took part in, which events relate to another event. The source is
a Kiwix ZIM file; the result is a `.zx` archive whose built-in database
(zxdb) holds the text and the indexes.

## 1. What zx gives us (from ~/code/x1watt/zx, version 0.5.0)

- Pure Dart: runs on Android, Linux, Windows, macOS; the web build has a
  read-only Data view that reads archives in blocks (range reads), so a
  local file works in the browser too.
- zxdb: SQLite dialect (joins, indexes, CTEs, prepared statements,
  streaming cursors), KV stores, time series, AS OF time travel; copy on
  write B+trees in 16 KiB pages, page cache, writer lock, worker isolate
  API (`ZxDatabaseAsync`).
- Compression per table: `fast` (LZ4, cold read about 130 us),
  `balanced` (LZMA2), `max` (zcm). zcm decodes at about 85 KB/s, so a
  cold read of a 256 KiB block takes seconds: `max` is wrong for an
  interactive encyclopedia. Use `balanced` for article text and `fast`
  for indexes.
- Measured: point lookup 1.4 to 2.6 us hot, sequential load 267k
  rows/s, 4 to 17 times smaller than SQLite on text.
- Has a zstd and an xz decoder (the two codecs ZIM clusters use).
- Missing for this job: a ZIM reader, full-text search over ordinary
  tables (today `fts_search` covers only file metadata and layers), a
  spatial index, a bulk page builder for very large sorted loads (open
  item in docs/zxdb-design.md 11.4).

## 2. Source: Kiwix ZIM files (download.kiwix.org, checked today)

| File | Size | Content |
|---|---|---|
| wikipedia_en_all_mini_2026-09.zim | 13 GB | lead section and infobox of every article |
| wikipedia_en_all_nopic_2026-06.zim | 49 GB | whole articles, no images |
| wikipedia_en_all_maxi_2026-08.zim | 119 GB | with images (not needed) |

About 6.9 million articles plus redirects. ZIM: a header, MIME list,
directory entries (URL, title, redirects) and clusters compressed with
zstd (older files: xz). Wikipedia text is CC BY-SA 4.0: the archive must
carry the license and attribution (a README.md inside the .zx, which zx
shows when the archive is opened).

Machine: 150 GB free on disk, 16 GB RAM (about 4 GB free while other
work runs), 16 threads. Enough for nopic plus the output, but the
conversion must cap its isolates and memory, and run when no Android or
Flutter build is going (the machine freezes under two heavy jobs).

## 3. Approach in one paragraph

Read the ZIM with a new zx format handler; parse each article's HTML in
worker isolates into plain text, sections, infobox fields, dates,
coordinates, the article's type (person, event, place, other) and its
links to other articles; load everything into a zxdb schema with sorted
bulk inserts; compute an importance weight per article from its incoming
links; fold the pages (LZMA2 for text, LZ4 for indexes) and write a
README with the license. Inspira opens the archive through zx in an
isolate and uses it in On this day, the map, a person or event page and
the quizzes. Start with the mini ZIM (leads and infoboxes are where the
dates, places and people are), then the nopic one for whole articles.

## 4. Phases

### Phase 0: spikes, 1 to 2 days, decides the numbers

- Download the mini ZIM (13 GB) and a tiny test ZIM (Kiwix's Ray Charles
  sample) for unit tests.
- Read 10,000 articles and check what survives Kiwix's HTML cleanup:
  infobox tables and their microformats (`bday`, `dday`, `dtstart`,
  `dtend`, `vcard`, `vevent`), coordinates (`<span class="geo">`),
  link targets, and whether the Wikidata id (QID) is anywhere in the
  page.
- Measure on this machine: zstd decode MB/s in Dart, HTML to text MB/s
  per isolate, LZMA2 page encode MB/s, final bytes per article.
- Output: the real size and time of the lite and full archives, and a
  go or change on the schema below.

### Phase 1: ZIM reader in the zx repo

- `lib/src/format/zim/`: header, MIME list, URL and title pointer lists,
  directory entries (content, redirect), clusters (zstd, xz, plain),
  blobs with extended (64 bit) offsets; a cluster cache.
- zx gains `zx l file.zim`, `zx x file.zim`, and in the app ZIM files
  open like folders. A Dart API `ZimArchive` to iterate articles in
  cluster order (sequential, fast) and to get one by URL or title.
- Tests on the small test ZIM, checked against libzim's listing.

### Phase 2: the extractor (Inspira repo, tool/pipeline/wikipedia/)

For each article, in worker isolates (cluster order, so each cluster is
decoded once):

- Text: headings, paragraphs and lists as light markdown; links kept as
  `[text](#id)` once ids are known; tables other than the infobox and
  navigation boxes dropped; references dropped (or kept as a last
  section, decided in phase 0).
- Infobox: key and value pairs as text, plus the parsed fields below.
- Dates: from microformats first, then infobox rows (Born, Died, Date,
  Founded, Signed...), then the first sentence ("(14 October 1066 ...)").
  Stored as year, month, day and precision (year, month or day); BC and
  Julian handled as in tool/pipeline/events (verify.py has the calendar
  code).
- Coordinates: the page's main coordinates (title coordinates), not
  every coordinate in tables.
- Type: person (vcard, Born or Died rows), event (vevent, battles,
  treaties, disasters, elections: infobox kind), place (coordinates and
  a settlement, building or site infobox), other.
- Event participants: infobox rows Combatants, Commanders, Participants,
  Belligerents, Location, Result, Part of; resolved to article ids.
- Links: every link to another article, redirects resolved to the
  target.

### Phase 3: the loader and the schema

```sql
CREATE TABLE page (
  id INTEGER PRIMARY KEY,         -- dense, in title order
  title TEXT NOT NULL,
  kind TEXT,                      -- person, event, place, other
  lead TEXT,                      -- first paragraph, for lists and cards
  weight INTEGER,                 -- importance 1 to 100 from incoming links
  lat REAL, lon REAL,
  cell INTEGER                    -- quadkey at zoom 12, for map queries
) WITH (compression = 'balanced');
CREATE INDEX page_title ON page(lower(title));  -- prefix search via a column
CREATE INDEX page_cell ON page(cell);

CREATE TABLE body (page INTEGER PRIMARY KEY, text TEXT)
  WITH (compression = 'balanced');              -- whole article (full tier)

CREATE TABLE redirect (title_lower TEXT PRIMARY KEY, page INTEGER);

CREATE TABLE date (                             -- one row per dated fact
  page INTEGER, role TEXT,                      -- birth, death, start, end, point, founded
  year INTEGER, month INTEGER, day INTEGER, precision TEXT,
  calendar TEXT
);
CREATE INDEX date_day ON date(month, day, role);
CREATE INDEX date_year ON date(year);
CREATE INDEX date_page ON date(page);

CREATE TABLE link (src INTEGER, dst INTEGER, role TEXT); -- role: body, participant, location, part_of
CREATE INDEX link_dst ON link(dst, role);       -- backlinks: what mentions a person or event
-- (src, dst) is the rowid order: loaded sorted by src

CREATE TABLE infobox (page INTEGER, key TEXT, value TEXT)
  WITH (compression = 'balanced');
```

- Loading: write each table sorted by its key so the B+tree only
  appends (267k rows/s measured); about 150 million link rows take
  roughly 10 minutes. Add the bulk page builder to zx if this proves
  slow.
- Weight: incoming body links, log scaled to 1..100 (pageview dumps can
  refine it later).
- Title search: prefix range scan on the lowercased title index;
  full-text search over article text needs a zx feature (`CREATE FTS
  INDEX ON body(text)`, reusing meta/fts.dart): phase 6.
- Map: the quadkey cell makes "inside this box" a few range scans and
  "nearest" a ring search; no R-tree needed.
- After loading: `fold()` with LZMA2 for text tables, LZ4 for indexes,
  then VACUUM; a README.md inside with the source ZIM name, the date and
  the CC BY-SA 4.0 notice.

Queries the app needs (each should take under 20 ms warm on a phone):

- On this day: `date` by (month, day), joined to `page`, ordered by
  weight.
- Near a place: `page` by cell ranges around the point, then distance.
- A person: their dates, birth and death places, and the events that
  link to them or that they link to (`link` both ways, `kind = 'event'`),
  as a timeline by date.
- Related events: events sharing participants or a `part_of` parent,
  then events close in date and place, ranked by shared links and
  weight.

### Phase 4: zx inside Inspira

- `pubspec.yaml`: `zx: path: ../zx` (or a git ref with a tag), the
  library only; tree shaking drops the codecs Inspira never calls.
- `lib/data/wiki_repository.dart`: opens the archive with
  `ZxDatabaseAsync` (queries off the UI isolate, docs/performance.md
  rule 1), prepared statements for the queries above, a small result
  cache.
- Where the file comes from: Settings, Offline Wikipedia: pick a .zx
  file on the device or download it (resumable, split into volumes of
  under 2 GB, since GitHub release assets are limited to 2 GB each; zx
  reads volumes). On the web: open a local file (zx reads it in blocks,
  nothing is uploaded); GitHub Pages cannot host it.
- Inspira works as now without the archive; every Wikipedia feature
  appears only when one is present.

### Phase 5: features in the app

- An offline article page (light markdown, links between articles,
  back stack); the Wikipedia buttons open it instead of the browser when
  the archive has the page.
- On this day: "More on this day" from Wikipedia under the curated
  events, ranked by weight; births and deaths on a separate tab.
- Map: a "Wikipedia" layer with every geotagged article (over a million
  in English), thinned by weight like today's markers; near me lists
  them too.
- Person and event pages: timeline, places on a small map, related
  events.
- Quizzes: "When did this happen?" and "Where did this happen?" from
  Wikipedia events the user opened.

### Phase 6: full tier and later

- Repeat phases 2 and 3 on the nopic ZIM for whole articles (`body`).
- Full-text search in zx over table columns.
- Other languages (Portuguese, German), one archive each, linked by
  title or Wikidata id when phase 0 finds it.
- Optional Wikidata enrichment (exact dates, coordinates, participants
  by property) if the infobox parsing proves too noisy.

## 5. Size and time (estimates, phase 0 replaces them)

| | Lite (mini ZIM) | Full (nopic ZIM) |
|---|---|---|
| Download | 13 GB | 49 GB |
| Archive | about 2 to 3 GB | about 8 to 12 GB |
| Conversion | a few hours | most of a day |
| Target | phones and desktop | desktop, large phones |

## 6. Decisions for the owner

1. Start with the lite tier (mini ZIM), then full: recommended.
2. Article text compression `balanced` (LZMA2) rather than `max`
   (zcm decodes too slowly for reading): recommended.
3. ZIM reader and table full-text search go into the zx repo, the
   extractor into Inspira: recommended.
4. Hosting the archive: GitHub release volumes, or a server of yours
   with range requests (which would also let the web version read it
   remotely).
5. Wikidata enrichment now or only if infobox parsing is not good
   enough.

## 7. Risks

- Infobox formats vary a lot; dates and types will be wrong for some
  pages. Measure precision on a sample of 500 pages by hand in phase 0
  and accept or fix by kind.
- Kiwix may strip elements we rely on (coordinates, microformats);
  phase 0 checks before anything is built.
- Memory: the conversion must stream (one cluster at a time per
  isolate, spilling transactions, as zxdb already does past 128 MiB).
- Phone storage: the full tier is large; the lite tier is the default
  download.

## 8. Phase 0 results (mini ZIM, 2026-10-15)

Tools: `tool/wikizx/` (a Dart package of its own, zx as a path
dependency, not part of the app): `zim.dart` (the ZIM reader),
`extract.dart` (HTML to facts), `bin/convert.dart`, `bin/finish.dart`
(fold and vacuum), `bin/slim.dart` (the app's lookup tables),
`bin/validate.dart`, `bin/query.dart`, `bin/probe.dart`, `bin/dump.dart`.
Output in `build/wiki/` (not in git).

### What the ZIM holds

- wikipedia_en_all_mini_2026-09.zim: 14.4 GB, 18.1 million entries:
  7.33 million articles, 10.76 million redirects, 57,188 zstd clusters.
- Kept by Kiwix: infobox tables (72% of articles), birth date
  microformats (`bday`, 26%; death dates have none, the Died row is
  parsed), `dtstart` (11%), title coordinates (`<span class="geo">`,
  13%), links (`<a rel="mw:WikiLink" href="Title">`). No Wikidata ids.
- Military infoboxes nest tables and use header rows (Belligerents,
  Commanders and leaders): parsed by header cell, not by row class.

### The archive

| | |
|---|---|
| Pages | 7,306,588 (0.3% failed to parse): person 1,327,855, place 1,112,642, event 72,712, disambiguation 284,364, other 4,509,015 |
| With coordinates | 1,036,838 |
| Dated facts | 3,320,480 (birth, death, start, end, point) |
| Links | 67,400,116, both directions |
| Redirects | 10.7 million |
| Size | 2.8 GiB folded (15 GB before the fold), plus 0.2 GB for the lookup tables |
| Time | about 1 hour on this machine, 5 parse workers |
| Memory | 0.9 to 1.3 GB while loading pages (after the fixes below) |

Schema as built (differs from section 4 where the test showed it had
to): links in `link` keyed `src << 23 | dst` and `backlink` keyed
`dst << 23 | src`, sorted on disk before loading (an index on 67 million
random rows was too slow); facts keyed `page * 16 + n`; infobox rows
`page * 256 + n`; `page_meta` (title, kind, coordinates, incoming links)
LZ4 compressed apart from the lead text; `day_fact` keyed by (month,
day, importance) with the title copied in.

### Accuracy against Inspira's 1000 verified events

| | |
|---|---|
| Article found (title or redirect) | 99.1% |
| Has a date | 62.5% |
| Year right, when there is a date | 93% |
| Exact day right, when there is a date | 67% |
| Has coordinates | 26.9% (the mini ZIM keeps few) |
| Coordinates within 50 km | 95.4% |
| Classified as an event | 42.6% |

Many of Inspira's events point at a person or a city (Pompey, Baghdad),
so part of the 57% is right. Real misses: earthquakes and disasters
(no Date row; Magnitude, Casualties, Areas affected), and articles
without an infobox (Crossing the Rubicon, Great Fire of Rome). Next
fixes: those labels, the lead's first date for pages without an
infobox, and the full nopic ZIM for coordinates.

### Query times (desktop, AOT)

| Question | Cold | Warm |
|---|---|---|
| Title lookup (index, NOCASE) | 27 to 35 ms | 0.1 ms |
| On this day, top facts (`day_fact`) | 6 ms | 0.1 ms |
| Events linking to a person (Napoleon) | 734 ms | 7.5 ms |
| Events related to an event (shared links; Battle of Hastings gives Stamford Bridge, Northumbrian Revolt...) | 1.2 s | 17 ms |
| Places near a point (Lisbon, cell range) | 146 ms | 2 ms |

Lesson: never join millions of rows to a table whose rows carry text
compressed with LZMA2 (each lookup decodes a 256 KiB block, about 6 ms):
on this day through `page` took 45 s, through `page_meta` 6 s, through
`day_fact` 6 ms. The app gets tables shaped for each question.

### zx fixes made during the test (x1watt/zx)

1. CREATE INDEX on a filled table read every row into memory (killed at
   4 GB on 7.3 million pages): it now streams in sorted 32 MiB chunks.
2. A table created and filled in one transaction never used the delta
   layer: random index writes rewrote the same leaves at every spill
   (6 million keys wrote 7.7 GB). Such trees now switch within the
   transaction: 3 million keys 43 s instead of 110 s, memory flat.
3. The synchronous worker pool kept every block it handed to a worker
   until the operation ended (the VM holds a spawn message until the
   caller's event loop runs): a fold of the 15 GB database grew past
   4.4 GB and was killed. Blocks now go by file: the fold ran in under
   160 MB. This also bounds the memory of `zx a` and extraction.

4. INSERT ... SELECT streams its rows when the SELECT does not read the
   table it writes; DELETE and simple UPDATEs keep only rowids between
   their two passes (2 million rows: 616 MB instead of 853 MB to copy).
5. Inside an explicit transaction the statement undo log read the old
   value of every index key it wrote (a cold page each): 10 million
   random index keys in one transaction now take 149 s instead of 858 s.

Still open in zx: the undo log of one huge statement inside BEGIN ...
COMMIT holds an entry per key (autocommit statements have none).

### This machine

earlyoom kills any process when free memory drops under 10%; with the
other programs running, about 3 to 5 GB were free. The converter keeps
link keys in sorted run files on disk (`spill_sort.dart`) and frees its
lookup arrays as soon as it can, so it stays near 1.3 GB.

## 9. Better locations (first measurements, 2026-10-15)

Goal: coordinates for as many events, buildings and places as possible,
reusable for every update and every language. Join key: the Wikidata id
(Q number); every language's articles map to it through that language's
`page_props` table, so coordinates are gathered once.

Measured on the verified events that have coordinates and a Wikidata id
(892; their coordinates were checked against Wikidata when they were
made, so agreement with Wikidata's own coordinates is partly circular):

| Source | Events with a usable point | Within 50 km |
|---|---|---|
| Mini ZIM (title coordinates in the HTML) | 26.9% | 95.4% |
| English `geo_tags` table (0.05 GB), primary or other | 36.8% | 92.1% |
| Wikidata, own coordinates (P625) | 43.0% | 93% |
| Wikidata, coordinates of the location (P276) | +18.8% | 70% |
| Wikidata, coordinates of the area (P131) | +1.3% | 8 of 12 |
| Wikidata, country only (P17) | 12.2% | not a point |
| Nothing | 24.6% | |

Whole English Wikipedia: `page_props` links 10.36 million pages to
Wikidata; `geo_tags` has 1.26 million primary coordinates, only 11,056
of them typed as events. Events are where Wikipedia's coordinates are
thinnest and Wikidata's location (P276) helps most.

Tools: `lib/sqldump.dart` (streams any MediaWiki SQL dump),
`bin/geocheck.dart` (geo_tags and page_props against the verified
events, 77 s, 46 MB), `scripts/wdcheck.py` (Wikidata tiers through the
API, for samples only).

### 9.1 Full Wikidata pass (2026-10-16)

Pipeline, rerunnable for every new dump and every language:

1. `lbzip2 -dc latest-truthy.nt.bz2 | grep -F -f scripts/wd_patterns.txt
   | bin/wdfilter | zstd > wd_facts.tsv.zst`: 657.8 million candidate
   lines, 304.4 million facts kept, 3.5 GB, 40 min on 16 threads
   (single threaded `bzip2` would take about 4.2 h). The 43.5 GB dump is
   read once and not needed afterwards.
2. `bin/geobuild.dart wd_facts.tsv.zst
   wikidatawiki-latest-wb_items_per_site.sql.gz geo.zx [--langs ...]`:
   34 min, peak 1.9 GB RSS, `geo.zx` 860 MiB for en, pt, de, es, fr, it.
   The truthy dump has no sitelinks, so the 1.9 GB sitelinks table gives
   the article titles (24.6 million articles, 15.2 million items).

`geo.zx` contents: `sitelink` (lang, title NOCASE, qid), `point` (one per
item, with the tier it came from), `person_place` (birth, death,
burial), `item_type` (P31), `item_date` (point, start, end, inception,
dissolved, birth, death, opening). 12.4 million Wikidata items have
their own coordinates; 2.66 million of the linked items got a point
(own 2.07 M, location 190 k, headquarters 218 k, area 183 k, terrain
2.4 k) and 3.37 million person places were resolved.

Against the 892 verified events (`bin/geovalidate.dart`):

| Tier | Events | Within 50 km | Within 5 km |
|---|---|---|---|
| Own (P625) | 43.0% | 92.7% | 76.3% |
| Location (P276) | 18.9% | 69.2% | 60.4% |
| Headquarters (P159) | 1.3% | 7 of 12 | 6 of 12 |
| Area (P131, up to 4 hops) | 1.1% | 7 of 10 | 5 of 10 |
| None | 35.5% | | |
| **With a point** | **64.5%** | | |

Same result as the API sample (63%), so the offline pass is right.
Dates: 594 events dated by Wikidata, year right 93.9%, day right 67.2%.
English `geo_tags` on top adds only 1.3% (3 of 12 within 50 km) and
agrees with Wikidata on 96.8% of the shared ones, so it is dropped.

Queries (warm): title to point in any of the 6 languages 1 to 8 ms
(26 ms cold), a person's birth, death and burial 0.5 ms.

Typical misses: events whose own coordinates are a country centroid
(India becomes independent, 868 km; Union of South Africa, 549 km) and
treaties located at the capital that signed rather than where it was
signed. A check could prefer P276 when the own point is within a few km
of the P17 country's own point.

Next: GeoNames (allCountries, about 0.4 GB) for locations given as text
in the article lead or infobox; a review of the most linked event items
still without a point; the centroid check above; joining `geo.zx` into
each language archive by Q number.
