import 'package:flutter_test/flutter_test.dart';
import 'package:inspira/data/wiki/tiles.dart';

void main() {
  test('the zoom 12 cell is the one tool/wikizx keys the places by', () {
    expect(tileOf(49.7225, 8.6113), (2145, 1394));
    expect(cellOf(49.7225, 8.6113), 6438409);
    expect(firstKey(1), 1 << 24);
  });

  test('cells around a point and in a box', () {
    final around = cellsAround(49.7225, 8.6113, 2);
    expect(around.length, 25);
    expect(around.toSet().length, 25);
    expect(around[12], cellOf(49.7225, 8.6113));
    final box = cellsInBox(49.70, 8.58, 49.74, 8.64)!;
    expect(box, contains(cellOf(49.7225, 8.6113)));
    // across the date line: the tiles at both ends
    final dl = cellsInBox(-17.9, 179.95, -17.8, -179.95)!;
    expect(dl, contains(cellOf(-17.85, 179.99)));
    expect(dl, contains(cellOf(-17.85, -179.99)));
    // a whole country is too many tiles to ask for
    expect(cellsInBox(47, 6, 55, 15), isNull);
  });

  test('many cells become a few ranges of their parent tiles', () {
    final cells = cellsAround(49.7225, 8.6113, 6); // 169 cells
    final ranges = keyRanges(cells);
    expect(ranges.length, lessThanOrEqualTo(32));
    for (final c in cells) {
      expect(
        ranges.any((r) => firstKey(c) >= r.$1 && firstKey(c) < r.$2),
        isTrue,
      );
    }
    expect(keyRanges([5]), [(5 << 24, 6 << 24)]);
  });
}
