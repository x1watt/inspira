# Quote pipeline

How `quotes/` was produced. Python 3, no dependencies. Set `INSPIRA_WORK` to a
working folder outside the repo (it gets `sources/`, `candidates/`,
`attributed/`, `review/`).

1. `python3 -I fetch_sources.py $INSPIRA_WORK/sources` downloads the works in
   `manifest.py` from Project Gutenberg and writes `manifest.json`.
2. Extraction: agents follow `AGENT_BRIEF.md` and write
   `$INSPIRA_WORK/candidates/<group>/partNN.jsonl`. `check.py <file>` verifies
   every text appears word for word in its source.
3. Attributed quotes (not checked against a text) go in
   `$INSPIRA_WORK/attributed/*.jsonl` with all fields filled in.
4. Review: agents follow `REVIEW_BRIEF.md` and write
   `$INSPIRA_WORK/review/decisionsNN.tsv` (DROP or RECAT per id).
5. `python3 -I write_quotes.py <project dir>` verifies again, deduplicates,
   applies review decisions and regenerates `quotes/<category>/*.json`.
6. `dart run tool/bundle_quotes.dart` rebuilds `assets/quotes.json`.

Stories (`stories/`) have their own pipeline: `stories/README.md` in this folder.
