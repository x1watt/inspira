// Converts a Kiwix Wikipedia ZIM into a .zx archive whose database holds
// pages (lead text, kind, coordinates), dated facts, infobox rows, links
// between pages and redirects. See docs/plan-offline-wikipedia.md.
//
//   dart run bin/convert.dart IN.zim OUT.zx [--workers 6] [--limit N]
//
// --limit converts only the first N articles (in cluster order), for a
// timing test.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:wikizx/extract.dart';
import 'package:wikizx/spill_sort.dart';
import 'package:wikizx/zim.dart';
// ignore: implementation_imports
import 'package:zx/src/db/engine/store.dart' show ZxDbStoreOptions;
// ignore: implementation_imports
import 'package:zx/src/db/zxdb.dart' show ZxDatabase;

/// FNV-1a 64 of the code units; paths of entries and link targets.
int pathHash(String s) {
  var h = 0xcbf29ce484222325;
  for (var i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i);
    h = (h * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return h;
}

/// Quadkey of the zoom 12 tile holding (lat, lon), as an integer: nearby
/// places share a prefix, so a box is a few ranges.
int cellOf(double lat, double lon) {
  const z = 12;
  final n = 1 << z;
  final x = ((lon + 180) / 360 * n).floor().clamp(0, n - 1);
  final r = lat.clamp(-85.05, 85.05) * pi / 180;
  final y = ((1 - log(tan(r) + 1 / cos(r)) / pi) / 2 * n).floor().clamp(0, n - 1);
  var q = 0;
  for (var i = z - 1; i >= 0; i--) {
    q = q * 4 + ((x >> i) & 1) + 2 * ((y >> i) & 1);
  }
  return q;
}

// Keys that make the B+tree append instead of writing at random places:
// fact and infobox rows are numbered within their page (page * 16 + n,
// page * 256 + n), and links are keyed by (source, target) and, in
// backlink, by (target, source): 23 bits each, so `id >> 23` is the first
// page and `id & 8388607` the second. Links are sorted in memory before
// they are written.
const _schema = '''
CREATE TABLE page (id INTEGER PRIMARY KEY, title TEXT NOT NULL, kind TEXT,
  lead TEXT, lat REAL, lon REAL, cell INTEGER) WITH (compression = 'balanced');
CREATE TABLE redirect (title TEXT, page INTEGER) WITH (compression = 'balanced');
CREATE TABLE fact (id INTEGER PRIMARY KEY, role TEXT, year INTEGER,
  month INTEGER, day INTEGER, precision TEXT) WITH (compression = 'balanced');
CREATE TABLE infobox (id INTEGER PRIMARY KEY, key TEXT, value TEXT)
  WITH (compression = 'balanced');
CREATE TABLE link (id INTEGER PRIMARY KEY, role INTEGER) WITH (compression = 'balanced');
CREATE TABLE backlink (id INTEGER PRIMARY KEY, role INTEGER) WITH (compression = 'balanced');
CREATE TABLE link_role (code INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE rank (page INTEGER PRIMARY KEY, inlinks INTEGER) WITH (compression = 'balanced');
''';

const _indexes = '''
CREATE INDEX page_title ON page (title COLLATE NOCASE);
CREATE INDEX page_cell ON page (cell);
CREATE INDEX page_kind ON page (kind);
CREATE INDEX redirect_title ON redirect (title COLLATE NOCASE);
CREATE INDEX fact_day ON fact (month, day, role);
CREATE INDEX fact_year ON fact (year);
CREATE INDEX rank_inlinks ON rank (inlinks);
''';

const _pageBits = 23;

/// Rows waiting for a multi-row INSERT.
class _Batch {
  _Batch(this.db, this.table, this.cols);

  final ZxDatabase db;
  final String table;
  final int cols;
  final rows = <Object?>[];
  int count = 0;
  static const per = 200;

  void add(List<Object?> r) {
    rows.addAll(r);
    if (++count == per) flush();
  }

  void flush() {
    if (count == 0) return;
    final one = '(${List.filled(cols, '?').join(',')})';
    db.sql.execute(
        'INSERT INTO $table VALUES ${List.filled(count, one).join(',')}',
        rows);
    rows.clear();
    count = 0;
  }
}

Future<void> main(List<String> args) async {
  final inPath = args[0], outPath = args[1];
  int opt(String name, int def) {
    final i = args.indexOf(name);
    return i < 0 ? def : int.parse(args[i + 1]);
  }

  final workers = opt('--workers', 6);
  final limit = opt('--limit', 1 << 40);
  final total = Stopwatch()..start();
  void log(String s) =>
      print('[${(total.elapsedMilliseconds / 1000).toStringAsFixed(1)}s] $s');

  // ---- Pass A: the directory.
  final zim = ZimFile.open(inPath);
  final n = zim.entryCount;
  log('entries $n, clusters ${zim.clusterCount}');
  final offs = zim.entryOffsets();
  final order = Int32List.fromList(List<int>.generate(n, (i) => i))
    ..sort((a, b) => offs[a].compareTo(offs[b]));
  final kind = Int8List(n); // 1 html, 2 redirect, 0 other
  var cluster = Int32List(n);
  var blob = Int32List(n);
  final target = Int32List(n)..fillRange(0, n, -1);
  var hashes = Int64List(n);
  final htmlMime = zim.mimeTypes.indexOf('text/html');
  var redirectCount = 0;
  // Walks the directory in file order (sequential reads).
  void sweep(void Function(ZimEntry e) f) {
    const window = 8 << 20;
    var bufStart = -1;
    Uint8List buf = Uint8List(0);
    for (final i in order) {
      final o = offs[i];
      if (bufStart < 0 || o + 4096 > bufStart + buf.length) {
        bufStart = o;
        buf = zim.read(o, window);
      }
      f(ZimFile.parseEntry(buf, o - bufStart, i).$1);
    }
  }

  sweep((e) {
    if (e.namespace != 'C') return;
    final i = e.index;
    hashes[i] = pathHash(e.path);
    if (e.isRedirect) {
      kind[i] = 2;
      target[i] = e.redirect;
      redirectCount++;
    } else if (e.mime == htmlMime) {
      kind[i] = 1;
      cluster[i] = e.cluster;
      blob[i] = e.blob;
    }
  });
  // Follow redirect chains to an article.
  for (var i = 0; i < n; i++) {
    if (kind[i] != 2) continue;
    var t = target[i], hops = 0;
    while (t >= 0 && kind[t] == 2 && hops++ < 8) {
      t = target[t];
    }
    target[i] = t >= 0 && kind[t] == 1 ? t : -1;
  }
  // Path hash to entry, sorted, for link resolution.
  var byHash = List<int>.generate(n, (i) => i)
      .where((i) => kind[i] != 0)
      .toList()
    ..sort((a, b) => hashes[a].compareTo(hashes[b]));
  var sortedHash = Int64List.fromList([for (final i in byHash) hashes[i]]);
  var sortedEntry = Int32List.fromList(byHash);
  // Only the sorted copies are needed from here.
  byHash = const [];
  hashes = Int64List(0);
  int resolve(int h) {
    var lo = 0, hi = sortedHash.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final v = sortedHash[mid];
      if (v == h) {
        final e = sortedEntry[mid];
        return kind[e] == 1 ? e : target[e];
      }
      v < h ? lo = mid + 1 : hi = mid - 1;
    }
    return -1;
  }

  var articles = [for (var i = 0; i < n; i++) if (kind[i] == 1) i]
    ..sort((a, b) => cluster[a] != cluster[b]
        ? cluster[a].compareTo(cluster[b])
        : blob[a].compareTo(blob[b]));
  var todo = articles.length > limit ? articles.sublist(0, limit) : articles;
  // Page ids follow the conversion order (cluster order), so each worker
  // appends to the page table instead of writing at random places.
  final pageId = Int32List(n)..fillRange(0, n, -1);
  for (var k = 0; k < todo.length; k++) {
    pageId[todo[k]] = k + 1;
  }
  log('articles ${articles.length}, redirects $redirectCount, '
      'converting ${todo.length}');

  // ---- The database.
  final f = File(outPath);
  if (f.existsSync()) f.deleteSync();
  final db = ZxDatabase.open(outPath,
      create: true,
      options: ZxDbStoreOptions(
          compression: 'balanced',
          durable: false,
          threads: workers,
          memoryLimit: 1024 << 20,
          pageCacheBytes: 64 << 20));
  db.sql.execute(_schema);
  // Indexes before the rows: zx's CREATE INDEX on a filled table reads
  // every row into memory (docs/plan-offline-wikipedia.md, findings).
  db.sql.execute(_indexes);
  db.sql.execute('BEGIN');
  var sinceCommit = 0;
  void maybeCommit() {
    if (++sinceCommit < 20000) return;
    db.sql.execute('COMMIT');
    db.sql.execute('BEGIN');
    sinceCommit = 0;
  }

  final pages = _Batch(db, 'page', 7);
  final facts = _Batch(db, 'fact', 6);
  final boxes = _Batch(db, 'infobox', 3);
  if (todo.length >= 1 << _pageBits) throw StateError('too many pages');
  // Link keys go to sorted run files, not memory (67 million of them).
  final runs = '$outPath.runs';
  final linkKeys = SpillSorter('$runs/out');
  final roleCode = <String, int>{'body': 0};
  final inlinks = Int32List(todo.length + 1);

  // ---- Pass B: articles, parsed in workers.
  final port = ReceivePort();
  final per = (todo.length / workers).ceil();
  // Contiguous cluster ranges per worker: each cluster is decoded once.
  for (var w = 0; w < workers; w++) {
    final part = todo.sublist(
        min(w * per, todo.length), min((w + 1) * per, todo.length));
    final triples = Int32List(part.length * 3);
    for (var k = 0; k < part.length; k++) {
      triples[k * 3] = part[k];
      triples[k * 3 + 1] = cluster[part[k]];
      triples[k * 3 + 2] = blob[part[k]];
    }
    await Isolate.spawn(_worker, (port.sendPort, inPath, triples));
  }
  // The workers have their lists; these are not needed any more.
  final pageCount = todo.length;
  cluster = Int32List(0);
  blob = Int32List(0);
  articles = const [];
  todo = const [];
  var done = 0, finished = 0, linkCount = 0, factCount = 0;
  var kinds = <String, int>{};
  var withCoords = 0;
  await for (final msg in port) {
    if (msg == null) {
      if (++finished == workers) break;
      continue;
    }
    final (ack, batch) = msg as (SendPort, List);
    for (final r in batch) {
      final rec = r as List;
      final id = pageId[rec[0] as int];
      final (title, k, lead, lat, lon) = (rec[1] as String, rec[2] as String,
          rec[3] as String, rec[4] as double?, rec[5] as double?);
      kinds[k] = (kinds[k] ?? 0) + 1;
      if (lat != null) withCoords++;
      pages.add([id, title, k, lead, lat, lon, lat == null ? null : cellOf(lat, lon!)]);
      final fs = rec[6] as List;
      for (var j = 0, n = 0; j < fs.length && n < 16; j += 5, n++) {
        final y = fs[j + 1] as int, m = fs[j + 2] as int, d = fs[j + 3] as int;
        facts.add([id * 16 + n, fs[j], y, m == 0 ? null : m, d == 0 ? null : d,
            fs[j + 4]]);
        factCount++;
      }
      final ib = rec[7] as List;
      for (var j = 0, n = 0; j < ib.length && n < 256; j += 2, n++) {
        boxes.add([id * 256 + n, ib[j], ib[j + 1]]);
      }
      final lh = rec[8] as Int64List;
      final lr = rec[9] as List;
      final seen = <int>{};
      for (var j = 0; j < lh.length; j++) {
        final e = resolve(lh[j]);
        // Links to pages outside a --limit run are dropped.
        final dst = e < 0 ? -1 : pageId[e];
        if (dst < 0 || dst == id || !seen.add(dst)) continue;
        // Rare roles share one code.
        final role = roleCode[lr[j]] ??
            (roleCode.length < 255 ? (roleCode[lr[j] as String] = roleCode.length) : 255);
        linkKeys.add((((id << _pageBits) | dst) << 8) | role);
        inlinks[dst]++;
        linkCount++;
      }
      maybeCommit();
      if (++done % 100000 == 0) {
        log('$done pages, $linkCount links, $factCount facts, '
            'rss ${ProcessInfo.currentRss >> 20} MiB');
      }
    }
    // Lets the worker send its next batch: parsing is faster than
    // writing, and unread batches would fill the memory.
    ack.send(true);
  }
  port.close();
  for (final b in [pages, facts, boxes]) {
    b.flush();
  }
  db.sql.execute('COMMIT');
  log('pages done: $done, kinds $kinds, with coordinates $withCoords, '
      'links $linkCount, facts $factCount');

  // Link resolution is over: its tables go before the links are sorted.
  sortedHash = Int64List(0);
  sortedEntry = Int32List(0);

  // Links, sorted by (source, target), then by (target, source).
  {
    db.sql.execute('BEGIN');
    final roles = _Batch(db, 'link_role', 2);
    for (final r in roleCode.entries) {
      roles.add([r.value, r.key]);
    }
    roles.add([255, 'other']);
    roles.flush();
    db.sql.execute('COMMIT');
    const mask = (1 << _pageBits) - 1;
    final back = SpillSorter('$runs/in');
    void write(String table, Iterable<int> keys, [SpillSorter? also]) {
      final b = _Batch(db, table, 2);
      db.sql.execute('BEGIN');
      var i = 0;
      for (final k in keys) {
        b.add([k >> 8, k & 255]);
        if (also != null) {
          final src = k >> (8 + _pageBits), dst = (k >> 8) & mask;
          also.add((((dst << _pageBits) | src) << 8) | (k & 255));
        }
        if (++i % 2000000 == 0) {
          b.flush();
          db.sql.execute('COMMIT');
          db.sql.execute('BEGIN');
        }
      }
      b.flush();
      db.sql.execute('COMMIT');
      log('$table written: $i, rss ${ProcessInfo.currentRss >> 20} MiB');
    }

    write('link', linkKeys.sorted(), back);
    write('backlink', back.sorted());
    Directory(runs).deleteSync(recursive: true);
  }

  // Redirects and ranks, appended in id order.
  db.sql.execute('BEGIN');
  final red = _Batch(db, 'redirect', 2);
  var redirects = 0;
  sweep((e) {
    if (e.namespace == 'C' &&
        e.isRedirect &&
        target[e.index] >= 0 &&
        pageId[target[e.index]] > 0) {
      red.add([e.title, pageId[target[e.index]]]);
      if (++redirects % 1000000 == 0) {
        red.flush();
        db.sql.execute('COMMIT');
        db.sql.execute('BEGIN');
        log('$redirects redirects, rss ${ProcessInfo.currentRss >> 20} MiB');
      }
    }
  });
  red.flush();
  final rank = _Batch(db, 'rank', 2);
  for (var id = 1; id <= pageCount; id++) {
    if (inlinks[id] > 0) rank.add([id, inlinks[id]]);
  }
  rank.flush();
  db.sql.execute('COMMIT');
  log('redirects and ranks written');

  final fold = db.fold();
  log('folded: $fold');
  db.vacuum();
  db.close();
  log('done: ${File(outPath).lengthSync() >> 20} MiB');
}

Future<void> _worker((SendPort, String, Int32List) a) async {
  final (port, path, triples) = a;
  final acks = ReceivePort();
  final ackIt = StreamIterator(acks);
  var unacked = 0;
  Future<void> send(List<List<Object?>> b) async {
    port.send((acks.sendPort, b));
    if (++unacked >= 2) {
      await ackIt.moveNext();
      unacked--;
    }
  }

  final zim = ZimFile.open(path);
  final clusters = zim.clusterOffsets();
  var batch = <List<Object?>>[];
  var cur = -1;
  List<Uint8List> blobs = const [];
  for (var k = 0; k < triples.length; k += 3) {
    final id = triples[k], c = triples[k + 1], b = triples[k + 2];
    if (c != cur) {
      blobs = zim.cluster(c, clusters);
      cur = c;
    }
    final Article art;
    try {
      art = extract(utf8.decode(blobs[b], allowMalformed: true));
    } catch (_) {
      continue;
    }
    final facts = <Object?>[];
    for (final f in art.facts) {
      facts.addAll(
          [f.role, f.date.year, f.date.month, f.date.day, f.date.precision]);
    }
    final ib = <Object?>[];
    for (final r in art.infobox) {
      ib
        ..add(r.$1)
        ..add(r.$2);
    }
    final lh = Int64List(art.links.length);
    final lr = <String>[];
    for (var j = 0; j < art.links.length; j++) {
      lh[j] = pathHash(art.links[j].target);
      lr.add(art.links[j].role);
    }
    batch.add(
        [id, art.title, art.kind, art.lead, art.lat, art.lon, facts, ib, lh, lr]);
    if (batch.length == 500) {
      await send(batch);
      batch = [];
    }
  }
  if (batch.isNotEmpty) await send(batch);
  while (unacked > 0) {
    await ackIt.moveNext();
    unacked--;
  }
  acks.close();
  zim.close();
  port.send(null);
}
