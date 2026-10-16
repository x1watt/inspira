// Checks geo.zx against Inspira's verified events: how many get a point,
// by which tier, and how far it is from the verified coordinates.
//   dart run bin/geovalidate.dart geo.zx ../../events
import 'dart:convert';
import 'dart:io';
import 'dart:math';

// ignore: implementation_imports
import 'package:zx/src/db/zxdb.dart' show ZxDatabase;

double km(double a, double b, double c, double d) {
  double r(double x) => x * pi / 180;
  final h = pow(sin(r(c - a) / 2), 2) +
      cos(r(a)) * cos(r(c)) * pow(sin(r(d - b) / 2), 2);
  return 12742 * asin(sqrt(h));
}

void main(List<String> args) {
  final db = ZxDatabase.open(args[0], readOnly: true);
  final point = db.sql.prepare('SELECT lat, lon, tier FROM point WHERE qid = ?');
  final dates = db.sql.prepare(
      'SELECT role, year, month, day FROM item_date WHERE id BETWEEN ? * 16 AND ? * 16 + 15');
  final tiers = <String, (int, int, int)>{};
  var n = 0, dated = 0, dayOk = 0, yearOk = 0;
  final far = <String>[];
  for (final f in Directory(args[1]).listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.json')) continue;
    final e = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final qs = e['wikidata'] as String?;
    if (qs == null) continue;
    final q = int.parse(qs.substring(1));
    final ds = dates.select([q, q]).where((r) =>
        r[0] == 'point' || r[0] == 'start' || r[0] == 'end');
    if (ds.isNotEmpty) {
      dated++;
      if (ds.any((r) => r[1] == e['year'])) yearOk++;
      if (ds.any((r) => r[1] == e['year'] && r[2] == e['month'] && r[3] == e['day'])) {
        dayOk++;
      }
    }
    if (e['lat'] == null) continue;
    n++;
    final rows = point.select([q]);
    final tier = rows.isEmpty ? 'none' : rows.first[2] as String;
    var (c, near, near5) = tiers[tier] ?? (0, 0, 0);
    c++;
    if (rows.isNotEmpty) {
      final d = km((e['lat'] as num).toDouble(), (e['lon'] as num).toDouble(),
          (rows.first[0] as num).toDouble(), (rows.first[1] as num).toDouble());
      if (d < 50) near++;
      if (d < 5) near5++;
      if (d >= 50 && far.length < 10) far.add('${e['title']} [$tier] ${d.round()} km');
    }
    tiers[tier] = (c, near, near5);
  }
  String pc(int a, int b) => '${(100 * a / max(b, 1)).toStringAsFixed(1)}%';
  print('$n verified events with coordinates');
  var got = 0;
  for (final t in ['own', 'location', 'headquarters', 'terrain', 'area', 'none']) {
    final v = tiers[t];
    if (v == null) continue;
    if (t != 'none') got += v.$1;
    print('  ${t.padRight(13)} ${v.$1.toString().padLeft(4)} (${pc(v.$1, n)})'
        '${t == 'none' ? '' : ', within 50 km ${pc(v.$2, v.$1)}, within 5 km ${pc(v.$3, v.$1)}'}');
  }
  print('  with a point: $got (${pc(got, n)})');
  print('Dates: $dated events dated by Wikidata; year right ${pc(yearOk, dated)}, '
      'day right ${pc(dayOk, dated)} (day only when Wikidata gives more than a year)');
  print('Far, e.g.: ${far.join('; ')}');
  db.close();
}
