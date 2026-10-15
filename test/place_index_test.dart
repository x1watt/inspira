import 'package:flutter_test/flutter_test.dart';
import 'package:inspira/data/place_index.dart';
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
}
