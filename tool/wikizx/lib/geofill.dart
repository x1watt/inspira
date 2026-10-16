// Shared by the location fill tools (docs/plan-geofill.md).
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

  /// 'place' (the Wikidata point of the named place) or 'model'.
  final String source;

  /// The Wikidata item of the named place, when it was found.
  final int? via;
}

/// Resolves the place an answer names to its Wikidata point in geo.zx.
class PlaceResolver {
  PlaceResolver(ZxDatabase geo)
      : _q = geo.sql.prepare(
            'SELECT s.qid, p.lat, p.lon FROM sitelink s JOIN point p ON p.qid = s.qid '
            "WHERE s.lang = 'en' AND s.title = ? COLLATE NOCASE");

  final ZxSqlStatement _q;

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
    return Chosen(ml, mn, 'model', null);
  }
}
