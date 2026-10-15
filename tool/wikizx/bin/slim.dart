// Adds page_meta: the small columns of page plus the incoming link count,
// LZ4 compressed ('fast'), so lists of pages (on this day, near a place)
// do not decode LZMA2 blocks full of lead text for every row.
//   dart run bin/slim.dart OUT.zx
import 'dart:io';

// ignore: implementation_imports
import 'package:zx/src/db/engine/store.dart' show ZxDbStoreOptions;
// ignore: implementation_imports
import 'package:zx/src/db/zxdb.dart' show ZxDatabase;

void main(List<String> args) {
  final sw = Stopwatch()..start();
  void log(String s) =>
      print('[${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s] $s, '
          'rss ${ProcessInfo.currentRss >> 20} MiB');
  final db = ZxDatabase.open(args[0],
      options: ZxDbStoreOptions(
          compression: 'balanced',
          durable: false,
          threads: 4,
          memoryLimit: 768 << 20));
  db.sql.execute('''
    CREATE TABLE IF NOT EXISTS page_meta (id INTEGER PRIMARY KEY, title TEXT,
      kind TEXT, lat REAL, lon REAL, cell INTEGER, inlinks INTEGER)
      WITH (compression = 'fast')''');
  final have = db.sql
      .execute('SELECT count(*) FROM (SELECT 1 FROM page_meta LIMIT 1)')
      .rows
      .first
      .first as int;
  if (have == 0) {
    db.sql.execute('''
      INSERT INTO page_meta
      SELECT p.id, p.title, p.kind, p.lat, p.lon, p.cell, coalesce(r.inlinks, 0)
      FROM page p LEFT JOIN rank r ON r.page = p.id''');
  }
  log('page_meta filled');
  db.sql
      .execute('CREATE INDEX IF NOT EXISTS page_meta_cell ON page_meta (cell)');
  log('cell index');
  // On this day: one row per dated fact, keyed so that a day's facts come
  // out most linked first: (month * 32 + day) << 47, then 2^20 - 1 minus
  // the incoming links (capped), then the fact id (page * 16 + n).
  db.sql.execute('''
    CREATE TABLE IF NOT EXISTS day_fact (id INTEGER PRIMARY KEY, title TEXT,
      kind TEXT, role TEXT, year INTEGER, inlinks INTEGER)
      WITH (compression = 'fast')''');
  db.sql.execute('''
    INSERT INTO day_fact
    SELECT ((f.month * 32 + f.day) << 47)
             | ((1048575 - min(m.inlinks, 1048575)) << 27) | f.id,
           m.title, m.kind, f.role, f.year, m.inlinks
    FROM fact f JOIN page_meta m ON m.id = (f.id >> 4)
    WHERE f.day IS NOT NULL''');
  log('day_fact filled');
  db.close();
  log('closed, file ${File(args[0]).lengthSync() >> 20} MiB');
}
