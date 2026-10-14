// Bundles quotes/<category>/*.json into assets/quotes.json,
// stories/<category>/*.json into assets/stories.json and
// events/<month>/*.json into assets/events.json.
//
// Run from the project root after adding or editing quotes or stories:
//   dart run tool/bundle_quotes.dart
//
// The app loads one asset per collection instead of thousands of small
// files (docs/performance.md, rule 2). Exits non-zero on invalid files.
import 'dart:convert';
import 'dart:io';

const categories = ['relations', 'leadership', 'team', 'family', 'strategy'];
const storyRequired = [
  'id',
  'category',
  'kind',
  'title',
  'text',
  'lesson',
  'source',
  'basis',
];
const storyKinds = {
  'story': {'fable', 'parable', 'folktale', 'literature'},
  'history': {'documented', 'anecdote', 'legend'},
  'study': {'study'},
};
const eventTags = {
  'war',
  'politics',
  'revolution',
  'law',
  'diplomacy',
  'science',
  'technology',
  'exploration',
  'medicine',
  'religion',
  'culture',
  'economy',
  'disaster',
  'sport',
  'rights',
};
const required = [
  'id',
  'category',
  'text',
  'author',
  'reference',
  'date',
  'location',
  'confidence',
];

void main() {
  final errors = <String>[];
  final quotes = _read('quotes', required, errors, (path, q) {
    if (q['confidence'] != 'verified' && q['confidence'] != 'attributed') {
      errors.add('$path: bad confidence ${q['confidence']}');
    }
    if ('${q['id']}'.startsWith('story-')) {
      errors.add('$path: quote ids must not start with story-');
    }
  });
  final stories = _read('stories', storyRequired, errors, (path, s) {
    final bases = storyKinds[s['kind']];
    if (bases == null) {
      errors.add('$path: bad kind ${s['kind']}');
    } else if (!bases.contains(s['basis'])) {
      errors.add('$path: basis ${s['basis']} does not fit kind ${s['kind']}');
    }
    if (!'${s['id']}'.startsWith('story-')) {
      errors.add('$path: story ids must start with story-');
    }
  });

  final events = _readEvents(errors);

  if (errors.isNotEmpty) {
    stderr.writeln(errors.take(50).join('\n'));
    stderr.writeln('${errors.length} errors');
    exit(1);
  }
  File('assets/quotes.json').writeAsStringSync(jsonEncode(quotes));
  File('assets/stories.json').writeAsStringSync(jsonEncode(stories));
  File('assets/events.json').writeAsStringSync(jsonEncode(events));
  stdout.writeln('Bundled ${quotes.length} quotes: ${_count(quotes)}');
  stdout.writeln('Bundled ${stories.length} stories: ${_count(stories)}');
  stdout.writeln('Bundled ${events.length} events');
}

/// Reads `events/<mm>/*.json` (folder = month), checks every field and
/// returns them in date order.
List<Map<String, dynamic>> _readEvents(List<String> errors) {
  final items = <Map<String, dynamic>>[];
  final ids = <String>{};
  final root = Directory('events');
  if (!root.existsSync()) return items;
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final Map<String, dynamic> e;
    try {
      e = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } on FormatException catch (x) {
      errors.add('${f.path}: $x');
      continue;
    }
    void bad(String why) => errors.add('${f.path}: $why');
    for (final k in [
      'id',
      'title',
      'summary',
      'reason',
      'place',
      'wikipedia',
    ]) {
      if (e[k] is! String || (e[k] as String).isEmpty) bad('missing $k');
    }
    if (!'${e['id']}'.startsWith('event-')) bad('ids must start with event-');
    if (!ids.add('${e['id']}')) bad('duplicate id');
    final y = e['year'], m = e['month'], d = e['day'];
    if (y is! int || y == 0) bad('bad year');
    if (m is! int || m < 1 || m > 12) bad('bad month');
    if (d is! int || d < 1 || d > 31) bad('bad day');
    final folder = f.parent.path.split(Platform.pathSeparator).last;
    if (m is int && folder != m.toString().padLeft(2, '0')) {
      bad('month $m != folder $folder');
    }
    if (e['calendar'] != 'gregorian' && e['calendar'] != 'julian') {
      bad('bad calendar');
    }
    final w = e['weight'];
    if (w is! int || w < 1 || w > 100) bad('bad weight');
    final lat = e['lat'], lon = e['lon'];
    if ((lat == null) != (lon == null)) bad('lat and lon go together');
    if (lat != null && (lat is! num || lat.abs() > 90)) bad('bad lat');
    if (lon != null && (lon is! num || lon.abs() > 180)) bad('bad lon');
    final tags = e['tags'];
    if (tags is! List || tags.isEmpty || !tags.every(eventTags.contains)) {
      bad('bad tags $tags');
    }
    for (final k in ['participants', 'countries']) {
      if (e[k] is! List) bad('$k must be a list');
    }
    items.add(e);
  }
  int key(Map<String, dynamic> e) =>
      ((e['year'] as int? ?? 0) * 10000) +
      ((e['month'] as int? ?? 0) * 100) +
      (e['day'] as int? ?? 0);
  items.sort((a, b) => key(a).compareTo(key(b)));
  return items;
}

Map<String, int> _count(List<Map<String, dynamic>> items) => {
  for (final c in categories) c: items.where((i) => i['category'] == c).length,
};

/// Reads `<folder>/<category>/*.json`, checks the common rules and
/// [check], and returns the items oldest first.
List<Map<String, dynamic>> _read(
  String folder,
  List<String> requiredFields,
  List<String> errors,
  void Function(String path, Map<String, dynamic> item) check,
) {
  final items = <Map<String, dynamic>>[];
  final ids = <String>{};
  for (final category in categories) {
    final dir = Directory('$folder/$category');
    if (!dir.existsSync()) continue;
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final Map<String, dynamic> q;
      try {
        q = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      } on FormatException catch (e) {
        errors.add('${f.path}: $e');
        continue;
      }
      for (final k in requiredFields) {
        if (q[k] is! String || (q[k] as String).isEmpty) {
          errors.add('${f.path}: missing $k');
        }
      }
      if (q['category'] != category) {
        errors.add('${f.path}: category ${q['category']} != folder $category');
      }
      if (!ids.add('${q['id']}')) errors.add('${f.path}: duplicate id');
      check(f.path, q);
      items.add(q);
    }
  }

  // Oldest first, so lists read as a walk through history.
  items.sort((a, b) {
    final y = ((a['year'] as int?) ?? 0).compareTo((b['year'] as int?) ?? 0);
    return y != 0 ? y : (a['id'] as String).compareTo(b['id'] as String);
  });
  return items;
}
