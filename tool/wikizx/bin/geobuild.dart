// Builds geo.zx: a point for every Wikidata item that has an article in
// one of the chosen Wikipedias, with the way it was found, plus the
// places of people (birth, death, burial), types, dates and the articles
// of each language. Language independent: every Wikipedia joins on the
// Wikidata id. See docs/plan-offline-wikipedia.md, section 9.
//
//   dart run bin/geobuild.dart wd_facts.tsv.zst \
//       wikidatawiki-latest-wb_items_per_site.sql.gz geo.zx [--langs en,pt]
//
// wd_facts.tsv.zst comes from bin/wdfilter.dart.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:wikizx/sqldump.dart';
// ignore: implementation_imports
import 'package:zx/src/db/engine/store.dart' show ZxDbStoreOptions;
// ignore: implementation_imports
import 'package:zx/src/db/zxdb.dart' show ZxDatabase;

/// The order in which an item's point is chosen: its own coordinates,
/// else those of where it happened or stands, else of its area.
const pointTiers = ['P625', 'P276', 'P159', 'P706', 'P131'];
const tierName = {
  'P625': 'own',
  'P276': 'location',
  'P159': 'headquarters',
  'P706': 'terrain',
  'P131': 'area',
};
const personRoles = {'P19': 'birth', 'P20': 'death', 'P119': 'burial'};
const dateProps = {
  'P585': 'point',
  'P580': 'start',
  'P582': 'end',
  'P571': 'inception',
  'P576': 'dissolved',
  'P569': 'birth',
  'P570': 'death',
  'P1619': 'opening',
};

/// Item ids (Q numbers) to a value, filled in any order, then sorted for
/// binary search.
class _IntTable {
  final _keys = <int>[];
  final _vals = <int>[];
  late Int32List keys;
  late Int32List vals;

  void add(int k, int v) {
    _keys.add(k);
    _vals.add(v);
  }

  void seal() {
    final order = List<int>.generate(_keys.length, (i) => i)
      ..sort((a, b) => _keys[a].compareTo(_keys[b]));
    keys = Int32List.fromList([for (final i in order) _keys[i]]);
    vals = Int32List.fromList([for (final i in order) _vals[i]]);
    _keys.clear();
    _vals.clear();
  }

  int? operator [](int k) {
    var lo = 0, hi = keys.length - 1;
    while (lo <= hi) {
      final m = (lo + hi) >> 1;
      final v = keys[m];
      if (v == k) return vals[m];
      v < k ? lo = m + 1 : hi = m - 1;
    }
    return null;
  }
}

/// Coordinates by item, stored as fixed point (1e-6 degrees).
class _Coords {
  final _t = _IntTable();
  final _lat = <int>[];
  final _lon = <int>[];
  late Int32List lat;
  late Int32List lon;

  void add(int q, double la, double lo) {
    _t.add(q, _lat.length);
    _lat.add((la * 1e6).round());
    _lon.add((lo * 1e6).round());
  }

  void seal() {
    _t.seal();
    lat = Int32List.fromList(_lat);
    lon = Int32List.fromList(_lon);
    _lat.clear();
    _lon.clear();
  }

  (double, double)? operator [](int q) {
    final i = _t[q];
    return i == null ? null : (lat[i] / 1e6, lon[i] / 1e6);
  }

  int get length => _t.keys.length;
}

int? _q(String s) => s.startsWith('Q') ? int.tryParse(s.substring(1)) : null;

Stream<List<String>> _facts(String path) async* {
  final p = await Process.start('zstd', ['-dc', '-q', path]);
  p.stderr.listen((_) {});
  await for (final line in p.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())) {
    yield line.split('\t');
  }
}

/// A set of item ids as bits (Q numbers reach about 140 million: 18 MB).
class _Bits {
  var _b = Uint8List(1 << 20);
  void add(int q) {
    if (q >> 3 >= _b.length) {
      final n = Uint8List(((q >> 3) + 1) * 2)..setRange(0, _b.length, _b);
      _b = n;
    }
    _b[q >> 3] |= 1 << (q & 7);
  }

  bool contains(int q) => q >> 3 < _b.length && _b[q >> 3] & (1 << (q & 7)) != 0;
}

class _Batch {
  _Batch(this.db, this.table, this.cols);

  final ZxDatabase db;
  final String table;
  final int cols;
  final rows = <Object?>[];
  int count = 0, total = 0;

  void add(List<Object?> r) {
    rows.addAll(r);
    total++;
    if (++count == 300) flush();
  }

  void flush() {
    if (count == 0) return;
    final one = '(${List.filled(cols, '?').join(',')})';
    db.sql.execute(
        'INSERT INTO $table VALUES ${List.filled(count, one).join(',')}', rows);
    rows.clear();
    count = 0;
    if (total % 500000 < 300) {
      db.sql.execute('COMMIT');
      db.sql.execute('BEGIN');
    }
  }
}

Future<void> main(List<String> args) async {
  final factsPath = args[0], sitesPath = args[1], outPath = args[2];
  final li = args.indexOf('--langs');
  final langs = (li < 0 ? 'en,pt,de,es,fr,it' : args[li + 1]).split(',');
  final sites = {for (final l in langs) '${l}wiki': l};
  final sw = Stopwatch()..start();
  void log(String s) => print('[${(sw.elapsedMilliseconds / 1000).toStringAsFixed(0)}s] '
      '$s, rss ${ProcessInfo.currentRss >> 20} MiB');

  for (final f in [outPath, '$outPath.zx-lock']) {
    if (File(f).existsSync()) File(f).deleteSync();
  }
  final db = ZxDatabase.open(outPath,
      create: true,
      options: ZxDbStoreOptions(
          compression: 'balanced',
          durable: false,
          threads: 4,
          memoryLimit: 768 << 20,
          pageCacheBytes: 64 << 20));
  db.sql.execute('''
CREATE TABLE sitelink (id INTEGER PRIMARY KEY, lang TEXT, title TEXT, qid INTEGER)
  WITH (compression = 'balanced');
CREATE INDEX sitelink_title ON sitelink (lang, title COLLATE NOCASE);
CREATE INDEX sitelink_qid ON sitelink (qid);
CREATE TABLE point (qid INTEGER PRIMARY KEY, lat REAL, lon REAL, tier TEXT,
  via INTEGER, country INTEGER) WITH (compression = 'fast');
CREATE TABLE person_place (id INTEGER PRIMARY KEY, role TEXT, lat REAL,
  lon REAL, via INTEGER) WITH (compression = 'fast');
CREATE TABLE item_type (id INTEGER PRIMARY KEY, type INTEGER)
  WITH (compression = 'fast');
CREATE TABLE item_date (id INTEGER PRIMARY KEY, role TEXT, year INTEGER,
  month INTEGER, day INTEGER) WITH (compression = 'fast');
''');

  // ---- Sitelinks: which items matter, and their article titles.
  final linked = _Bits();
  var linkedCount = 0;
  db.sql.execute('BEGIN');
  final links = _Batch(db, 'sitelink', 4);
  var id = 0;
  await for (final r in sqlDumpRows(sitesPath)) {
    // (ips_row_id, ips_item_id, ips_site_id, ips_site_page)
    final lang = sites[r[2]];
    if (lang == null) continue;
    final q = r[1] as int;
    if (!linked.contains(q)) linkedCount++;
    linked.add(q);
    links.add([++id, lang, r[3], q]);
  }
  links.flush();
  db.sql.execute('COMMIT');
  log('sitelinks: ${links.total} articles, $linkedCount items');

  // ---- Pass 1: coordinates and areas of every item.
  final coords = _Coords();
  final area = _IntTable();
  var lines = 0;
  await for (final f in _facts(factsPath)) {
    lines++;
    if (f[1] == 'P625' && f.length == 4) {
      final q = _q(f[0]);
      if (q != null) coords.add(q, double.parse(f[2]), double.parse(f[3]));
    } else if (f[1] == 'P131') {
      final q = _q(f[0]), t = _q(f[2]);
      if (q != null && t != null) area.add(q, t);
    }
  }
  coords.seal();
  area.seal();
  log('pass 1: $lines facts, ${coords.length} items with coordinates');

  /// The point of [q], climbing its areas when it has none.
  (double, double, int)? pointOf(int q) {
    var cur = q;
    for (var hop = 0; hop < 4; hop++) {
      final c = coords[cur];
      if (c != null) return (c.$1, c.$2, cur);
      final up = area[cur];
      if (up == null) return null;
      cur = up;
    }
    return null;
  }

  // ---- Pass 2: resolve each linked item, its facts grouped by subject.
  db.sql.execute('BEGIN');
  final points = _Batch(db, 'point', 6);
  final persons = _Batch(db, 'person_place', 5);
  final types = _Batch(db, 'item_type', 2);
  final dates = _Batch(db, 'item_date', 5);
  final tiers = <String, int>{};
  int? cur;
  var group = <List<String>>[];
  void flushItem() {
    final q = cur;
    if (q == null || !linked.contains(q)) return;
    final byProp = <String, List<String>>{};
    for (final f in group) {
      (byProp[f[1]] ??= []).add(f.length == 4 ? '${f[2]} ${f[3]}' : f[2]);
    }
    int? country;
    for (final v in byProp['P17'] ?? const <String>[]) {
      country ??= _q(v);
    }
    for (final p in pointTiers) {
      final vs = byProp[p];
      if (vs == null) continue;
      (double, double, int)? got;
      if (p == 'P625') {
        final ll = vs.first.split(' ');
        got = (double.parse(ll[0]), double.parse(ll[1]), q);
      } else {
        for (final v in vs) {
          final t = _q(v);
          if (t != null) got ??= pointOf(t);
        }
      }
      if (got != null) {
        final name = tierName[p]!;
        tiers[name] = (tiers[name] ?? 0) + 1;
        points.add([q, got.$1, got.$2, name, got.$3 == q ? null : got.$3, country]);
        break;
      }
    }
    var n = 0;
    for (final e in personRoles.entries) {
      final v = byProp[e.key]?.first;
      final t = v == null ? null : _q(v);
      final c = t == null ? null : pointOf(t);
      if (c != null) persons.add([q * 4 + n, e.value, c.$1, c.$2, t]);
      n++;
    }
    var k = 0;
    for (final v in byProp['P31'] ?? const <String>[]) {
      final t = _q(v);
      if (t != null && k < 8) types.add([q * 8 + k++, t]);
    }
    k = 0;
    for (final e in dateProps.entries) {
      for (final v in byProp[e.key] ?? const <String>[]) {
        if (k >= 16) break;
        final neg = v.startsWith('-');
        final p = (neg ? v.substring(1) : v).split('-');
        if (p.length != 3) continue;
        final y = int.parse(p[0]), m = int.parse(p[1]), d = int.parse(p[2]);
        // Truthy dates carry no precision: year precision shows as
        // January 1 (or 0); the day is kept only when it says more.
        final yearOnly = (m <= 1 && d <= 1);
        dates.add([q * 16 + k++, e.value, neg ? -y : y,
            yearOnly ? null : m, yearOnly ? null : d]);
      }
    }
  }

  var items = 0;
  await for (final f in _facts(factsPath)) {
    final q = _q(f[0]);
    if (q != cur) {
      flushItem();
      if (++items % 2000000 == 0) log('pass 2: $items items');
      cur = q;
      group = [];
    }
    group.add(f);
  }
  flushItem();
  for (final b in [points, persons, types, dates]) {
    b.flush();
  }
  db.sql.execute('COMMIT');
  log('pass 2: points ${points.total} $tiers, person places ${persons.total}, '
      'types ${types.total}, dates ${dates.total}');
  final fold = db.fold();
  db.vacuum();
  db.close();
  log('folded ${fold.pages} pages; ${File(outPath).lengthSync() >> 20} MiB');
}
