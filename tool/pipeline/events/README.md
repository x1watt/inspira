# Events pipeline

About 1000 dated events in world history, for "on this day" and date
quizzes. Output: `events/<mm>/<key>.json` (folder = month), bundled into
`assets/events.json` by `dart run tool/bundle_quotes.dart`.

1. Write: ten model passes, one per era slice, follow `WRITE_BRIEF.md`
   and write `raw/<slice>.jsonl`. Each asks for about 10 percent more than
   its share, so dropped events can be absorbed.
2. Check: `python3 -I tool/pipeline/events/verify.py` resolves each
   `wikipedia` title to its Wikidata item and compares the day (P585, else
   P580; Julian and Gregorian are converted) and the coordinates (P625, or
   the P625 of the P276 location; more than 100 km apart is flagged).
   Writes `checked.jsonl`.
3. Review: a model pass looks only at the flagged events (date mismatch,
   no Wikidata item or date, coordinates far off) and writes
   `review_out/<n>.jsonl` (input batches in `review_in/`) with keep, fix or drop for each, following
   `REVIEW_BRIEF.md`.
4. Write files: `python3 -I tool/pipeline/events/write_events.py` applies
   the review, fills missing coordinates from Wikidata, drops duplicates
   and keeps the 1000 with the highest weight.

The events are written in our own words. Nothing but the day and the
coordinates is machine checked.
