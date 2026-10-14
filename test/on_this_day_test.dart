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
import 'package:inspira/screens/on_this_day_screen.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('lists the day ranked by weight and moves between days', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    HistoryEvent ev(String title, int m, int d, int w) => HistoryEvent(
      id: 'event-$title',
      title: title,
      year: 1969,
      month: m,
      day: d,
      summary: 'What happened in $title.',
      reason: 'Because of $title.',
      place: 'Somewhere',
      lat: 1,
      lon: 2,
      weight: w,
    );
    final data = AppData(
      quotes: QuoteRepository(const []),
      stories: StoryRepository(const []),
      favorites: await FavoritesStore.load(),
      images: ImageRepository.empty(),
      progress: await ProgressStore.load(),
      events: EventRepository([
        ev('Minor', 7, 20, 10),
        ev('Landing', 7, 20, 95),
        ev('Next day', 7, 21, 50),
        ev('August', 8, 5, 50),
      ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(
          data: data,
          child: OnThisDayScreen(now: () => DateTime(2026, 7, 20)),
        ),
      ),
    );
    expect(find.text('Today, 20 July'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Landing')).dy,
      lessThan(tester.getTopLeft(find.text('Minor')).dy),
    );
    expect(find.text('20 July 1969, 57 years ago, Somewhere'), findsWidgets);
    expect(find.text('Show on the map'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Next day'));
    await tester.pump();
    expect(find.text('Next day'), findsOneWidget);
    expect(find.text('Landing'), findsNothing);

    // An empty day offers the next day that has events.
    await tester.tap(find.byTooltip('Next day'));
    await tester.pump();
    await tester.tap(find.text('Go to 5 August'));
    await tester.pump();
    expect(find.text('August'), findsOneWidget);
  });
}
