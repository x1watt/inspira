// How much do Wikipedia's own coordinate tables (geo_tags, page_props) add
// over the ZIM? Checked against Inspira's verified events (Wikidata id,
// coordinates).
//   dart run bin/geocheck.dart ../../events enwiki-latest-page_props.sql.gz \
//       enwiki-latest-geo_tags.sql.gz
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:wikizx/sqldump.dart';

double km(double a, double b, double c, double d) {
  double r(double x) => x * pi / 180;
  final h = pow(sin(r(c - a) / 2), 2) +
      cos(r(a)) * cos(r(c)) * pow(sin(r(d - b) / 2), 2);
  return 12742 * asin(sqrt(h));
}

Future<void> main(List<String> args) async {
  final sw = Stopwatch()..start();
  // Verified events with a Wikidata id.
  final events = <String, Map<String, dynamic>>{};
  for (final f in Directory(args[0]).listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.json')) continue;
    final e = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final q = e['wikidata'] as String?;
    if (q != null) events[q] = e;
  }
  // Page of each of those items.
  final pageOf = <int, String>{};
  var items = 0;
  await for (final r in sqlDumpRows(args[1])) {
    if (r[1] != 'wikibase_item') continue;
    items++;
    final q = r[2] as String;
    if (events.containsKey(q)) pageOf[r[0] as int] = q;
  }
  print('page_props: $items pages with a Wikidata item '
      '(${sw.elapsed.inSeconds}s); ${pageOf.length} of ${events.length} events found');
  // Coordinates.
  var rows = 0, primary = 0;
  final types = <String, int>{};
  final best = <String, (double, double, bool, String?)>{};
  await for (final r in sqlDumpRows(args[2])) {
    rows++;
    if (r[2] != 'earth' || r[4] == null || r[5] == null) continue;
    final isPrimary = r[3] == 1;
    if (isPrimary) {
      primary++;
      final t = (r[7] as String?) ?? '(none)';
      types[t] = (types[t] ?? 0) + 1;
    }
    final q = pageOf[r[1] as int];
    if (q == null) continue;
    final old = best[q];
    if (old == null || (isPrimary && !old.$3)) {
      best[q] = ((r[4] as num).toDouble(), (r[5] as num).toDouble(),
          isPrimary, r[7] as String?);
    }
  }
  print('geo_tags: $rows rows, $primary primary on earth '
      '(${sw.elapsed.inSeconds}s)');
  final top = types.entries.toList()..sort((a, b) => b.value - a.value);
  print('  primary by type: ${top.take(16).map((e) => '${e.key} ${e.value}').join(', ')}');

  var withVerified = 0, has = 0, hasPrimary = 0, near = 0, near5 = 0;
  final far = <String>[];
  for (final e in events.entries) {
    if (e.value['lat'] == null) continue;
    withVerified++;
    final b = best[e.key];
    if (b == null) continue;
    has++;
    if (b.$3) hasPrimary++;
    final d = km(e.value['lat'], e.value['lon'], b.$1, b.$2);
    if (d < 50) near++;
    if (d < 5) near5++;
    if (d >= 50 && far.length < 8) far.add('${e.value['title']} (${d.round()} km)');
  }
  String pc(int a, int b) => '$a/$b (${(100 * a / max(b, 1)).toStringAsFixed(1)}%)';
  print('Verified events with coordinates: $withVerified');
  print('  geo_tags has a coordinate:  ${pc(has, withVerified)}  (ZIM: 26.9%)');
  print('  of them primary (title):    ${pc(hasPrimary, has)}');
  print('  within 50 km of verified:   ${pc(near, has)}  (ZIM: 95.4%)');
  print('  within 5 km of verified:    ${pc(near5, has)}');
  print('  far, e.g.: ${far.join('; ')}');
}
