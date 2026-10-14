# Planner task

Read BRIEF.md (same folder) first. You plan, you do not write the stories.

Produce a list of distinct items of ONE kind (given in your prompt) spread
over the five categories, with the target count per category given in your
prompt. Choose the best: well known, instructive, varied in era, region and
theme. Each category must feel like its own topic; put an item where its
main lesson fits best.

Output: a JSONL file (path in your prompt), one object per line:

    {"key": "...", "category": "...", "kind": "...", "title": "...", "basis": "...", "people": "...", "date": "...", "source": "...", "angle": "..."}

- `key`: canonical kebab-case slug of the item itself, independent of
  category, for dedup (e.g. `alexander-gordian-knot`,
  `asch-conformity-1951`, `aesop-bundle-of-sticks`).
- `basis`: story kind: `fable`, `parable`, `folktale` or `literature`.
  history kind: `documented` (well attested by contemporary sources),
  `anecdote` (reported by an ancient or later author, maybe embellished)
  or `legend`. study kind: `study`.
- `people`: main figures (or researchers for a study).
- `date`: when it happened or was published, as text.
- `source`: the primary source. For a study: authors, year, title, journal
  (volume and pages only if you are certain). For history: ancient author
  and work, or a standard reference. For stories: collection or author and
  work.
- `angle`: one sentence, the lesson this item will teach.

Rules: no two lines with the same key or the same underlying episode;
only items you are confident are real and correctly attributed. Write the
file with the Write tool. When done, reply with counts per category only.
