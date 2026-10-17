import 'dart:math';

/// Map tiles of the offline places file (tool/wikizx/bin/build_places.dart):
/// a place's key is `cell << 24 | n`, where cell is the quadkey of its
/// zoom 12 tile and n its rank in the tile, best known first.
const placeZoom = 12;
const _side = 1 << placeZoom;

/// Tile column and row of (lat, lon) at zoom 12.
(int, int) tileOf(double lat, double lon) {
  final x = ((lon + 180) / 360 * _side).floor().clamp(0, _side - 1);
  final r = lat.clamp(-85.05, 85.05) * pi / 180;
  final y = ((1 - log(tan(r) + 1 / cos(r)) / pi) / 2 * _side).floor().clamp(
    0,
    _side - 1,
  );
  return (x, y);
}

/// The quadkey of a zoom 12 tile, as an integer.
int quadkey(int x, int y) {
  var q = 0;
  for (var i = placeZoom - 1; i >= 0; i--) {
    q = q * 4 + ((x >> i) & 1) + 2 * ((y >> i) & 1);
  }
  return q;
}

int cellOf(double lat, double lon) {
  final (x, y) = tileOf(lat, lon);
  return quadkey(x, y);
}

/// The first key of a cell; its keys are `[first, first + (1 << 24))`.
int firstKey(int cell) => cell << 24;

/// The cells of the tiles within [ring] tiles of (lat, lon): a square of
/// (2 * ring + 1)^2 tiles, about 6 km a side each in central Europe.
List<int> cellsAround(double lat, double lon, int ring) {
  final (cx, cy) = tileOf(lat, lon);
  return [
    for (var dy = -ring; dy <= ring; dy++)
      for (var dx = -ring; dx <= ring; dx++)
        if (cy + dy >= 0 && cy + dy < _side)
          quadkey((cx + dx) % _side, cy + dy),
  ];
}

/// The cells of the tiles that cover the box, or null when there are
/// more than [max] of them. The box may cross the date line (west > east).
List<int>? cellsInBox(
  double south,
  double west,
  double north,
  double east, {
  int max = 400,
}) {
  final (x0, y0) = tileOf(north, west);
  final (x1, y1) = tileOf(south, east);
  final w = x1 >= x0 ? x1 - x0 + 1 : x1 + _side - x0 + 1;
  if (w * (y1 - y0 + 1) > max) return null;
  return [
    for (var y = y0; y <= y1; y++)
      for (var i = 0; i < w; i++) quadkey((x0 + i) % _side, y),
  ];
}

/// The key ranges of all the places in [cells]: one per cell, or, when
/// there are more than [max] cells, one per parent tile of a lower zoom
/// (a parent's keys are contiguous), so a query stays at most [max]
/// ranges. The parents may hold places outside [cells].
List<(int, int)> keyRanges(List<int> cells, {int max = 32}) {
  var shift = 0;
  var parents = cells.toSet();
  while (parents.length > max) {
    shift += 2;
    parents = {for (final c in cells) c >> shift};
  }
  return [
    for (final p in parents) (p << (shift + 24), (p + 1) << (shift + 24)),
  ];
}
