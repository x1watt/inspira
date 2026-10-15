// Streams the rows of a MediaWiki SQL dump (table.sql.gz): every tuple of
// every INSERT INTO statement, as a list of values (null, int, double or
// String). Reads the file once, in chunks; nothing is kept but the row.
import 'dart:convert';
import 'dart:io';

Stream<List<Object?>> sqlDumpRows(String path) async* {
  final rows = <List<Object?>>[];
  final p = _Parser(rows.add);
  await for (final chunk in File(path)
      .openRead()
      .transform(gzip.decoder)
      .transform(latin1.decoder)) {
    p.feed(chunk);
    if (rows.isNotEmpty) {
      yield* Stream.fromIterable(List.of(rows));
      rows.clear();
    }
  }
}

/// A character level parser that keeps its state across chunks. Strings
/// are read as Latin-1 and turned back into UTF-8 when the row ends.
class _Parser {
  _Parser(this.onRow);

  final void Function(List<Object?>) onRow;
  var _inInsert = false;
  var _depth = 0; // 1 inside a tuple
  var _inStr = false;
  var _esc = false;
  final _tok = StringBuffer();
  var _quoted = false;
  final _row = <Object?>[];
  final _line = StringBuffer(); // start of a line, to spot INSERT INTO

  void feed(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (!_inInsert) {
        if (c == 10) {
          _line.clear();
        } else if (_line.length < 11) {
          _line.writeCharCode(c);
          if (_line.length == 11 && _line.toString() == 'INSERT INTO') {
            _inInsert = true;
          }
        }
        continue;
      }
      if (_inStr) {
        if (_esc) {
          _tok.writeCharCode(switch (c) {
            0x6e => 10, // n
            0x72 => 13, // r
            0x74 => 9, // t
            0x30 => 0, // 0
            _ => c,
          });
          _esc = false;
        } else if (c == 0x5c) {
          _esc = true;
        } else if (c == 0x27) {
          _inStr = false;
        } else {
          _tok.writeCharCode(c);
        }
        continue;
      }
      if (_depth == 0) {
        if (c == 0x28) {
          _depth = 1;
          _row.clear();
          _tok.clear();
          _quoted = false;
        } else if (c == 0x3b) {
          _inInsert = false; // end of the statement
        }
        continue;
      }
      switch (c) {
        case 0x27:
          _inStr = true;
          _quoted = true;
        case 0x2c:
          _value();
        case 0x29:
          _value();
          onRow(List.of(_row));
          _depth = 0;
        default:
          _tok.writeCharCode(c);
      }
    }
  }

  void _value() {
    final t = _tok.toString();
    _tok.clear();
    if (_quoted) {
      _row.add(utf8.decode(latin1.encode(t), allowMalformed: true));
    } else if (t == 'NULL') {
      _row.add(null);
    } else {
      _row.add(int.tryParse(t) ?? double.tryParse(t) ?? t);
    }
    _quoted = false;
  }
}
