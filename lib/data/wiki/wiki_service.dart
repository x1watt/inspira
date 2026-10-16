import 'package:flutter/foundation.dart';

import 'wiki_service_stub.dart'
    if (dart.library.io) 'wiki_service_io.dart'
    as impl;

/// Where the offline Wikipedia database is hosted
/// (docs/plan-wiki-hosting.md, section 2a).
const wikiBaseUrl =
    'https://huggingface.co/datasets/maxbrito/inspira-wikipedia/resolve/main/';
const wikiFile = 'en_mini.zx';

enum WikiStatus {
  /// This platform can not keep the database (the web, for now).
  unsupported,
  absent,
  downloading,
  verifying,
  ready,
  failed,
}

/// A dated fact of Wikipedia on a calendar day (`day_fact`).
class WikiFact {
  const WikiFact({
    required this.title,
    required this.kind,
    required this.role,
    required this.year,
  });

  final String title;

  /// `person`, `event`, `place` or `other`.
  final String kind;

  /// `birth`, `death`, `point` (it happened), `start`, `end` and others.
  final String role;

  /// Negative is BC.
  final int? year;

  String get yearLabel {
    final y = year;
    if (y == null) return '';
    return y < 0 ? '${-y} BC' : '$y';
  }

  String get roleLabel => switch (role) {
    'birth' => 'Born',
    'death' => 'Died',
    'start' => 'Began',
    'end' => 'Ended',
    'point' => 'Happened',
    _ => '',
  };
}

/// The start of a Wikipedia article.
class WikiArticle {
  const WikiArticle({
    required this.title,
    required this.kind,
    required this.lead,
  });

  final String title;
  final String kind;
  final String lead;

  String get url =>
      'https://en.wikipedia.org/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}';
}

/// The offline English Wikipedia on Android and desktop: downloaded on
/// request (about 3.2 GB), checked against the SHA-256 of its manifest,
/// then queried in a worker isolate (docs/architecture.md, section 6).
abstract class WikiService extends ChangeNotifier {
  WikiStatus get status;

  /// Bytes on disk so far, and the size of the whole file (0 until known).
  int get downloaded;
  int get total;

  /// Bytes received from the network since the app started: what a
  /// download costs in data.
  int get received;

  /// The reason of [WikiStatus.failed].
  String? get error;

  Future<void> download();
  Future<void> cancel();
  Future<void> delete();

  /// Facts of the calendar day, the most linked articles first; empty
  /// when the database is not ready.
  Future<List<WikiFact>> onThisDay(int month, int day, {int limit = 30});

  Future<WikiArticle?> article(String title);
}

WikiService createWikiService() => impl.createWikiService();
