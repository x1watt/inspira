/// One story, historical episode or study, as stored in
/// `stories/<category>/<id>.json` and bundled into `assets/stories.json` by
/// `tool/bundle_quotes.dart`.
class Story {
  const Story({
    required this.id,
    required this.category,
    required this.kind,
    required this.title,
    required this.text,
    required this.lesson,
    required this.people,
    required this.date,
    required this.year,
    required this.location,
    required this.source,
    required this.sourceUrl,
    required this.basis,
    required this.caveat,
    this.place = '',
    this.lat,
    this.lon,
  });

  factory Story.fromJson(Map<String, dynamic> j) => Story(
    id: j['id'] as String,
    category: j['category'] as String,
    kind: StoryKind.byId(j['kind'] as String),
    title: j['title'] as String,
    text: j['text'] as String,
    lesson: j['lesson'] as String,
    people: j['people'] as String? ?? '',
    date: j['date'] as String? ?? '',
    year: j['year'] as int?,
    location: j['location'] as String? ?? '',
    source: j['source'] as String,
    sourceUrl: j['source_url'] as String? ?? '',
    basis: j['basis'] as String? ?? '',
    caveat: j['caveat'] as String? ?? '',
    place: j['place'] as String? ?? '',
    lat: (j['lat'] as num?)?.toDouble(),
    lon: (j['lon'] as num?)?.toDouble(),
  );

  final String id;
  final String category;
  final StoryKind kind;
  final String title;

  /// The retelling; paragraphs are separated by blank lines.
  final String text;

  /// One or two sentences: what the reader can take away.
  final String lesson;

  /// Main figures, or the researchers of a study.
  final String people;
  final String date;

  /// Sort key; negative is BC.
  final int? year;
  final String location;
  final String source;
  final String sourceUrl;

  /// How solid the account is: documented, anecdote, legend, fable,
  /// parable, folktale, literature or study.
  final String basis;

  /// Known doubts, such as failed replications or disputed details.
  final String caveat;

  /// Where a visitor can go to see the place, with its coordinates; empty
  /// and null when there is no single real place.
  final String place;
  final double? lat;
  final double? lon;

  bool get hasPlace => lat != null && lon != null;

  /// What [basis] means for the reader, or empty when it needs no note.
  String get basisNote => switch (basis) {
    'documented' => 'Documented history',
    'anecdote' => 'Anecdote reported by the source; details may be embellished',
    'legend' => 'Legend; not documented history',
    'fable' => 'Fable',
    'parable' => 'Parable',
    'folktale' => 'Folk tale',
    'literature' => 'Retelling of a literary work',
    _ => '',
  };

  /// Plain text for copy and share.
  String toShareText() =>
      [title, text, 'Lesson: $lesson', 'Source: $source'].join('\n\n');
}

enum StoryKind {
  story('story', 'Story'),
  history('history', 'History'),
  study('study', 'Study');

  const StoryKind(this.id, this.label);

  final String id;
  final String label;

  static StoryKind byId(String id) =>
      values.firstWhere((k) => k.id == id, orElse: () => story);
}
