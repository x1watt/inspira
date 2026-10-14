import 'package:flutter/widgets.dart';

import 'data/favorites_store.dart';
import 'data/image_repository.dart';
import 'data/progress_store.dart';
import 'data/quote_repository.dart';
import 'data/story_repository.dart';

/// Everything loaded at startup.
class AppData {
  const AppData({
    required this.quotes,
    required this.stories,
    required this.favorites,
    required this.images,
    required this.progress,
  });

  final QuoteRepository quotes;
  final StoryRepository stories;

  /// Holds quote ids and story ids; they never collide because story ids
  /// start with `story-`.
  final FavoritesStore favorites;
  final ImageRepository images;
  final ProgressStore progress;
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

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) => data != old.data;
}
