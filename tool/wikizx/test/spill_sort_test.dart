import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:wikizx/spill_sort.dart';

void main() {
  test('sorts across many runs, duplicates and negatives included', () {
    final dir = Directory.systemTemp.createTempSync('spill').path;
    final s = SpillSorter(dir, chunk: 1000);
    final r = Random(3);
    final want = [for (var i = 0; i < 25555; i++) r.nextInt(1 << 31) * 4096 - (1 << 42)];
    want.forEach(s.add);
    want.add(want.first);
    s.add(want.first);
    final got = s.sorted().toList();
    expect(got, want..sort());
    expect(Directory(dir).listSync(), isEmpty);
  });
}
