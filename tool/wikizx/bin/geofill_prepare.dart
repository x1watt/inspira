// Prepares the location fill (docs/plan-geofill.md): finds the English
// articles whose Wikidata item has no point in geo.zx and writes them as
// batch files for a language model, most linked first.
//
//   dart run bin/geofill_prepare.dart en_mini.zx geo.zx geofill \
//       [--batch 200] [--c-limit 50000] [--tag 2027-01] [--groups A,B,C]
//
// Group C leaves out items of the types listed in geofill/skip_types.txt.
//
// With --tag (for a later dump) the groups are named A-<tag>, B-<tag> and
// C-<tag>, and items already answered in geofill/out are left out, so the
// earlier batches and answers never change.
//
// Groups (geofill/in/<group>/<nnnn>.jsonl):
//   A  event pages (ZIM kind event) without any point
//   B  place pages without any point
//   C  other dated items (point in time, start or end; not people), the
//      --c-limit most linked
// Place and event pages that have coordinates in the ZIM but not in
// Wikidata need no model: they go to geofill/zim_points.tsv.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ignore: implementation_imports
import 'package:zx/src/db/zxdb.dart' show ZxDatabase;

Iterable<List<Object?>> _rows(ZxDatabase db, String sql) sync* {
  final c = db.sql.query(sql);
  while (c.moveNext()) {
    yield c.current;
  }
}

class _Bits {
  final _b = Uint8List(1 << 25);
  void add(int q) => _b[q >> 3] |= 1 << (q & 7);
  bool operator [](int q) => _b[q >> 3] & (1 << (q & 7)) != 0;
}

class _Page {
  _Page(this.id, this.title, this.kind, this.inlinks, this.lat, this.lon);
  final int id, inlinks;
  final String title, kind;
  final double? lat, lon;
  int qid = 0;
}

final _boxKey = RegExp(
    r'location|place|site|venue|country|city|region|area|territory|signed|coordinates');

Future<void> main(List<String> args) async {
  final wiki = ZxDatabase.open(args[0], readOnly: true);
  final geo = ZxDatabase.open(args[1], readOnly: true);
  final dir = args[2];
  int opt(String name, int def) {
    final i = args.indexOf(name);
    return i < 0 ? def : int.parse(args[i + 1]);
  }

  final batch = opt('--batch', 200), cLimit = opt('--c-limit', 50000);
  final gi = args.indexOf('--groups');
  final groups = (gi < 0 ? 'A,B,C' : args[gi + 1]).split(',').toSet();
  final ti = args.indexOf('--tag');
  final suffix = ti < 0 ? '' : '-${args[ti + 1]}';
  final answered = <int>{};
  final outDir = Directory('$dir/out');
  if (outDir.existsSync()) {
    for (final f in outDir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.jsonl')) continue;
      for (final l in f.readAsLinesSync()) {
        final m = RegExp(r'"qid":(\d+)').firstMatch(l);
        if (m != null) answered.add(int.parse(m[1]!));
      }
    }
  }
  final sw = Stopwatch()..start();
  void log(String s) => print('[${sw.elapsed.inSeconds}s] $s, '
      'rss ${ProcessInfo.currentRss >> 20} MiB');

  final point = _Bits(), dated = _Bits(), person = _Bits();
  for (final r in _rows(geo, 'SELECT qid FROM point')) {
    point.add(r[0] as int);
  }
  for (final r in _rows(geo, 'SELECT id, role FROM item_date')) {
    final q = (r[0] as int) >> 4, role = r[1];
    if (role == 'birth' || role == 'death') person.add(q);
    if (role == 'point' || role == 'start' || role == 'end') dated.add(q);
  }
  final skipTypes = <int>{};
  final st = File('$dir/skip_types.txt');
  if (st.existsSync()) {
    for (final l in st.readAsLinesSync()) {
      final m = RegExp(r'^Q(\d+)').firstMatch(l);
      if (m != null) skipTypes.add(int.parse(m[1]!));
    }
  }
  final skipped = _Bits();
  for (final r in _rows(geo, 'SELECT id, type FROM item_type')) {
    if (skipTypes.contains(r[1])) skipped.add((r[0] as int) >> 3);
  }
  log('points, dates and types read');

  // Event and place pages by lower case title.
  final pages = <String, _Page>{};
  for (final r in _rows(wiki, 'SELECT id, title, kind, inlinks, lat, lon FROM page_meta')) {
    final k = r[2];
    if (k != 'event' && k != 'place') continue;
    final t = r[1] as String;
    pages[t.toLowerCase()] = _Page(r[0] as int, t, k as String, r[3] as int,
        (r[4] as num?)?.toDouble(), (r[5] as num?)?.toDouble());
  }
  log('${pages.length} event and place pages');

  final a = <_Page>[], b = <_Page>[];
  final cTitle = <String, int>{}; // lower case title -> qid
  final zim = File('$dir/zim_points$suffix.tsv');
  zim.parent.createSync(recursive: true);
  final writeZim = groups.contains('A') || groups.contains('B');
  final zimOut = (writeZim ? zim : File('/dev/null')).openWrite()..writeln('qid\tlat\tlon\ttitle');
  var zimCount = 0;
  for (final r in _rows(geo, 'SELECT lang, title, qid FROM sitelink')) {
    if (r[0] != 'en') continue;
    final q = r[2] as int;
    if (point[q] || answered.contains(q)) continue;
    final lower = (r[1] as String).toLowerCase();
    final p = pages.remove(lower);
    if (p != null) {
      p.qid = q;
      if (p.lat != null) {
        zimOut.writeln('$q\t${p.lat}\t${p.lon}\t${p.title}');
        zimCount++;
      } else {
        (p.kind == 'event' ? a : b).add(p);
      }
    } else if (dated[q] && !person[q] && !skipped[q]) {
      cTitle[lower] = q;
    }
  }
  await zimOut.close();
  pages.clear();
  log('A ${a.length}, B ${b.length}, ZIM points $zimCount, C candidates ${cTitle.length}');

  // Incoming links of the C candidates, to keep the most linked.
  final c = <_Page>[];
  for (final r in _rows(wiki, 'SELECT id, title, kind, inlinks FROM page_meta')) {
    final q = cTitle.remove((r[1] as String).toLowerCase());
    if (q == null || r[2] == 'disambiguation') continue;
    c.add(_Page(r[0] as int, r[1] as String, r[2] as String, r[3] as int, null, null)
      ..qid = q);
  }
  c.sort((x, y) => y.inlinks.compareTo(x.inlinks));
  if (c.length > cLimit) c.removeRange(cLimit, c.length);
  log('C kept ${c.length}');

  final lead = wiki.sql.prepare('SELECT lead FROM page WHERE id = ?');
  final box = wiki.sql.prepare('SELECT key, value FROM infobox WHERE id BETWEEN ? AND ?');
  String cut(String s, int n) => s.length > n ? s.substring(0, n) : s;
  for (final (name, list) in [('A', a), ('B', b), ('C', c)]) {
    if (!groups.contains(name)) continue;
    list.sort((x, y) => y.inlinks.compareTo(x.inlinks));
    final out = Directory('$dir/in/$name$suffix')..createSync(recursive: true);
    for (var i = 0; i < list.length; i += batch) {
      final f = File('${out.path}/${(i ~/ batch + 1).toString().padLeft(4, '0')}.jsonl');
      final sb = StringBuffer();
      for (final p in list.skip(i).take(batch)) {
        final l = lead.select([p.id]);
        final info = <String, String>{};
        for (final r in box.select([p.id * 256, p.id * 256 + 255])) {
          final k = (r[0] as String).toLowerCase();
          if (_boxKey.hasMatch(k)) info[k] = cut(r[1] as String, 160);
        }
        sb.writeln(jsonEncode({
          'qid': p.qid,
          'title': p.title,
          'lead': cut(l.isEmpty ? '' : (l.first[0] as String? ?? ''), 600),
          if (info.isNotEmpty) 'infobox': info,
        }));
      }
      f.writeAsStringSync(sb.toString());
    }
    log('group $name$suffix: ${list.length} items in ${(list.length + batch - 1) ~/ batch} batches');
  }
  wiki.close();
  geo.close();
}
