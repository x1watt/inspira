// Writes assets/wiki_places.json for the app's map: the most linked dated
// English Wikipedia articles (events, not people) that have a point in
// geo.zx. Leaves out Inspira's own events (by Wikidata id), points the
// model gave low confidence, and points that are still only a country
// (geofill/centroids.tsv) or sit within 25 km of any country's point (a
// war with no single country, placed at one). Also leaves out place
// pages and the types in geofill/skip_types.txt and [_notEvents] (a
// language, a university or a magazine has a start date too).
// See docs/architecture.md, section 5.
//
//   dart run bin/export_wikiplaces.dart en_mini.zx geo.zx ../../events \
//       geofill ../../assets/wiki_places.json [--limit 20000]
//
// Output: {"places": [[title, year or null, lat, lon, approximate (0/1),
// incoming links], ...]}, most linked first.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:wikizx/geofill.dart' show km;
// ignore: implementation_imports
import 'package:zx/src/db/zxdb.dart' show ZxDatabase;

/// Types (P31) that have a start date but are not events.
const _notEvents = {
  34770, 1288568, 33742, 25295, // language, modern, natural, language family
  3918, 875538, 902104, 3914, 9842, 159334, // university, schools
  43229, 4830453, 783794, 891723, 6881511, // organisation, company, enterprise
  11032, 1002697, 5633421, // newspaper, periodical, scientific journal
  7278, 847017, 476028, 103229495, // party, sports club, football club
  215380, 5741069, 2088357, // band, rock band, musical group
  35127, 7397, 7889, // website, software, video game
  482994, 134556, 7366, 571, 7725634, 47461344, // album, single, song, book, work
  46970, 11446, 15416, // airline, ship, television program
  6256, 3624078, 3024240, 7275, 1763527, // country, state, historical country
  515, 486972, 1549591, 3957, 532, // city, settlement, big city, town, village
  10864048, 36784, 28575, 15284, 1620908, 82794, // admin areas, regions
  34442, 2198855, 968159, // road, cultural and art movements
  5107, 9430, 165, // continent, ocean, sea
};

/// Items whose point, when another item has it, means "somewhere in
/// there": countries, continents, oceans and seas.
const _countryTypes = {6256, 3624078, 3024240, 7275, 5107, 9430, 165};

Iterable<List<Object?>> _rows(ZxDatabase db, String sql) sync* {
  final c = db.sql.query(sql);
  while (c.moveNext()) {
    yield c.current;
  }
}

void main(List<String> args) {
  final wiki = ZxDatabase.open(args[0], readOnly: true);
  final geo = ZxDatabase.open(args[1], readOnly: true);
  final li = args.indexOf('--limit');
  final limit = li < 0 ? 20000 : int.parse(args[li + 1]);

  final curated = <int>{};
  for (final f in Directory(args[2]).listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.json')) continue;
    final q = (jsonDecode(f.readAsStringSync()) as Map)['wikidata'] as String?;
    if (q != null) curated.add(int.parse(q.substring(1)));
  }
  final centroids = <int>{
    for (final l in File('${args[3]}/centroids.tsv').readAsLinesSync().skip(1))
      if (l.isNotEmpty) int.parse(l),
  };

  final skip = <int>{..._notEvents};
  for (final l in File('${args[3]}/skip_types.txt').readAsLinesSync()) {
    final m = RegExp(r'^Q(\d+)').firstMatch(l);
    if (m != null) skip.add(int.parse(m[1]!));
  }
  final skipped = Uint8List(1 << 25);
  final countries = <int>{};
  for (final r in _rows(geo, 'SELECT id, type FROM item_type')) {
    final q = (r[0] as int) >> 3, t = r[1] as int;
    if (skip.contains(t)) skipped[q >> 3] |= 1 << (q & 7);
    if (_countryTypes.contains(t)) countries.add(q);
  }

  // Year of each dated item (earliest point in time or start); people out.
  final person = Uint8List(1 << 25);
  final year = <int, int>{};
  for (final r in _rows(geo, 'SELECT id, role, year FROM item_date')) {
    final q = (r[0] as int) >> 4, role = r[1];
    if (role == 'birth' || role == 'death') person[q >> 3] |= 1 << (q & 7);
    if (role == 'point' || role == 'start') {
      final y = r[2] as int;
      final old = year[q];
      if (old == null || y < old) year[q] = y;
    }
  }
  bool on(Uint8List b, int q) => b[q >> 3] & (1 << (q & 7)) != 0;
  year.removeWhere((q, _) => on(person, q) || on(skipped, q) || curated.contains(q));

  final pt = <int, (double, double, bool)>{};
  final countryPts = <(double, double)>[];
  for (final r in _rows(geo, 'SELECT qid, lat, lon, tier FROM point')) {
    final q = r[0] as int;
    if (countries.contains(q)) {
      countryPts.add(((r[1] as num).toDouble(), (r[2] as num).toDouble()));
    }
    if (!year.containsKey(q)) continue;
    final tier = r[3] as String;
    if (tier == 'model-low') continue;
    if (centroids.contains(q) && !tier.startsWith('model')) continue;
    pt[q] = ((r[1] as num).toDouble(), (r[2] as num).toDouble(),
        tier == 'area' || tier == 'model-medium');
  }

  final before = pt.length;
  pt.removeWhere((_, p) => countryPts.any((c) => km(p.$1, p.$2, c.$1, c.$2) < 25));
  print('${countryPts.length} country points; ${before - pt.length} items at one left out');

  final titleQ = <String, int>{};
  for (final r in _rows(geo, 'SELECT lang, title, qid FROM sitelink')) {
    if (r[0] != 'en') continue;
    final q = r[2] as int;
    if (pt.containsKey(q)) titleQ[(r[1] as String).toLowerCase()] = q;
  }
  // Elections and referendums are nationwide; "Judo at the 1996 Summer
  // Olympics" repeats the games' own marker.
  final titleSkip = RegExp(r'\b(election|elections|referendum|by-election)\b| at the \d{4} ',
      caseSensitive: false);
  final rows = <(String, int, int)>[]; // title, qid, inlinks
  for (final r in _rows(wiki, 'SELECT title, kind, inlinks FROM page_meta')) {
    if (r[1] != 'event' && r[1] != 'other') continue;
    final t = r[0] as String;
    if (titleSkip.hasMatch(t)) continue;
    final q = titleQ.remove(t.toLowerCase());
    if (q != null) rows.add((t, q, r[2] as int));
  }
  rows.sort((a, b) => b.$3.compareTo(a.$3));
  double r4(double v) => (v * 10000).round() / 10000;
  final out = [
    for (final (t, q, n) in rows.take(limit))
      [t, year[q], r4(pt[q]!.$1), r4(pt[q]!.$2), pt[q]!.$3 ? 1 : 0, n],
  ];
  File(args[4]).writeAsStringSync(jsonEncode({'places': out}));
  print('${rows.length} candidates, ${out.length} written to ${args[4]} '
      '(${File(args[4]).lengthSync() >> 10} KiB); least linked kept: '
      '${out.isEmpty ? 0 : out.last.last} links');
  wiki.close();
  geo.close();
}
