// With --indexes builds the indexes of a converted archive one by one;
// then folds
// (compresses the write buffer) and vacuums, logging each step.
//   dart run bin/finish.dart OUT.zx
import 'dart:io';

// ignore: implementation_imports
import 'package:zx/src/db/engine/store.dart' show ZxDbStoreOptions;
// ignore: implementation_imports
import 'package:zx/src/db/zxdb.dart' show ZxDatabase;

const indexes = [
  'CREATE INDEX IF NOT EXISTS page_title ON page (title COLLATE NOCASE)',
  'CREATE INDEX IF NOT EXISTS page_cell ON page (cell)',
  'CREATE INDEX IF NOT EXISTS page_kind ON page (kind)',
  'CREATE INDEX IF NOT EXISTS redirect_title ON redirect (title COLLATE NOCASE)',
  'CREATE INDEX IF NOT EXISTS fact_day ON fact (month, day, role)',
  'CREATE INDEX IF NOT EXISTS fact_year ON fact (year)',
  'CREATE INDEX IF NOT EXISTS fact_page ON fact (page)',
  'CREATE INDEX IF NOT EXISTS infobox_page ON infobox (page)',
  'CREATE INDEX IF NOT EXISTS link_src ON link (src)',
  'CREATE INDEX IF NOT EXISTS link_dst ON link (dst, role)',
  'CREATE INDEX IF NOT EXISTS rank_inlinks ON rank (inlinks)',
];

void main(List<String> args) {
  final sw = Stopwatch()..start();
  void log(String s) => print(
      '[${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s] $s, '
      'rss ${ProcessInfo.currentRss >> 20} MiB, '
      'file ${File(args[0]).lengthSync() >> 20} MiB');
  final db = ZxDatabase.open(args[0],
      options: ZxDbStoreOptions(
          compression: 'balanced',
          durable: false,
          threads: 4,
          memoryLimit: 768 << 20,
          pageCacheBytes: 64 << 20));
  log('opened');
  for (final q in args.contains('--indexes') ? indexes : const <String>[]) {
    try {
      db.sql.execute(q);
      log(q.split(' ')[5]);
    } catch (e, st) {
      log('FAILED $q: $e\n$st');
      rethrow;
    }
  }
  if (!args.contains('--no-fold')) {
    final d = db.store.foldDeltas();
    log('deltas folded (generation $d)');
    final f = db.fold();
    log('folded ${f.pages} pages, ${f.bytesIn >> 20} MiB in, ${f.bytesOut >> 20} MiB out');
    db.vacuum();
    log('vacuumed');
  }
  db.close();
  log('closed');
}
