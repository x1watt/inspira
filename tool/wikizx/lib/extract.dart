// Turns one Kiwix Wikipedia article (HTML) into the facts the database
// keeps: title, lead text, infobox rows, dates, coordinates, a kind and
// the links to other articles. Regular expressions over the HTML, no DOM:
// Kiwix pages are regular and this runs millions of times.

import 'dart:math';

/// A date with the precision it was given in. Negative years are BC;
/// there is no year 0.
class WikiDate {
  const WikiDate(this.year, [this.month = 0, this.day = 0]);

  final int year;

  /// 0 when unknown.
  final int month;
  final int day;

  String get precision => day > 0
      ? 'day'
      : month > 0
          ? 'month'
          : 'year';

  @override
  String toString() => '$year-$month-$day';
}

class Fact {
  const Fact(this.role, this.date);

  /// birth, death, start, end or point.
  final String role;
  final WikiDate date;
}

class LinkOut {
  const LinkOut(this.target, this.role);

  /// Article path (Kiwix: the title with underscores).
  final String target;

  /// body, or the infobox label it was found under (lowercase).
  final String role;
}

class Article {
  Article({
    required this.title,
    required this.lead,
    required this.kind,
    required this.infobox,
    required this.facts,
    required this.links,
    this.lat,
    this.lon,
  });

  final String title;
  final String lead;

  /// person, event, place, disambiguation or other.
  final String kind;
  final List<(String, String)> infobox;
  final List<Fact> facts;
  final List<LinkOut> links;
  final double? lat;
  final double? lon;
}

final _title = RegExp(r'<title>([^<]*)</title>');
final _style = RegExp(r'<style[\s\S]*?</style>|<script[\s\S]*?</script>');
final _infoboxStart = RegExp(r'<table class="(infobox[^"]*)"');
final _th = RegExp(r'<th\b[^>]*>([\s\S]*?)</th>');
final _tableTag = RegExp(r'<table\b|</table>');
final _para = RegExp(r'<p\b[^>]*>([\s\S]*?)</p>');
final _tag = RegExp(r'<[^>]+>');
final _ref = RegExp(r'\[\d+\]|\[[a-z]\]|\[citation needed\]');
final _ws = RegExp(r'\s+');
// The hidden "(2016-10-21)" that date templates add.
final _isoNote = RegExp(r'\(\s*-?\d{1,4}-\d\d(-\d\d)?\s*\)');
final _link = RegExp(r'<a rel="mw:WikiLink" href="([^"#]+)(?:#[^"]*)?"');
final _micro = RegExp(
  r'<span class="([^"]*\b(?:bday|dday|deathdate|dtstart|dtend)\b[^"]*)">(-?\d{1,4})(?:-(\d\d)(?:-(\d\d))?)?</span>',
);
final _geo = RegExp(r'<span class="geo">(-?[\d.]+); (-?[\d.]+)</span>');
final _geoDec = RegExp(
  r'<span class="geo-dec"[^>]*>([\d.]+)°([NS]) ([\d.]+)°([EW])</span>',
);

const _months = {
  'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5,
  'june': 6, 'july': 7, 'august': 8, 'september': 9, 'october': 10,
  'november': 11, 'december': 12,
};

String _entities(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&#160;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&ndash;', '-')
    .replaceAll('&mdash;', ', ')
    .replaceAll('–', '-')
    .replaceAll('—', ', ');

String plain(String html) => _entities(
      html.replaceAll(_tag, ' ').replaceAll(_ref, ''),
    ).replaceAll(_ws, ' ').replaceAll(' ,', ',').replaceAll(' .', '.').trim();

/// Parses "14 October 1066", "October 14, 1066", "October 1066", "1066",
/// "44 BC", "c. 500 BCE". The first date in [s], or null.
WikiDate? parseDate(String s) {
  final t = s.toLowerCase();
  final bc = RegExp(r'\b(bc|bce)\b').hasMatch(t);
  int sign(int y) => bc ? -y : y;
  var m = RegExp(r'\b(\d{1,2}) ([a-z]+),? (\d{1,4})\b').firstMatch(t);
  if (m != null && _months.containsKey(m[2])) {
    return WikiDate(sign(int.parse(m[3]!)), _months[m[2]]!, int.parse(m[1]!));
  }
  m = RegExp(r'\b([a-z]+) (\d{1,2}),? (\d{1,4})\b').firstMatch(t);
  if (m != null && _months.containsKey(m[1])) {
    return WikiDate(sign(int.parse(m[3]!)), _months[m[1]]!, int.parse(m[2]!));
  }
  m = RegExp(r'\b([a-z]+) (\d{3,4})\b').firstMatch(t);
  if (m != null && _months.containsKey(m[1])) {
    return WikiDate(sign(int.parse(m[2]!)), _months[m[1]]!);
  }
  m = RegExp(r'\b(\d{1,4})\s*(?:bc|bce|ad|ce)\b|\b(\d{3,4})\b').firstMatch(t);
  if (m != null) return WikiDate(sign(int.parse(m[1] ?? m[2]!)));
  return null;
}

const _eventLabels = {
  'location', 'result', 'belligerents', 'participants', 'casualties',
  'outcome', 'deaths', 'cause', 'territorial changes', 'type', 'parties',
  'signatories', 'commanders and leaders',
};
const _eventDateLabels = {'date', 'signed', 'date signed', 'effective'};
const _personLabels = {'born', 'died', 'spouse', 'spouses', 'children',
    'occupation', 'parents', 'resting place', 'reign', 'predecessor'};
const _placeLabels = {'country', 'population', 'area', 'elevation',
    'coordinates', 'region', 'state', 'municipality'};
const _workClasses = ['haudio', 'hproduct', 'album', 'single', 'film'];

Article extract(String html) {
  final title = _entities(_title.firstMatch(html)?.group(1) ?? '');
  final body = html.replaceAll(_style, '');

  // Infobox: the first one, up to its end.
  final infobox = <(String, String)>[];
  final links = <LinkOut>[];
  final facts = <Fact>[];
  var classes = '';
  var leadFrom = 0;
  final ib = _infoboxStart.firstMatch(body);
  if (ib != null) {
    classes = ib[1]!;
    // The matching </table>: military infoboxes nest tables.
    var depth = 0, end = body.length;
    for (final t in _tableTag.allMatches(body, ib.start)) {
      depth += t[0] == '</table>' ? -1 : 1;
      if (depth == 0) {
        end = t.end;
        break;
      }
    }
    final box = body.substring(ib.start, end);
    leadFrom = end;
    // Each header cell labels everything up to the next header cell:
    // "Born | 14 March 1879" rows and section headers such as
    // "Belligerents" followed by a row of data cells alike.
    final ths = _th.allMatches(box).toList();
    for (var k = 0; k < ths.length; k++) {
      final key = plain(ths[k][1]!).toLowerCase();
      final raw = box.substring(
          ths[k].end, k + 1 < ths.length ? ths[k + 1].start : box.length);
      final value = plain(raw.replaceAll('</li>', ';').replaceAll('<br>', '; '))
          .replaceAll(_isoNote, '')
          .replaceAll(RegExp(r'\s*;\s*$'), '')
          .replaceAll(' ;', ';');
      if (key.isEmpty || value.isEmpty || key.length > 40) continue;
      final partOf = raw.indexOf('Part of');
      final role = partOf >= 0 && k == 0 ? 'part of' : key;
      // "Part of the X" sits in the title cell's span with the picture and
      // its caption; keep only the cell that says it.
      final linkHtml = role == 'part of'
          ? raw.substring(partOf, max(partOf, raw.indexOf('</td>', partOf)))
          : raw;
      if (k > 0 || role == 'part of') {
        infobox.add((role, role == 'part of' ? plain(linkHtml) : value));
      }
      for (final l in _link.allMatches(linkHtml)) {
        links.add(LinkOut(Uri.decodeComponent(_cleanHref(l[1]!)), role));
      }
      final factRole = switch (key) {
        'born' => 'birth',
        'died' => 'death',
        'date' || 'date signed' || 'signed' => 'point',
        'founded' || 'established' || 'formed' || 'opened' => 'start',
        'dissolved' || 'abolished' || 'closed' => 'end',
        _ => null,
      };
      if (factRole != null && !facts.any((f) => f.role == factRole)) {
        // Microformat inside this row wins over the visible text.
        final mf = _micro.firstMatch(raw);
        final d = mf != null ? _microDate(mf) : parseDate(value);
        if (d != null) facts.add(Fact(factRole, d));
      }
    }
  }
  for (final mf in _micro.allMatches(body)) {
    final c = mf[1]!;
    final role = c.contains('bday')
        ? 'bday'
        : c.contains('dday') || c.contains('deathdate')
            ? 'death'
            : c.contains('dtstart')
                ? 'start'
                : 'end';
    if (!facts.any((f) => f.role == role)) facts.add(Fact(role, _microDate(mf)));
  }

  double? lat, lon;
  final g = _geo.firstMatch(body);
  if (g != null) {
    lat = double.tryParse(g[1]!);
    lon = double.tryParse(g[2]!);
  } else if (_geoDec.firstMatch(body) case final d?) {
    lat = double.parse(d[1]!) * (d[2] == 'S' ? -1 : 1);
    lon = double.parse(d[3]!) * (d[4] == 'W' ? -1 : 1);
  }

  // Lead: paragraphs after the infobox until the first heading.
  final h2 = body.indexOf('<h2', leadFrom);
  final leadHtml = body.substring(leadFrom, h2 < 0 ? body.length : h2);
  final paras = <String>[];
  for (final p in _para.allMatches(leadHtml)) {
    final t = plain(p[1]!);
    if (t.length > 20) paras.add(t);
    for (final l in _link.allMatches(p[1]!)) {
      links.add(LinkOut(Uri.decodeComponent(_cleanHref(l[1]!)), 'body'));
    }
  }
  final lead = paras.join('\n\n');

  final labels = {for (final r in infobox) r.$1};
  final isWork = _workClasses.any(classes.contains);
  final String kind;
  if (lead.endsWith('may refer to:') || lead.endsWith('may also refer to:')) {
    kind = 'disambiguation';
  } else if (labels.contains('born') ||
      labels.contains('died') ||
      labels.intersection(_personLabels).length >= 2) {
    kind = 'person';
  } else if (!isWork &&
      labels.intersection(_eventDateLabels).isNotEmpty &&
      labels.intersection(_eventLabels).isNotEmpty) {
    kind = 'event';
  } else if (lat != null || labels.intersection(_placeLabels).length >= 2) {
    kind = 'place';
  } else {
    kind = 'other';
  }
  // bday marks a birth on people and an opening or release elsewhere.
  for (var k = 0; k < facts.length; k++) {
    if (facts[k].role == 'bday') {
      final r = kind == 'person' ? 'birth' : 'start';
      facts[k] = facts.any((f) => f.role == r)
          ? const Fact('', WikiDate(0))
          : Fact(r, facts[k].date);
    }
  }
  facts.removeWhere((f) => f.role.isEmpty);
  // Typos in the source ("October 15, 182"): a death before the birth.
  final born = facts.where((f) => f.role == 'birth').firstOrNull;
  facts.removeWhere((f) =>
      f.role == 'death' && born != null && f.date.year < born.date.year);
  // A start on the same day as the point adds nothing.
  final point = facts.where((f) => f.role == 'point').firstOrNull;
  facts.removeWhere((f) =>
      f.role == 'start' &&
      point != null &&
      f.date.toString() == point.date.toString());
  if (kind == 'event' && !facts.any((f) => f.role == 'point' || f.role == 'start')) {
    // Events without an infobox date: the first date of the lead.
    final d = parseDate(paras.isEmpty ? '' : paras.first);
    if (d != null) facts.add(Fact('point', d));
  }
  return Article(
    title: title,
    lead: lead,
    kind: kind,
    infobox: infobox,
    facts: facts,
    links: links,
    lat: lat,
    lon: lon,
  );
}

String _cleanHref(String h) {
  var s = h;
  while (s.startsWith('./') || s.startsWith('../')) {
    s = s.substring(s.indexOf('/') + 1);
  }
  return s;
}

WikiDate _microDate(RegExpMatch m) => WikiDate(
      int.parse(m[2]!),
      m[3] == null ? 0 : int.parse(m[3]!),
      m[4] == null ? 0 : int.parse(m[4]!),
    );
