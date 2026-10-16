import 'package:flutter_test/flutter_test.dart';
import 'package:inspira/data/place_index.dart';
import 'package:inspira/data/wiki_place_repository.dart';
import 'package:inspira/models/event.dart';
import 'package:inspira/models/story.dart';

Story _story(String id, {double? lat, double? lon}) => Story.fromJson({
  'id': id,
  'category': 'team',
  'kind': 'history',
  'title': id,
  'text': 'Text.',
  'lesson': 'Lesson.',
  'source': 'Source',
  'basis': 'documented',
  'place': lat == null ? null : 'Somewhere',
  'lat': lat,
  'lon': lon,
});

void main() {
  final index = PlaceIndex(
    [
      _story('story-lisbon', lat: 38.7139, lon: -9.1394),
      _story('story-porto', lat: 41.1496, lon: -8.6109),
      _story('story-nowhere'),
    ],
    [
      const HistoryEvent(
        id: 'event-fiji',
        title: 'Fiji',
        year: 1874,
        month: 10,
        day: 10,
        summary: '',
        lat: -17.8,
        lon: 178.0,
        weight: 70,
      ),
      const HistoryEvent(
        id: 'event-no-place',
        title: 'Nowhere',
        year: 1900,
        month: 1,
        day: 1,
        summary: '',
      ),
    ],
  );

  test('only items with coordinates become places', () {
    expect(index.places.map((p) => p.id), [
      'event-fiji',
      'story-lisbon',
      'story-porto',
    ]);
  });

  test('nearest sorts by distance and respects the radius', () {
    // Coimbra: Porto is about 100 km away, Lisbon about 175.
    final near = index.nearest(40.2033, -8.4103, maxKm: 500);
    expect(near.map((n) => n.$1.id), ['story-porto', 'story-lisbon']);
    expect(near.first.$2, closeTo(105, 10));
    expect(PlaceIndex.km(0, 0, 0, 1), closeTo(111.2, 0.5));
  });

  test('box search works across the date line and keeps the heaviest', () {
    expect(index.inBox(-30, 170, -10, -170).map((p) => p.id), ['event-fiji']);
    expect(index.inBox(30, -20, 50, 0).length, 2);
    expect(index.inBox(-90, -180, 90, 180, limit: 1).single.id, 'event-fiji');
    // Lisbon and Porto share a 45 degree cell; one marker stays.
    expect(index.inBox(30, -20, 50, 0, cell: 45).length, 1);
    expect(index.inBox(30, -20, 50, 0, cell: 1).length, 2);
  });

  group('Wikipedia places', () {
    final wiki = parseWikiPlaces(
      '{"places": [["Siege of Lisbon", 1147, 38.71, -9.13, 0, 120], '
      '["Battle of Aljubarrota", 1385, 39.6, -8.85, 1, 300], '
      '["Battle of Actium", -31, 38.95, 20.74, 0, 900]]}',
    );
    final withWiki = PlaceIndex(
      [_story('story-lisbon', lat: 38.7139, lon: -9.1394)],
      const [],
      wiki,
    );

    test('parse fields, BC years and links', () {
      expect(wiki.length, 3);
      expect(wiki[1].approximate, isTrue);
      expect(wiki[2].yearLabel, '31 BC');
      expect(wiki[0].url, 'https://en.wikipedia.org/wiki/Siege_of_Lisbon');
      expect(withWiki.places.last.kind, 'wiki');
    });

    test('the own story of the app wins a marker cell over an article', () {
      final one = withWiki.inBox(30, -20, 50, 0, cell: 45);
      expect(one.single.id, 'story-lisbon');
      // Among articles the better linked one wins.
      final arts = PlaceIndex(
        const [],
        const [],
        wiki,
      ).inBox(30, -20, 50, 0, cell: 45);
      expect(arts.single.title, 'Battle of Aljubarrota');
    });

    test('nearest keeps only the closest, in order', () {
      final near = withWiki.nearest(38.7, -9.1, limit: 2);
      expect(near.map((n) => n.$1.id), [
        'wiki-Siege of Lisbon',
        'story-lisbon',
      ]);
      expect(near[0].$2 <= near[1].$2, isTrue);
    });
  });
}
