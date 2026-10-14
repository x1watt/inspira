# Images pipeline

How `assets/images/` and `assets/images.json` were produced. Only needed to
change the pictures. Run with `python3 -I`, with a work dir outside the
project; it needs network access to Wikidata and Wikimedia Commons.

1. Portraits
   - `names.py <project> work/names.json`: quote authors, speakers and the
     first person of each history or study item, with context.
   - `search.py work/names.json work/search.jsonl`: Wikidata search, top 5.
   - `images_for.py work/search.jsonl work/candidates.jsonl`: keeps hits
     that have a picture (P18).
   - A model agent follows `PICK_BRIEF.md` and writes `work/picks_*.jsonl`
     (the right person or null). The result used is `picks.jsonl` here.
2. Art
   - Agents follow `ART_BRIEF.md` and check every file with
     `check_files.py`. Results used: `pools.jsonl` (30 per category, plus
     `fable` and `study`) and `events.jsonl` (paintings of history items).
3. `build_images.py <work> <download dir> <project>` reads the files above
   (copy them into the work dir), keeps only Commons files whose license is
   public domain or CC0, downloads thumbnails, converts them to WebP
   (portraits 256 px square, art max 640 px wide, ImageMagick) and writes
   `assets/images.json`.
4. `wiki_links.py <work> <project>` adds `wikipedia` (person name to
   English Wikipedia URL) to `assets/images.json`, from the Wikidata items
   in `work/picks_*.jsonl` (all matched people, with or without a
   portrait). Run it after every `build_images.py`, which rewrites the
   manifest.
