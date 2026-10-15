# Places for stories

Puts history, study and story items on the map, for the Map screen
(historical tourism: what happened near me).

1. `in/<n>.jsonl`: the stories in four slices (id, kind, title, location,
   start of text).
2. Writers follow `BRIEF.md` and write `out/<n>.jsonl`: precision (site,
   city, region, none), a visitor friendly place name, coordinates and a
   geocoder query. Only site and city get a map point.
3. `verify.py` geocodes every query with OpenStreetMap Nominatim (one
   request per second, cached in `cache.json`) and marks points more than
   15 km (site) or 30 km (city) away as far.
4. Far and not found points are reviewed by hand into `review.jsonl`
   (keep, fix with new coordinates, or drop).
5. `apply.py` writes `place`, `lat` and `lon` into the story files; then
   run `dart run tool/bundle_quotes.dart`.

Events already have coordinates (see `tool/pipeline/events/`).
