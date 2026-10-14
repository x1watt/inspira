import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/quote.dart';

const quotesAsset = 'assets/quotes.json';

/// Parses the bundled JSON array. Top level so it can run in an isolate.
List<Quote> parseQuotes(String raw) => [
  for (final j in jsonDecode(raw) as List)
    Quote.fromJson(j as Map<String, dynamic>),
];

/// All quotes, held in memory (about 1-2 MB). Loaded once at startup;
/// decoding runs off the UI isolate (docs/performance.md, rule 1).
class QuoteRepository {
  QuoteRepository(List<Quote> quotes)
    : quotes = List.unmodifiable(quotes),
      _byId = {for (final q in quotes) q.id: q},
      _byCategory = _group(quotes),
      _haystack = [
        for (final q in quotes)
          '${q.text} ${q.author} ${q.speaker ?? ''} ${q.reference}'
              .toLowerCase(),
      ];

  static Future<QuoteRepository> load(AssetBundle bundle) async {
    final raw = await bundle.loadString(quotesAsset);
    final quotes = await compute(parseQuotes, raw);
    return QuoteRepository(quotes);
  }

  final List<Quote> quotes;
  final Map<String, Quote> _byId;
  final Map<String, List<Quote>> _byCategory;
  final List<String> _haystack;

  static Map<String, List<Quote>> _group(List<Quote> quotes) {
    final m = <String, List<Quote>>{};
    for (final q in quotes) {
      (m[q.category] ??= []).add(q);
    }
    return m;
  }

  Quote? byId(String id) => _byId[id];

  List<Quote> inCategory(String category) => _byCategory[category] ?? const [];

  int countIn(String category) => inCategory(category).length;

  /// Same quote for everyone on a given calendar day, different each day.
  Quote? quoteOfDay(DateTime day) => _pick(_dayNumber(day), 0);

  /// The n-th quote after the quote of the day. Stable for a given day, so
  /// swiping back shows the same quotes again.
  Quote? quoteForPage(DateTime day, int page) => _pick(_dayNumber(day), page);

  Quote? _pick(int dayNumber, int page) {
    if (quotes.isEmpty) return null;
    final seed = dayNumber * 1009 + page;
    return quotes[Random(seed).nextInt(quotes.length)];
  }

  static int _dayNumber(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  /// Case-insensitive match on text, author, speaker and reference; every
  /// word of [query] must match. [category] null searches everything.
  List<Quote> search(String query, {String? category}) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final result = <Quote>[];
    for (var i = 0; i < quotes.length; i++) {
      final q = quotes[i];
      if (category != null && q.category != category) continue;
      final h = _haystack[i];
      if (words.every(h.contains)) result.add(q);
    }
    return result;
  }
}
