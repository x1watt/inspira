import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zx/zx.dart' show ZxDatabaseAsync;

import '../wiki_place_repository.dart';
import 'tiles.dart';
import 'wiki_service.dart';

/// Android and desktop: the databases are files in the app's support
/// folder. The download (and the SHA-256s) runs in a background isolate,
/// one file after the other, resumes a partial file, and a file is used
/// only once its SHA-256 matches its manifest; queries run in zx's worker
/// isolates.
class _NativeWiki extends WikiService {
  _NativeWiki() {
    _init();
  }

  WikiStatus _status = WikiStatus.absent;
  int _downloaded = 0, _total = 0, _received = 0;
  String? _error;
  Directory? _dir;
  Isolate? _worker;
  ReceivePort? _port;
  final _db = <String, Future<ZxDatabaseAsync>>{};
  final _ready = <String>{};

  @override
  WikiStatus get status => _status;
  @override
  bool get articlesReady => _ready.contains(wikiFile);
  @override
  bool get placesReady => _ready.contains(wikiPlacesFile);
  @override
  int get downloaded => _downloaded;
  @override
  int get total => _total;
  @override
  int get received => _received;
  @override
  String? get error => _error;

  File _file(String name) => File('${_dir!.path}/$name');
  File _part(String name) => File('${_dir!.path}/$name.part');
  File _ok(String name) => File('${_dir!.path}/$name.ok');

  Future<void> _init() async {
    final base = await getApplicationSupportDirectory();
    _dir = Directory('${base.path}/wikipedia')..createSync(recursive: true);
    _scan();
    notifyListeners();
  }

  /// What is on disk: the files that are checked, and the bytes so far.
  void _scan() {
    _ready.clear();
    _downloaded = 0;
    for (final name in wikiFiles) {
      if (_file(name).existsSync() && _ok(name).existsSync()) {
        _ready.add(name);
        _downloaded += _file(name).lengthSync();
      } else if (_part(name).existsSync()) {
        _downloaded += _part(name).lengthSync();
      }
    }
    if (_ready.length == wikiFiles.length) {
      _status = WikiStatus.ready;
      _total = _downloaded;
    } else if (_status == WikiStatus.ready) {
      _status = WikiStatus.absent;
    }
  }

  @override
  Future<void> download() async {
    if (_status == WikiStatus.downloading ||
        _status == WikiStatus.verifying ||
        _status == WikiStatus.ready) {
      return;
    }
    if (_dir == null) await _init();
    _status = WikiStatus.downloading;
    _error = null;
    notifyListeners();
    final port = _port = ReceivePort();
    _worker = await Isolate.spawn(_downloadWorker, (
      port.sendPort,
      wikiBaseUrl,
      [
        for (final f in wikiFiles)
          if (!_ready.contains(f)) f,
      ],
      _dir!.path,
    ), errorsAreFatal: true);
    port.listen((m) {
      final msg = m as Map<String, Object?>;
      if (msg['total'] case final int t) _total = t;
      if (msg['downloaded'] case final int d) _downloaded = d;
      if (msg['received'] case final int r) _received += r;
      if (msg['verifying'] == true) _status = WikiStatus.verifying;
      if (msg['downloading'] == true) _status = WikiStatus.downloading;
      if (msg['file'] case final String f) _ready.add(f);
      if (msg['done'] == true) {
        _stopWorker();
        _scan();
      }
      if (msg['error'] case final String e) {
        _status = WikiStatus.failed;
        _error = e;
        _stopWorker();
      }
      notifyListeners();
    });
  }

  void _stopWorker() {
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _port?.close();
    _port = null;
  }

  @override
  Future<void> cancel() async {
    if (_worker == null) return;
    _stopWorker();
    _status = WikiStatus.absent;
    _scan();
    notifyListeners();
  }

  @override
  Future<void> delete() async {
    await cancel();
    final open = _db.values.toList();
    _db.clear();
    for (final db in open) {
      await (await db).close();
    }
    for (final name in wikiFiles) {
      for (final f in [_file(name), _part(name), _ok(name)]) {
        if (f.existsSync()) f.deleteSync();
      }
    }
    _status = WikiStatus.absent;
    _scan();
    notifyListeners();
  }

  Future<ZxDatabaseAsync?> _open(String name) {
    if (!_ready.contains(name)) return Future.value(null);
    return _db[name] ??= ZxDatabaseAsync.open(_file(name).path, readOnly: true);
  }

  @override
  Future<List<WikiFact>> onThisDay(int month, int day, {int limit = 30}) async {
    final db = await _open(wikiFile);
    if (db == null) return const [];
    // day_fact keys: (month * 32 + day) << 47, most linked first
    // (docs/plan-offline-wikipedia.md)
    final from = (month * 32 + day) << 47, to = (month * 32 + day + 1) << 47;
    // people (born, died), events, and anything that happened on the
    // day; not clubs, series or companies that merely began or ended
    final r = await db.execute(
      'SELECT title, kind, role, year FROM day_fact '
      'WHERE id >= ? AND id < ? '
      "AND (kind = 'person' OR kind = 'event' OR role = 'point') LIMIT ?",
      [from, to, limit],
    );
    return [
      for (final row in r.rows)
        WikiFact(
          title: row[0] as String,
          kind: row[1] as String? ?? 'other',
          role: row[2] as String? ?? '',
          year: row[3] as int?,
        ),
    ];
  }

  WikiArticle? _article(List<List<Object?>> rows) {
    if (rows.isEmpty) return null;
    final row = rows.first;
    return WikiArticle(
      title: row[0] as String,
      kind: row[1] as String? ?? 'other',
      lead: row[2] as String? ?? '',
    );
  }

  @override
  Future<WikiArticle?> article(String title) async {
    final db = await _open(wikiFile);
    if (db != null) {
      final r = await db.execute(
        'SELECT title, kind, lead FROM page WHERE title = ? COLLATE NOCASE '
        'LIMIT 1',
        [title],
      );
      if (_article(r.rows) case final a?) return a;
    }
    // the articles en_mini.zx lacks, kept in the places file
    final places = await _open(wikiPlacesFile);
    if (places == null) return null;
    final r = await places.execute(
      'SELECT title, kind, lead FROM article WHERE title = ? COLLATE NOCASE '
      'LIMIT 1',
      [title],
    );
    return _article(r.rows);
  }

  @override
  Future<WikiArticle?> placeArticle(WikiPlace place) async {
    final page = place.page;
    if (page == null) return article(place.title);
    final db = await _open(page > 0 ? wikiFile : wikiPlacesFile);
    if (db == null) return null;
    final r = await db.execute(
      'SELECT title, kind, lead FROM ${page > 0 ? 'page' : 'article'} '
      'WHERE id = ?',
      [page.abs()],
    );
    return _article(r.rows);
  }

  @override
  Future<List<WikiPlace>> placesIn(
    List<int> cells, {
    int? perCell,
    String? cat,
  }) async {
    final db = await _open(wikiPlacesFile);
    if (db == null || cells.isEmpty) return const [];
    // A tile is a range of keys, its best known first: the first few
    // keys of each tile, or one range per tile. (zx reads a key list or
    // a UNION ALL of ranges through the index; an OR of ranges is a full
    // scan of the table.)
    const cols =
        'SELECT title, cat, year, lat, lon, score, approx, page '
        'FROM place';
    final String sql;
    final List<Object> keys;
    if (cat == null && perCell != null && perCell <= 16) {
      keys = [
        for (final c in cells)
          for (var n = 0; n < perCell; n++) firstKey(c) + n,
      ];
      sql = '$cols WHERE id IN (${List.filled(keys.length, '?').join(',')})';
    } else {
      final ranges = cat == null && perCell != null
          ? [for (final c in cells) (firstKey(c), firstKey(c) + perCell)]
          : keyRanges(cells);
      keys = [
        for (final (from, to) in ranges) ...[from, to, ?cat],
      ];
      final where = cat == null
          ? 'id >= ? AND id < ?'
          : 'id >= ? AND id < ? AND cat = ?';
      sql = [for (final _ in ranges) '$cols WHERE $where'].join(' UNION ALL ');
    }
    final r = await db.execute(sql, keys);
    return [
      for (final row in r.rows)
        WikiPlace(
          title: row[0] as String,
          cat: row[1] as String,
          year: row[2] as int?,
          lat: (row[3] as num).toDouble(),
          lon: (row[4] as num).toDouble(),
          links: row[5] as int,
          approximate: row[6] == 1,
          page: row[7] as int?,
        ),
    ];
  }
}

WikiService createWikiService() => _NativeWiki();

/// Follows redirects by hand, so the Range header goes to the final URL.
Future<HttpClientResponse> _get(HttpClient c, String url, int from) async {
  var u = Uri.parse(url);
  for (var hops = 0; hops < 5; hops++) {
    final req = await c.getUrl(u);
    req.followRedirects = false;
    req.headers.set(
      HttpHeaders.userAgentHeader,
      'Inspira (https://github.com/x1watt/inspira)',
    );
    if (from > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-');
    final res = await req.close();
    if (res.isRedirect) {
      final loc = res.headers.value(HttpHeaders.locationHeader);
      await res.drain<void>();
      if (loc == null) break;
      u = u.resolve(loc);
      continue;
    }
    return res;
  }
  throw const HttpException('too many redirects');
}

/// The download, in its own isolate: the manifests (size and SHA-256 of
/// each file), then for each file the SHA-256 of a partial file already
/// there, the rest of it with a Range request, the check and the rename.
/// Progress counts the bytes of all files, the ones already checked too.
Future<void> _downloadWorker(
  (SendPort, String, List<String>, String) args,
) async {
  final (out, base, files, dir) = args;
  final c = HttpClient();
  try {
    final sizes = <String, int>{}, sums = <String, String>{};
    for (final name in files) {
      final mres = await _get(c, '$base$name.parts', 0);
      if (mres.statusCode != 200) {
        throw HttpException('$name manifest: HTTP ${mres.statusCode}');
      }
      final manifest =
          jsonDecode(await mres.transform(utf8.decoder).join()) as Map;
      sizes[name] = manifest['size'] as int;
      sums[name] =
          ((manifest['parts'] as List).first as Map)['sha256'] as String;
    }
    // the files already checked, which this download leaves alone
    var done = 0;
    for (final name in wikiFiles) {
      if (files.contains(name)) continue;
      final f = File('$dir/$name');
      if (f.existsSync()) done += f.lengthSync();
    }
    out.send({'total': done + sizes.values.fold<int>(0, (a, b) => a + b)});

    for (final name in files) {
      final size = sizes[name]!;
      final part = File('$dir/$name.part');
      final sink = _DigestSink();
      final hash = sha256.startChunkedConversion(sink);
      var have = part.existsSync() ? part.lengthSync() : 0;
      if (have > size) {
        part.deleteSync();
        have = 0;
      }
      if (have > 0) {
        out.send({'verifying': true});
        await for (final chunk in part.openRead()) {
          hash.add(chunk);
        }
        out.send({'downloading': true});
      }
      var got = have;
      if (have < size) {
        final res = await _get(c, '$base$name', have);
        if (res.statusCode != (have > 0 ? 206 : 200)) {
          throw HttpException('$name: HTTP ${res.statusCode}');
        }
        final raf = part.openSync(mode: FileMode.append);
        var last = DateTime.now(), sinceLast = 0;
        try {
          await for (final chunk in res) {
            raf.writeFromSync(chunk);
            hash.add(chunk);
            got += chunk.length;
            sinceLast += chunk.length;
            final now = DateTime.now();
            if (now.difference(last).inMilliseconds >= 250) {
              out.send({'downloaded': done + got, 'received': sinceLast});
              last = now;
              sinceLast = 0;
            }
          }
        } finally {
          raf.closeSync();
        }
        out.send({'downloaded': done + got, 'received': sinceLast});
        if (got != size) {
          throw HttpException('$name stopped at $got of $size bytes');
        }
      }
      out.send({'verifying': true});
      hash.close();
      final sum = sink.value.toString();
      if (sum != sums[name]) {
        part.deleteSync();
        throw HttpException(
          '$name does not match its SHA-256; it was removed, try again',
        );
      }
      part.renameSync('$dir/$name');
      File('$dir/$name.ok').writeAsStringSync(sum);
      done += size;
      out.send({'file': name, 'downloading': true});
    }
    out.send({'done': true});
  } catch (e) {
    out.send({'error': '$e'});
  } finally {
    c.close(force: true);
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
