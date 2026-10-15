// Runs SQL against a converted archive and prints rows with timings.
//   dart run bin/query.dart OUT.zx "SELECT ..." ["SELECT ..."]
import 'package:zx/src/db/zxdb.dart' show ZxDatabase; // ignore: implementation_imports

void main(List<String> args) {
  final db = ZxDatabase.open(args[0], readOnly: true);
  for (final q in args.skip(1)) {
    for (var run = 0; run < 2; run++) {
      final sw = Stopwatch()..start();
      final r = db.sql.execute(q);
      final ms = sw.elapsedMicroseconds / 1000;
      print('-- ${run == 0 ? 'cold' : 'warm'} ${ms.toStringAsFixed(1)} ms, ${r.rows.length} rows: $q');
      if (run == 1) {
        for (final row in r.rows.take(15)) {
          print('   ${row.map((v) => v is String && v.length > 70 ? '${v.substring(0, 70)}...' : v).join(' | ')}');
        }
      }
    }
  }
  db.close();
}
