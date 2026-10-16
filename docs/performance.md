# Performance

Rules for keeping start-up fast and the UI smooth. Read with
`docs/architecture.md`. No measurements on phones yet; add them here with the
method next to each number.

## Rules

1. Nothing heavy on the UI isolate. `QuoteRepository.load`,
   `StoryRepository.load`, `EventRepository.load` and `WikiPlaceRepository.load` decode their bundles with `compute`, which uses
   a background isolate on Android and desktop. The web has no isolates,
   so there the decode runs inline once at start-up, behind the loading
   spinner. `rootBundle.loadString` already decodes large assets off the
   UI isolate.
2. One asset per collection, not one file per quote or story. Loading thousands of small assets costs
   one platform round trip each; `tool/bundle_quotes.dart` merges them.
3. Load once at start-up and keep everything in memory (a few MB). Screens
   read from the repository; they never reload the asset.
4. Lists use `ListView.separated` / `PageView.builder` so only visible quotes
   are built.
5. Search runs on lowercased strings built once in the repository
   constructor, and is debounced (250 ms) in the quote and story list
   screens. A full scan
   of 5000 quotes takes well under a frame; move it to an isolate only if
   the collection grows by an order of magnitude.
6. Favorites are kept in memory; writes to `shared_preferences` are async
   and not awaited by the UI.
7. Feed pictures: one `Image.asset` per visible page (max 720 px wide, so
   no extra decode size is needed) and `precacheImage` for the next two
   pages only. Avatars are 256 px. On this day builds its cards with
   `ListView.builder` (at most about a dozen per day); each card's banner
   is the same 720 px art, so it shares the image cache with the feed.
8. Picking the next feed card costs O(kinds + categories): each (kind,
   category) has its own queue, shuffled once on first use. Replanning
   after a like or skip drops at most the two cards planned ahead. A quiz
   from earlier sessions scans the seen ids (capped at 4000) once per quiz,
   which is every 3 to 8 cards in the feed.
9. `ProgressStore` writes its JSON on XP, quiz and goal changes only.
   Marking a card seen or read, or nudging weights, stays in memory until the next
   write, so a swipe never encodes the seen list.
10. Animations on feed pages run once (slow zoom 25 s, confetti 2.6 s,
    XP and heart bursts under 1.2 s); nothing repeats forever.
11. Map: markers and the closest list are recomputed by a linear scan of
    about 22,000 places (2,000 of Inspira's own and 20,000 Wikipedia
    places), debounced 200 ms after the map moves, never per frame.
    `nearest` keeps only the closest 50 in a sorted list instead of
    sorting everything. Measured on the Linux desktop (flutter test, 20
    runs after 5 warm-up runs, 2026-10-16): parsing the 1 MB
    `wiki_places.json` 39 ms (in a background isolate), `nearest` 1.6 ms,
    `inBox` 0.45 ms; expect a few times that on a phone, still well
    inside the debounce. At most 200 markers are built. `PlaceIndex` is
    built once, on the first map open.
