# Events: writer brief

You write one slice of a list of about 1000 important events in world
history. The list feeds an "on this day" view (events that happened on the
same calendar day in other years) and date quizzes in the Inspira app.

## Output

Write exactly one file, `tool/pipeline/events/raw/<slice>.jsonl` (the
slice name is given in your task), one JSON object per line, UTF-8, no
other text. Fields, all required unless marked optional:

| Field | Meaning |
|---|---|
| `key` | lowercase slug, `<year>-<mm>-<dd>-<short-words>`, BC years as `bc44`; unique |
| `title` | short headline, at most 70 characters, e.g. `Apollo 11 lands on the Moon` |
| `year`, `month`, `day` | integers; BC years negative (44 BC is `-44`; there is no year 0) |
| `calendar` | `gregorian` or `julian`, see below |
| `summary` | what happened, 1 to 3 plain sentences, in your own words |
| `reason` | why it happened: causes, motives, the situation that led to it; 1 or 2 sentences |
| `significance` | why it matters, 1 sentence |
| `participants` | list: the main people, states, armies, organizations, as named at the time (`Roman Republic`, `Ottoman Empire`, `NASA`, `Neil Armstrong`) |
| `countries` | list: modern country names (short English names) where it happened and of the main parties, for search (`Italy`, `United States`) |
| `place` | where it mostly took place, specific (`Waterloo, near Brussels`), with the modern country |
| `lat`, `lon` | decimal degrees of that place, 4 decimals; `null` both when there is no single place on Earth (a law, a Moon landing, an online event) |
| `tags` | 1 to 3 of: `war`, `politics`, `revolution`, `law`, `diplomacy`, `science`, `technology`, `exploration`, `medicine`, `religion`, `culture`, `economy`, `disaster`, `sport`, `rights` |
| `weight` | importance 1 to 100, see below |
| `wikipedia` | the English Wikipedia article title that covers exactly this event (`Apollo 11`, `Battle of Waterloo`, `Assassination of Julius Caesar`) |

## Rules

- Only events with one known calendar day. A war is not an event; its
  start (the invasion, the declaration), a decisive battle, or the
  signing that ended it are. Multi-day events: use the day they are known
  by (first day of a battle, unless it is known by its last day).
- Dates as English Wikipedia gives them. Before 15 October 1582: Julian
  (`calendar: julian`). From then on: Gregorian, also for countries that
  still used the Julian calendar (Russia before 1918: use the New Style
  date, so the October Revolution is 7 November 1917).
- Accuracy over quantity. If you are not sure of the day, the place or the
  coordinates, leave the event out and pick another one. Every date will
  be checked against Wikidata by script, and errors are removed.
- World history, not only Europe and North America: at least 35 percent
  of each slice happened elsewhere (Asia, Africa, Middle East, Latin
  America, Oceania), where the slice's era allows.
- Mix the kinds: politics and war, but also science, discoveries,
  inventions, exploration, medicine, culture, religion, rights, disasters,
  economy. At most 40 percent `war`.
- Spread the days: avoid stacking many events on the same day of the year
  inside your slice.
- No duplicates, no overlaps with neighbouring slices: stay strictly inside
  your slice's years.
- Plain text: no em dashes, en dashes, arrows or curly quotes. Use commas,
  colons or full stops. Straight quotes only.

## Weight

How much the event changed the world, judged today:

- 90 to 100: turned world history (fall of Constantinople, storming of the
  Bastille, Hiroshima bombing, Apollo 11, fall of the Berlin Wall). Few.
- 70 to 89: major for a continent or a field (Battle of Hastings,
  Darwin publishes On the Origin of Species, independence of India).
- 50 to 69: major for a country, or a well known milestone.
- 30 to 49: notable, worth knowing.
- below 30: do not include.

Use the whole range; the median should be around 60.
