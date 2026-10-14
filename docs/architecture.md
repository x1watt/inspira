# Architecture

Inspira shows quotes from well-known people of history, and short stories,
historical episodes and psychology studies, in five categories: relations,
leadership, team, family and strategy. It runs on Android and on
desktop (Linux, Windows, macOS) and the web from one Flutter code base. The
web build is a static site on GitHub Pages, deployed by
`.github/workflows/pages.yml` on every push to `main`. Read with
`docs/performance.md`.

## 1. Data

The source of truth is one JSON file per quote:

    quotes/<category>/<author-slug>-<hash>.json

| Field | Meaning |
|---|---|
| `id` | file name without `.json`; hash is of the normalized text |
| `category` | one of the five; must match the folder |
| `text` | the quote, in English |
| `author`, `author_lifespan` | who wrote the work |
| `speaker` | optional: who says the words inside the work (Pericles in Thucydides) |
| `reference`, `locator` | the book or letter, and the place in it (book, chapter, letter, maxim) |
| `date`, `year` | when it was written, as text; `year` is a sort key, negative is BC |
| `location` | presumed place of writing or speaking |
| `original_language`, `translation` | translator and year for public domain translations |
| `source_url` | the edition the text was checked against |
| `confidence` | `verified` or `attributed`, see below |

`verified` quotes were matched word for word (letters and digits only)
against the downloaded public domain edition named in `source_url`.
`attributed` quotes are well documented attributions that were not checked
against a source text. The card shows which one a quote is.

A quote belongs to exactly one category. Texts are unique across all
categories. Every quote also passed a review that removed plain narrative,
passages that need their surrounding story, and fragments. How the files
were produced, and how to regenerate them: `tool/pipeline/README.md`.

### Stories

One JSON file per story:

    stories/<category>/<key>.json

| Field | Meaning |
|---|---|
| `id` | `story-<key>`; the prefix keeps it apart from quote ids in favorites |
| `category` | one of the five; must match the folder |
| `kind` | `story` (fable, parable, folk tale, literature), `history` or `study` |
| `title`, `text`, `lesson` | the retelling (paragraphs split by blank lines) and its takeaway |
| `people` | main figures, or the researchers of a study |
| `date`, `year`, `location` | when and where it happened or the study ran; `year` sorts |
| `source` | primary source or full citation of the study |
| `basis` | `documented`, `anecdote`, `legend` (history); `fable`, `parable`, `folktale`, `literature` (story); `study` |
| `caveat` | optional: failed replications, disputed details |

Stories are retold in our own words, not copied. They were planned, written
and then fact-checked by separate model passes; nothing in them is
machine-checked against a source text, so the card shows the `basis` and
any `caveat`. How they were produced: `tool/pipeline/stories/README.md`.

## 2. Bundle

`tool/bundle_quotes.dart` validates every file and writes all quotes into one
asset, `assets/quotes.json`, and all stories into `assets/stories.json`, both
sorted oldest first. Run it after any change in `quotes/` or `stories/`:

    dart run tool/bundle_quotes.dart

The app never reads `quotes/` or `stories/` directly.

### Images

`assets/images.json` lists the bundled pictures, written by
`tool/pipeline/images` (see its README):

| Key | Meaning |
|---|---|
| `avatars` | person name (quote author, speaker, first person of a history or study item) to `avatars/<slug>.webp`, 256 px square |
| `wikipedia` | person name to their English Wikipedia page, when Wikidata has one |
| `art` | artworks: `file` (`art/<slug>.webp`, max 720 px wide), `title`, `artist`, `year`, `url` (Commons page), `license`, `pools` (a category, `fable` or `study`), optional `stories` (ids of history items the work depicts) |

Only Wikimedia Commons files whose license is public domain or CC0 are
kept. Every artwork is credited on its card and in Me, Image credits.
A card's background is the artwork of its own episode when there is one,
else a pool picture chosen by a stable hash of the card id, so a card
always shows the same picture.

## 3. App

| Path | Role |
|---|---|
| `lib/models/` | `Quote`, `Story`, `StoryKind`, `QuoteCategory` (labels, icons) |
| `lib/data/quote_repository.dart` | loads the quote bundle, indexes by category, quote of the day, search |
| `lib/data/story_repository.dart` | loads the story bundle, story of the day, filter by category, kind and words |
| `lib/data/favorites_store.dart` | favorite quote and story ids in `shared_preferences` |
| `lib/data/image_repository.dart` | portraits, Wikipedia links and background art from `assets/images.json` |
| `lib/data/progress_store.dart` | XP, levels, daily goal, streak and freezes, quiz review boxes, feed affinity, seen ids; one JSON value in `shared_preferences` |
| `lib/data/quiz_generator.dart` | questions made from the data: who said this, what is the lesson, what did the study show, when did it happen |
| `lib/data/feed_engine.dart` | the endless feed: which card comes next |
| `lib/app_scope.dart` | `AppData` (everything loaded at startup) in an `InheritedWidget`, inserted by `MaterialApp.builder` above the Navigator so pushed routes see it |
| `lib/screens/` | Feed (home), Quiz (the feed in quiz mode), Quotes (categories, list with search), Stories (story of the day, categories, list with kind filter and search), Favorites, Me (streak, goal, levels, credits), single quote, single story |
| `lib/widgets/` | feed pages (quote, story, quiz) with the action rail, `ArtBackground`, `Confetti`, `QuoteCard`, `StoryCard`, `ItemActions`, quote and story tiles and lists |

## 4. Feed and rewards

The feed is a vertical `PageView` of full-screen cards. `FeedEngine` decides
the next card; `FeedScreen` measures reading time and hands out XP.

- First card: a random story, history or study, so no two visits (and no
  two new users) start the same way.
- Story cards show the whole text and the lesson; there is no teaser that
  asks for a click.
- Kind (quote 45, story 20, history 20, study 15 percent) and category are
  drawn by those base shares times the user's affinity weights times a
  session boost. 20 percent of category picks ignore the weights, so new
  topics keep appearing.
- Session boost (`FeedEngine.steer`): a like multiplies the boost of the
  card's category and kind by 4, a read by 1.3, a quick skip by 0.7; the
  boost fades 10 percent toward 1 with every card. Cards planned ahead but
  not shown yet are dropped and planned again, so a like shows in the
  very next card.
- Each (kind, category) has its own shuffled queue; unseen items first.
- A quiz every 3 to 8 cards (random gap). Due reviews first, then a card
  from this session, then anything seen before.
- Quiz tab: the same feed screen with `quizOnly`, a question on every
  card. Due reviews first; then half the time something seen before,
  half the time a new item picked like a feed card.
- XP: quote read 4 s: 2; story read 12 s or opened in full: 5; right quiz
  answer: 10, or 20 from the third right answer in a row. Each card pays
  once per session.
- Affinity (kept across sessions): like +0.5, read +0.1, skipped in under 1.5 s -0.05; weights are
  kept between 0.3 and 3.
- Daily goal 20, 50 (default) or 100 XP. Reaching it extends the streak.
  One streak freeze is earned every 7 streak days (max 2) and covers a
  missed day automatically.
- Levels per category: 50, 150, 300, 500 XP, then every 300.
- Reviews (Leitner): a right answer moves an item up a box (next review
  after 0, 1, 3, 7 or 21 days); a wrong one sends it back to box 1, due
  the same day.
- Goal reached and level up show a confetti card. The goal card says the
  streak is safe for today, a natural place to stop.

Rules that must hold:

- Double tap likes only on the picture, never over buttons, so buttons
  answer at once (no double tap delay).
- Quote and quiz cards never scroll inside; long text shrinks to fit.
  Story cards scroll inside their panel only when the text overflows
  (clamping physics), and pulling past either end turns the page, so a
  vertical drag always ends up moving the feed.
- The quote and the story of the day depend only on the calendar day, so it is the same
  all day and swiping back shows the same quotes again.
- Share uses `share_plus` and is hidden on Linux, where it has no share
  sheet. Copy works everywhere.
- No network access. Everything ships in the bundle. The only way out is
  a Wikipedia link, which `url_launcher` opens in the browser.
