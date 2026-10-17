import 'dart:convert';
import 'dart:io';
import 'package:wikizx/zim.dart';

// Prints the HTML of ZIM articles: dart run bin/zim_get.dart file.zim Title...
void main(List<String> args) {
  final zim = ZimFile.open(args[0]);
  final offs = zim.entryOffsets(), clusters = zim.clusterOffsets();
  for (final t in args.skip(1)) {
    final want = 'C/${t.replaceAll(' ', '_')}';
    var lo = 0, hi = zim.entryCount - 1;
    while (lo <= hi) {
      final m = (lo + hi) >> 1;
      var e = zim.entryAt(m, offs);
      final c = '${e.namespace}/${e.path}'.compareTo(want);
      if (c == 0) {
        while (e.isRedirect) { e = zim.entryAt(e.redirect, offs); }
        stdout.writeln(utf8.decode(zim.cluster(e.cluster, clusters)[e.blob], allowMalformed: true));
        break;
      }
      c < 0 ? lo = m + 1 : hi = m - 1;
    }
  }
}
