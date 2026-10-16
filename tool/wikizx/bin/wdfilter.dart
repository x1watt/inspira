// Keeps the facts the place pipeline needs from the Wikidata truthy dump
// (N-Triples on stdin, ideally pre-filtered by grep -F -f
// scripts/wd_patterns.txt) and writes compact lines to stdout:
//
//   Q<id> \t P625  \t lat \t lon          coordinates (Earth only)
//   Q<id> \t P<n>  \t Q<id>               item links (location, area...)
//   Q<id> \t P<n>  \t [-]YYYY-MM-DD       dates (truthy keeps no precision)
//   Q<id> \t wiki:<lang> \t Title         Wikipedia articles (sitelinks)
//   Q<id> \t label \t text                English label
//
//   bzip2 -dc latest-truthy.nt.bz2 | grep -F -f wd_patterns.txt |
//     dart run bin/wdfilter.dart | zstd -T4 -q -o wd_facts.tsv.zst
import 'dart:convert';
import 'dart:io';

const _entity = '<http://www.wikidata.org/entity/Q';
const _direct = '<http://www.wikidata.org/prop/direct/';
const _about = '> <http://schema.org/about> <http://www.wikidata.org/entity/Q';
const _label = '> <http://www.w3.org/2000/01/rdf-schema#label> "';
final _date = RegExp(r'^"([+-]?)(\d+)-(\d\d)-(\d\d)T');
const _langs = {'en', 'pt', 'de', 'es', 'fr', 'it'};

/// The item (Q number) in `<http://www.wikidata.org/entity/Q42>` at [at].
String? _item(String s, int at) {
  if (!s.startsWith(_entity, at)) return null;
  final end = s.indexOf('>', at);
  return end < 0 ? null : s.substring(at + _entity.length - 1, end);
}

/// Undoes N-Triples string escapes.
String _unescape(String s) {
  if (!s.contains(r'\')) return s;
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c != r'\' || i + 1 == s.length) {
      b.write(c);
      continue;
    }
    final n = s[++i];
    switch (n) {
      case 'n' || 't' || 'r':
        b.write(' ');
      case 'u':
        b.writeCharCode(int.parse(s.substring(i + 1, i + 5), radix: 16));
        i += 4;
      case 'U':
        b.writeCharCode(int.parse(s.substring(i + 1, i + 9), radix: 16));
        i += 8;
      default:
        b.write(n);
    }
  }
  return b.toString();
}

String? convert(String line) {
  // Sitelinks: <https://pt.wikipedia.org/wiki/Lisboa> schema:about <Q597> .
  if (line.startsWith('<https://')) {
    final a = line.indexOf(_about);
    if (a < 0) return null;
    final host = line.substring(9, line.indexOf('/', 9));
    if (!host.endsWith('.wikipedia.org')) return null;
    final lang = host.substring(0, host.indexOf('.'));
    if (!_langs.contains(lang)) return null;
    final path = line.substring(line.indexOf('/wiki/') + 6, a);
    final q = line.substring(a + _about.length - 1, line.indexOf('>', a + _about.length));
    String title;
    try {
      title = Uri.decodeComponent(path).replaceAll('_', ' ');
    } on ArgumentError {
      return null;
    }
    return '$q\twiki:$lang\t$title';
  }
  final q = _item(line, 0);
  if (q == null) return null;
  final p = line.indexOf('> ', 0) + 2;
  if (line.startsWith(_label, p - 2) && line.endsWith('"@en .')) {
    final text = line.substring(p - 2 + _label.length, line.length - 6);
    return '$q\tlabel\t${_unescape(text).replaceAll('\t', ' ')}';
  }
  if (!line.startsWith(_direct, p)) return null;
  final pe = line.indexOf('>', p);
  final prop = line.substring(p + _direct.length, pe);
  final o = pe + 2;
  if (prop == 'P625') {
    // "Point(lon lat)"^^<...wktLiteral>; other globes start with <...>.
    if (!line.startsWith('"Point(', o)) return null;
    final close = line.indexOf(')', o);
    final parts = line.substring(o + 7, close).split(' ');
    if (parts.length != 2) return null;
    final lon = double.tryParse(parts[0]), lat = double.tryParse(parts[1]);
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
      return null;
    }
    return '$q\tP625\t$lat\t$lon';
  }
  final target = _item(line, o);
  if (target != null) return '$q\t$prop\t$target';
  if (line.startsWith('"', o)) {
    // Dates: "+1066-10-14T00:00:00Z"^^xsd:dateTime (sign optional).
    final m = _date.firstMatch(line.substring(o));
    if (m == null) return null;
    final y = int.parse(m[2]!);
    return '$q\t$prop\t${m[1] == '-' ? '-' : ''}$y-${m[3]}-${m[4]}';
  }
  return null;
}

Future<void> main() async {
  final out = stdout;
  var n = 0, kept = 0;
  await for (final line in stdin
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())) {
    n++;
    final r = convert(line);
    if (r != null) {
      kept++;
      out.writeln(r);
    }
  }
  await out.flush();
  stderr.writeln('wdfilter: $n lines read, $kept kept');
}
