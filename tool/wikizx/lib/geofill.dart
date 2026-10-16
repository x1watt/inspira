// Shared by the location fill tools (docs/plan-geofill.md).
import 'dart:io';
import 'dart:math';

// ignore: implementation_imports
import 'package:zx/src/db/zxdb.dart' show ZxDatabase;
// ignore: implementation_imports
import 'package:zx/src/db/sql/zx_sql.dart' show ZxSqlStatement;

/// Great circle distance in km.
double km(double a, double b, double c, double d) {
  double r(double x) => x * pi / 180;
  final h = pow(sin(r(c - a) / 2), 2) +
      cos(r(a)) * cos(r(c)) * pow(sin(r(d - b) / 2), 2);
  return 12742 * asin(sqrt(min(1.0, h.toDouble())));
}

/// The point kept for one model answer.
class Chosen {
  Chosen(this.lat, this.lon, this.source, this.via);
  final double lat, lon;

  /// 'place' (the Wikidata point of the named place), 'geonames' (a
  /// GeoNames place of that name near the model's coordinates) or 'model'.
  final String source;

  /// The Wikidata item of the named place, when it was found.
  final int? via;
}

/// GeoNames places by lower case name (towns of 500 people or more and
/// historic sites), from the slim TSV of docs/plan-geofill.md: name,
/// ascii name, lat, lon, feature code, country, population.
class Gazetteer {
  Gazetteer(String path) {
    for (final l in File(path).readAsLinesSync()) {
      final f = l.split('\t');
      if (f.length < 4) continue;
      final la = double.tryParse(f[2]), lo = double.tryParse(f[3]);
      if (la == null || lo == null) continue;
      final p = (la, lo);
      (_byName[f[0].toLowerCase()] ??= []).add(p);
      if (f[1] != f[0]) (_byName[f[1].toLowerCase()] ??= []).add(p);
    }
  }

  final _byName = <String, List<(double, double)>>{};

  /// The place called [name] (or its part before the first comma)
  /// nearest to ([lat], [lon]), when it is within [maxKm].
  (double, double)? near(String name, double lat, double lon, {double maxKm = 50}) {
    final n = name.toLowerCase();
    final keys = {n, n.split(',').first.trim(), n.replaceAll(RegExp(r' \(.*\)$'), '')};
    (double, double)? best;
    var bestKm = maxKm;
    for (final k in keys) {
      for (final p in _byName[k] ?? const <(double, double)>[]) {
        final d = km(lat, lon, p.$1, p.$2);
        if (d < bestKm) {
          bestKm = d;
          best = p;
        }
      }
    }
    return best;
  }
}

/// Resolves the place an answer names to its Wikidata point in geo.zx,
/// else to a GeoNames place of that name when [gazetteer] is given.
class PlaceResolver {
  PlaceResolver(ZxDatabase geo, {this.gazetteer})
      : _q = geo.sql.prepare(
            'SELECT s.qid, p.lat, p.lon FROM sitelink s JOIN point p ON p.qid = s.qid '
            "WHERE s.lang = 'en' AND s.title = ? COLLATE NOCASE");

  final ZxSqlStatement _q;
  final Gazetteer? gazetteer;

  /// The named place's point when it agrees with the model's coordinates
  /// (within 100 km) or the model gave none, else the model's coordinates.
  Chosen? choose(Map answer) {
    final ml = (answer['lat'] as num?)?.toDouble();
    final mn = (answer['lon'] as num?)?.toDouble();
    final place = answer['place'];
    if (place is String && place.isNotEmpty) {
      final r = _q.select([place]);
      if (r.isNotEmpty) {
        final rl = (r.first[1] as num).toDouble(), rn = (r.first[2] as num).toDouble();
        if (ml == null || mn == null || km(ml, mn, rl, rn) < 100) {
          return Chosen(rl, rn, 'place', r.first[0] as int);
        }
      }
    }
    if (ml == null || mn == null) return null;
    if (place is String && gazetteer != null) {
      final g = gazetteer!.near(place, ml, mn);
      if (g != null) return Chosen(g.$1, g.$2, 'geonames', null);
    }
    return Chosen(ml, mn, 'model', null);
  }
}
