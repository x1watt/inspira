import 'package:flutter_test/flutter_test.dart';
import 'package:inspira/data/stable_hash.dart';

void main() {
  test('matches reference FNV-1a 32 bit values', () {
    expect(stableHash(''), 0x811c9dc5);
    expect(stableHash('a'), 0xe40c292c);
    expect(stableHash('foobar'), 0xbf9cf968);
  });
}
