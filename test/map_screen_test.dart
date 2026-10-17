import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspira/app_scope.dart';
import 'package:inspira/data/event_repository.dart';
import 'package:inspira/data/favorites_store.dart';
import 'package:inspira/data/image_repository.dart';
import 'package:inspira/data/progress_store.dart';
import 'package:inspira/data/quote_repository.dart';
import 'package:inspira/data/story_repository.dart';
import 'package:inspira/data/wiki/wiki_service.dart';
import 'package:inspira/data/wiki_place_repository.dart';
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
    // pull the list up over the map
    await tester.drag(find.text('Near the map center'), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(find.text('Gama sails from Belem'), findsOneWidget);
    expect(find.text('Lisbon earthquake'), findsOneWidget);
    expect(find.text('0 m'), findsOneWidget);
    expect(find.byTooltip('Lisbon earthquake'), findsOneWidget);

    // Plain map first; the app bar button switches to satellite and back.
    expect(find.text('OpenStreetMap contributors'), findsOneWidget);
    await tester.tap(find.byTooltip('Satellite view'));
    await tester.pump();
    expect(find.text('Esri, Maxar, Earthstar Geographics'), findsOneWidget);
    await tester.tap(find.byTooltip('Map view'));
    await tester.pump();
    expect(find.text('OpenStreetMap contributors'), findsOneWidget);
  });

  testWidgets('with the places file: its places, the filter and the article', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final data = AppData(
      quotes: QuoteRepository(const []),
      stories: StoryRepository(const []),
      favorites: await FavoritesStore.load(),
      images: ImageRepository.empty(),
      progress: await ProgressStore.load(),
      wiki: _PlacesWiki(),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, nav) => AppScope(data: data, child: nav!),
        home: const MapScreen(locate: false, tiles: false),
      ),
    );
    await tester.pumpAndSettle();
    // the map starts at (35, 10): the abbey is about 1.4 km away
    expect(find.text('Lorsch Abbey'), findsOneWidget);
    expect(find.text('Church or temple'), findsOneWidget);
    expect(find.text('Castles'), findsOneWidget);

    await tester.tap(find.text('Castles'));
    await tester.pumpAndSettle();
    expect(find.text('Lorsch Abbey'), findsNothing);
    expect(find.text('Nothing of this kind nearby.'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lorsch Abbey'));
    await tester.pumpAndSettle();
    // the lead comes from the offline Wikipedia, not from a link
    expect(find.text('A former Imperial abbey.'), findsOneWidget);
    expect(find.text('Whole article on wikipedia.org'), findsOneWidget);
  });
}

/// The offline Wikipedia with the places file on the device.
class _PlacesWiki extends WikiService {
  static const _abbey = WikiPlace(
    title: 'Lorsch Abbey',
    cat: 'religious',
    year: null,
    lat: 35.01,
    lon: 10.01,
    approximate: false,
    links: 100,
    page: -7,
  );

  @override
  WikiStatus get status => WikiStatus.ready;
  @override
  bool get articlesReady => true;
  @override
  bool get placesReady => true;
  @override
  int get downloaded => 1;
  @override
  int get total => 1;
  @override
  int get received => 0;
  @override
  String? get error => null;
  @override
  Future<void> download() async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<void> delete() async {}
  @override
  Future<List<WikiFact>> onThisDay(
    int month,
    int day, {
    int limit = 30,
  }) async => const [];
  @override
  Future<WikiArticle?> article(String title) async => null;
  @override
  Future<WikiArticle?> placeArticle(WikiPlace place) async => WikiArticle(
    title: place.title,
    kind: 'place',
    lead: place.page == -7 ? 'A former Imperial abbey.' : '',
  );
  @override
  Future<List<WikiPlace>> placesIn(
    List<int> cells, {
    int? perCell,
    String? cat,
  }) async => [if (cat == null || cat == _abbey.cat) _abbey];
}
