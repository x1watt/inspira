import 'package:flutter/widgets.dart';

import 'data/event_repository.dart';
import 'data/favorites_store.dart';
import 'data/image_repository.dart';
import 'data/place_index.dart';
import 'data/progress_store.dart';
import 'data/quote_repository.dart';
import 'data/story_repository.dart';
import 'data/wiki_place_repository.dart';

/// Everything loaded at startup.
class AppData {
  const AppData({
    required this.quotes,
    required this.stories,
    required this.favorites,
    required this.images,
    required this.progress,
    this.events,
    this.wikiPlaces,
  });

  final QuoteRepository quotes;
  final StoryRepository stories;

  /// Holds quote ids and story ids; they never collide because story ids
  /// start with `story-`.
  final FavoritesStore favorites;
  final ImageRepository images;
  final ProgressStore progress;

  /// Dated world events; null in tests that do not need them.
  final EventRepository? events;

  /// Wikipedia places for the map; null in tests that do not need them.
  final WikiPlaceRepository? wikiPlaces;
}

/// Gives screens access to the loaded [AppData].
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.data, required super.child});

  final AppData data;

  QuoteRepository get repository => data.quotes;
  StoryRepository get stories => data.stories;
  FavoritesStore get favorites => data.favorites;
  ImageRepository get images => data.images;
  ProgressStore get progress => data.progress;
  EventRepository get events => data.events ?? _noEvents;

  /// Events, stories and Wikipedia places with coordinates, built on
  /// first use.
  PlaceIndex get places => _places[data] ??= PlaceIndex(
    stories.stories,
    events.events,
    data.wikiPlaces?.places ?? const [],
  );

  static final _noEvents = EventRepository(const []);
  static final _places = Expando<PlaceIndex>();

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) => data != old.data;
}
