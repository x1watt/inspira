import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zx/zx.dart' show ZxDatabaseAsync;

import 'wiki_service.dart';

/// Android and desktop: the database is a file in the app's support
/// folder. The download (and its SHA-256) runs in a background isolate,
/// resumes a partial file, and the file is used only once its SHA-256
/// matches the manifest; queries run in zx's worker isolate.
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
  Future<ZxDatabaseAsync>? _db;

  @override
  WikiStatus get status => _status;
  @override
  int get downloaded => _downloaded;
  @override
  int get total => _total;
  @override
  int get received => _received;
  @override
  String? get error => _error;

  File get _file => File('${_dir!.path}/$wikiFile');
  File get _part => File('${_dir!.path}/$wikiFile.part');
  File get _ok => File('${_dir!.path}/$wikiFile.ok');

  Future<void> _init() async {
    final base = await getApplicationSupportDirectory();
    _dir = Directory('${base.path}/wikipedia')..createSync(recursive: true);
    if (_file.existsSync() && _ok.existsSync()) {
      _status = WikiStatus.ready;
      _downloaded = _total = _file.lengthSync();
    } else if (_part.existsSync()) {
      _downloaded = _part.lengthSync();
    }
    notifyListeners();
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
      '$wikiBaseUrl$wikiFile',
      _dir!.path,
    ), errorsAreFatal: true);
    port.listen((m) {
      final msg = m as Map<String, Object?>;
      if (msg['total'] case final int t) _total = t;
      if (msg['downloaded'] case final int d) _downloaded = d;
      if (msg['received'] case final int r) _received += r;
      if (msg['verifying'] == true) _status = WikiStatus.verifying;
      if (msg['downloading'] == true) _status = WikiStatus.downloading;
      if (msg['done'] == true) {
        _status = WikiStatus.ready;
        _stopWorker();
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
    if (_part.existsSync()) _downloaded = _part.lengthSync();
    notifyListeners();
  }

  @override
  Future<void> delete() async {
    await cancel();
    final db = _db;
    _db = null;
    if (db != null) await (await db).close();
    for (final f in [_file, _part, _ok]) {
      if (f.existsSync()) f.deleteSync();
    }
    _status = WikiStatus.absent;
    _downloaded = 0;
    notifyListeners();
  }

  Future<ZxDatabaseAsync?> _open() {
    if (_status != WikiStatus.ready) return Future.value(null);
    return _db ??= ZxDatabaseAsync.open(_file.path, readOnly: true);
  }

  @override
  Future<List<WikiFact>> onThisDay(int month, int day, {int limit = 30}) async {
    final db = await _open();
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

  @override
  Future<WikiArticle?> article(String title) async {
    final db = await _open();
    if (db == null) return null;
    final r = await db.execute(
      'SELECT title, kind, lead FROM page WHERE title = ? COLLATE NOCASE '
      'LIMIT 1',
      [title],
    );
    if (r.rows.isEmpty) return null;
    final row = r.rows.first;
    return WikiArticle(
      title: row[0] as String,
      kind: row[1] as String? ?? 'other',
      lead: row[2] as String? ?? '',
    );
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

/// The download, in its own isolate: the manifest (size and SHA-256),
/// the SHA-256 of a partial file already there, the rest of the file
/// with a Range request, then the check and the rename.
Future<void> _downloadWorker((SendPort, String, String) args) async {
  final (out, url, dir) = args;
  final part = File('$dir/$wikiFile.part');
  final c = HttpClient();
  try {
    final mres = await _get(c, '$url.parts', 0);
    if (mres.statusCode != 200) {
      throw HttpException('manifest: HTTP ${mres.statusCode}');
    }
    final manifest =
        jsonDecode(await mres.transform(utf8.decoder).join()) as Map;
    final size = manifest['size'] as int;
    final want = ((manifest['parts'] as List).first as Map)['sha256'] as String;
    out.send({'total': size});

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
    if (have < size) {
      final res = await _get(c, url, have);
      if (res.statusCode != (have > 0 ? 206 : 200)) {
        throw HttpException('download: HTTP ${res.statusCode}');
      }
      final raf = part.openSync(mode: FileMode.append);
      var done = have, last = DateTime.now(), sinceLast = 0;
      try {
        await for (final chunk in res) {
          raf.writeFromSync(chunk);
          hash.add(chunk);
          done += chunk.length;
          sinceLast += chunk.length;
          final now = DateTime.now();
          if (now.difference(last).inMilliseconds >= 250) {
            out.send({'downloaded': done, 'received': sinceLast});
            last = now;
            sinceLast = 0;
          }
        }
      } finally {
        raf.closeSync();
      }
      out.send({'downloaded': done, 'received': sinceLast});
      if (done != size) {
        throw HttpException('the download stopped at $done of $size bytes');
      }
    }
    out.send({'verifying': true});
    hash.close();
    final got = sink.value.toString();
    if (got != want) {
      part.deleteSync();
      throw const HttpException(
        'the file does not match its SHA-256; it was removed, try again',
      );
    }
    part.renameSync('$dir/$wikiFile');
    File('$dir/$wikiFile.ok').writeAsStringSync(got);
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
