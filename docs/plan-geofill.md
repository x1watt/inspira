# Plan: filling missing locations with a language model

Status: done for the 2026-10 dumps (2026-10-16), see section 9. Any model or person can do
the work in small batches, stop at any time and resume later; progress
lives only in files, never in a conversation.

Related: `docs/plan-offline-wikipedia.md` sections 9 and 9.1 (how
`geo.zx` is built from Wikidata and how good it is).

## 1. Why

`geo.zx` gives a point to an item from Wikidata (own coordinates, else
where it happened, headquarters, terrain, area). That covers 64.5% of
Inspira's verified events. The rest are mostly events whose place is
only written in the article text ("signed in Bangkok"). A language model
that reads the lead names that place; the place's own Wikidata point
then gives exact coordinates.

The big run happens once. Answers are keyed by Wikidata id (Q number),
so they serve every language and survive new dumps; later updates only
send the new items (section 7).

## 2. What GeoNames would add (optional, later)

GeoNames (geonames.org, CC BY 4.0, `allCountries.zip` about 0.4 GB) is a
gazetteer: about 12 million places (villages, towns, mountains, rivers,
some ruins and battlefields) with coordinates, feature type, country,
admin area, population and names in many languages. It knows places,
not events. Here it would only resolve a `place` the model names that
has no Wikipedia article or no Wikidata point (about 10% in the pilot),
and cross check model coordinates. Needs an attribution line in the
app's credits.

## 3. Pilot result (317 verified events Wikidata leaves without a point)

| Model | Within 50 km | Within 5 km | "high" answers within 50 km | Tokens per 80 items |
|---|---|---|---|---|
| Claude Haiku | 79.2% | 67.8% | 88.7% | about 76k |
| Claude Sonnet | 81.1% | 73.8% | 90.8% | about 59k |

These are the hardest cases, and part of the misses come from the
article being about something else than the verified event (the film
"Citizen Kane" placed in Hollywood, the event is its New York premiere).
The named place was found in `geo.zx` for 90% of the answers. Sonnet's
answers are kept as group P. Merged into `geo.zx`, they bring the
verified events with a point from 64.5% to 99.1%: `model-high` 93.1%
within 50 km, `model-medium` 81.0%, `model-low` 44.1%.

## 4. The work

Prepared by `bin/geofill_prepare.dart` (English pages whose Wikidata
item has no point), most linked first, 200 items per batch:

| Group | What | Items | Batches | Tokens (about) |
|---|---|---|---|---|
| A | event pages | 25,104 | 126 | 14M |
| B | place pages | 5,257 | 27 | 3M |
| C | other dated items (wars, treaties, disasters, protests, crimes, matches), the most linked | 48,262 | 242 | 26M |
| P | pilot, already done | 317 | 1 | |

Also 13,989 place and event pages have coordinates in the ZIM but not in
Wikidata: `geofill/zim_points.tsv`, merged without a model.

Group C leaves out 135 low value types listed in
`geofill/skip_types.txt` (sports seasons, TV series, lists, calendar
pages, elections, taxa): 385,325 dated items drop to 72,718. Edit the
list and rebuild only C with `--groups C`. A few abstract topics remain
(for example "Agriculture"); the model answers them with no place.

Order: A, then B, then C. Within a group, lower batch numbers are more
linked and more useful, so stopping early still gives the best part.

## 5. Files

All under `tool/wikizx/geofill/` (committed; answers are the valuable
part and must not be lost with `build/wiki`):

- `PROMPT.md`: the exact instructions for one batch (input and output
  format, rules). Give it to the model as is.
- `in/<group>/<nnnn>.jsonl`: batch inputs, never edited after creation.
- `out/<group>/<nnnn>.jsonl`: answers, one line per input line.
- `out/<group>/<nnnn>.claim`: a worker is on it (ignored after 3 hours).
- `gate/<model>.jsonl`: quality gate answers of a model (section 6).
- `zim_points.tsv`: points from the ZIM.
- `skip_types.txt`: Wikidata types group C leaves out.

## 6. How to work (any model, resumable)

All commands run in `tool/wikizx`.

**Once per new model: the quality gate.** Have the model answer
`geofill/in/P/0001.jsonl` following `PROMPT.md`, writing to
`geofill/gate/<model>.jsonl`, then:

    dart run bin/geofill_score.dart ../../build/wiki/geo.zx ../../events geofill/gate/<model>.jsonl

It prints PASS when at least 75% are within 50 km. Do not use a model
that fails.

**Each batch:**

1. Pick and claim the next batch:

       dart run bin/geofill_status.dart geofill --next 1 --claim <worker name>

   It prints `next: in/A/0007.jsonl, answers to out/A/0007.jsonl`.
2. The model reads `geofill/PROMPT.md` and that input file and writes
   the whole answer file once, or saves it in new part files
   (`0007.part1.jsonl`, `0007.part2.jsonl`, ...). It must never rewrite
   a file it already wrote: a worker that did so lost most of batch
   A/0001 on 2026-10-16.
3. Check it:

       dart run bin/geofill_status.dart geofill --check out/A/0007.jsonl

   `ok` means done. Otherwise it lists the problems (missing items, bad
   JSON, bad fields): fix or redo the file. A file that does not pass
   counts as not done and comes back as pending.
4. Repeat. Several workers can run in parallel; claims keep them apart.

`dart run bin/geofill_status.dart geofill` alone shows the progress per
group. To resume after a stop, just start again at step 1: done batches
are skipped, unfinished ones come back after their claim expires (or
delete the `.claim` file).

**With Claude Code agents**, one agent per batch, prompt:

> Read tool/wikizx/geofill/PROMPT.md and follow it for the input file
> tool/wikizx/geofill/in/A/0007.jsonl, writing
> tool/wikizx/geofill/out/A/0007.jsonl. Use only Read and Write, no web
> tools. Reply only with the number of lines written.

Then run the check of step 3. A Sonnet agent takes about 1 to 2 minutes
per batch. Commit `tool/wikizx/geofill/out` from time to time (the owner
decides when).

## 7. Merge and measure

    dart run bin/geofill_merge.dart ../../build/wiki/geo.zx geofill
    dart run bin/geovalidate.dart ../../build/wiki/geo.zx ../../events

The merge adds points only for items without a Wikidata point, with tier
`model-high`, `model-medium`, `model-low` or `zim` and, in `via`, the
Wikidata item of the named place. It keeps the named place's Wikidata
point when it is within 100 km of the model's coordinates, else the
model's own coordinates. It can run at any time (after a few batches or
at the end) and again: it first removes earlier fill rows. Apps can
choose which tiers to trust (for example hide `model-low` on the map, or
show it with a "approximate" mark).

**Next dumps.** Rebuild `geo.zx` (plan-offline-wikipedia.md 9.1), run
the merge (the old answers still apply by Q number), then

    dart run bin/geofill_prepare.dart ../../build/wiki/en_mini.zx ../../build/wiki/geo.zx geofill --tag 2027-01

which writes only items that are still without a point and not answered
before, into new groups A-2027-01, B-2027-01, C-2027-01. Then work them
as in section 6. Other languages: their articles map to the same Q
numbers, so they need no new run; only items with no English article
would, through a prepare step reading that language's ZIM.

## 8. Later improvements

- Prefer "where it happened" (P276) when an event's own point is within
  a few km of its country's point (a country centroid, e.g. "India
  becomes independent" 868 km off).
- GeoNames for named places without a Wikidata point (section 2).
- A second opinion on `model-low` answers of the most linked items.
- More of group C (the 335,325 less linked dated items) if wanted.

## 9. Result of the first run (2026-10-16)

All 396 batches answered by Claude Sonnet agents (20 at a time, 3
batches each, about 60k tokens and 1.5 minutes per batch): 78,944
answers. Typos in qids (about 1 batch in 8) were fixed by
`geofill/repair.py`.

| Group | Answers | high / medium / low | site / city / region / country / none |
|---|---|---|---|
| A events | 25,107 | 14,003 / 7,781 / 3,323 | 7,010 / 12,030 / 2,437 / 1,346 / 2,284 |
| B places | 5,258 | 1,049 / 2,929 / 1,280 | 75 / 2,136 / 2,808 / 219 / 20 |
| C dated items | 48,262 | 29,517 / 15,207 / 3,538 | 3,321 / 20,326 / 9,805 / 8,713 / 6,097 |

Merged into `geo.zx`: 70,485 model points (high 38,934, medium 24,382,
low 7,169) and 13,984 ZIM points, 84,469 new points in all. Verified
events with a point: 99.1% (from 64.5%); `model-high` 93.5% within
50 km, `model-medium` 82.5%, `model-low` 42.9%. The merge needs little
memory now (160 MB limit), so it runs next to a busy desktop.
