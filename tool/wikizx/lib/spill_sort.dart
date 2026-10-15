// Sorts more 64 bit keys than should sit in memory: keys are gathered in
// chunks, each chunk is sorted and written to a run file, and [sorted]
// merges the runs with a small read buffer per run.
import 'dart:io';
import 'dart:typed_data';

class SpillSorter {
  SpillSorter(this.dir, {this.chunk = 4 << 20}) {
    Directory(dir).createSync(recursive: true);
  }

  final String dir;

  /// Keys per run (32 MiB at the default).
  final int chunk;
  final _runs = <String>[];
  Int64List? _buf;
  int _n = 0;
  int length = 0;

  void add(int key) {
    final b = _buf ??= Int64List(chunk);
    b[_n++] = key;
    length++;
    if (_n == chunk) _spill();
  }

  void _spill() {
    final b = _buf;
    if (b == null || _n == 0) return;
    final part = Int64List.sublistView(b, 0, _n)..sort();
    final path = '$dir/run${_runs.length}.bin';
    File(path).writeAsBytesSync(
        Uint8List.view(part.buffer, part.offsetInBytes, _n * 8));
    _runs.add(path);
    _n = 0;
  }

  /// Every key added, in ascending order; deletes the run files when done.
  Iterable<int> sorted() sync* {
    _spill();
    _buf = null;
    final readers = [for (final p in _runs) _RunReader(p)];
    // A binary heap of reader indexes, by their current key.
    final heap = <int>[];
    bool less(int a, int b) => readers[a].current < readers[b].current;
    void down(int i) {
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < heap.length && less(heap[l], heap[m])) m = l;
        if (r < heap.length && less(heap[r], heap[m])) m = r;
        if (m == i) return;
        final t = heap[i];
        heap[i] = heap[m];
        heap[m] = t;
        i = m;
      }
    }

    for (var i = 0; i < readers.length; i++) {
      if (readers[i].moveNext()) heap.add(i);
    }
    for (var i = heap.length ~/ 2 - 1; i >= 0; i--) {
      down(i);
    }
    while (heap.isNotEmpty) {
      final r = readers[heap[0]];
      yield r.current;
      if (r.moveNext()) {
        down(0);
      } else {
        heap[0] = heap.last;
        heap.removeLast();
        if (heap.isNotEmpty) down(0);
      }
    }
    for (final r in readers) {
      r.close();
    }
    for (final p in _runs) {
      File(p).deleteSync();
    }
    _runs.clear();
  }
}

class _RunReader {
  _RunReader(String path) : _f = File(path).openSync();

  final RandomAccessFile _f;
  Int64List _buf = Int64List(0);
  int _i = 0;
  int current = 0;

  bool moveNext() {
    if (_i == _buf.length) {
      final bytes = _f.readSync(1 << 20);
      if (bytes.isEmpty) return false;
      _buf = Int64List.view(
          Uint8List.fromList(bytes).buffer, 0, bytes.length ~/ 8);
      _i = 0;
    }
    current = _buf[_i++];
    return true;
  }

  void close() => _f.closeSync();
}
