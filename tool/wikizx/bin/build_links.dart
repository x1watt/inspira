// Writes en_links.zx, the external links of the English articles, for
// the app's article sheets: what Wikipedia lists under "External links"
// (bin/extlinks.dart), else the official website of the article's
// Wikidata item (P856). See docs/architecture.md, section 7.
//
//   lbzip2 -dc latest-truthy.nt.bz2 |
//     LC_ALL=C grep -F '/prop/direct/P856> ' > wd_p856.nt
//   dart run bin/build_links.dart en_mini.zx geo.zx wd_p856.nt \
//       extlinks.tsv en_places.zx en_links.zx
//
//   extlink (id = page * 16 + n, url TEXT, label TEXT)
//
// page is the id of the article in en_mini.zx, or minus the id of one in
// en_places.zx's own article table (read, not changed), as place.page; n orders an article's
// links as Wikipedia does (16 at most), so an article is one key range.
import 'dart:io';

// ignore: implementation_imports
import 'package:zx/src/db/engine/store.dart' show ZxDbStoreOptions;

// ignore: implementation_imports
import 'package:zx/src/db/zxdb.dart' show ZxDatabase;

Iterable<List<Object?>> _rows(ZxDatabase db, String sql) sync* {
  final c = db.sql.query(sql);
  while (c.moveNext()) {
    yield c.current;
  }
}

const _entity = '<http://www.wikidata.org/entity/Q';

void main(List<String> args) {
  final sw = Stopwatch()..start();
  void log(String s) => print(
        '[${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s] $s, '
        'rss ${ProcessInfo.currentRss >> 20} MiB',
      );
  bool web(String url) =>
      url.startsWith(RegExp('https?://')) && !url.contains(RegExp(r'[\s\\\t]'));

  // ---- Q number to official website.
  final site = <int, String>{};
  for (final l in File(args[2]).readAsLinesSync()) {
    if (!l.startsWith(_entity)) continue;
    final q = int.tryParse(l.substring(_entity.length, l.indexOf('>')));
    final s = l.indexOf('> <', l.indexOf('/P856>')) + 3;
    final e = l.lastIndexOf('>');
    if (q == null || s < 3 || e <= s || site.containsKey(q)) continue;
    final url = l.substring(s, e);
    if (web(url)) site[q] = url;
  }
  log('${site.length} items with a website');

  // ---- English title to its official website.
  final geo = ZxDatabase.open(args[1], readOnly: true);
  final official = <String, String>{};
  // a full scan: a filter on lang would go through its index row by row
  for (final r in _rows(geo, 'SELECT lang, title, qid FROM sitelink')) {
    if (r[0] != 'en') continue;
    final url = site[r[2] as int];
    if (url != null) official[(r[1] as String).toLowerCase()] = url;
  }
  geo.close();
  site.clear();
  log('${official.length} English articles with a website');

  // ---- English title to its links: url \t label lines, in order.
  final links = <String, String>{};
  for (final l in File(args[3]).readAsLinesSync()) {
    final a = l.indexOf('\t'), b = l.indexOf('\t', a + 1);
    if (a < 0 || b < 0) continue;
    final key = l.substring(0, a).toLowerCase();
    var url = l.substring(a + 1, b);
    if (url == 'wikidata') {
      url = official[key] ?? '';
    }
    if (!web(url)) continue;
    // "Name:, note" when the name ends in a colon (bin/extlinks.dart)
    final label = l.substring(b + 1).replaceAll(RegExp(r'[:;,]+, '), ', ');
    final line = '$url\t$label';
    final have = links[key];
    if (have != null && have.contains('$url\t')) continue;
    links[key] = have == null ? line : '$have\n$line';
  }
  for (final MapEntry(:key, :value) in official.entries) {
    links.putIfAbsent(key, () => '$value\tOfficial website');
  }
  official.clear();
  log('${links.length} English articles with links');

  // ---- Article ids, as build_places.dart: title, then redirects, then
  // this file's own articles.
  final wiki = ZxDatabase.open(args[0], readOnly: true);
  final out = <int, String>{};
  for (final r in _rows(wiki, 'SELECT id, title FROM page_meta')) {
    final l = links.remove((r[1] as String).toLowerCase());
    if (l != null) out[r[0] as int] = l;
  }
  log('${out.length} by title');
  for (final r in _rows(wiki, 'SELECT title, page FROM redirect')) {
    final l = links.remove((r[0] as String).toLowerCase());
    if (l != null) out.putIfAbsent(r[1] as int, () => l);
  }
  wiki.close();
  log('${out.length} with redirects');

  final places = ZxDatabase.open(args[4], readOnly: true);
  for (final r in _rows(places, 'SELECT id, title FROM article')) {
    final l = links.remove((r[1] as String).toLowerCase());
    if (l != null) out[-(r[0] as int)] = l;
  }
  places.close();
  links.clear();
  final file = File(args[5]);
  if (file.existsSync()) file.deleteSync();
  final db = ZxDatabase.open(
    args[5],
    create: true,
    options: ZxDbStoreOptions(
      compression: 'max',
      durable: false,
      threads: 4,
      memoryLimit: 256 << 20,
    ),
  );
  db.sql.execute('''
CREATE TABLE extlink (id INTEGER PRIMARY KEY, url TEXT, label TEXT)
  WITH (compression = 'max')''');
  final pages = out.keys.toList()..sort();
  final batch = <Object?>[];
  var count = 0, written = 0;
  void flush() {
    if (count == 0) return;
    db.sql.execute(
      'INSERT INTO extlink VALUES ${List.filled(count, '(?,?,?)').join(',')}',
      batch,
    );
    batch.clear();
    count = 0;
  }

  db.sql.execute('BEGIN');
  for (final p in pages) {
    var n = 0;
    for (final line in out[p]!.split('\n')) {
      if (n == 16) break;
      final t = line.indexOf('\t');
      batch.addAll([p * 16 + n++, line.substring(0, t), line.substring(t + 1)]);
      if (++count == 200) flush();
      written++;
    }
  }
  flush();
  db.sql.execute('COMMIT');
  db.close();
  log(
    '$written links of ${pages.length} articles in ${args[5]}, '
    '${file.lengthSync() >> 20} MiB',
  );
}
