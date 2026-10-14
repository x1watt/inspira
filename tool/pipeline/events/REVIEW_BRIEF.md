# Events: review brief

You check events that the automatic checks could not confirm. Your input
file has one event per line, with a `check` object:

- `date`: `mismatch` (Wikidata gives another day, see `wikidata_dates`),
  `no_date` (the Wikidata item has no day), `no_item` (the `wikipedia`
  title was not found on Wikidata).
- `text`: `found` or `not_found`: whether the day is written in the
  English Wikipedia article (`resolved_title` when the title redirected or
  was replaced by a search hit).
- `coords`: `far` means the event's `lat`/`lon` is `km` kilometres from
  Wikidata's coordinates (`wikidata_coords`).

For each event, open the English Wikipedia article (WebFetch
`https://en.wikipedia.org/wiki/<title>`; if it does not exist, search for
the right one) and decide:

- `keep`: the event is right as it is (for example Wikidata's date is the
  end of a battle known by its first day, or Wikidata's coordinates point
  to a city or country while ours point to the actual site).
- `fix`: the event is right but fields need changing. Give only the
  changed fields: `year`, `month`, `day`, `calendar`, `lat`, `lon`,
  `place`, `wikipedia` (the exact article title), `title`, `summary`.
  Rules for dates and calendars are in `WRITE_BRIEF.md`: Julian before 15
  October 1582, Gregorian (New Style) after, also for Britain before 1752
  and Russia before 1918.
- `drop`: the day cannot be confirmed in the article or another reliable
  source, or the event is not really a single-day event.

Coordinates: the place where the event mostly happened (the battlefield,
the building, the city), 4 decimals. Use the article's coordinates when it
has them and they are of that place.

Output: write `tool/pipeline/events/review_out/<n>.jsonl` (same number as
your input file), one line per input event, in input order:

    {"key": "...", "action": "keep" | "fix" | "drop", "fields": {...}, "note": "one short line why"}

`fields` only with `fix`. Plain text: no em dashes, en dashes, arrows or
curly quotes, also not in `wikipedia` titles: when a real title has an en
dash, write it with a hyphen (it redirects).
