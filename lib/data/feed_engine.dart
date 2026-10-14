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
/// - The first card is a random story, history or study, so every visit
///   (and every new user) starts somewhere different.
/// - Kind and category are drawn by the user's affinity weights times a
///   session boost, with 20 percent pure exploration so new topics keep
///   appearing. [steer] changes the boost and replans the cards not shown
///   yet, so a like shows up in the very next card.
/// - Unseen items come first; each (kind, category) has its own shuffled
///   queue, so picking a card costs O(categories), not O(items).
/// - A quiz comes every 3 to 8 cards (an unpredictable gap keeps it a small
///   surprise), first from reviews that are due, else from a card seen
///   earlier in this session or before. With [quizOnly] every card is one.
class FeedEngine {
  FeedEngine({
    required this.quotes,
    required this.stories,
    required this.progress,
    required this.quizzes,
    Random? random,
    this.quizOnly = false,
  }) : _random = random ?? Random() {
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
  static const _openers = ['story', 'history', 'study'];

  /// How fast a session boost fades back to 1 with each new card.
  static const _boostDecay = 0.9;

  final ProgressStore progress;

  /// Quiz tab: every card is a question.
  final bool quizOnly;
  final QuizGenerator quizzes;
  final QuoteRepository quotes;
  final StoryRepository stories;
  final Random _random;
  final _cards = <FeedCard>[];

  /// Cards left until the next quiz, after each card; restored by [steer]
  /// so replanning keeps the quiz rhythm.
  final _untilQuizAfter = <int>[];
  final _queues = <String, _Queue>{};
  final _sessionSeen = <String>[];
  final _quizzed = <String>{};
  final _boost = <String, double>{};
  late int _untilQuiz;

  int _quizGap() => 3 + _random.nextInt(6);

  FeedCard cardAt(int index) {
    while (_cards.length <= index) {
      _cards.add(_next());
      _untilQuizAfter.add(_untilQuiz);
    }
    return _cards[index];
  }

  /// Multiplies the session boost of [card]'s category and kind by
  /// [factor] (above 1: more like it, below 1: less) and drops the cards
  /// after [keep] that were planned but not shown yet.
  void steer(FeedCard card, double factor, {required int keep}) {
    for (final k in [card.category, card.kind]) {
      _boost[k] = ((_boost[k] ?? 1) * factor).clamp(0.25, 8.0);
    }
    if (_cards.length <= keep + 1) return;
    for (final dropped in _cards.sublist(keep + 1)) {
      switch (dropped) {
        case QuizFeedCard(:final quiz):
          _quizzed.remove(quiz.itemId);
        case QuoteFeedCard(:final quote):
          _sessionSeen.remove(quote.id);
        case StoryFeedCard(:final story):
          _sessionSeen.remove(story.id);
      }
    }
    _cards.length = keep + 1;
    _untilQuizAfter.length = keep + 1;
    _untilQuiz = _untilQuizAfter[keep];
  }

  double _weight(String key) => progress.weight(key) * (_boost[key] ?? 1);

  FeedCard _next() {
    if (quizOnly) {
      if (_nextQuiz() case final quiz?) return quiz;
    }
    if (_cards.isEmpty && !quizOnly) {
      for (var tries = 0; tries < 8; tries++) {
        final kind = _openers[_random.nextInt(_openers.length)];
        final card = _content(kind, _pickCategory());
        if (card != null) return _shown(card);
      }
    }
    _boost.updateAll((_, b) => 1 + (b - 1) * _boostDecay);
    if (--_untilQuiz <= 0) {
      _untilQuiz = _quizGap();
      final quiz = _nextQuiz();
      if (quiz != null) return quiz;
    }
    for (var tries = 0; tries < 8; tries++) {
      final card = _content(_pickKind(), _pickCategory());
      if (card != null) return _shown(card);
    }
    // Only reachable with an empty collection.
    return _cards.isNotEmpty ? _cards.first : throw StateError('No content');
  }

  FeedCard _shown(FeedCard card) {
    _sessionSeen.add(switch (card) {
      QuoteFeedCard(:final quote) => quote.id,
      StoryFeedCard(:final story) => story.id,
      QuizFeedCard() => '',
    });
    return card;
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
    for (var tries = 0; tries < 8; tries++) {
      final id = _quizCandidate();
      if (id == null) return null;
      _quizzed.add(id);
      final q = quizzes.forId(id, _random);
      if (q != null) return QuizFeedCard(q, review: false);
    }
    return null;
  }

  /// What to ask about: a card from this session (not one of the last two
  /// shown), else anything seen before. In quiz mode, half the questions
  /// are about something new, picked like a feed card.
  String? _quizCandidate() {
    if (quizOnly && _random.nextBool()) return _anyItem();
    final session = [
      for (var i = 0; i < _sessionSeen.length - 2; i++)
        if (!_quizzed.contains(_sessionSeen[i])) _sessionSeen[i],
    ];
    if (session.isNotEmpty) return session[_random.nextInt(session.length)];
    final earlier = [
      for (final id in progress.seen)
        if (!_quizzed.contains(id) && !_sessionSeen.contains(id)) id,
    ];
    if (earlier.isNotEmpty) return earlier[_random.nextInt(earlier.length)];
    return quizOnly ? _anyItem() : null;
  }

  String? _anyItem() => switch (_content(_pickKind(), _pickCategory())) {
    QuoteFeedCard(:final quote) => quote.id,
    StoryFeedCard(:final story) => story.id,
    _ => null,
  };

  String _pickKind() => _weighted(
    kinds,
    (k) => _kindBase[k]! * _weight(k),
    exploreUniform: false,
  );

  String _pickCategory() =>
      _weighted([for (final c in QuoteCategory.all) c.id], _weight);

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
