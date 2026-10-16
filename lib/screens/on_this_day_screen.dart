import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/event.dart';
import '../widgets/event_details.dart';
import '../widgets/wiki_widgets.dart';

/// Events in world history on one calendar day, most important first.
/// Opens on today; arrows and the calendar move to other days.
class OnThisDayScreen extends StatefulWidget {
  const OnThisDayScreen({
    super.key,
    this.month,
    this.day,
    this.highlight,
    this.now,
  });

  /// The day to show; today when null.
  final int? month;
  final int? day;

  /// Event id to scroll to and mark.
  final String? highlight;

  /// For tests.
  final DateTime Function()? now;

  @override
  State<OnThisDayScreen> createState() => _OnThisDayScreenState();
}

class _OnThisDayScreenState extends State<OnThisDayScreen> {
  // A leap year, so 29 February can be picked.
  static const _leap = 2024;

  late final DateTime _today = (widget.now ?? DateTime.now)();
  late DateTime _day = DateTime(
    _leap,
    widget.month ?? _today.month,
    widget.day ?? _today.day,
  );
  final _highlightKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.highlight != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _highlightKey.currentContext;
        if (c != null && c.mounted) {
          Scrollable.ensureVisible(
            c,
            duration: const Duration(milliseconds: 300),
          );
        }
      });
    }
  }

  void _move(int days) => setState(() {
    final d = _day.add(Duration(days: days));
    // Stay inside the same leap year when wrapping around New Year.
    _day = DateTime(_leap, d.month, d.day);
  });

  /// The calendar shows this year, so weekdays look right; 29 February
  /// stays reachable with the arrows in a common year.
  Future<void> _pick() async {
    final year = _today.year;
    var initial = DateTime(year, _day.month, _day.day);
    if (initial.month != _day.month) initial = DateTime(year, 2, 28);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(year),
      lastDate: DateTime(year, 12, 31),
      helpText: 'Pick a day of the year',
    );
    if (picked != null) {
      setState(() => _day = DateTime(_leap, picked.month, picked.day));
    }
  }

  /// The closest day after [_day] that has events, for an empty day.
  DateTime? _nextWithEvents() {
    final events = AppScope.of(context).events;
    for (var i = 1; i <= 366; i++) {
      final d = _day.add(Duration(days: i));
      if (events.onDay(d.month, d.day).isNotEmpty) {
        return DateTime(_leap, d.month, d.day);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final events = scope.events.onDay(_day.month, _day.day);
    final isToday = _day.month == _today.month && _day.day == _today.day;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('On this day')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous day',
                      onPressed: () => _move(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _pick,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text(
                          isToday
                              ? 'Today, ${HistoryEvent.dayLabel(_day.month, _day.day)}'
                              : HistoryEvent.dayLabel(_day.month, _day.day),
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next day',
                      onPressed: () => _move(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: events.isEmpty && scope.wiki == null
                    ? _empty(context)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                        // the events, then More from Wikipedia (offline)
                        itemCount: events.length + 1,
                        itemBuilder: (context, i) {
                          if (i == events.length) {
                            return Column(
                              children: [
                                if (events.isEmpty) _empty(context),
                                if (scope.wiki case final w?)
                                  WikiDaySection(
                                    wiki: w,
                                    month: _day.month,
                                    day: _day.day,
                                  ),
                              ],
                            );
                          }
                          final e = events[i];
                          final marked = e.id == widget.highlight;
                          final art = scope.images.artForEvent(e);
                          return Card(
                            key: marked ? _highlightKey : ValueKey(e.id),
                            color: const Color(0xFF141414),
                            clipBehavior: Clip.antiAlias,
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: marked
                                  ? const BorderSide(
                                      color: Colors.amber,
                                      width: 1.5,
                                    )
                                  : BorderSide.none,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (art != null)
                                  Image.asset(
                                    art.asset,
                                    height: 120,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const SizedBox.shrink(),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    14,
                                    16,
                                    8,
                                  ),
                                  child: EventDetails(
                                    event: e,
                                    nowYear: _today.year,
                                  ),
                                ),
                                if (art != null && art.credit.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      12,
                                    ),
                                    child: Text(
                                      'Image: ${art.credit}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final next = _nextWithEvents();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No events for this day in the collection yet.',
              textAlign: TextAlign.center,
            ),
            if (next != null) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => setState(() => _day = next),
                child: Text(
                  'Go to ${HistoryEvent.dayLabel(next.month, next.day)}',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
