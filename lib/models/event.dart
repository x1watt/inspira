/// One dated event in world history, for "on this day" and date quizzes.
class HistoryEvent {
  const HistoryEvent({
    required this.id,
    required this.title,
    required this.year,
    required this.month,
    required this.day,
    required this.summary,
    this.calendar = 'gregorian',
    this.reason = '',
    this.significance = '',
    this.participants = const [],
    this.countries = const [],
    this.place = '',
    this.lat,
    this.lon,
    this.tags = const [],
    this.weight = 50,
    this.wikipedia = '',
  });

  factory HistoryEvent.fromJson(Map<String, dynamic> j) => HistoryEvent(
    id: j['id'] as String,
    title: j['title'] as String,
    year: j['year'] as int,
    month: j['month'] as int,
    day: j['day'] as int,
    calendar: j['calendar'] as String? ?? 'gregorian',
    summary: j['summary'] as String,
    reason: j['reason'] as String? ?? '',
    significance: j['significance'] as String? ?? '',
    participants: _strings(j['participants']),
    countries: _strings(j['countries']),
    place: j['place'] as String? ?? '',
    lat: (j['lat'] as num?)?.toDouble(),
    lon: (j['lon'] as num?)?.toDouble(),
    tags: _strings(j['tags']),
    weight: j['weight'] as int? ?? 50,
    wikipedia: j['wikipedia'] as String? ?? '',
  );

  static List<String> _strings(Object? v) => [
    for (final s in v as List? ?? const []) s as String,
  ];

  final String id;
  final String title;

  /// Negative for BC; there is no year 0.
  final int year;
  final int month;
  final int day;

  /// `julian` before 15 October 1582, else `gregorian`.
  final String calendar;
  final String summary;

  /// Why it happened.
  final String reason;
  final String significance;
  final List<String> participants;

  /// Modern country names, for search.
  final List<String> countries;
  final String place;

  /// Where it mostly took place; null when there is no single place.
  final double? lat;
  final double? lon;
  final List<String> tags;

  /// Importance 1 to 100; ranks events that share a day.
  final int weight;

  /// English Wikipedia article title.
  final String wikipedia;

  static const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// `20 July 1969`, `15 March 44 BC`.
  String get dateLabel =>
      '$day ${months[month - 1]} ${year < 0 ? '${-year} BC' : '$year'}';

  /// `20 July`, for headings of a calendar day.
  static String dayLabel(int month, int day) => '$day ${months[month - 1]}';

  /// Whole years between this event and [nowYear]; there is no year 0.
  int yearsAgo(int nowYear) => nowYear - year - (year < 0 ? 1 : 0);

  bool get hasPlace => lat != null && lon != null;

  /// Plain text for copy and share.
  String toShareText() => [
    '$dateLabel: $title',
    summary,
    if (wikipediaUrl.isNotEmpty) wikipediaUrl,
  ].join('\n\n');

  /// One of the five app categories, for XP: from the first tag.
  String get category => switch (tags.isEmpty ? '' : tags.first) {
    'war' => 'strategy',
    'politics' || 'revolution' || 'law' => 'leadership',
    'diplomacy' || 'culture' || 'religion' || 'rights' => 'relations',
    'disaster' || 'medicine' => 'family',
    _ => 'team',
  };

  String get wikipediaUrl => wikipedia.isEmpty
      ? ''
      : 'https://en.wikipedia.org/wiki/${Uri.encodeComponent(wikipedia.replaceAll(' ', '_'))}';
}
