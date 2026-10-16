// Finds dated items (events, not people) whose Wikidata point is only
// their country: their own coordinates within 25 km of the country's
// point, or a location or area that is the country itself. They go to
// the model as group D (docs/plan-geofill.md, section 8), and
// geofill/centroids.tsv lets geofill_merge.dart replace their point.
//
//   dart run bin/geofill_centroids.dart en_mini.zx geo.zx geofill [--batch 200]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:wikizx/geofill.dart';
// ignore: implementation_imports
import 'package:zx/src/db/zxdb.dart' show ZxDatabase;

Iterable<List<Object?>> _rows(ZxDatabase db, String sql) sync* {
  final c = db.sql.query(sql);
  while (c.moveNext()) {
    yield c.current;
  }
}

final _boxKey = RegExp(
    r'location|place|site|venue|country|city|region|area|territory|signed|coordinates');

void main(List<String> args) {
  final wiki = ZxDatabase.open(args[0], readOnly: true);
  final geo = ZxDatabase.open(args[1], readOnly: true);
  final dir = args[2];
  final bi = args.indexOf('--batch');
  final batch = bi < 0 ? 200 : int.parse(args[bi + 1]);

  final dated = Uint8List(1 << 25), person = Uint8List(1 << 25);
  bool on(Uint8List b, int q) => b[q >> 3] & (1 << (q & 7)) != 0;
  for (final r in _rows(geo, 'SELECT id, role FROM item_date')) {
    final q = (r[0] as int) >> 4, role = r[1];
    if (role == 'birth' || role == 'death') person[q >> 3] |= 1 << (q & 7);
    if (role == 'point' || role == 'start' || role == 'end') {
      dated[q >> 3] |= 1 << (q & 7);
    }
  }
  final pts = <int, (double, double)>{};
  final cand = <(int, String, int?, int, double, double)>[];
  for (final r in _rows(geo, 'SELECT qid, lat, lon, tier, via, country FROM point')) {
    final q = r[0] as int;
    final la = (r[1] as num).toDouble(), lo = (r[2] as num).toDouble();
    pts[q] = (la, lo);
    final c = r[5] as int?;
    if (c == null || c == q || !on(dated, q) || on(person, q)) continue;
    cand.add((q, r[3] as String, r[4] as int?, c, la, lo));
  }
  final found = <int>[];
  for (final (q, tier, via, c, la, lo) in cand) {
    final cp = pts[c];
    if (cp == null) continue;
    final own = tier == 'own' && km(la, lo, cp.$1, cp.$2) < 25;
    final viaCountry = (tier == 'location' || tier == 'area') && via == c;
    if (own || viaCountry) found.add(q);
  }
  print('${found.length} dated items placed only at their country');

  final title = geo.sql.prepare("SELECT title FROM sitelink WHERE qid = ? AND lang = 'en'");
  final page = wiki.sql.prepare('SELECT id, lead FROM page WHERE title = ? COLLATE NOCASE');
  final box = wiki.sql.prepare('SELECT key, value FROM infobox WHERE id BETWEEN ? AND ?');
  String cut(String s, int n) => s.length > n ? s.substring(0, n) : s;
  final lines = <String>[];
  final tsv = StringBuffer('qid\n');
  for (final q in found) {
    final t = title.select([q]);
    if (t.isEmpty) continue;
    final p = page.select([t.first[0]]);
    final info = <String, String>{};
    var lead = '';
    if (p.isNotEmpty) {
      final id = p.first[0] as int;
      lead = cut(p.first[1] as String? ?? '', 600);
      for (final r in box.select([id * 256, id * 256 + 255])) {
        final k = (r[0] as String).toLowerCase();
        if (_boxKey.hasMatch(k)) info[k] = cut(r[1] as String, 160);
      }
    }
    tsv.writeln(q);
    lines.add(jsonEncode({
      'qid': q,
      'title': t.first[0],
      'lead': lead,
      if (info.isNotEmpty) 'infobox': info,
    }));
  }
  File('$dir/centroids.tsv').writeAsStringSync(tsv.toString());
  final out = Directory('$dir/in/D')..createSync(recursive: true);
  for (var i = 0; i < lines.length; i += batch) {
    File('${out.path}/${(i ~/ batch + 1).toString().padLeft(4, '0')}.jsonl')
        .writeAsStringSync('${lines.skip(i).take(batch).join('\n')}\n');
  }
  print('group D: ${lines.length} items in ${(lines.length + batch - 1) ~/ batch} batches');
  wiki.close();
  geo.close();
}
