---
license: cc-by-sa-4.0
language:
- en
pretty_name: Inspira Wikipedia (zx databases)
tags:
- wikipedia
- wikidata
- history
- geography
size_categories:
- 1M<n<10M
---

# Inspira Wikipedia

Databases built from Wikipedia and Wikidata for the Inspira app
(https://github.com/x1watt/inspira), in the zx database format
(https://github.com/x1watt/zx). They are queried in place: the app's web
version reads only the byte ranges a question needs, so nothing is
downloaded whole.

## Files

| File | What |
|---|---|
| `en_mini.zx` | English Wikipedia (Kiwix "mini" dump): pages with their lead and kind, dated facts, infobox rows, the link graph, redirects, a table of dated facts by calendar day |
| `geo.zx` | Wikidata places: a point for each item with an article in en, pt, de, es, fr or it, with the way it was found; places of birth, death and burial; types; dates; article titles |
| `en_places.zx` | The map: about a million English articles with a point (events, castles, churches, museums, monuments, other buildings, nature, towns), keyed by map tile and ranked by how well known they are; the leads of the articles `en_mini.zx` lacks |
| `*.parts` | zx part manifests (size and SHA-256 of each file), the URLs the app opens |

Read one with the zx command line tool, after downloading it:

    zx sql en_mini.zx "SELECT title, kind FROM page_meta WHERE title = 'Battle of Hastings' COLLATE NOCASE"

or in place over HTTP with the zx web engine (`url` with the manifest's
URL, then `db.open` and `db.sql`).

How they are built: `tool/wikizx` and `docs/plan-offline-wikipedia.md`,
`docs/plan-geofill.md` in the Inspira repository.

## Sources and licenses

- Wikipedia text: CC BY-SA 4.0, from the Kiwix English Wikipedia "mini"
  ZIM. The content of this dataset is shared under the same license;
  credit the Wikipedia contributors.
- Wikidata: CC0 (truthy dump and sitelinks).
- GeoNames (https://www.geonames.org): CC BY 4.0, for a part of the
  points in `geo.zx`.
- Some points in `geo.zx` were placed by a language model (Claude) from
  the article's lead; their tier says so (`model-high`, `model-medium`,
  `model-low`). Treat them as approximate.
