// Reader for ZIM files (openzim.org, format version 6), enough to walk a
// Kiwix Wikipedia: header, MIME list, directory entries and clusters
// (zstd, xz or uncompressed, 32 or 64 bit blob offsets).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ignore: implementation_imports
import 'package:zx/src/codec/zstd/zstd.dart' show zstdDecompress;
import 'package:zx/zx.dart' show xzDecompress;

const zimMagic = 72173914;

class ZimEntry {
  ZimEntry(this.index, this.mime, this.namespace, this.path, this.title,
      this.cluster, this.blob, this.redirect);

  final int index;

  /// Index into [ZimFile.mimeTypes]; -1 for a redirect.
  final int mime;
  final String namespace;
  final String path;
  final String title;
  final int cluster;
  final int blob;

  /// Entry index of the target, for a redirect; else -1.
  final int redirect;

  bool get isRedirect => redirect >= 0;
}

class ZimFile {
  ZimFile._(this._f, this.length, this.entryCount, this.clusterCount,
      this.pathPtrPos, this.clusterPtrPos, this.mimeTypes, this.checksumPos,
      this.mainPage);

  static ZimFile open(String path) {
    final f = File(path).openSync();
    final h = _read(f, 0, 80);
    final bd = ByteData.sublistView(h);
    if (bd.getUint32(0, Endian.little) != zimMagic) {
      throw const FormatException('not a ZIM file');
    }
    final mimePos = bd.getUint64(56, Endian.little);
    final mimes = <String>[];
    var block = _read(f, mimePos, 4096);
    var p = 0;
    while (true) {
      var e = block.indexOf(0, p);
      while (e < 0) {
        block = _read(f, mimePos, block.length * 2);
        e = block.indexOf(0, p);
      }
      if (e == p) break;
      mimes.add(String.fromCharCodes(block, p, e));
      p = e + 1;
    }
    return ZimFile._(
      f,
      f.lengthSync(),
      bd.getUint32(24, Endian.little),
      bd.getUint32(28, Endian.little),
      bd.getUint64(32, Endian.little),
      bd.getUint64(48, Endian.little),
      mimes,
      bd.getUint64(72, Endian.little),
      bd.getUint32(64, Endian.little),
    );
  }

  final RandomAccessFile _f;
  final int length;
  final int entryCount;
  final int clusterCount;
  final int pathPtrPos;
  final int clusterPtrPos;
  final List<String> mimeTypes;
  final int checksumPos;
  final int mainPage;

  static Uint8List _read(RandomAccessFile f, int pos, int n) {
    f.setPositionSync(pos);
    return f.readSync(n);
  }

  Uint8List read(int pos, int n) => _read(_f, pos, n);

  /// Offsets of every directory entry, in path order.
  Int64List entryOffsets() {
    final b = read(pathPtrPos, entryCount * 8);
    final bd = ByteData.sublistView(b);
    final out = Int64List(entryCount);
    for (var i = 0; i < entryCount; i++) {
      out[i] = bd.getUint64(i * 8, Endian.little);
    }
    return out;
  }

  Int64List clusterOffsets() {
    final b = read(clusterPtrPos, clusterCount * 8);
    final out = Int64List(clusterCount + 1);
    final bd = ByteData.sublistView(b);
    for (var i = 0; i < clusterCount; i++) {
      out[i] = bd.getUint64(i * 8, Endian.little);
    }
    out[clusterCount] = checksumPos;
    return out;
  }

  /// Parses the entry at [buf] offset [p]; returns it and its length.
  static (ZimEntry, int) parseEntry(Uint8List buf, int p, int index) {
    final bd = ByteData.sublistView(buf);
    final mime = bd.getUint16(p, Endian.little);
    final paramLen = buf[p + 2];
    final ns = String.fromCharCode(buf[p + 3]);
    var q = p + 8;
    var cluster = -1, blob = -1, redirect = -1;
    if (mime == 0xffff) {
      redirect = bd.getUint32(q, Endian.little);
      q += 4;
    } else if (mime == 0xfffe || mime == 0xfffd) {
      // link target or deleted: no data
    } else {
      cluster = bd.getUint32(q, Endian.little);
      blob = bd.getUint32(q + 4, Endian.little);
      q += 8;
    }
    final pe = buf.indexOf(0, q);
    final path = _utf8(buf, q, pe);
    final te = buf.indexOf(0, pe + 1);
    final title = te == pe + 1 ? path : _utf8(buf, pe + 1, te);
    final end = te + 1 + paramLen;
    return (
      ZimEntry(index, mime >= 0xfffd ? -1 : mime, ns, path, title, cluster,
          blob, redirect),
      end - p
    );
  }

  static String _utf8(Uint8List b, int s, int e) {
    for (var i = s; i < e; i++) {
      if (b[i] >= 0x80) {
        return const Utf8Codec().decode(Uint8List.sublistView(b, s, e));
      }
    }
    return String.fromCharCodes(b, s, e);
  }

  ZimEntry entryAt(int index, Int64List offsets) {
    final buf = read(offsets[index], 4096);
    return parseEntry(buf, 0, index).$1;
  }

  /// Blobs of cluster [c] given the cluster offsets.
  List<Uint8List> cluster(int c, Int64List clusterOffsets) {
    final start = clusterOffsets[c];
    final raw = read(start, clusterOffsets[c + 1] - start);
    return parseCluster(raw);
  }

  static List<Uint8List> parseCluster(Uint8List raw) {
    final info = raw[0];
    final comp = info & 0x0f;
    final ext = (info & 0x10) != 0;
    final body = Uint8List.sublistView(raw, 1);
    final Uint8List data = switch (comp) {
      0 || 1 => body,
      4 => xzDecompress(body),
      5 => zstdDecompress(body),
      _ => throw FormatException('cluster compression $comp'),
    };
    final bd = ByteData.sublistView(data);
    final w = ext ? 8 : 4;
    int off(int i) => ext
        ? bd.getUint64(i * 8, Endian.little)
        : bd.getUint32(i * 4, Endian.little);
    final n = off(0) ~/ w - 1;
    return [
      for (var i = 0; i < n; i++)
        Uint8List.sublistView(data, off(i), off(i + 1)),
    ];
  }

  void close() => _f.closeSync();
}
