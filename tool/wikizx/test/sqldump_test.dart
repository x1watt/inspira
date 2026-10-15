import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wikizx/sqldump.dart';

void main() {
  test('rows of every INSERT, strings with escapes and UTF-8, NULLs', () async {
    final dir = Directory.systemTemp.createTempSync('sqldump');
    final f = File('${dir.path}/t.sql.gz');
    const sql = '''-- comment (with parens);
CREATE TABLE `t` (`a` int, `b` varbinary(9));
INSERT INTO `t` VALUES (1,'x',NULL,-2.5),(2,'it\\'s, (ok)\\n','Lisboa é São',3);
INSERT INTO `t` VALUES
(3,'',NULL,0);
''';
    f.writeAsBytesSync(gzip.encode(utf8.encode(sql)));
    final rows = await sqlDumpRows(f.path).toList();
    expect(rows, [
      [1, 'x', null, -2.5],
      [2, "it's, (ok)\n", 'Lisboa é São', 3],
      [3, '', null, 0],
    ]);
    dir.deleteSync(recursive: true);
  });
}
