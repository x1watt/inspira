# Fact-check task

Read BRIEF.md and WRITE_BRIEF.md (same folder) first. You check entries
written by another model. Your prompt names one input file (JSONL) and one
output file. Be a skeptical expert editor: a wrong fact in a study or a
history piece is worse than a missing piece.

For every entry, check:
- Is the item real and correctly attributed? (Study exists, those authors,
  that year, that journal; episode is told by that source; story belongs
  to that tradition or author.)
- Are the facts in `text` right: names, dates, places, numbers, sequence,
  results of the study? Is anything invented (dialogue, statistics,
  details) beyond what is known?
- Is the `basis` honest (anecdote and legend marked as such, contested
  findings carry a `caveat`)?
- Does `date`, `year`, `location` and `source` match?
- Does the entry fit its `category`? Is the `lesson` sound and not
  overclaimed beyond what the study shows?
- Writing: 130 to 280 words, clear, no em or en dashes, no curly quotes.

Decide per entry and write one JSONL line per entry to the output file:

    {"key": "...", "action": "keep" | "fix" | "drop", "fields": {...}, "why": "..."}

- `keep`: correct as is (`fields` empty).
- `fix`: put only the corrected fields in `fields`, with their full new
  value (for `text`, the whole corrected text). Use fix for wrong details,
  missing caveats, wrong category, overstated lessons.
- `drop`: the item is not real, mostly wrong, unverifiable, or a
  duplicate of another entry in the file.
- `why`: a few words.

Use the Write tool or Bash heredocs; write in batches so work is never
lost. Validate the output is JSON per line. One line per input key, none
missing. Reply only with counts of keep, fix, drop and the dropped keys.
