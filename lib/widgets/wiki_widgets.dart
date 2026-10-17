import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/wiki/wiki_service.dart';
import 'person_sheet.dart' show openLink;

/// Decimal units, as the size is announced ("about 3.5 GB").
String _size(int bytes) {
  if (bytes >= 1000000000) return '${(bytes / 1e9).toStringAsFixed(2)} GB';
  if (bytes >= 1000000) return '${(bytes / 1e6).toStringAsFixed(0)} MB';
  return '${(bytes / 1000).toStringAsFixed(0)} KB';
}

/// The offline Wikipedia in Me: download it (about 3.5 GB, once), see the
/// progress and the data it used, cancel or delete it.
class WikiDownloadCard extends StatelessWidget {
  const WikiDownloadCard({super.key, required this.wiki});

  final WikiService wiki;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: wiki,
      builder: (context, _) {
        final s = wiki.status;
        if (s == WikiStatus.unsupported) return const SizedBox.shrink();
        final total = wiki.total;
        final progress = total > 0 ? wiki.downloaded / total : null;
        final String subtitle = switch (s) {
          WikiStatus.ready =>
            'Ready, ${_size(wiki.downloaded)} on this device. More from '
                'Wikipedia shows in On this day, and its places on the map.',
          WikiStatus.downloading =>
            '${_size(wiki.downloaded)} of ${total > 0 ? _size(total) : 'about 3.5 GB'}',
          WikiStatus.verifying => 'Checking the file...',
          WikiStatus.failed => 'Failed: ${wiki.error}',
          _ when wiki.placesReady =>
            'New: the External links of the articles, as Wikipedia lists '
                'them, without leaving the app. About 280 MB more.',
          _ when wiki.articlesReady =>
            'New: about a million places for the map (castles, churches, '
                'museums, monuments, nature), each with its article, and the '
                'External links of the articles. About 320 MB more.',
          _ =>
            wiki.downloaded > 0
                ? 'Paused at ${_size(wiki.downloaded)}; it continues where it '
                      'stopped.'
                : 'English Wikipedia on this device, offline: about 3.5 GB, '
                      'downloaded once. Use Wi-Fi.',
        };
        return Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: const Text('Offline Wikipedia'),
                  subtitle: Text(subtitle),
                ),
                if (s == WikiStatus.downloading || s == WikiStatus.verifying)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: LinearProgressIndicator(
                      value: s == WikiStatus.verifying ? null : progress,
                    ),
                  ),
                if (wiki.received > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Data used since the app started: ${_size(wiki.received)}',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Wrap(
                    alignment: WrapAlignment.start,
                    spacing: 8,
                    children: [
                      if (s == WikiStatus.absent || s == WikiStatus.failed)
                        FilledButton.icon(
                          onPressed: wiki.download,
                          icon: const Icon(Icons.download_rounded),
                          label: Text(
                            wiki.articlesReady
                                ? 'Update'
                                : wiki.downloaded > 0
                                ? 'Continue'
                                : 'Download',
                          ),
                        ),
                      if (s == WikiStatus.downloading)
                        OutlinedButton(
                          onPressed: wiki.cancel,
                          child: const Text('Pause'),
                        ),
                      if (s == WikiStatus.ready || wiki.downloaded > 0)
                        TextButton(
                          onPressed:
                              s == WikiStatus.downloading ||
                                  s == WikiStatus.verifying
                              ? null
                              : wiki.delete,
                          child: const Text('Delete'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "More from Wikipedia" under the curated events of a day, when the
/// offline Wikipedia is on the device. The day's query runs once per day
/// shown (docs/performance.md, rule 12).
class WikiDaySection extends StatefulWidget {
  const WikiDaySection({
    super.key,
    required this.wiki,
    required this.month,
    required this.day,
  });

  final WikiService wiki;
  final int month;
  final int day;

  @override
  State<WikiDaySection> createState() => _WikiDaySectionState();
}

class _WikiDaySectionState extends State<WikiDaySection> {
  Future<List<WikiFact>>? _facts;
  String? _key;

  Future<List<WikiFact>> _factsOfDay() {
    final key = '${widget.month}-${widget.day}';
    if (_key != key || _facts == null) {
      _key = key;
      _facts = widget.wiki.onThisDay(widget.month, widget.day);
    }
    return _facts!;
  }

  @override
  Widget build(BuildContext context) {
    final wiki = widget.wiki;
    return ListenableBuilder(
      listenable: wiki,
      builder: (context, _) {
        if (!wiki.articlesReady) {
          _facts = null;
          return const SizedBox.shrink();
        }
        return FutureBuilder<List<WikiFact>>(
          future: _factsOfDay(),
          builder: (context, snap) {
            final facts = snap.data ?? const <WikiFact>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 12, 8, 4),
                  child: Text(
                    'More from Wikipedia',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                if (snap.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (facts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Nothing for this day.'),
                  ),
                for (final f in facts)
                  ListTile(
                    dense: true,
                    leading: Icon(switch (f.kind) {
                      'person' => Icons.person_outline,
                      'event' => Icons.event_outlined,
                      'place' => Icons.place_outlined,
                      _ => Icons.article_outlined,
                    }),
                    title: Text(f.title),
                    subtitle: Text(
                      [
                        f.yearLabel,
                        f.roleLabel,
                      ].where((s) => s.isNotEmpty).join(', '),
                    ),
                    onTap: () => showWikiArticle(context, wiki, f.title),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// The start of an article, from the offline Wikipedia.
Future<void> showWikiArticle(
  BuildContext context,
  WikiService wiki,
  String title,
) {
  // one query per sheet, not one per rebuild of the dragged sheet
  final article = wiki.article(title);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scroll) => FutureBuilder<WikiArticle?>(
        future: article,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final a = snap.data;
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(
                a?.title ?? title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              if (a == null)
                const Text(
                  'Not found in the offline Wikipedia.',
                  style: wikiBodyStyle,
                )
              else
                WikiArticleView(article: a, wiki: wiki),
              const SizedBox(height: 8),
              const Text(
                'Text from Wikipedia, CC BY-SA 4.0.',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          );
        },
      ),
    ),
  );
}

const wikiBodyStyle = TextStyle(color: Colors.white, fontSize: 16, height: 1.5);

/// An article of the offline Wikipedia as Wikipedia shows it, without
/// leaving the app: the lead, the articles it names linked (they open
/// here too), its external links, and the other articles it links to.
class WikiArticleView extends StatefulWidget {
  const WikiArticleView({super.key, required this.article, required this.wiki});

  final WikiArticle article;
  final WikiService wiki;

  @override
  State<WikiArticleView> createState() => _WikiArticleViewState();
}

class _WikiArticleViewState extends State<WikiArticleView> {
  final _taps = <TapGestureRecognizer>[];
  late List<List<InlineSpan>> _paragraphs;
  late List<String> _others;

  static const _link = TextStyle(color: Color(0xFF8AB4F8));
  static const _heading = TextStyle(
    color: Colors.white70,
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void didUpdateWidget(WikiArticleView old) {
    super.didUpdateWidget(old);
    if (old.article != widget.article) {
      _dispose();
      _build();
    }
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  void _dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
  }

  void _open(String title) => showWikiArticle(context, widget.wiki, title);

  /// Each related title's first mention in the lead becomes a link: the
  /// title itself, or without its "(district)" part.
  void _build() {
    final a = widget.article;
    final named = <String>{};
    _paragraphs = [
      for (final p in a.lead.split('\n'))
        if (p.trim().isNotEmpty) _spans(p.trim(), a.related, named),
    ];
    _others = [
      for (final t in a.related)
        if (!named.contains(t)) t,
    ];
  }

  List<InlineSpan> _spans(String text, List<String> titles, Set<String> named) {
    // (start, end, title) of the mentions, longest names first
    final found = <(int, int, String)>[];
    final names = [
      for (final t in titles)
        if (!named.contains(t)) (t.replaceFirst(RegExp(r' \(.*\)$'), ''), t),
    ]..sort((x, y) => y.$1.length - x.$1.length);
    for (final (name, title) in names) {
      if (name.length < 3) continue;
      for (final m in RegExp(
        '(?<![\\p{L}\\p{N}])${RegExp.escape(name)}(?![\\p{L}\\p{N}])',
        unicode: true,
      ).allMatches(text)) {
        if (found.any((f) => m.start < f.$2 && f.$1 < m.end)) continue;
        found.add((m.start, m.end, title));
        named.add(title);
        break;
      }
    }
    found.sort((x, y) => x.$1 - y.$1);
    final spans = <InlineSpan>[];
    var at = 0;
    for (final (start, end, title) in found) {
      if (start > at) spans.add(TextSpan(text: text.substring(at, start)));
      final tap = TapGestureRecognizer()..onTap = () => _open(title);
      _taps.add(tap);
      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: _link,
          recognizer: tap,
        ),
      );
      at = end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.article;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in _paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text.rich(TextSpan(children: p), style: wikiBodyStyle),
          ),
        if (a.links.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 2),
            child: Text('External links', style: _heading),
          ),
          for (final (url, label) in a.links)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.language_rounded, size: 20),
              title: Text(label.isEmpty ? url : label),
              subtitle: Text(
                Uri.tryParse(url)?.host ?? url,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () => openLink(context, url),
            ),
        ],
        if (_others.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 6),
            child: Text('Related', style: _heading),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in _others.take(16))
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(t),
                  onPressed: () => _open(t),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
