# Place each story on the map

Input: `in/<n>.jsonl`, one story per line: id, kind (story = fable, myth,
parable or literary tale; history; study), title, location (free text),
date, start of the text.

Output: `out/<n>.jsonl`, exactly one line per input line, same order:

    {"id": "...", "precision": "site|city|region|none", "place": "...", "lat": 0.0, "lon": 0.0, "query": "..."}

The app shows these on a map for historical tourism: a traveler standing
nearby should be able to walk or drive to the spot. So:

- `site`: a specific spot a visitor can stand at (a battlefield, building,
  bridge, palace, university campus, monument, ruin). Coordinates of that
  spot, 4 decimals.
- `city`: the event clearly happened in one town or city, but no precise
  spot is known. Coordinates of the historic town center, 3 decimals.
- `region`: only a country, province, sea or broad region is known
  ("Ancient Greece", "Illinois, USA", "Major US symphony orchestras").
  lat/lon null.
- `none`: invented or unknown place, or several unrelated places with no
  main one. lat/lon null.

Rules:
- Use the main place where the story happened, not where it was written
  or published ("Crete (myth); written in Rome": the scene is Crete,
  which is a region, so `region`).
- Fables and parables with no real setting: `none`. Myths and legends
  tied to a real visitable place (Troy, Delphi, Ithaca, Ayodhya) may be
  `site` or `city`, since visitors go there.
- Studies: the university or lab where it was run (`site` when one
  campus is named, `city` when only the city). Surveys of a whole country
  or many sites: `region`.
- Two places ("Washington and Moscow"): pick the one where the story's key
  moment happened; if none dominates, `none`.
- `place`: short modern name a visitor would recognize, e.g. "Thermopylae
  pass, Greece", "Dexter Avenue Baptist Church, Montgomery, Alabama, USA".
- `query`: a string a geocoder (OpenStreetMap Nominatim) would find for
  the same spot or town, e.g. "Thermopylae, Greece", "Montgomery,
  Alabama". Empty for region and none.
- Only coordinates you are confident about. If unsure of a site's
  coordinates but sure of the town, use `city` with the town.
- Plain ASCII punctuation; no em dashes, en dashes or curly quotes.

Write the file with a script or by hand; check it has the same number of
lines as the input and every id matches. Report counts per precision.
