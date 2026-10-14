import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:inspira/data/feed_engine.dart';
import 'package:inspira/data/progress_store.dart';
import 'package:inspira/data/quiz_generator.dart';
import 'package:inspira/data/quote_repository.dart';
import 'package:inspira/data/story_repository.dart';
import 'package:inspira/models/quote.dart';
import 'package:inspira/models/story.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const _cats = ['relations', 'leadership', 'team', 'family', 'strategy'];

List<Quote> _quotes() => [
  for (final c in _cats)
    for (var i = 0; i < 20; i++)
      Quote.fromJson({
        'id': 'q-$c-$i',
        'category': c,
        'text': 'Quote $i about $c.',
        'author': 'Author ${i % 6}',
        'reference': 'Book',
        'confidence': 'verified',
      }),
];

List<Story> _stories() => [
  for (final c in _cats)
    for (final k in ['story', 'history', 'study'])
      for (var i = 0; i < 6; i++)
        Story.fromJson({
          'id': 'story-$c-$k-$i',
          'category': c,
          'kind': k,
          'title': '$k $i on $c',
          'text': 'Text.',
          'lesson': 'Lesson $k $i on $c.',
          'date': '${1000 + i * 300}',
          'year': 1000 + i * 300,
          'source': 'Source',
          'basis': k == 'study'
              ? 'study'
              : k == 'history'
              ? 'documented'
              : 'fable',
        }),
];

void main() {
  late ProgressStore progress;
  late QuoteRepository quotes;
  late StoryRepository stories;
  late QuizGenerator quizzes;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    progress = await ProgressStore.load();
    quotes = QuoteRepository(_quotes());
    stories = StoryRepository(_stories());
    quizzes = QuizGenerator(quotes.quotes, stories.stories);
  });

  FeedEngine engine(int seed) => FeedEngine(
    quotes: quotes,
    stories: stories,
    progress: progress,
    quizzes: quizzes,
    random: Random(seed),
  );

  test('quiz questions contain the right answer once', () {
    final r = Random(1);
    for (final id in [
      'q-team-3',
      'story-family-study-2',
      'story-team-story-1',
      'story-strategy-history-4',
    ]) {
      final q = quizzes.forId(id, r)!;
      expect(q.options.toSet(), hasLength(q.options.length));
      expect(q.answer, inInclusiveRange(0, q.options.length - 1));
    }
    final who = quizzes.forId('q-team-3', r)!;
    expect(who.options[who.answer], 'Author 3');
  });

  test('starts with a random story and quizzes every 3 to 8 cards', () {
    final openers = {
      for (var seed = 0; seed < 20; seed++)
        (engine(seed).cardAt(0) as StoryFeedCard).story.id,
    };
    expect(openers.length, greaterThan(5));
    final e = engine(7);
    final quizAt = [
      for (var i = 0; i < 120; i++)
        if (e.cardAt(i) is QuizFeedCard) i,
    ];
    expect(quizAt, isNotEmpty);
    for (var i = 1; i < quizAt.length; i++) {
      expect(quizAt[i] - quizAt[i - 1], inInclusiveRange(3, 8));
    }
  });

  test('no repeats while unseen content remains', () {
    final e = engine(3);
    final ids = <String>[];
    for (var i = 0; i < 60; i++) {
      switch (e.cardAt(i)) {
        case QuoteFeedCard(:final quote):
          ids.add(quote.id);
        case StoryFeedCard(:final story):
          ids.add(story.id);
        case QuizFeedCard():
          break;
      }
    }
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('liking a category shows more of it', () {
    int countTeam(FeedEngine e) =>
        [for (var i = 1; i < 300; i++) e.cardAt(i)]
            .where((c) => c is! QuizFeedCard && c.category == 'team')
            .length;
    final before = countTeam(engine(11));
    for (var i = 0; i < 10; i++) {
      progress.nudge('team', 'quote', 0.3);
    }
    final after = countTeam(engine(11));
    expect(after, greaterThan(before * 1.5));
  });

  test('a like steers the very next cards', () {
    double share(double factor) {
      var same = 0, total = 0;
      for (var seed = 0; seed < 40; seed++) {
        final e = engine(seed);
        final liked = e.cardAt(0);
        e.cardAt(6); // planned ahead, then replanned by the like
        e.steer(liked, factor, keep: 0);
        for (var i = 1; i < 6; i++) {
          final c = e.cardAt(i);
          if (c is QuizFeedCard) continue;
          total++;
          if (c.category == liked.category) same++;
        }
      }
      return same / total;
    }

    expect(share(4), greaterThan(share(1) * 1.6));
  });

  test('quiz mode asks a question on every card, even for a new user', () {
    final e = FeedEngine(
      quotes: quotes,
      stories: stories,
      progress: progress,
      quizzes: quizzes,
      random: Random(9),
      quizOnly: true,
    );
    final ids = [
      for (var i = 0; i < 20; i++) (e.cardAt(i) as QuizFeedCard).quiz.itemId,
    ];
    expect(ids.toSet().length, greaterThan(10));
  });

  test('wrong answers come back as reviews', () {
    progress.answerQuiz('q-family-5', correct: false);
    final e = engine(5);
    final firstQuiz = [for (var i = 0; i < 20; i++) e.cardAt(i)]
        .whereType<QuizFeedCard>()
        .first;
    expect(firstQuiz.review, isTrue);
    expect(firstQuiz.quiz.itemId, 'q-family-5');
  });
}
