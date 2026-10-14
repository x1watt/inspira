import 'dart:math';

import '../models/category.dart';
import '../models/quote.dart';
import '../models/story.dart';
import 'progress_store.dart';
import 'quiz_generator.dart';
import 'quote_repository.dart';
import 'story_repository.dart';

/// One page of the feed.
sealed class FeedCard {
  const FeedCard();

  String get category;

  /// `quote`, `story`, `history`, `study` or `quiz`.
  String get kind;
}

class QuoteFeedCard extends FeedCard {
  const QuoteFeedCard(this.quote, {this.header});
  final Quote quote;
  final String? header;
  @override
  String get category => quote.category;
  @override
  String get kind => 'quote';
}

class StoryFeedCard extends FeedCard {
  const StoryFeedCard(this.story);
  final Story story;
  @override
  String get category => story.category;
  @override
  String get kind => story.kind.id;
}

class QuizFeedCard extends FeedCard {
  const QuizFeedCard(this.quiz, {required this.review});
  final Quiz quiz;

  /// True when the item came back from the review schedule.
  final bool review;
  @override
  String get category => quiz.category;
  @override
  String get kind => 'quiz';
}

/// Builds the endless feed one card at a time.
///
/// - Kind and category are drawn by the user's affinity weights, with 20
///   percent pure exploration so new topics keep appearing.
/// - Unseen items come first; each (kind, category) has its own shuffled
///   queue, so picking a card costs O(categories), not O(items).
/// - A quiz comes every 4 to 7 cards (an unpredictable gap keeps it a small
///   surprise), first from reviews that are due, else from a card seen
///   earlier in this session.
class FeedEngine {
  FeedEngine({
    required this.quotes,
    required this.stories,
    required this.progress,
    required this.quizzes,
    Random? random,
    DateTime? today,
  }) : _random = random ?? Random() {
    final first = quotes.quoteOfDay(today ?? DateTime.now());
    if (first != null) {
      _cards.add(QuoteFeedCard(first, header: 'Quote of the day'));
    }
    _untilQuiz = _quizGap();
  }

  static const kinds = ['quote', 'story', 'history', 'study'];

  /// Base share of each kind before the user's own weights.
  static const _kindBase = {
    'quote': 0.45,
    'story': 0.2,
    'history': 0.2,
    'study': 0.15,
  };
  static const _explore = 0.2;

  final ProgressStore progress;
  final QuizGenerator quizzes;
  final QuoteRepository quotes;
  final StoryRepository stories;
  final Random _random;
  final _cards = <FeedCard>[];
  final _queues = <String, _Queue>{};
  final _sessionSeen = <String>[];
  final _quizzed = <String>{};
  late int _untilQuiz;

  int _quizGap() => 4 + _random.nextInt(4);

  FeedCard cardAt(int index) {
    while (_cards.length <= index) {
      _cards.add(_next());
    }
    return _cards[index];
  }

  FeedCard _next() {
    if (--_untilQuiz <= 0) {
      _untilQuiz = _quizGap();
      final quiz = _nextQuiz();
      if (quiz != null) return quiz;
    }
    for (var tries = 0; tries < 8; tries++) {
      final card = _content(_pickKind(), _pickCategory());
      if (card != null) {
        final id = switch (card) {
          QuoteFeedCard(:final quote) => quote.id,
          StoryFeedCard(:final story) => story.id,
          QuizFeedCard() => '',
        };
        _sessionSeen.add(id);
        return card;
      }
    }
    // Only reachable with an empty collection.
    return _cards.isNotEmpty ? _cards.first : throw StateError('No content');
  }

  QuizFeedCard? _nextQuiz() {
    for (final id in progress.dueReviews()) {
      if (_quizzed.contains(id)) continue;
      final q = quizzes.forId(id, _random);
      if (q != null) {
        _quizzed.add(id);
        return QuizFeedCard(q, review: true);
      }
    }
    // Something from this session, not the card just shown.
    final candidates = [
      for (var i = 0; i < _sessionSeen.length - 2; i++)
        if (!_quizzed.contains(_sessionSeen[i])) _sessionSeen[i],
    ];
    if (candidates.isEmpty) return null;
    final id = candidates[_random.nextInt(candidates.length)];
    final q = quizzes.forId(id, _random);
    if (q == null) return null;
    _quizzed.add(id);
    return QuizFeedCard(q, review: false);
  }

  String _pickKind() => _weighted(
    kinds,
    (k) => _kindBase[k]! * progress.weight(k),
    exploreUniform: false,
  );

  String _pickCategory() =>
      _weighted([for (final c in QuoteCategory.all) c.id], progress.weight);

  String _weighted(
    List<String> keys,
    double Function(String) w, {
    bool exploreUniform = true,
  }) {
    if (exploreUniform && _random.nextDouble() < _explore) {
      return keys[_random.nextInt(keys.length)];
    }
    final total = keys.fold(0.0, (s, k) => s + w(k));
    var r = _random.nextDouble() * total;
    for (final k in keys) {
      r -= w(k);
      if (r <= 0) return k;
    }
    return keys.last;
  }

  FeedCard? _content(String kind, String category) {
    final queue = _queues['$kind/$category'] ??= _Queue(
      _items(kind, category)..shuffle(_random),
    );
    final id = queue.next(progress.seen);
    if (id == null) return null;
    if (kind == 'quote') return QuoteFeedCard(quotes.byId(id)!);
    return StoryFeedCard(stories.byId(id)!);
  }

  List<String> _items(String kind, String category) => kind == 'quote'
      ? [for (final q in quotes.inCategory(category)) q.id]
      : [
          for (final s in stories.filter(
            category: category,
            kind: StoryKind.byId(kind),
          ))
            s.id,
        ];
}

/// Shuffled ids served in a loop, skipping ids already seen until a whole
/// round found nothing new.
class _Queue {
  _Queue(this.ids);

  final List<String> ids;
  int _pos = 0;

  String? next(Set<String> seen) {
    if (ids.isEmpty) return null;
    for (var i = 0; i < ids.length; i++) {
      final id = ids[_pos];
      _pos = (_pos + 1) % ids.length;
      if (!seen.contains(id)) return id;
    }
    // Everything seen: start repeating.
    final id = ids[_pos];
    _pos = (_pos + 1) % ids.length;
    return id;
  }
}
