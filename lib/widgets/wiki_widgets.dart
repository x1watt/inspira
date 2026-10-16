import 'package:flutter/material.dart';

import '../data/wiki/wiki_service.dart';
import 'person_sheet.dart' show openLink;

/// Decimal units, as the size is announced ("about 3.2 GB").
String _size(int bytes) {
  if (bytes >= 1000000000) return '${(bytes / 1e9).toStringAsFixed(2)} GB';
  if (bytes >= 1000000) return '${(bytes / 1e6).toStringAsFixed(0)} MB';
  return '${(bytes / 1000).toStringAsFixed(0)} KB';
}

/// The offline Wikipedia in Me: download it (about 3.2 GB, once), see the
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
                'Wikipedia shows in On this day.',
          WikiStatus.downloading =>
            '${_size(wiki.downloaded)} of ${total > 0 ? _size(total) : 'about 3.2 GB'}',
          WikiStatus.verifying => 'Checking the file...',
          WikiStatus.failed => 'Failed: ${wiki.error}',
          _ =>
            wiki.downloaded > 0
                ? 'Paused at ${_size(wiki.downloaded)}; it continues where it '
                      'stopped.'
                : 'English Wikipedia on this device, offline: about 3.2 GB, '
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
                            wiki.downloaded > 0 ? 'Continue' : 'Download',
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
        if (wiki.status != WikiStatus.ready) {
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
              for (final p
                  in (a?.lead ?? 'Not found in the offline Wikipedia.').split(
                    '\n',
                  ))
                if (p.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      p.trim(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ),
              if (a != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => openLink(context, a.url),
                    icon: const Icon(Icons.menu_book_rounded),
                    label: const Text('Read on Wikipedia'),
                  ),
                ),
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
