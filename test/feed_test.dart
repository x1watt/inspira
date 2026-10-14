import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:inspira/data/feed_engine.dart';
import 'package:inspira/data/progress_store.dart';
import 'package:inspira/data/quiz_generator.dart';
import 'package:inspira/data/quote_repository.dart';
import 'package:inspira/data/story_repository.dart';
import 'package:inspira/models/event.dart';
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

List<HistoryEvent> _events() => [
  for (var i = 0; i < 40; i++)
    HistoryEvent(
      id: 'event-$i',
      title: 'Event $i',
      year: 1500 + i * 12,
      month: 1 + i % 12,
      day: 1 + i % 28,
      summary: 'Something happened.',
      reason: 'Because.',
      place: 'Place $i',
      tags: const ['politics'],
      weight: 30 + i,
    ),
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
        case EventFeedCard() || QuizFeedCard():
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

  FeedEngine quizEngine(int seed, {List<String> liked = const []}) =>
      FeedEngine(
        quotes: quotes,
        stories: stories,
        progress: progress,
        quizzes: QuizGenerator(quotes.quotes, stories.stories, _events()),
        random: Random(seed),
        quizOnly: true,
        events: _events(),
        liked: () => liked,
      );

  List<String> quizIds(FeedEngine e, int n) => [
    for (var i = 0; i < n; i++) (e.cardAt(i) as QuizFeedCard).quiz.itemId,
  ];

  test('quizzes ask about stories read or liked first', () {
    final read = [
      for (var i = 0; i < 6; i++) 'story-team-history-$i',
      for (var i = 0; i < 6; i++) 'story-family-study-$i',
      for (var i = 0; i < 6; i++) 'story-leadership-story-$i',
    ];
    read.forEach(progress.markRead);
    const liked = ['story-relations-story-0', 'q-team-1'];
    final ids = quizIds(quizEngine(1, liked: liked), 9);
    // 19 recent stories: the first 9 questions all come from them.
    expect(ids.toSet(), hasLength(9));
    expect({...read, liked.first}.containsAll(ids), isTrue);
  });

  test('few or no recent stories: quizzes about dated events', () {
    final none = quizIds(quizEngine(2), 20);
    expect(none.every((id) => id.startsWith('event-')), isTrue);
    expect(none.toSet(), hasLength(20));

    progress.markRead('story-team-story-0');
    final few = quizIds(quizEngine(3), 20);
    expect(few, contains('story-team-story-0'));
    expect(few.where((id) => id.startsWith('event-')).length, 19);
  });

  test('event questions have the answer and explain it', () {
    final gen = QuizGenerator(const [], const [], _events());
    final r = Random(4);
    for (var i = 0; i < 20; i++) {
      final q = gen.forId('event-${i % 40}', r)!;
      expect(q.options.toSet(), hasLength(3));
      expect(q.options[q.answer], anyOf('Event ${i % 40}', contains(' 1')));
      expect(q.explanation, contains('Because.'));
    }
    final e = _events()[3];
    expect(e.dateLabel, '4 April 1536');
    expect(
      const HistoryEvent(
        id: 'event-x',
        title: 'Ides',
        year: -44,
        month: 3,
        day: 15,
        summary: '',
      ).dateLabel,
      '15 March 44 BC',
    );
  });

  test('on this day: today\'s events, most important first, once', () {
    final events = [
      ..._events(),
      for (var i = 0; i < 3; i++)
        HistoryEvent(
          id: 'event-today-$i',
          title: 'Today $i',
          year: 1900 + i,
          month: 10,
          day: 14,
          summary: 'On the day.',
          weight: 50 + i * 20,
        ),
    ];
    FeedEngine make(bool quizOnly) => FeedEngine(
      quotes: quotes,
      stories: stories,
      progress: progress,
      quizzes: QuizGenerator(quotes.quotes, stories.stories, events),
      random: Random(6),
      quizOnly: quizOnly,
      events: events,
      today: DateTime(2026, 10, 14),
    );
    final e = make(false);
    final at = <int, String>{
      for (var i = 0; i < 80; i++)
        if (e.cardAt(i) case EventFeedCard(:final event)) i: event.id,
    };
    expect(at.values, ['event-today-2', 'event-today-1', 'event-today-0']);
    final pos = at.keys.toList();
    expect(pos.first, 1);
    for (var i = 1; i < pos.length; i++) {
      expect(pos[i] - pos[i - 1], inInclusiveRange(10, 16));
    }
    // Seen ones do not come back; the quiz tab has none.
    progress.markSeen('event-today-2');
    final again = make(false);
    expect((again.cardAt(1) as EventFeedCard).event.id, 'event-today-1');
    final quiz = make(true);
    expect(
      [for (var i = 0; i < 30; i++) quiz.cardAt(i)].whereType<EventFeedCard>(),
      isEmpty,
    );
    expect(
      const HistoryEvent(
        id: 'x',
        title: 'x',
        year: -44,
        month: 3,
        day: 15,
        summary: '',
      ).yearsAgo(2026),
      2069,
    );
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
