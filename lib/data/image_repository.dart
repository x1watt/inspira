import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/event.dart';
import '../models/quote.dart';
import '../models/story.dart';
import 'stable_hash.dart';

const imagesManifest = 'assets/images.json';
const _imagesDir = 'assets/images/';

/// A public domain artwork bundled with the app.
class ArtImage {
  const ArtImage({
    required this.asset,
    required this.title,
    required this.artist,
    required this.year,
    required this.url,
  });

  factory ArtImage.fromJson(Map<String, dynamic> j) => ArtImage(
    asset: '$_imagesDir${j['file']}',
    title: j['title'] as String? ?? '',
    artist: j['artist'] as String? ?? '',
    year: j['year'] as String? ?? '',
    url: j['url'] as String? ?? '',
  );

  final String asset;
  final String title;
  final String artist;
  final String year;

  /// Wikimedia Commons file page.
  final String url;

  String get credit => [
    if (title.isNotEmpty) title,
    if (artist.isNotEmpty) artist,
    if (year.isNotEmpty) year,
  ].join(', ');
}

/// Portraits, Wikipedia links and background art from `assets/images.json` (written by
/// `tool/pipeline/images`). The manifest is small, so it is decoded on the
/// UI isolate; the pictures themselves load lazily through `Image.asset`.
class ImageRepository {
  ImageRepository(
    this._avatars,
    this._pools,
    this._storyArt, [
    this._wikipedia = const {},
  ]);

  ImageRepository.empty() : this({}, {}, {});

  factory ImageRepository.fromJson(Map<String, dynamic> j) {
    final pools = <String, List<ArtImage>>{};
    final storyArt = <String, ArtImage>{};
    for (final raw in j['art'] as List? ?? const []) {
      final m = raw as Map<String, dynamic>;
      final art = ArtImage.fromJson(m);
      for (final p in m['pools'] as List? ?? const []) {
        (pools[p as String] ??= []).add(art);
      }
      for (final id in m['stories'] as List? ?? const []) {
        storyArt[id as String] = art;
      }
    }
    return ImageRepository(
      {
        for (final e in (j['avatars'] as Map? ?? const {}).entries)
          e.key as String: '$_imagesDir${e.value}',
      },
      pools,
      storyArt,
      {
        for (final e in (j['wikipedia'] as Map? ?? const {}).entries)
          e.key as String: e.value as String,
      },
    );
  }

  static Future<ImageRepository> load(AssetBundle bundle) async =>
      ImageRepository.fromJson(
        jsonDecode(await bundle.loadString(imagesManifest))
            as Map<String, dynamic>,
      );

  final Map<String, String> _avatars;
  final Map<String, List<ArtImage>> _pools;
  final Map<String, ArtImage> _storyArt;
  final Map<String, String> _wikipedia;

  /// Every distinct artwork, for the credits list.
  List<ArtImage> get allArt =>
      {for (final p in _pools.values) ...p, ..._storyArt.values}.toList();

  /// Asset path of a portrait, or null.
  String? avatarFor(String? name) => name == null ? null : _avatars[name];

  /// English Wikipedia page of a person, or null.
  String? wikipediaFor(String? name) => name == null ? null : _wikipedia[name];

  ArtImage? artForQuote(Quote q) => _pick(q.category, q.id);

  /// The painting of the episode itself when there is one; fables and
  /// studies get their own pools, everything else the category pool.
  ArtImage? artForStory(Story s) {
    final own = _storyArt[s.id];
    if (own != null) return own;
    final pool = switch (s.kind) {
      StoryKind.study => 'study',
      StoryKind.story when s.basis != 'literature' => 'fable',
      _ => s.category,
    };
    return _pick(pool, s.id) ?? _pick(s.category, s.id);
  }

  /// Science and discovery events get the study pool, the rest the pool
  /// of their category.
  ArtImage? artForEvent(HistoryEvent e) {
    const studyTags = {'science', 'technology', 'exploration', 'medicine'};
    final pool = e.tags.any(studyTags.contains) ? 'study' : e.category;
    return _pick(pool, e.id) ?? _pick(e.category, e.id);
  }

  ArtImage? _pick(String pool, String id) {
    final list = _pools[pool];
    if (list == null || list.isEmpty) return null;
    return list[stableHash(id) % list.length];
  }
}
