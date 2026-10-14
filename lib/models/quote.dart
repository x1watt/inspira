/// One quote as stored in `quotes/<category>/<id>.json` and bundled into
/// `assets/quotes.json` by `tool/bundle_quotes.dart`.
class Quote {
  const Quote({
    required this.id,
    required this.category,
    required this.text,
    required this.author,
    required this.authorLifespan,
    required this.reference,
    required this.locator,
    required this.date,
    required this.year,
    required this.location,
    required this.originalLanguage,
    required this.translation,
    required this.sourceUrl,
    required this.confidence,
    this.speaker,
  });

  factory Quote.fromJson(Map<String, dynamic> j) => Quote(
    id: j['id'] as String,
    category: j['category'] as String,
    text: j['text'] as String,
    author: j['author'] as String,
    authorLifespan: j['author_lifespan'] as String? ?? '',
    speaker: j['speaker'] as String?,
    reference: j['reference'] as String,
    locator: j['locator'] as String? ?? '',
    date: j['date'] as String? ?? '',
    year: j['year'] as int?,
    location: j['location'] as String? ?? '',
    originalLanguage: j['original_language'] as String? ?? '',
    translation: j['translation'] as String? ?? '',
    sourceUrl: j['source_url'] as String? ?? '',
    confidence: j['confidence'] as String? ?? 'attributed',
  );

  final String id;
  final String category;
  final String text;
  final String author;
  final String authorLifespan;

  /// Who speaks the words inside the work, when not the author
  /// (Pericles in Thucydides, Laelius in Cicero's dialogue).
  final String? speaker;
  final String reference;
  final String locator;
  final String date;

  /// Sort key; negative is BC.
  final int? year;
  final String location;
  final String originalLanguage;
  final String translation;
  final String sourceUrl;

  /// `verified`: text was matched word for word against the source text.
  /// `attributed`: well documented attribution, not machine checked.
  final String confidence;

  bool get isVerified => confidence == 'verified';

  /// "Pericles, in Thucydides" or just "Seneca".
  String get byline => speaker == null ? author : '$speaker, in $author';

  String get citation {
    final parts = [
      reference,
      if (locator.isNotEmpty) locator,
      if (date.isNotEmpty) date,
    ];
    return parts.join(', ');
  }

  /// Plain text for copy and share.
  String toShareText() => '"$text"\n\n$byline\n$citation';
}
