import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspira/app_scope.dart';
import 'package:inspira/data/event_repository.dart';
import 'package:inspira/data/favorites_store.dart';
import 'package:inspira/data/image_repository.dart';
import 'package:inspira/data/progress_store.dart';
import 'package:inspira/data/quote_repository.dart';
import 'package:inspira/data/story_repository.dart';
import 'package:inspira/models/event.dart';
import 'package:inspira/models/story.dart';
import 'package:inspira/screens/map_screen.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('focus opens the place; the list shows the closest', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final data = AppData(
      quotes: QuoteRepository(const []),
      stories: StoryRepository([
        Story.fromJson({
          'id': 'story-belem',
          'category': 'strategy',
          'kind': 'history',
          'title': 'Gama sails from Belem',
          'text': 'The fleet left the river.\n\nIt reached India.',
          'lesson': 'Go far.',
          'source': 'Chronicle',
          'basis': 'documented',
          'date': '1497',
          'place': 'Belem Tower, Lisbon, Portugal',
          'lat': 38.6916,
          'lon': -9.216,
        }),
      ]),
      favorites: await FavoritesStore.load(),
      images: ImageRepository.empty(),
      progress: await ProgressStore.load(),
      events: EventRepository([
        const HistoryEvent(
          id: 'event-quake',
          title: 'Lisbon earthquake',
          year: 1755,
          month: 11,
          day: 1,
          summary: 'The city fell.',
          place: 'Lisbon, Portugal',
          lat: 38.71,
          lon: -9.14,
          weight: 80,
        ),
      ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        // As in the app: above the Navigator, so sheets reach it.
        builder: (context, nav) => AppScope(data: data, child: nav!),
        home: const MapScreen(
          focus: 'story-belem',
          locate: false,
          tiles: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The sheet with the whole story and directions.
    expect(find.text('Directions'), findsOneWidget);
    expect(find.text('It reached India.'), findsOneWidget);
    expect(find.text('Go far.'), findsOneWidget);

    Navigator.of(tester.element(find.text('Go far.'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Near the map center'), findsOneWidget);
    expect(find.text('Gama sails from Belem'), findsOneWidget);
    expect(find.text('Lisbon earthquake'), findsOneWidget);
    expect(find.text('0 m'), findsOneWidget);
    expect(find.byTooltip('Lisbon earthquake'), findsOneWidget);
  });
}
