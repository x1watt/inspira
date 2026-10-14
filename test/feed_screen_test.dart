import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspira/app_scope.dart';
import 'package:inspira/data/favorites_store.dart';
import 'package:inspira/data/feed_engine.dart';
import 'package:inspira/data/image_repository.dart';
import 'package:inspira/data/progress_store.dart';
import 'package:inspira/data/quote_repository.dart';
import 'package:inspira/data/story_repository.dart';
import 'package:inspira/models/story.dart';
import 'package:inspira/screens/feed_screen.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('reading earns XP, quizzes answer, double tap likes', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final quotes = QuoteRepository(
      parseQuotes(
        jsonEncode([
          for (final c in [
            'relations',
            'leadership',
            'team',
            'family',
            'strategy',
          ])
            for (var i = 0; i < 8; i++)
              {
                'id': 'q-$c-$i',
                'category': c,
                'text': 'Quote $i about $c.',
                'author': 'Author $i',
                'reference': 'Book',
                'confidence': 'verified',
              },
        ]),
      ),
    );
    final data = AppData(
      quotes: quotes,
      stories: StoryRepository(const []),
      favorites: await FavoritesStore.load(),
      images: ImageRepository.empty(),
      progress: await ProgressStore.load(),
    );
    var now = DateTime(2026, 10, 1, 9);
    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(
          data: data,
          child: Scaffold(
            body: FeedScreen(random: Random(2), now: () => now),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsOneWidget);

    Future<void> next() async {
      now = now.add(const Duration(seconds: 5));
      await tester.drag(find.byType(PageView), const Offset(0, -500));
      await tester.pumpAndSettle();
    }

    await next();
    expect(data.progress.todayXp, 2);
    expect(find.text('2 / 50 XP'), findsOneWidget);

    // Double tap likes the card on screen.
    // Top left is picture only (text and buttons sit lower).
    final pic =
        tester.getTopLeft(find.byType(PageView)) + const Offset(40, 120);
    await tester.tapAt(pic);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(pic);
    await tester.pumpAndSettle();
    expect(data.favorites.ids, hasLength(1));

    // Swipe until a quiz shows up and answer it right.
    for (
      var i = 0;
      i < 8 && find.text('Who said this?').evaluate().isEmpty;
      i++
    ) {
      await next();
    }
    expect(find.text('Who said this?'), findsOneWidget);
    final quizCard = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'QuizFeedPage',
    );
    final quiz = (tester.widget(quizCard) as dynamic).quiz;
    final before = data.progress.todayXp;
    await tester.tap(
      find.descendant(
        of: quizCard,
        matching: find.text(quiz.options[quiz.answer] as String),
      ),
    );
    await tester.pumpAndSettle();
    expect(data.progress.todayXp, before + 10);
    expect(find.textContaining('Correct!'), findsOneWidget);
    expect(FeedEngine.kinds, contains('quote'));
  });

  testWidgets('a long story scrolls, then hands the drag to the feed', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final long = List.filled(
      12,
      'A sentence that goes on for a while.',
    ).join(' ');
    final stories = StoryRepository([
      for (final c in ['relations', 'leadership', 'team', 'family', 'strategy'])
        for (var i = 0; i < 4; i++)
          Story.fromJson({
            'id': 'story-$c-$i',
            'category': c,
            'kind': 'history',
            'title': 'Story $i about $c',
            'text': List.filled(3, long).join('\n\n'),
            'lesson': 'Lesson $i.',
            'source': 'Source',
            'basis': 'documented',
          }),
    ]);
    final data = AppData(
      quotes: QuoteRepository(const []),
      stories: stories,
      favorites: await FavoritesStore.load(),
      images: ImageRepository.empty(),
      progress: await ProgressStore.load(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(
          data: data,
          child: Scaffold(body: FeedScreen(random: Random(4))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = find.textContaining('Story ').evaluate().first.widget;
    final title = (first as Text).data!;

    // The first drag scrolls the text; the card stays.
    // A point on the text panel (left of the action rail).
    final at = tester.getCenter(find.byType(PageView)) + const Offset(-60, 120);
    await tester.dragFrom(at, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(find.text(title), findsOneWidget);

    // Pulling past the end turns the page.
    for (var i = 0; i < 6 && find.text(title).evaluate().isNotEmpty; i++) {
      await tester.dragFrom(at, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    expect(find.text(title), findsNothing);
  });
}
