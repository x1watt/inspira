// Quality gate for a model doing the location fill (docs/plan-geofill.md):
// scores answers to geofill/in/P/0001.jsonl (the verified events that
// Wikidata leaves without a point) against the verified coordinates.
//
//   dart run bin/geofill_score.dart geo.zx ../../events answers.jsonl [more ...]
//       [--geonames geonames_slim.tsv]
//
// "combined" is what geofill_merge.dart keeps: the Wikidata point of the
// named place when it is within 100 km of the model's coordinates, else
// the model's coordinates.
import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:zx/src/db/zxdb.dart' show ZxDatabase;
import 'package:wikizx/geofill.dart';

void main(List<String> args) {
  final geo = ZxDatabase.open(args[0], readOnly: true);
  final gi = args.indexOf('--geonames');
  final resolver = PlaceResolver(geo,
      gazetteer: gi < 0 ? null : Gazetteer(args[gi + 1]));
  final truth = <int, (double, double, String)>{};
  for (final f in Directory(args[1]).listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.json')) continue;
    final e = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final q = e['wikidata'] as String?;
    if (q == null || e['lat'] == null) continue;
    truth[int.parse(q.substring(1))] = (
      (e['lat'] as num).toDouble(),
      (e['lon'] as num).toDouble(),
      e['title'] as String
    );
  }
  final answers = <int, Map>{};
  var bad = 0;
  final files = [
    for (var i = 2; i < args.length; i++)
      if (args[i] != '--geonames' && (i == 0 || args[i - 1] != '--geonames')) args[i]
  ];
  for (final f in files) {
    for (final l in File(f).readAsLinesSync()) {
      if (l.trim().isEmpty) continue;
      try {
        final o = jsonDecode(l) as Map;
        answers[o['qid'] as int] = o;
      } catch (_) {
        bad++;
      }
    }
  }
  final s = <String, List<int>>{}; // [count, < 50 km, < 5 km]
  void add(String k, double? d) {
    final v = s[k] ??= [0, 0, 0];
    v[0]++;
    if (d != null && d < 50) v[1]++;
    if (d != null && d < 5) v[2]++;
  }

  final worst = <String>[];
  var scored = 0;
  for (final MapEntry(key: q, value: o) in answers.entries) {
    final t = truth[q];
    if (t == null) continue;
    scored++;
    final c = resolver.choose(o);
    final d = c == null ? null : km(t.$1, t.$2, c.lat, c.lon);
    add('all', d);
    add('confidence ${o['confidence']}', d);
    add('precision ${o['precision']}', d);
    add('from ${c?.source ?? 'nothing'}', d);
    if (d != null && d > 300 && worst.length < 10) {
      worst.add('${t.$3}: ${o['place']} (${d.round()} km)');
    }
  }
  print('$scored answers scored, $bad bad lines');
  for (final k in s.keys.toList()..sort()) {
    final v = s[k]!;
    String pc(int x) => '${(100 * x / v[0]).toStringAsFixed(1)}%';
    print('  ${k.padRight(24)} ${v[0].toString().padLeft(4)}  '
        'within 50 km ${pc(v[1])}  within 5 km ${pc(v[2])}');
  }
  print('Far off, e.g.: ${worst.join('; ')}');
  final all = s['all'];
  if (all != null) {
    final ok = all[1] / all[0] >= 0.75;
    print(ok
        ? 'PASS: at least 75% within 50 km'
        : 'FAIL: under 75% within 50 km, do not use this model for the fill');
  }
  geo.close();
}
