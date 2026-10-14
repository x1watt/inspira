# Stories pipeline

How `stories/` was produced. Nothing here is needed to build the app.

1. Plan: one model agent per kind (story, history, study) follows
   `PLAN_BRIEF.md` and writes `plan/<kind>.jsonl`, about 80 items per
   category, each with a canonical `key`. Keys and titles are compared
   across the three plans and duplicates removed; then the plans are split
   into `plan/<kind>-<category>.jsonl`.
2. Write: one agent per plan file follows `WRITE_BRIEF.md` and writes
   `raw/<kind>-<category>.jsonl`.
3. Fact-check: a separate agent per raw file follows `REVIEW_BRIEF.md` and
   writes `review/<kind>-<category>.jsonl` with keep, fix or drop per key.
4. Merge: `python3 -I write_stories.py <work dir> <project dir>` applies
   the reviews, normalizes punctuation, validates fields and duplicates, and
   rewrites `stories/<category>/*.json`. Then run
   `dart run tool/bundle_quotes.dart`.

The briefs assume the work dir holds them next to `plan/`, `raw/` and
`review/`.
