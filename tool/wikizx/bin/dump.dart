// Writes the HTML of the named articles (ZIM paths) to a folder.
//   dart run bin/dump.dart IN.zim OUTDIR Path_One Path_Two
import 'dart:io';
import 'dart:typed_data';

import 'package:wikizx/zim.dart';

void main(List<String> args) {
  final zim = ZimFile.open(args[0]);
  final want = args.skip(2).toSet();
  final offs = zim.entryOffsets();
  final clusters = zim.clusterOffsets();
  Directory(args[1]).createSync(recursive: true);
  // Entries are sorted by namespace and path: binary search.
  for (final path in want) {
    var lo = 0, hi = zim.entryCount - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      var e = zim.entryAt(mid, offs);
      final c = '${e.namespace}/${e.path}'.compareTo('C/$path');
      if (c == 0) {
        while (e.isRedirect) {
          e = zim.entryAt(e.redirect, offs);
        }
        final Uint8List b = zim.cluster(e.cluster, clusters)[e.blob];
        File('${args[1]}/${e.path.replaceAll('/', '_')}.html').writeAsBytesSync(b);
        print('wrote ${e.path}');
        break;
      }
      c < 0 ? lo = mid + 1 : hi = mid - 1;
    }
  }
}
