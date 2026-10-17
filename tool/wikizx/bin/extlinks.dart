// Reads the English Wikipedia wikitext dump on stdin and writes, for every
// article, the links of its "External links" section, as Wikipedia shows
// them there:
//
//   title \t url \t label
//
// url is "wikidata" for {{Official website}} without a URL (Wikipedia
// takes it from Wikidata, P856). Templates of sister projects (Commons,
// Wikivoyage...) and authority controls are left out; 8 links at most.
//
//   curl -s https://dumps.wikimedia.org/enwiki/latest/enwiki-latest-pages-articles-multistream.xml.bz2 |
//     lbzip2 -dc | LC_ALL=C grep -E '^ *<title>|^ *<ns>|^=|^\*|^\{\{' |
//     dart run bin/extlinks.dart > extlinks.tsv
import 'dart:convert';
import 'dart:io';

final _heading = RegExp(r'^(=+)\s*(.*?)\s*=+\s*$');
final _bracket = RegExp(r'\[(https?://[^\s\]]+)(?:\s+([^\]]*))?\]');
final _official = RegExp(
  r'\{\{\s*(?:official website|official site|official|offsite)\s*(?:\|([^}]*))?\}\}',
  caseSensitive: false,
);

/// Wiki markup out of a label: links, bold and italics, templates.
String _plain(String s) => s
    .replaceAllMapped(
      RegExp(r'\[\[(?:[^\]|]*\|)?([^\]]*)\]\]'),
      (m) => m[1]!,
    )
    .replaceAll(RegExp(r"'{2,}"), '')
    .replaceAll(RegExp(r'\{\{[^}]*\}\}'), '')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// XML escapes of the dump's text.
String _xml(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&amp;', '&');

Future<void> main() async {
  final out = IOSink(stdout);
  String? title;
  var article = false, inLinks = false, n = 0, pages = 0;
  await for (final raw in stdin
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())) {
    final t = raw.trimLeft();
    if (t.startsWith('<title>')) {
      title = _xml(t.substring(7, t.indexOf('</title>')));
      article = false;
      inLinks = false;
      n = 0;
      continue;
    }
    if (t.startsWith('<ns>')) {
      article = t.startsWith('<ns>0<');
      continue;
    }
    if (!article) continue;
    // the text's first line starts with <text ...>; others are plain
    final line = _xml(raw);
    final h = _heading.firstMatch(line);
    if (h != null) {
      if (h[1]!.length == 2) {
        inLinks = h[2]!.toLowerCase() == 'external links';
        if (inLinks) pages++;
      }
      continue;
    }
    if (!inLinks || n >= 8) continue;
    if (!line.startsWith('*') && !line.startsWith('{{')) continue;
    final o = _official.firstMatch(line);
    if (o != null) {
      var url = (o[1] ?? '').split('|').first.trim();
      if (url.startsWith('url=') || url.startsWith('URL=')) {
        url = url.substring(4).trim();
      }
      if (url.isNotEmpty && !url.contains('://')) url = 'http://$url';
      if (url.isEmpty || url.contains('=') && !url.contains('://')) {
        url = 'wikidata';
      }
      out.writeln('$title\t$url\tOfficial website');
      n++;
      continue;
    }
    final b = _bracket.firstMatch(line);
    if (b == null || !line.startsWith('*')) continue;
    final url = b[1]!;
    var label = _plain(b[2] ?? '');
    // text after the link: "* [url Name], a description"
    final rest = _plain(line.substring(b.end));
    if (label.isEmpty) label = Uri.tryParse(url)?.host ?? url;
    final note = rest.replaceFirst(RegExp(r'^[-,:;.\s]+'), '');
    if (note.length > 2 && note.length < 80) label = '$label, $note';
    if (url.contains('\t') || label.contains('\t')) continue;
    out.writeln('$title\t$url\t$label');
    n++;
  }
  await out.flush();
  stderr.writeln('$pages articles with External links');
}
