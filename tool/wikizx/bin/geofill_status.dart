// Progress of the location fill (docs/plan-geofill.md). A batch is done
// when geofill/out/<group>/<nnnn>.jsonl holds one valid answer for every
// item of geofill/in/<group>/<nnnn>.jsonl.
//
//   dart run bin/geofill_status.dart geofill            summary
//   dart run bin/geofill_status.dart geofill --next 3   next pending batches
//   dart run bin/geofill_status.dart geofill --next 1 --claim NAME
//       also writes out/<group>/<nnnn>.claim so parallel workers skip it
//   dart run bin/geofill_status.dart geofill --check out/A/0001.jsonl
//       validates one answer file and lists its problems
//
// Claims older than 3 hours are ignored (the worker stopped).
import 'dart:convert';
import 'dart:io';

const precisions = {'site', 'city', 'region', 'country', 'none'};
const confidences = {'high', 'medium', 'low'};

/// Problems of answer file [out] for input [inp]; empty when it is done.
List<String> check(File inp, File out) {
  if (!out.existsSync()) return ['missing'];
  final want = <int>{};
  for (final l in inp.readAsLinesSync()) {
    if (l.trim().isNotEmpty) want.add((jsonDecode(l) as Map)['qid'] as int);
  }
  final problems = <String>[];
  final got = <int>{};
  var n = 0;
  for (final l in out.readAsLinesSync()) {
    n++;
    if (l.trim().isEmpty) continue;
    Map o;
    try {
      o = jsonDecode(l) as Map;
    } catch (_) {
      problems.add('line $n: not JSON');
      continue;
    }
    final q = o['qid'];
    if (q is! int || !want.contains(q)) {
      problems.add('line $n: unknown qid $q');
      continue;
    }
    got.add(q);
    final lat = o['lat'], lon = o['lon'];
    if ((lat == null) != (lon == null) ||
        (lat != null && (lat is! num || lon is! num || lat.abs() > 90 || lon.abs() > 180))) {
      problems.add('line $n: bad lat/lon');
    }
    if (!precisions.contains(o['precision'])) problems.add('line $n: bad precision');
    if (!confidences.contains(o['confidence'])) problems.add('line $n: bad confidence');
    if (o['place'] != null && o['place'] is! String) problems.add('line $n: bad place');
  }
  final missing = want.length - got.length;
  if (missing > 0) problems.add('$missing of ${want.length} items unanswered');
  return problems;
}

void main(List<String> args) {
  final dir = args[0];
  final ci = args.indexOf('--check');
  if (ci >= 0) {
    final rel = args[ci + 1].replaceFirst(RegExp(r'^.*?out/'), '');
    final p = check(File('$dir/in/$rel'), File('$dir/out/$rel'));
    print(p.isEmpty ? 'ok' : p.take(20).join('\n'));
    exit(p.isEmpty ? 0 : 1);
  }
  final ni = args.indexOf('--next');
  final next = ni < 0 ? 0 : int.parse(args[ni + 1]);
  final cl = args.indexOf('--claim');
  final claimer = cl < 0 ? null : args[cl + 1];
  final now = DateTime.now();
  final pending = <String>[];
  var allDone = 0, allBatches = 0;
  final groups = Directory('$dir/in').listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final g in groups) {
    final name = g.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final files = g.listSync().whereType<File>().where((f) => f.path.endsWith('.jsonl')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    var done = 0, partial = 0, claimed = 0;
    for (final f in files) {
      final base = f.uri.pathSegments.last;
      final out = File('$dir/out/$name/$base');
      final p = check(f, out);
      if (p.isEmpty) {
        done++;
        continue;
      }
      if (out.existsSync()) partial++;
      final claim = File('$dir/out/$name/${base.replaceAll('.jsonl', '.claim')}');
      if (claim.existsSync() &&
          now.difference(claim.lastModifiedSync()).inHours < 3) {
        claimed++;
        continue;
      }
      pending.add('$name/$base');
    }
    allDone += done;
    allBatches += files.length;
    print('$name: ${files.length} batches, done $done, partial $partial, '
        'claimed $claimed, pending ${files.length - done - claimed}');
  }
  print('total: $allDone of $allBatches batches done');
  for (final p in pending.take(next)) {
    print('next: in/$p, answers to out/$p');
    if (claimer != null) {
      File('$dir/out/$p'.replaceAll('.jsonl', '.claim'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('$claimer ${now.toIso8601String()}\n');
    }
  }
}
