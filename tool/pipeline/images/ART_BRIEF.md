# Art curation task

Inspira is an offline learning app (quotes and short stories on relations,
leadership, team, family, strategy). Each card in its TikTok style feed has
a full-screen background picture. Pictures must be public domain artworks
on Wikimedia Commons (old paintings, engravings, prints, photos before
about 1925), bundled in the app.

Your prompt names the pools you curate and the output file. For each pool,
list well-known, visually strong artworks that fit its theme: mostly
paintings, varied in era and region (Europe, China, Japan, India, Persia,
Islamic world, Americas), mostly portrait-friendly or with a strong center
(the app crops to a tall phone screen). Avoid nudity, gore, and anything
that would be disturbing on a phone feed.

Output JSONL, one per line:

    {"file": "File:Exact Commons file name.jpg", "pool": "...", "title": "...", "artist": "...", "year": "..."}

You MUST check every file name: write your list to a draft JSONL and run

    python3 -I SCRIPTS/check_files.py draft.jsonl checked.jsonl

(SCRIPTS is given in your prompt). It reports `exists` and `ok` (license
is public domain or CC0). Fix or replace every line with exists false or
ok false (search Commons with
`curl -s -A 'InspiraBuild/1.0' 'https://commons.wikimedia.org/w/api.php?action=query&list=search&srnamespace=6&format=json&srlimit=10&srsearch=QUERY'`,
sleep 1 s between calls; do not hammer the API). Prefer files at least
1000 px on the long side. The final output file must contain only lines
that checked ok. Reply with counts per pool.
