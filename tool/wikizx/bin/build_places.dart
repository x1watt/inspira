// Writes en_places.zx for the app's map: every English Wikipedia article
// in en_mini.zx whose Wikidata item has a point in geo.zx and is a place
// worth a visit or something that happened there: events, castles,
// churches, museums, monuments, other buildings, nature and settlements
// (the categories of the item's types, geofill/place_types.tsv). People,
// companies, schools, stations, roads and the like are left out.
// See docs/architecture.md, section 7.
//
//   dart run bin/build_places.dart en_mini.zx geo.zx geofill en_places.zx \
//       [wikipedia_en_all_mini.zim]
//
// The places, keyed so that a map tile is one range of keys and its best
// known articles come first:
//
//   place (id = cell << 24 | n, page, title, cat, year, lat, lon, score,
//          approx)
//
// cell is the quadkey of the zoom 12 tile (24 bits; a zoom z tile is the
// keys [q << (2 * (12 - z) + 24), (q + 1) << ...)), n the rank of the
// article in its tile by score (English incoming links + 4 per Wikipedia
// language with an article; a quarter of that for towns), page the id of the article in en_mini.zx
// (its lead), approx 1 when only the area is known.
//
// With the ZIM, the articles en_mini.zx lost (an extractor error, fixed
// since) are read from it and kept in article (id, title, kind, lead);
// their places have page = -id.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:wikizx/extract.dart';
import 'package:wikizx/geofill.dart' show km;
import 'package:wikizx/zim.dart';
// ignore: implementation_imports
import 'package:zx/src/db/zxdb.dart' show ZxDatabase;
// ignore: implementation_imports
import 'package:zx/src/db/engine/store.dart' show ZxDbStoreOptions;

/// In priority order: an item with several types takes the first.
const cats = [
  'event',
  'castle',
  'religious',
  'museum',
  'monument',
  'building',
  'nature',
  'settlement',
];

/// Items whose point, when another item has it, means "somewhere in
/// there": countries, continents, oceans and seas.
const _countryTypes = {6256, 3624078, 3024240, 7275, 5107, 9430, 165};

/// Quadkey of the zoom 12 tile holding (lat, lon); the same as
/// bin/convert.dart and the app's lib/data/wiki/wiki_places.dart.
int cellOf(double lat, double lon) {
  const z = 12;
  final n = 1 << z;
  final x = ((lon + 180) / 360 * n).floor().clamp(0, n - 1);
  final r = lat.clamp(-85.05, 85.05) * pi / 180;
  final y = ((1 - log(tan(r) + 1 / cos(r)) / pi) / 2 * n).floor().clamp(
    0,
    n - 1,
  );
  var q = 0;
  for (var i = z - 1; i >= 0; i--) {
    q = q * 4 + ((x >> i) & 1) + 2 * ((y >> i) & 1);
  }
  return q;
}

Iterable<List<Object?>> _rows(ZxDatabase db, String sql) sync* {
  final c = db.sql.query(sql);
  while (c.moveNext()) {
    yield c.current;
  }
}

void main(List<String> args) {
  final sw = Stopwatch()..start();
  void log(String s) => print(
    '[${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s] $s, '
    'rss ${ProcessInfo.currentRss >> 20} MiB',
  );
  final wiki = ZxDatabase.open(args[0], readOnly: true);
  final geo = ZxDatabase.open(args[1], readOnly: true);
  final dir = args[2];

  // ---- Points, in qid order (the table's key): binary search by qid.
  final qs = <int>[], lat = <double>[], lon = <double>[];
  final tierOf = <String>[];
  final tierCode = Uint8List(4 << 20);
  for (final r in _rows(geo, 'SELECT qid, lat, lon, tier FROM point')) {
    final t = r[3] as String;
    var code = tierOf.indexOf(t);
    if (code < 0) {
      tierOf.add(t);
      code = tierOf.length - 1;
    }
    tierCode[qs.length] = code;
    qs.add(r[0] as int);
    lat.add((r[1] as num).toDouble());
    lon.add((r[2] as num).toDouble());
  }
  final q = Int64List.fromList(qs);
  final n = q.length;
  int at(int qid) {
    var lo = 0, hi = n - 1;
    while (lo <= hi) {
      final m = (lo + hi) >> 1;
      final v = q[m];
      if (v == qid) return m;
      if (v < qid) {
        lo = m + 1;
      } else {
        hi = m - 1;
      }
    }
    return -1;
  }

  log('$n points');

  // ---- Categories of the types; 255 = none, 254 = never a place.
  final typeCat = <int, int>{};
  for (final l in File('$dir/place_types.tsv').readAsLinesSync()) {
    if (l.startsWith('#') || l.isEmpty) continue;
    final f = l.split('\t');
    typeCat[int.parse(f[0].substring(1))] = f[1] == '-'
        ? 254
        : cats.indexOf(f[1]);
  }
  final skip = <int>{};
  for (final l in File('$dir/skip_types.txt').readAsLinesSync()) {
    final m = RegExp(r'^Q(\d+)').firstMatch(l);
    if (m != null) skip.add(int.parse(m[1]!));
  }
  final cat = Uint8List(n)..fillRange(0, n, 255);
  final never = Uint8List(n); // a type that is never a place, or skipped
  final country = Uint8List(n);
  for (final r in _rows(geo, 'SELECT id, type FROM item_type')) {
    final i = at((r[0] as int) >> 3);
    if (i < 0) continue;
    final t = r[1] as int;
    if (_countryTypes.contains(t)) country[i] = 1;
    final c = typeCat[t];
    if (c == 254 || skip.contains(t)) never[i] = 1;
    if (c != null && c < 254 && c < cat[i]) cat[i] = c;
  }
  log('types');

  // ---- Years (earliest point in time or start) and people.
  final year = Int32List(n)..fillRange(0, n, -1 << 30);
  final person = Uint8List(n);
  for (final r in _rows(geo, 'SELECT id, role, year FROM item_date')) {
    final i = at((r[0] as int) >> 4);
    if (i < 0) continue;
    final role = r[1];
    if (role == 'birth' || role == 'death') person[i] = 1;
    if ((role == 'point' || role == 'start') && r[2] != null) {
      final y = r[2] as int;
      if (year[i] == -1 << 30 || y < year[i]) year[i] = y;
    }
  }
  log('dates');

  // Points that only say "the country": a model's or a centroid's,
  // within 25 km of a country's point (export_wikiplaces.dart).
  final centroids = <int>{
    for (final l in File('$dir/centroids.tsv').readAsLinesSync().skip(1))
      if (l.isNotEmpty) int.parse(l),
  };
  final countryPts = <(double, double)>[
    for (var i = 0; i < n; i++)
      if (country[i] == 1) (lat[i], lon[i]),
  ];
  final low = tierOf.indexOf('model-low');
  final own = tierOf.indexOf('own');
  final approxTiers = {tierOf.indexOf('area'), tierOf.indexOf('model-medium')};

  // ---- English titles of the items that could be places.
  final keep = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (person[i] == 1 || country[i] == 1) continue;
    if (tierCode[i] == low) continue;
    if (cat[i] == 255 && (never[i] == 1 || year[i] == -1 << 30)) continue;
    keep[i] = 1;
  }
  // The number of Wikipedias with an article: how well known it is, for
  // the ranking, with the English incoming links.
  final langs = Uint16List(n);
  final enTitle = List<String?>.filled(n, null);
  final titleAt = <String, int>{};
  for (final r in _rows(geo, 'SELECT lang, title, qid FROM sitelink')) {
    final i = at(r[2] as int);
    if (i < 0 || keep[i] == 0) continue;
    if (langs[i] < 65535) langs[i]++;
    if (r[0] != 'en') continue;
    enTitle[i] = r[1] as String;
    titleAt[(r[1] as String).toLowerCase()] = i;
  }
  log('${titleAt.length} titles');

  // Elections and referendums are nationwide; "Judo at the 1996 Summer
  // Olympics" is the games'; lists are not places.
  final titleSkip = RegExp(
    r'\b(election|elections|referendum|by-election)\b| at the \d{4} |^List of ',
    caseSensitive: false,
  );
  // cell, score, page (negative: an article of this file), title, i
  final rows = <(int, int, int, String, int)>[];
  final usedPage = <int>{};
  void consider(int page, String t, String? kind, int links, int i) {
    if (kind == 'person' || kind == 'disambiguation') return;
    if (titleSkip.hasMatch(t) || usedPage.contains(page)) return;
    if (cat[i] == 255) {
      // untyped but dated: an event, if the article agrees
      if (never[i] == 1) return;
      if (kind != 'event' && kind != 'other') return;
      cat[i] = 0;
    }
    if (tierCode[i] != own) {
      if (centroids.contains(q[i]) && !tierOf[tierCode[i]].startsWith('model')) {
        return;
      }
      if (countryPts.any((c) => km(lat[i], lon[i], c.$1, c.$2) < 25)) return;
    }
    usedPage.add(page);
    // towns count a quarter: they are everywhere and have articles in
    // many languages, and the map is for what to see there
    final score = links + 4 * langs[i];
    rows.add((
      cellOf(lat[i], lon[i]),
      cats[cat[i]] == 'settlement' ? score ~/ 4 : score,
      page,
      t,
      i,
    ));
  }

  for (final r in _rows(wiki, 'SELECT id, title, kind, inlinks FROM page_meta')) {
    final t = r[1] as String;
    final i = titleAt.remove(t.toLowerCase());
    if (i != null) consider(r[0] as int, t, r[2] as String?, r[3] as int? ?? 0, i);
  }
  log('${rows.length} places by title, ${titleAt.length} titles left');

  // Articles renamed since the Wikidata dump: their old title redirects.
  final pending = <int, int>{};
  for (final r in _rows(wiki, 'SELECT title, page FROM redirect')) {
    final i = titleAt.remove((r[0] as String).toLowerCase());
    if (i != null) pending[r[1] as int] = i;
  }
  final ids = pending.keys.toList();
  for (var k = 0; k < ids.length; k += 500) {
    final part = ids.sublist(k, min(k + 500, ids.length));
    for (final r in _rows(
      wiki,
      'SELECT id, title, kind, inlinks FROM page_meta WHERE id IN '
      '(${part.join(',')})',
    )) {
      final i = pending.remove(r[0] as int)!;
      consider(r[0] as int, r[1] as String, r[2] as String?, r[3] as int? ?? 0, i);
    }
  }
  // Redirects to an article en_mini.zx lost: try the title in the ZIM.
  for (final i in pending.values) {
    titleAt[enTitle[i]!.toLowerCase()] = i;
  }
  log('${rows.length} places with redirects, ${titleAt.length} titles left');

  // Articles missing from en_mini.zx (an extractor error dropped them):
  // their lead from the ZIM, kept in this file's article table.
  final extra = <(int, String, String, String)>[]; // id, title, kind, lead
  if (args.length > 4) {
    final zim = ZimFile.open(args[4]);
    final offs = zim.entryOffsets(), clusters = zim.clusterOffsets();
    String keyOf(ZimEntry e) => '${e.namespace}/${e.path}';
    final found = <(int, int, int)>[]; // cluster, blob, i
    for (final i in titleAt.values) {
      final want = 'C/${enTitle[i]!.replaceAll(' ', '_')}';
      var lo = 0, hi = zim.entryCount - 1;
      while (lo <= hi) {
        final m = (lo + hi) >> 1;
        var e = zim.entryAt(m, offs);
        final c = keyOf(e).compareTo(want);
        if (c == 0) {
          for (var hop = 0; e.isRedirect && hop < 8; hop++) {
            e = zim.entryAt(e.redirect, offs);
          }
          if (!e.isRedirect) found.add((e.cluster, e.blob, i));
          break;
        }
        c < 0 ? lo = m + 1 : hi = m - 1;
      }
    }
    found.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    var cur = -1;
    List<Uint8List> blobs = const [];
    for (final (c, b, i) in found) {
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
      final id = extra.length + 1;
      final before = rows.length;
      consider(-id, art.title, art.kind, 0, i);
      if (rows.length > before) extra.add((id, art.title, art.kind, art.lead));
    }
    zim.close();
    log('${found.length} titles in the ZIM, ${extra.length} articles kept');
  }
  titleAt.clear();
  log('${rows.length} places');

  rows.sort((a, b) {
    final c = a.$1.compareTo(b.$1);
    return c != 0 ? c : b.$2.compareTo(a.$2);
  });

  final out = File(args[3]);
  if (out.existsSync()) out.deleteSync();
  final db = ZxDatabase.open(
    args[3],
    create: true,
    options: ZxDbStoreOptions(
      compression: 'balanced',
      durable: false,
      threads: 4,
      memoryLimit: 256 << 20,
    ),
  );
  db.sql.execute('''
CREATE TABLE place (id INTEGER PRIMARY KEY, page INTEGER, title TEXT,
  cat TEXT, year INTEGER, lat REAL, lon REAL, score INTEGER, approx INTEGER)
  WITH (compression = 'balanced')''');
  db.sql.execute('''
CREATE TABLE article (id INTEGER PRIMARY KEY, title TEXT, kind TEXT,
  lead TEXT) WITH (compression = 'balanced');
CREATE INDEX article_title ON article (title COLLATE NOCASE)''');
  db.sql.execute('BEGIN');
  for (final (id, title, kind, lead) in extra) {
    db.sql.execute('INSERT INTO article VALUES (?, ?, ?, ?)', [
      id,
      title,
      kind,
      lead,
    ]);
  }
  final batch = <Object?>[];
  var count = 0, cell = -1, rank = 0;
  final perCat = List.filled(cats.length, 0);
  double r5(double v) => (v * 100000).round() / 100000;
  void flush() {
    if (count == 0) return;
    db.sql.execute(
      'INSERT INTO place VALUES '
      '${List.filled(count, '(?,?,?,?,?,?,?,?,?)').join(',')}',
      batch,
    );
    batch.clear();
    count = 0;
  }

  var written = 0;
  for (final (c, score, page, title, i) in rows) {
    rank = c == cell ? rank + 1 : 0;
    cell = c;
    if (rank >= 1 << 24) continue;
    perCat[cat[i]]++;
    batch.addAll([
      c << 24 | rank,
      page,
      title,
      cats[cat[i]],
      year[i] == -1 << 30 ? null : year[i],
      r5(lat[i]),
      r5(lon[i]),
      score,
      approxTiers.contains(tierCode[i]) ? 1 : 0,
    ]);
    if (++count == 200) flush();
    if (++written % 500000 == 0) {
      flush();
      db.sql.execute('COMMIT');
      db.sql.execute('BEGIN');
      log('$written written');
    }
  }
  flush();
  db.sql.execute('COMMIT');
  db.close();
  wiki.close();
  geo.close();
  for (var c = 0; c < cats.length; c++) {
    print('${cats[c]}: ${perCat[c]}');
  }
  log('$written places in ${args[3]}, ${out.lengthSync() >> 20} MiB');
}
