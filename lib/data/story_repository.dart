import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/story.dart';

const storiesAsset = 'assets/stories.json';

/// Parses the bundled JSON array. Top level so it can run in an isolate.
List<Story> parseStories(String raw) => [
  for (final j in jsonDecode(raw) as List)
    Story.fromJson(j as Map<String, dynamic>),
];

/// All stories, held in memory. Loaded once at startup; decoding runs off
/// the UI isolate (docs/performance.md, rule 1).
class StoryRepository {
  StoryRepository(List<Story> stories)
    : stories = List.unmodifiable(stories),
      _byId = {for (final s in stories) s.id: s},
      _haystack = [
        for (final s in stories)
          '${s.title} ${s.text} ${s.lesson} ${s.people} ${s.source}'
              .toLowerCase(),
      ];

  static Future<StoryRepository> load(AssetBundle bundle) async {
    final raw = await bundle.loadString(storiesAsset);
    final stories = await compute(parseStories, raw);
    return StoryRepository(stories);
  }

  final List<Story> stories;
  final Map<String, Story> _byId;
  final List<String> _haystack;

  Story? byId(String id) => _byId[id];

  int countIn(String category) =>
      stories.where((s) => s.category == category).length;

  /// Same story for everyone on a given calendar day, different each day.
  Story? storyOfDay(DateTime day) {
    if (stories.isEmpty) return null;
    final n =
        DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
    return stories[Random(n * 7919).nextInt(stories.length)];
  }

  /// Stories matching all filters. Every word of [query] must appear in the
  /// title, text, lesson, people or source; null filters match everything.
  List<Story> filter({String query = '', String? category, StoryKind? kind}) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final result = <Story>[];
    for (var i = 0; i < stories.length; i++) {
      final s = stories[i];
      if (category != null && s.category != category) continue;
      if (kind != null && s.kind != kind) continue;
      if (words.isEmpty || words.every(_haystack[i].contains)) result.add(s);
    }
    return result;
  }
}
