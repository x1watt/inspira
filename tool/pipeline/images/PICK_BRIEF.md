# Portrait matching task

Each input line is a person name used in a learning app, a `context` (what
the app says about them: work, lifespan, episode) and Wikidata `hits` that
have a picture (id, label, description, file).

Pick the hit that is really this person, judged by label, description and
context. Rules:
- Only a hit for the same individual. Not a namesake, not a ship, place,
  book, statue name, family or later person with the same name.
- If the name is a fictional or legendary figure (Achilles, Moses), a hit
  for that figure is fine (its picture will be an old artwork).
- If no hit fits, or you are not sure, output null.

Output JSONL, one line per input name, same order:

    {"name": "...", "id": "Q..." or null}

Write it with the Write tool or a Bash heredoc in batches; validate it is
JSON per line and that every input name is present. Reply with counts of
matched and null only.
