# Writer task

Read BRIEF.md (same folder) first. Your prompt names one input file of
planned items (JSONL, one per line) and one output file. Write one entry
per planned item, in the same order, as JSONL:

    {"key": "...", "category": "...", "kind": "...", "title": "...", "text": "...", "lesson": "...", "people": "...", "date": "...", "year": 0, "location": "...", "source": "...", "basis": "...", "caveat": ""}

- Keep `key`, `category`, `kind` and `basis` from the plan (change `basis`
  only if the plan got it wrong).
- `title`: short, specific, title case, max 60 characters.
- `text`: the retelling, 130 to 280 words, in your own words (never copy a
  translation or a paper). Two to four paragraphs separated by "\n\n".
  Plain modern English, concrete and vivid, past tense. Tell what happened
  (or what the researchers did and found), not the moral. End on the
  outcome, not a sermon.
  - history: name the source inside the text when it is an anecdote
    ("Plutarch says..."). Do not invent dialogue; reported words go in
    double quotes only if the source records them.
  - study: who, when, where, the setup in plain words, the main result
    (numbers only if you are sure of them), and what it shows.
- `lesson`: one or two sentences, max 40 words, the practical takeaway for
  the reader's own life or work. Do not start with "The lesson is".
- `people`: main figures, or researchers for a study.
- `date`: when it happened or was published ("c. 480 BC", "1951",
  "1914 to 1917"). `year`: integer sort key, negative for BC.
- `location`: where it happened or where the study was run, with modern
  country ("Gordium, Phrygia (modern Turkey)", "Yale University, New Haven,
  USA"). For a fable or parable: where the tradition comes from
  ("Ancient Greece").
- `source`: full citation. Study: Authors (year). Title. Journal,
  volume(issue), pages (volume and pages only if certain). History: author,
  work and book or chapter. Story: collection or author and work.
- `caveat`: empty unless there is a real doubt: failed or weak replications,
  disputed facts, later debunking, legend status of a detail. One sentence.

Hard rules:
- Accuracy first. If you find a planned item is doubtful, wrong or a
  duplicate of another line, skip it and do not replace it with something
  you are unsure of.
- ASCII punctuation only: straight quotes, no em or en dashes (use commas,
  colons, parentheses or full stops), no arrows, no ellipsis character.
- Valid JSON on each line (escape double quotes inside strings).
- Build the file with the Write tool in batches of about 10 entries
  (rewrite the whole file each time, or append with Bash heredoc), so work
  is never lost. Check at the end with
  `python3 -I -c "import json,sys;[json.loads(l) for l in open(sys.argv[1])]" FILE`.
- Reply only with: written count, skipped keys with a few words why.
