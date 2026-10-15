// Checks a converted archive against Inspira's 1000 verified events
// (assets/events.json: Wikipedia title, date, coordinates) and times the
// queries the app would make.
//   dart run bin/validate.dart OUT.zx ../../assets/events.json
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
  final sql = db.sql;
  final events = jsonDecode(File(args[1]).readAsStringSync()) as List;
  final byTitle = sql.prepare(
      'SELECT id, kind, lat, lon FROM page WHERE title = ? COLLATE NOCASE');
  final byRedirect = sql.prepare(
      'SELECT p.id, p.kind, p.lat, p.lon FROM redirect r JOIN page p ON p.id = r.page '
      'WHERE r.title = ? COLLATE NOCASE');
  final factsOf = sql.prepare(
      'SELECT role, year, month, day FROM fact WHERE id BETWEEN ? * 16 AND ? * 16 + 15');
  var found = 0, isEvent = 0, anyDate = 0, dayOk = 0, yearOk = 0;
  var coords = 0, near = 0, withCoordsInInspira = 0;
  final kinds = <String, int>{};
  final misses = <String>[];
  final sw = Stopwatch()..start();
  for (final e in events.cast<Map<String, dynamic>>()) {
    final title = (e['wikipedia'] as String).replaceAll('_', ' ');
    var rows = byTitle.select([title]);
    if (rows.isEmpty) rows = byRedirect.select([title]);
    if (rows.isEmpty) {
      if (misses.length < 10) misses.add(title);
      continue;
    }
    found++;
    final row = rows.first;
    final kind = row[1] as String;
    kinds[kind] = (kinds[kind] ?? 0) + 1;
    if (kind == 'event') isEvent++;
    if (kind != 'event' && args.contains('--why') && (kinds[kind]! <= 6)) {
      final keys = sql.select(
          'SELECT key FROM infobox WHERE id BETWEEN ? * 256 AND ? * 256 + 255',
          [row[0], row[0]]);
      print('  $kind: $title  [${keys.map((k) => k[0]).join(', ')}]');
    }
    final fs = factsOf.select([row[0], row[0]]);
    final dated = fs.where((f) => f[0] == 'point' || f[0] == 'start' || f[0] == 'end');
    if (dated.isNotEmpty) anyDate++;
    if (dated.any((f) => f[1] == e['year'])) yearOk++;
    if (dated.any((f) =>
        f[1] == e['year'] && f[2] == e['month'] && f[3] == e['day'])) {
      dayOk++;
    }
    if (e['lat'] != null) {
      withCoordsInInspira++;
      if (row[2] != null) {
        coords++;
        if (km(e['lat'], e['lon'], row[2] as double, row[3] as double) < 50) {
          near++;
        }
      }
    }
  }
  String pc(int a, int b) => '$a/$b (${(100 * a / max(b, 1)).toStringAsFixed(1)}%)';
  print('Validation against ${events.length} verified events '
      '(${sw.elapsedMilliseconds} ms):');
  print('  page found:          ${pc(found, events.length)}');
  print('  classified as event: ${pc(isEvent, found)}   kinds $kinds');
  print('  has a date:          ${pc(anyDate, found)}');
  print('  year matches:        ${pc(yearOk, found)}');
  print('  exact day matches:   ${pc(dayOk, found)}');
  print('  has coordinates:     ${pc(coords, withCoordsInInspira)}');
  print('  coordinates < 50 km: ${pc(near, coords)}');
  print('  not found, e.g.: ${misses.take(5).join('; ')}');
  db.close();
}
