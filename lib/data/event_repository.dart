import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/event.dart';

const eventsAsset = 'assets/events.json';

/// Parses the bundled JSON array. Top level so it can run in an isolate.
List<HistoryEvent> parseEvents(String raw) => [
  for (final j in jsonDecode(raw) as List)
    HistoryEvent.fromJson(j as Map<String, dynamic>),
];

/// Dated world events, held in memory; decoded off the UI isolate
/// (docs/performance.md, rule 1).
class EventRepository {
  EventRepository(List<HistoryEvent> events)
    : events = List.unmodifiable(events),
      _byId = {for (final e in events) e.id: e},
      _byDay = _index(events);

  static Future<EventRepository> load(AssetBundle bundle) async {
    final raw = await bundle.loadString(eventsAsset);
    return EventRepository(await compute(parseEvents, raw));
  }

  final List<HistoryEvent> events;
  final Map<String, HistoryEvent> _byId;
  final Map<int, List<HistoryEvent>> _byDay;

  static Map<int, List<HistoryEvent>> _index(List<HistoryEvent> events) {
    final m = <int, List<HistoryEvent>>{};
    for (final e in events) {
      (m[e.month * 100 + e.day] ??= []).add(e);
    }
    for (final list in m.values) {
      list.sort((a, b) => b.weight.compareTo(a.weight));
    }
    return m;
  }

  HistoryEvent? byId(String id) => _byId[id];

  /// Events on this calendar day in any year, most important first.
  List<HistoryEvent> onDay(int month, int day) =>
      _byDay[month * 100 + day] ?? const [];
}
