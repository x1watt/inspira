// Counts the types (P31) of the items that have a point in geo.zx, most
// common first, for the categories of bin/build_places.dart.
//
//   dart run bin/places_types.dart geo.zx > types.tsv
import 'dart:typed_data';

// ignore: implementation_imports
import 'package:zx/src/db/zxdb.dart' show ZxDatabase;

void main(List<String> args) {
  final geo = ZxDatabase.open(args[0], readOnly: true);
  final has = Uint8List(1 << 25);
  var c = geo.sql.query('SELECT qid FROM point');
  while (c.moveNext()) {
    final q = c.current[0] as int;
    has[q >> 3] |= 1 << (q & 7);
  }
  final n = <int, int>{};
  c = geo.sql.query('SELECT id, type FROM item_type');
  while (c.moveNext()) {
    final q = (c.current[0] as int) >> 3;
    if (has[q >> 3] & (1 << (q & 7)) == 0) continue;
    final t = c.current[1] as int;
    n[t] = (n[t] ?? 0) + 1;
  }
  final top = n.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final e in top.take(1500)) {
    print('Q${e.key}\t${e.value}');
  }
  geo.close();
}
