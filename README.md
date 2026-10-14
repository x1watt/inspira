# Inspira

Wisdom from history: quotes on relations, leadership, team, family and
strategy, each with author, book or letter, date and presumed place of
writing, plus short stories, historical episodes and psychology studies in
the same categories.

Runs on Android, Linux, Windows, macOS and the web. Use it in the browser:
https://x1watt.github.io/inspira/

Features: a full-screen feed (swipe up) of quotes, stories, history and
studies over public domain art, with quizzes popping up between cards and a Quiz tab of questions only, XP, levels per
category, a daily goal and a streak; story of the day, browse and search by
category, favorites, copy and share.

## Quotes

One JSON file per quote in `quotes/<category>/`. Most quotes were extracted
from public domain editions (Project Gutenberg) and checked word for word
against them (`"confidence": "verified"`); the rest are well documented
attributions (`"attributed"`). Format: `docs/architecture.md`; how the
collection was built: `tool/pipeline/README.md`.

## Stories

One JSON file per story in `stories/<category>/`: a retelling in our own
words with its lesson, source, `basis` (documented, anecdote, legend, fable,
study...) and caveats. Format: `docs/architecture.md`.

After adding or editing quotes or stories, rebuild the bundles:

    dart run tool/bundle_quotes.dart

## Build

On this machine builds go through the shared lock:

    ~/bin/android-build-locked flutter build apk
    ~/bin/android-build-locked flutter build linux
    ~/bin/android-build-locked flutter run -d linux
    ~/bin/android-build-locked flutter build web --base-href /inspira/

Every push to `main` builds the web version and publishes it on GitHub
Pages (`.github/workflows/pages.yml`).

To start the last Linux build without compiling: `./launch-linux.sh`.

Tests: `flutter test`.

App icon: `branding/icon.svg`, with a 1024 px render in `branding/`. The
web icons and Android launcher icons (`mipmap-*`, adaptive icon in
`mipmap-anydpi-v26`) are resized from that render.
