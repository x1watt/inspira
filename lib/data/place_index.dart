import 'dart:math';

import '../models/event.dart';
import '../models/story.dart';
import 'wiki_place_repository.dart';

/// A point on the map: an event, a story or a Wikipedia article about
/// something that happened there.
class MapPlace {
  MapPlace.event(HistoryEvent this.event)
    : story = null,
      wiki = null,
      id = event.id,
      title = event.title,
      subtitle = [
        event.dateLabel,
        event.place,
      ].where((s) => s.isNotEmpty).join(', '),
      lat = event.lat!,
      lon = event.lon!,
      kind = 'event',
      weight = event.weight;

  MapPlace.story(Story this.story)
    : event = null,
      wiki = null,
      id = story.id,
      title = story.title,
      subtitle = [
        story.date,
        story.place,
      ].where((s) => s.isNotEmpty).join(', '),
      lat = story.lat!,
      lon = story.lon!,
      kind = story.kind.id,
      weight = _storyWeight[story.kind.id] ?? 40;

  /// Below every event and story (whose weights are 1 to 100), so the
  /// app's own content wins a marker cell; better linked articles first.
  MapPlace.wiki(WikiPlace this.wiki)
    : event = null,
      story = null,
      id = wiki.id,
      title = wiki.title,
      subtitle = [
        wiki.yearLabel,
        if (wiki.approximate) 'approximate place',
      ].where((s) => s.isNotEmpty).join(', '),
      lat = wiki.lat,
      lon = wiki.lon,
      kind = 'wiki',
      weight = -100000 + (wiki.links > 99999 ? 99999 : wiki.links);

  static const _storyWeight = {'history': 60, 'study': 40, 'story': 35};

  final HistoryEvent? event;
  final Story? story;
  final WikiPlace? wiki;
  final String id;
  final String title;
  final String subtitle;
  final double lat;
  final double lon;

  /// `event`, `history`, `study`, `story` or `wiki`.
  final String kind;

  /// Importance, for which markers to keep when there are too many.
  final int weight;
}

/// Every event, story and Wikipedia place with coordinates, for the map
/// and "near me". About 22,000 points: a linear scan takes a few
/// milliseconds after the map stops moving (docs/performance.md, rule 11),
/// so there is no spatial index.
class PlaceIndex {
  PlaceIndex(
    Iterable<Story> stories,
    Iterable<HistoryEvent> events, [
    Iterable<WikiPlace> wiki = const [],
  ]) : places = List.unmodifiable([
         for (final e in events)
           if (e.hasPlace) MapPlace.event(e),
         for (final s in stories)
           if (s.hasPlace) MapPlace.story(s),
         for (final w in wiki) MapPlace.wiki(w),
       ]);

  final List<MapPlace> places;

  /// Great circle distance in kilometers.
  static double km(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    double rad(double d) => d * pi / 180;
    final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
    final h =
        pow(sin(dLat / 2), 2) +
        cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(dLon / 2), 2);
    return 2 * r * asin(sqrt(h));
  }

  /// Places by distance from (lat, lon), closest first, with their
  /// distance in km.
  List<(MapPlace, double)> nearest(
    double lat,
    double lon, {
    int limit = 50,
    double maxKm = double.infinity,
  }) {
    // Keeps only the closest [limit], sorted, instead of sorting all.
    final best = <(MapPlace, double)>[];
    for (final p in places) {
      final d = km(lat, lon, p.lat, p.lon);
      if (d > maxKm || (best.length == limit && d >= best.last.$2)) continue;
      var i = best.length;
      while (i > 0 && best[i - 1].$2 > d) {
        i--;
      }
      best.insert(i, (p, d));
      if (best.length > limit) best.removeLast();
    }
    return best;
  }

  /// The most important places inside the box, at most one per grid cell
  /// of [cell] degrees (so markers do not pile up when zoomed out) and at
  /// most [limit]. The box may cross the date line (west > east).
  List<MapPlace> inBox(
    double south,
    double west,
    double north,
    double east, {
    double cell = 0,
    int limit = 200,
  }) {
    bool inLon(double lon) =>
        west <= east ? lon >= west && lon <= east : lon >= west || lon <= east;
    final best = <int, MapPlace>{};
    var n = 0;
    for (final p in places) {
      if (p.lat < south || p.lat > north || !inLon(p.lon)) continue;
      final key = cell <= 0
          ? n++
          : (p.lat / cell).floor() * 10000000 + (p.lon / cell).floor();
      final old = best[key];
      if (old == null || p.weight > old.weight) best[key] = p;
    }
    final hits = best.values.toList();
    if (hits.length <= limit) return hits;
    hits.sort((a, b) => b.weight.compareTo(a.weight));
    return hits.sublist(0, limit);
  }
}
