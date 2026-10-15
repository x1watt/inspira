import 'dart:io';

import 'package:wikizx/extract.dart';

void main(List<String> args) {
  for (final p in args) {
    final a = extract(File(p).readAsStringSync());
    print('== ${a.title} [${a.kind}] ${a.lat},${a.lon}');
    print('   facts: ${a.facts.map((f) => '${f.role} ${f.date}').join('; ')}');
    print('   infobox: ${a.infobox.take(6).map((r) => '${r.$1}=${r.$2.length > 40 ? r.$2.substring(0, 40) : r.$2}').join(' | ')}');
    print('   links ${a.links.length}: ${a.links.take(5).map((l) => '${l.target}(${l.role})').join(', ')}');
    print('   lead: ${a.lead.length > 200 ? a.lead.substring(0, 200) : a.lead}');
  }
}
