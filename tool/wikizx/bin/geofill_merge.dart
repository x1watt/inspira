// Puts the location fill into geo.zx (docs/plan-geofill.md): the ZIM
// points (tier 'zim') and every answer in geofill/out (tier 'model-high',
// 'model-medium' or 'model-low'), only for items that have no Wikidata
// point. Safe to rerun: earlier fill rows are removed first.
//
// Items in geofill/centroids.tsv (bin/geofill_centroids.dart) have a
// Wikidata point that is only their country: a model answer of region
// precision or better replaces it.
//
//   dart run bin/geofill_merge.dart geo.zx geofill [--geonames geonames_slim.tsv]
import 'dart:convert';
import 'dart:io';

import 'package:wikizx/geofill.dart';
// ignore: implementation_imports
import 'package:zx/src/db/engine/store.dart' show ZxDbStoreOptions;
// ignore: implementation_imports
import 'package:zx/src/db/zxdb.dart' show ZxDatabase;

const fillTiers = ['zim', 'model-high', 'model-medium', 'model-low'];

void main(List<String> args) {
  final db = ZxDatabase.open(args[0],
      options: ZxDbStoreOptions(
          durable: false, threads: 2, memoryLimit: 160 << 20, pageCacheBytes: 24 << 20));
  final dir = args[1];
  db.sql.execute('BEGIN');
  final removed = db.sql
      .execute('DELETE FROM point WHERE tier IN (${fillTiers.map((t) => "'$t'").join(',')})')
      .changes;
  db.sql.execute('COMMIT');
  print('removed $removed earlier fill rows');

  final has = db.sql.prepare('SELECT 1 FROM point WHERE qid = ?');
  final drop = db.sql.prepare('DELETE FROM point WHERE qid = ?');
  final centroids = <int>{};
  final cf = File('$dir/centroids.tsv');
  if (cf.existsSync()) {
    for (final l in cf.readAsLinesSync().skip(1)) {
      if (l.isNotEmpty) centroids.add(int.parse(l));
    }
  }
  final insert = db.sql.prepare('INSERT INTO point VALUES (?, ?, ?, ?, ?, NULL)');
  final counts = <String, int>{};
  final seen = <int>{};
  void put(int q, double lat, double lon, String tier, int? via,
      {bool replace = false}) {
    if (!seen.add(q)) return;
    if (has.select([q]).isNotEmpty) {
      if (!replace) return;
      drop.execute([q]);
      counts['replaced country'] = (counts['replaced country'] ?? 0) + 1;
    }
    insert.execute([q, lat, lon, tier, via]);
    counts[tier] = (counts[tier] ?? 0) + 1;
  }

  // Model answers first (they are read, not guessed from a page), then
  // the ZIM coordinates for the rest.
  final gi = args.indexOf('--geonames');
  final resolver = PlaceResolver(db,
      gazetteer: gi < 0 ? null : Gazetteer(args[gi + 1]));
  db.sql.execute('BEGIN');
  final out = Directory('$dir/out');
  final files = out.existsSync()
      ? (out.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.jsonl')).toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];
  // Only items that were asked: a stray qid in an answer file is ignored.
  final asked = <int>{};
  final qidRe = RegExp(r'^\{"qid":(\d+)');
  final inDir = Directory('$dir/in');
  if (inDir.existsSync()) {
    for (final f in inDir.listSync(recursive: true).whereType<File>()) {
      for (final l in f.readAsLinesSync()) {
        final m = qidRe.firstMatch(l);
        if (m != null) asked.add(int.parse(m[1]!));
      }
    }
  }
  var answers = 0, skipped = 0;
  final sources = <String, int>{};
  for (final f in files) {
    for (final l in f.readAsLinesSync()) {
      if (l.trim().isEmpty) continue;
      Map o;
      try {
        o = jsonDecode(l) as Map;
      } catch (_) {
        skipped++;
        continue;
      }
      if (!asked.contains(o['qid'])) {
        skipped++;
        continue;
      }
      answers++;
      if (o['precision'] == 'none') continue;
      final c = resolver.choose(o);
      if (c == null) continue;
      final q = o['qid'] as int;
      sources[c.source] = (sources[c.source] ?? 0) + 1;
      put(q, c.lat, c.lon, 'model-${o['confidence']}', c.via,
          replace: centroids.contains(q) &&
              const {'site', 'city', 'region'}.contains(o['precision']));
    }
  }
  final zims = Directory(dir)
      .listSync()
      .whereType<File>()
      .where((f) => f.uri.pathSegments.last.startsWith('zim_points'));
  for (final zim in zims) {
    for (final l in zim.readAsLinesSync().skip(1)) {
      final p = l.split('\t');
      put(int.parse(p[0]), double.parse(p[1]), double.parse(p[2]), 'zim', null);
    }
  }
  db.sql.execute('COMMIT');
  print('${files.length} answer files, $answers answers ($skipped bad lines); added $counts; point from $sources');
  db.fold();
  db.close();
}
