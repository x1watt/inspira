import 'package:flutter/material.dart';

import '../models/event.dart';
import '../screens/map_screen.dart';
import 'person_sheet.dart';

/// Opens the in-app map at [id] (an event or story with a place).
void showOnMap(BuildContext context, String id) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => MapScreen(focus: id)));

/// Everything known about an event: date, place, what, why, what it
/// changed, who; with links to Wikipedia and the map. White on dark, for
/// the feed panel, On this day and the map alike.
class EventDetails extends StatelessWidget {
  const EventDetails({
    super.key,
    required this.event,
    required this.nowYear,
    this.header,
    this.mapLink = true,
  });

  static const _body = TextStyle(
    color: Colors.white,
    fontSize: 16.5,
    height: 1.5,
  );
  static const _muted = TextStyle(color: Colors.white70, fontSize: 13);

  final HistoryEvent event;
  final int nowYear;

  /// Chips above the title.
  final Widget? header;

  /// False on the map itself.
  final bool mapLink;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final ago = e.yearsAgo(nowYear);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (header != null) ...[header!, const SizedBox(height: 12)],
        Text(
          e.title,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          [
            e.dateLabel,
            if (ago > 0) '$ago years ago',
            if (e.place.isNotEmpty) e.place,
          ].join(', '),
          style: _muted,
        ),
        const SizedBox(height: 12),
        Text(e.summary, style: _body),
        if (e.reason.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Why: ',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: e.reason),
              ],
            ),
            style: _body,
          ),
        ],
        if (e.significance.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.lightbulb, color: Colors.amber, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.significance,
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (e.participants.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Who: ${e.participants.join(', ')}', style: _muted),
        ],
        if (e.wikipediaUrl.isNotEmpty || (mapLink && e.hasPlace)) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              if (e.wikipediaUrl.isNotEmpty)
                TextButton.icon(
                  onPressed: () => openLink(context, e.wikipediaUrl),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Read on Wikipedia'),
                ),
              if (mapLink && e.hasPlace)
                TextButton.icon(
                  onPressed: () => showOnMap(context, e.id),
                  icon: const Icon(Icons.place_outlined, size: 16),
                  label: const Text('Show on the map'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
