import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspira/app_scope.dart';
import 'package:inspira/data/favorites_store.dart';
import 'package:inspira/data/image_repository.dart';
import 'package:inspira/data/progress_store.dart';
import 'package:inspira/data/quote_repository.dart';
import 'package:inspira/data/story_repository.dart';
import 'package:inspira/main.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const _categories = ['relations', 'leadership', 'team', 'family', 'strategy'];

void main() {
  testWidgets('tabs and pushed screens can reach the data', (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final quotes = QuoteRepository(
      parseQuotes(
        jsonEncode([
          for (final c in _categories)
            {
              'id': 'q-$c',
              'category': c,
              'text': 'A quote about $c.',
              'author': 'Seneca',
              'reference': 'Letters',
              'date': 'c. AD 64',
              'location': 'Rome',
              'confidence': 'verified',
            },
        ]),
      ),
    );
    final stories = StoryRepository(
      parseStories(
        jsonEncode([
          for (final c in _categories)
            {
              'id': 'story-$c',
              'category': c,
              'kind': 'history',
              'title': 'A story about $c',
              'text': 'Once upon a time.',
              'lesson': 'Learn about $c.',
              'source': 'Plutarch',
              'basis': 'anecdote',
            },
        ]),
      ),
    );
    final favorites = await FavoritesStore.load();
    final progress = await ProgressStore.load();
    await tester.pumpWidget(
      InspiraApp(
        load: () async => AppData(
          quotes: quotes,
          stories: stories,
          favorites: favorites,
          images: ImageRepository.empty(),
          progress: progress,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('0 / 50 XP'), findsOneWidget);

    await tester.tap(find.text('Quotes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();
    expect(find.text('A quote about team.'), findsOneWidget);

    await tester.tap(find.text('A quote about team.'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.star_border).first);
    await tester.pump();
    expect(favorites.contains('q-team'), isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stories'));
    await tester.pumpAndSettle();
    expect(find.text('Story of the day'), findsOneWidget);
    await tester.tap(find.text('Family').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('A story about family'));
    await tester.pumpAndSettle();
    expect(find.text('Learn about family.'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.star_border).first);
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.text('A quote about team.'), findsOneWidget);
    expect(find.text('A story about family'), findsOneWidget);
  });
}
