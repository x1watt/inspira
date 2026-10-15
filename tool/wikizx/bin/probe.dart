// Phase 0 probe: what is in a Kiwix ZIM, how fast it decodes, and which
// HTML features (infobox, microformats, coordinates) survive.
import 'dart:io';
import 'dart:math';

import 'package:wikizx/zim.dart';

void main(List<String> args) {
  final zim = ZimFile.open(args[0]);
  final sample = args.length > 1 ? int.parse(args[1]) : 2000;
  final dump = args.length > 2 ? args[2] : null;
  print('entries ${zim.entryCount}, clusters ${zim.clusterCount}');
  print('mime types: ${zim.mimeTypes}');
  final sw = Stopwatch()..start();
  final offs = zim.entryOffsets();
  print('entry offsets read in ${sw.elapsedMilliseconds} ms');
  final clusters = zim.clusterOffsets();

  // Count kinds over a stride of entries (cheap estimate).
  final rnd = Random(1);
  final picks = <ZimEntry>[];
  var redirects = 0, html = 0, other = 0;
  final ns = <String, int>{};
  const stride = 997;
  for (var i = 0; i < zim.entryCount; i += stride) {
    final e = zim.entryAt(i, offs);
    ns[e.namespace] = (ns[e.namespace] ?? 0) + 1;
    if (e.isRedirect) {
      redirects++;
    } else if (e.mime >= 0 && zim.mimeTypes[e.mime] == 'text/html') {
      html++;
    } else {
      other++;
    }
  }
  print('by stride $stride: namespaces $ns, redirects $redirects, '
      'html $html, other $other (times $stride for totals)');

  while (picks.length < sample) {
    final e = zim.entryAt(rnd.nextInt(zim.entryCount), offs);
    if (e.namespace == 'C' &&
        !e.isRedirect &&
        e.mime >= 0 &&
        zim.mimeTypes[e.mime] == 'text/html') {
      picks.add(e);
    }
  }
  final features = {
    'infobox': 'class="infobox',
    'vcard': 'vcard',
    'vevent': 'vevent',
    'bday': 'class="bday',
    'dday': 'class="dday',
    'dtstart': 'dtstart',
    'geo': 'class="geo',
    'geo-dec': 'geo-dec',
    'wikidata': 'wikidata',
    'Q-id': RegExp(r'Q\d{3,}'),
    'a href': '<a ',
    'Born row': '>Born<',
    'Died row': '>Died<',
    'Date row': '>Date<',
    'Location row': '>Location<',
  };
  final hits = {for (final k in features.keys) k: 0};
  var bytes = 0, decodeMs = 0;
  final cache = <int, List<dynamic>>{};
  for (final e in picks) {
    final t = Stopwatch()..start();
    final blobs = cache[e.cluster] ??= zim.cluster(e.cluster, clusters);
    decodeMs += t.elapsedMilliseconds;
    final page = String.fromCharCodes(blobs[e.blob]);
    bytes += page.length;
    for (final f in features.entries) {
      final v = f.value;
      if (v is String ? page.contains(v) : (v as RegExp).hasMatch(page)) {
        hits[f.key] = hits[f.key]! + 1;
      }
    }
    if (cache.length > 50) cache.clear();
  }
  print('sample ${picks.length} articles, avg ${bytes ~/ picks.length} '
      'bytes html; cluster decode total $decodeMs ms');
  for (final h in hits.entries) {
    print('  ${h.key}: ${(100 * h.value / picks.length).toStringAsFixed(1)}%');
  }
  if (dump != null) {
    Directory(dump).createSync(recursive: true);
    for (final e in picks.take(40)) {
      final blobs = zim.cluster(e.cluster, clusters);
      File('$dump/${e.path.replaceAll('/', '_')}.html')
          .writeAsBytesSync(blobs[e.blob]);
    }
  }
  zim.close();
}
