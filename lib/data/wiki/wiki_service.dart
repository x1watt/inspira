import 'package:flutter/foundation.dart';

import '../wiki_place_repository.dart';

import 'wiki_service_stub.dart'
    if (dart.library.io) 'wiki_service_io.dart'
    as impl;

/// Where the offline Wikipedia database is hosted
/// (docs/plan-wiki-hosting.md, section 2a).
const wikiBaseUrl =
    'https://huggingface.co/datasets/maxbrito/inspira-wikipedia/resolve/main/';
const wikiFile = 'en_mini.zx';

/// The map's places: about a million articles with a point, by map tile
/// (tool/wikizx/bin/build_places.dart).
const wikiPlacesFile = 'en_places.zx';

/// Downloaded in this order; the database is ready when all are.
const wikiFiles = [wikiFile, wikiPlacesFile];

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
/// request (about 3.2 GB, [wikiFiles]), each file checked against the
/// SHA-256 of its manifest, then queried in worker isolates
/// (docs/architecture.md, sections 6 and 7).
abstract class WikiService extends ChangeNotifier {
  /// [WikiStatus.ready] when every file is on the device.
  WikiStatus get status;

  /// The articles (en_mini.zx) are on the device; they work before the
  /// places file is (an update that adds it).
  bool get articlesReady;

  /// The map's places (en_places.zx) are on the device.
  bool get placesReady;

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

  /// The lead of a place's article: by its page when it has one, else by
  /// title.
  Future<WikiArticle?> placeArticle(WikiPlace place);

  /// The places in the zoom 12 tiles [cells] (tiles.dart): the first
  /// [perCell] of each, best known first, or all of them; only those of
  /// the category [cat] when given (then all of them).
  Future<List<WikiPlace>> placesIn(
    List<int> cells, {
    int? perCell,
    String? cat,
  });
}

WikiService createWikiService() => impl.createWikiService();
