# Plan: the offline Wikipedia database online, queried in place

Status: plan (2026-10-16). Host decided: a Hugging Face dataset (section
2a). The zx side is done and tested (part sets and redirect caching,
x1watt/zx `docs/architecture.md` section 21); the upload and the app side
are the steps below.

Goal: put the whole Wikipedia database of `docs/plan-offline-wikipedia.md`
(`en_mini.zx`, 3.2 GB, and `geo.zx`, 1.0 GB) on GitHub, so that the web
version of Inspira searches and reads it where it is, fetching only the
few blocks each question needs, without downloading the database.

## 1. What zx does now

- **Part sets.** `zx parts split -size=95m FILE` cuts any file into parts
  of 95 MiB (`FILE.001`, `FILE.002`, ...) with a manifest `FILE.parts`
  (JSON: sizes and SHA-256 of the parts). `zx parts check`, `join` and
  `list` go with it. A part's file in the manifest may be a relative URL
  (`../inspira-wiki-2/en_mini.zx.012`), so one set can spread over
  several sites.
- **Reading in place.** zx reads a set as one read-only stream, opening a
  part only when a read reaches it and keeping at most four open.
  Natively `zx sql FILE` and `ZxDatabase.open(FILE, readOnly: true)` read
  `FILE.parts`; in the browser the zx web engine opens the manifest's URL
  and reads each part with HTTP range requests in 64 KiB blocks. Queries
  run unchanged (`db.open`, `db.sql`).
- **Measured** on the English Wikipedia test database cut into 33 parts:
  opening it takes 2 requests (82 KiB); four cold questions (a title, 20
  facts of a day, the links to an article, an article's lead) take 27
  requests and 3.3 MiB and touch 10 of the 33 parts. Warm questions need
  no request. In headless Chromium a database of 49 parts on another
  origin answered by its manifest's URL in 5 requests.

## 2. GitHub limits that shape the layout

| Limit | Value | Consequence |
|---|---|---|
| File size in a repository | 100 MB (warning at 50 MB) | parts of 95 MiB |
| Size of a published Pages site | 1 GB | at most 9 parts per site |
| Repository size | about 1 GB recommended, 5 GB strongly | one copy of the data per repository, history rewritten on update |
| Pages bandwidth | soft limit 100 GB a month | about 30,000 cold sessions of 3 MiB a month |
| Pages builds | 10 an hour | a data update is one push per repository |
| Release assets | 2 GB per file, but no CORS headers | the browser can not read them (zx reports them as blocked) |
| Git LFS | files not served by Pages | not usable |

Checked today: Pages answers `Range: bytes=0-9` with 206 and sends
`Access-Control-Allow-Origin: *`, `Accept-Ranges: bytes` and an ETag.

**Same origin.** Every project site of the account is under
`https://x1watt.github.io/`, so `x1watt.github.io/inspira/` (the app)
and `x1watt.github.io/inspira-wiki-1/` (data) are one origin: no CORS
question at all, and the browser's cache works across them.

**Native (2026-10-16, owner):** Android and desktop download the database
as an option (Me, Offline Wikipedia) and read it from the device;
done for desktop and Android code, tested on the Linux desktop
(`docs/architecture.md` section 6). The web reads the hosted copy in
place, with the warm set of section 2a.

## 2a. Decision: a Hugging Face dataset

The owner chose Hugging Face (2026-10-16) over GitHub Pages: it is made
for hosting large public datasets (no file or site limit to work around,
no question of Pages' policy), its Xet storage deduplicates chunks so an
update uploads mostly what changed, and a dataset card carries
Wikipedia's CC BY-SA license and attribution.

Checked from here: `huggingface.co/datasets/USER/NAME/resolve/main/FILE`
answers a Range request with a 302 to a signed CDN URL (valid one hour,
the redirect never cached), both with CORS headers, and the CDN answers
206 with Content-Range. Per request: 0.16 s for the redirect and about
0.17 s for the range from the CDN (Pages: 0.05 s). zx now keeps the
signed URL (`RedirectCachingTransport`), so only the first request of a
file in an hour pays the redirect: about 0.17 s per request, roughly 3
times Pages, so a cold question of 8 to 13 requests takes 1.5 to 2.5 s.

Layout on Hugging Face: one dataset repository (for example
`USER/inspira-wikipedia`), the database as one file (no 100 MB limit) and
a manifest with a single part, so the web engine reads it in 64 KiB
blocks with one redirect an hour:

    en_mini.zx          (later inspira_wiki.zx, section 5)
    en_mini.zx.parts    {"zxParts": 1, ..., "parts": [{"file": "en_mini.zx", ...}]}
    README.md           dataset card: source dumps, license, how it is built

The app reads `https://huggingface.co/datasets/USER/inspira-wikipedia/resolve/main/en_mini.zx.parts`.
Pinning a revision (`resolve/<commit>/...`) instead of `main` keeps a
session on one version while a new one is uploaded.

**Published** (2026-10-16): https://huggingface.co/datasets/maxbrito/inspira-wikipedia
holds `en_mini.zx`, `geo.zx`, their manifests and the dataset card
(`tool/wikizx/scripts/publish_hf.sh`; 4.2 GB at about 3 MiB/s).

**Measured in a browser** (headless Chromium here in Germany, zx
`tool/web_check/remote_bench.sh`, the four test questions: 20 facts of a
day, a title through its index, the count of the links to it, a lead):

| Run | Requests | Bytes | Cold, all four |
|---|---|---|---|
| 64 KiB blocks, CDN cold (first ever read) | 33 | 4.1 MiB | 21.9 s |
| 1 MiB blocks | 25 | 29 MiB | 15.2 s |
| 256 KiB blocks | 30 | 9.5 MiB | 12.5 s |
| 64 KiB blocks, CDN warm | 33 | 4.1 MiB | 13.0 s |

Opening takes 2 requests (1.5 to 3 s); warm questions take 1 ms. The
signed CDN URL answers a 4 KiB range in about 0.7 s and a 4 MiB range in
about 1.0 s (first byte after 0.17 s, then the CDN of Hugging Face's Xet
storage assembles the range), 0.35 s when the CDN has the range already.
So the cost is the number of requests made one after another (about 10
per cold question, one per level of the trees it walks), not the bytes:
block size barely matters, a CDN warmed by earlier readers helps (40%).

Warm set done (zx `zx parts warm`, 2026-10-16): the hosted manifest of
`en_mini.zx` lists 1.9 MB (15 ranges) that the web engine fetches in
parallel at open; four new cold questions then took 8.9 s and 19
requests instead of 14.3 s and 34, and opening 0.75 s instead of 1.5 s.

Ideas before it, kept for reference: (1) a warm set, the
byte ranges the app's questions always touch first (roots and upper
levels of the indexes, the day table), recorded once and listed in the
manifest, fetched in parallel when the database opens; (2) the web
database of section 5 with bigger pages (fewer tree levels); (3) parallel
range requests for the leaves a query will read (needs an asynchronous
step before the synchronous query in the zx engine).

Sections 3 and 7 describe the GitHub Pages layout, kept as the fallback:
moving there only changes the manifest's URLs.

## 3. Layout (GitHub Pages, fallback)

Data repositories `x1watt/inspira-wiki-1` ... `inspira-wiki-N`, each with
GitHub Pages on a `gh-pages` branch holding at most 9 parts (under
900 MB):

    inspira-wiki-1/  en_mini.zx.parts  geo.zx.parts  en_mini.zx.001 ... .009
    inspira-wiki-2/  en_mini.zx.010 ... .018
    inspira-wiki-3/  en_mini.zx.019 ... .027
    inspira-wiki-4/  en_mini.zx.028 ... .033
    inspira-wiki-5/  geo.zx.001 ... .009    (geo.zx: 11 parts)
    inspira-wiki-6/  geo.zx.010 ... .011

The manifests name each part by its URL relative to the manifest
(`../inspira-wiki-2/en_mini.zx.010`). `tool/wikizx/scripts/publish.sh`
(to write) does the split, rewrites the part paths to their sites, and
force-pushes one orphan commit per repository, so a repository always
holds one copy of the data and never grows with updates. The app reads
`https://x1watt.github.io/inspira-wiki-1/en_mini.zx.parts`.

Six repositories for 4.2 GB is the size of today's files. Section 5
makes them smaller first.

## 4. The app

- **Web.** Inspira's web build carries the zx engine: `zx_engine.wasm`,
  its `.mjs` and `zx_engine_worker.js`, about 2.4 MB (0.9 MB gzipped),
  built by zx's `tool/build_web.sh` and copied into `web/zx/` by the
  Pages workflow. The app talks to it through `package:zx/zx_client.dart`
  (a git dependency on x1watt/zx; the client compiles with dart2js and
  dart2wasm, the engine runs in its own worker, so the UI isolate never
  blocks). One `url` call per database at the first Wikipedia question,
  then `db.sql`. The engine is loaded only when a Wikipedia feature is
  opened, so the start of the app does not change.
- **Android and desktop.** zx reads synchronously, and Dart has no
  synchronous HTTP outside the browser, so the native app can not read
  ranges the same way. Two options for the owner: (a) the native app
  queries the same hosted data through a small range cache that downloads
  64 KiB blocks ahead of a query in a background isolate (work in zx:
  an asynchronous prefetch step before the synchronous query), or (b)
  the native app offers a download of the slimmed database (section 5)
  over Wi-Fi and reads it from files, offline. (b) works with today's zx
  and matches "offline first"; (a) is the same experience as the web.
- **What the app asks** (all through tables shaped for the question, as
  `docs/plan-offline-wikipedia.md` requires: no join of many rows to
  LZMA2-compressed text):
  - On this day: `day_fact` by day, most linked first (8 requests cold).
  - A person or event page: the title through its index, the lead
    (one block), its facts and infobox rows.
  - Related events and people: `backlink` and `link` ranges.
  - Near me: `page_meta` by grid cell, and `geo.zx`'s points (the map
    already ships 20,000 of them, `assets/wiki_places.json`).
  - Search: title prefix through the NOCASE title index (a range scan:
    a few requests). Full text search (zx's full-text index) only after
    measuring its size.

## 5. Make the database smaller for the web first

Every gigabyte saved is a repository less and fewer blocks per question.

1. Measure the size of each table and index of `en_mini.zx` (a zx
   `table_stats`-style query, or a copy without each table).
2. A web database `inspira_wiki.zx` with only what section 4 asks:
   `page_meta`, `page` leads (balanced compression, short leads),
   `day_fact`, `fact`, the title and cell indexes, and the link graph
   only if related events stay a feature (the 67 million links in both
   directions are likely the largest part).
3. Leads with `balanced` (LZ4-class) compression instead of `max`: a
   cold lead then costs one small block instead of a 256 KiB LZMA2 block.
4. Fold and vacuum before splitting, so the file holds one generation.
5. Merge `geo.zx` into the same file (points by Q number, sitelinks for
   the English titles only), so one manifest serves everything.

Target: under 2 GB, three data repositories.

## 6. Steps

1. Section 5: measure, build `inspira_wiki.zx`, record sizes and query
   times in `docs/plan-offline-wikipedia.md`.
2. `tool/wikizx/scripts/publish.sh`: split, write the manifest with
   site-relative URLs, push the data repositories (owner creates them and
   turns Pages on). Check with `curl -r` that a part answers 206 and is
   not compressed by the server (unknown extensions are served as
   `application/octet-stream`).
3. A test page (no app change yet): the zx online archive manager at
   `x1watt.github.io/zx/online/` opens a URL; give it the manifest's URL
   and run the section 4 queries in its SQL view. Record requests, bytes
   and times on a phone.
4. Inspira web: the zx client and engine in the build, a
   `WikiRepository` behind an interface (web: the engine; tests: a fake),
   first feature "More on this day" under the curated events, then person
   and event pages, related items, search.
5. Native: the owner's choice of section 4 (a) or (b).
6. Updates: rebuild from new dumps (`docs/plan-geofill.md` section 7 and
   10), publish again; the app reads the manifest at start of a session,
   so a new set is picked up without an app release. Keep the old set
   until the new one is published (manifest last), so readers in the
   middle of a session never see mixed parts.

## 7. Risks

- **Pages policy.** GitHub Pages is meant for websites, not file hosting,
  and asks to stay within its limits. A data site read by its own app is
  a website's assets, but several GB over six repositories is at the edge.
  If GitHub objects, the same part sets work unchanged from any host that
  serves ranges with CORS, by changing the manifest's URLs: Cloudflare R2
  (no egress fees, 10 GB free), or a Hugging Face dataset.
- **Latency.** Each request is a round trip (synchronous requests in the
  worker, one after another): about 7 to 13 requests per cold question,
  0.3 to 1 s on a good connection, more on mobile. Warm questions are
  instant (the block caches of the open parts). If it is too slow: fewer
  index levels (bigger pages for the read-only web database), and
  prefetching the top of each index when the database opens.
- **Bandwidth.** 3 MiB per cold session: about 30,000 a month within the
  soft limit. The browser cache (ETag) saves repeat visits.
- **Consistency.** A part replaced while a session reads the old set:
  parts carry SHA-256 in the manifest and each part's length is checked;
  publish new parts under new names (a version in the file name) and the
  manifest last.

## 8. Decisions for the owner

1. Host: GitHub Pages over several data repositories (section 3), or
   Cloudflare R2 from the start.
2. Native app: hosted ranges with prefetch (zx work) or a downloadable
   slim database (offline).
3. Which features need the link graph (it decides the size).
4. Update cadence (monthly dumps, or yearly).
