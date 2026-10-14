/// FNV-1a 32 bit hash. Unlike [String.hashCode] it is the same on every
/// run and platform, so a card keeps its picture.
///
/// The multiply by the FNV prime (0x01000193 = 2^24 + 0x193) is split so
/// no intermediate value passes 2^53: on the web ints are doubles.
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x193 + (h & 0xff) * 0x1000000) % 0x100000000;
  }
  return h;
}
