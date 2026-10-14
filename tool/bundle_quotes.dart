// Bundles quotes/<category>/*.json into assets/quotes.json and
// stories/<category>/*.json into assets/stories.json.
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

  if (errors.isNotEmpty) {
    stderr.writeln(errors.take(50).join('\n'));
    stderr.writeln('${errors.length} errors');
    exit(1);
  }
  File('assets/quotes.json').writeAsStringSync(jsonEncode(quotes));
  File('assets/stories.json').writeAsStringSync(jsonEncode(stories));
  stdout.writeln('Bundled ${quotes.length} quotes: ${_count(quotes)}');
  stdout.writeln('Bundled ${stories.length} stories: ${_count(stories)}');
}

Map<String, int> _count(List<Map<String, dynamic>> items) => {
      for (final c in categories)
        c: items.where((i) => i['category'] == c).length,
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
    final files = dir
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
