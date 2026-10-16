import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const wikiPlacesAsset = 'assets/wiki_places.json';

/// A dated Wikipedia article (an event, not a person) with the place it
/// happened, from tool/wikizx (docs/architecture.md, section 5).
class WikiPlace {
  const WikiPlace({
    required this.title,
    required this.year,
    required this.lat,
    required this.lon,
    required this.approximate,
    required this.links,
  });

  /// The English Wikipedia article.
  final String title;

  /// Year it happened or began; negative is BC; null when unknown.
  final int? year;
  final double lat;
  final double lon;

  /// The point is only the area or a medium confidence guess.
  final bool approximate;

  /// Incoming links in English Wikipedia: how well known it is.
  final int links;

  String get id => 'wiki-$title';

  String get yearLabel {
    final y = year;
    if (y == null) return '';
    return y < 0 ? '${-y} BC' : '$y';
  }

  String get url =>
      'https://en.wikipedia.org/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}';
}

/// Parses the bundled JSON. Top level so it can run in an isolate.
List<WikiPlace> parseWikiPlaces(String raw) => [
  for (final r in (jsonDecode(raw) as Map<String, dynamic>)['places'] as List)
    WikiPlace(
      title: r[0] as String,
      year: r[1] as int?,
      lat: (r[2] as num).toDouble(),
      lon: (r[3] as num).toDouble(),
      approximate: r[4] == 1,
      links: r[5] as int,
    ),
];

/// Wikipedia places for the map, held in memory; decoded off the UI
/// isolate (docs/performance.md, rule 1).
class WikiPlaceRepository {
  WikiPlaceRepository(List<WikiPlace> places)
    : places = List.unmodifiable(places);

  static Future<WikiPlaceRepository> load(AssetBundle bundle) async {
    final raw = await bundle.loadString(wikiPlacesAsset);
    return WikiPlaceRepository(await compute(parseWikiPlaces, raw));
  }

  final List<WikiPlace> places;
}
