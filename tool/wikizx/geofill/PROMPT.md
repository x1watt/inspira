# Location fill: instructions for one batch

You give a location to each Wikipedia article in one batch file, from your
own knowledge. Do not use web search or web fetch: it is slow, costly and
not needed. Best effort is fine; mark uncertain answers "low".

## Input

`tool/wikizx/geofill/in/<group>/<nnnn>.jsonl`, one JSON object per line:

- `qid`: Wikidata item number
- `title`: English Wikipedia article title
- `lead`: the start of the article
- `infobox` (optional): location-like infobox fields

## Output

`tool/wikizx/geofill/out/<group>/<nnnn>.jsonl` (same group and number),
one line per input line, same order, compact JSON with exactly these keys:

- `qid`: same number as the input line
- `place`: exact English Wikipedia article title of the most specific
  place where the subject mainly happened or is: a building, battlefield,
  village, town or city; a region or country only when nothing more
  specific is known. For a signing, declaration or proclamation, where it
  was signed or proclaimed. For a war, campaign or long process, the place
  of its defining moment (say so in `note`). For a sports season,
  election or tournament, the host city, or the country when it is
  nationwide. `null` when the subject has no physical location (an idea,
  a list, a fictional place).
- `lat`, `lon`: best decimal coordinates of that place (4 decimals), or
  `null` with `place` null
- `precision`: `site` (building or exact spot), `city`, `region`,
  `country` or `none`
- `confidence`: `high`, `medium` or `low`
- `note`: at most 8 words on why this place, may be `""`

Example line:

    {"qid":3042723,"place":"Bangkok","lat":13.7563,"lon":100.5018,"precision":"city","confidence":"high","note":"signed in Bangkok"}

Rules:

1. Prefer the place stated in the lead or infobox. When they name only a
   country, use your knowledge for the city where it happened.
2. When the lead names the building or venue (a hotel, palace, stadium,
   church), give that building's article with precision `site`, not
   just the city.
3. Use the exact, unambiguous article title: "Nashville, Tennessee",
   "Green Bay, Wisconsin", "Bristol, Tennessee" (not "Bristol", which is
   the English city), "Carthage" only for the ancient city.
4. For a coup, revolution or government act, the capital or the seat
   where it happened, not the country.
5. Never invent an article title you are not sure exists; give the
   article of the town or city instead.
6. Never overwrite answers you already wrote. Either write the whole
   output file once, after answering every line, or save in parts:
   `<nnnn>.part1.jsonl`, `<nnnn>.part2.jsonl`, ... (each part a new
   file, for example 50 lines each). Parts together must cover every
   line; a batch with missing lines counts as not done.
7. Answer every line, even with `"place":null,"precision":"none"`.

## Cheaper way to read and write (optional)

From `tool/wikizx`, show 50 items at a time in a short form:

    python3 -I geofill/show.py A 0002 0 50

and write the answers for them as pipe lines through a helper that makes
the JSON and the part file (`out/A/0002.part1.jsonl`):

    python3 -I geofill/wr.py A 0002 1 <<'X'
    qid|place|lat|lon|precision|confidence|note
    X

`precision` is one letter: s site, c city, r region, k country, n none.
`confidence` is h, m or l. An empty place means null (leave lat, lon
empty too). Example: `3042723|Bangkok|13.7563|100.5018|c|h|signed there`.
Repeat with part numbers 2, 3, 4 for the next 50 items. The helper
refuses to overwrite an existing part file.
