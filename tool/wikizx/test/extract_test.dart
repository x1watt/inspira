import 'package:test/test.dart';
import 'package:wikizx/extract.dart';

void main() {
  test('a "Part of" row header does not drop the article', () {
    // Lorsch Abbey and about 25,000 more were left out of en_mini.zx
    // when a row's own header said "Part of".
    final a = extract('<html><head><title>Lorsch Abbey</title></head><body>'
        '<table class="infobox"><tr><th>Type</th><td>Abbey</td></tr>'
        '<tr><th>Part of</th><td><a href="./Lorsch">Lorsch</a></td></tr>'
        '</table><p>Lorsch Abbey is a former Imperial abbey.</p>'
        '</body></html>');
    expect(a.title, 'Lorsch Abbey');
    expect(a.lead, contains('former Imperial abbey'));
    expect(a.infobox, contains(('part of', 'Lorsch')));
  });
}
