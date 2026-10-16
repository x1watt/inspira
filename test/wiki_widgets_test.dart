import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspira/data/wiki/wiki_service.dart';
import 'package:inspira/widgets/wiki_widgets.dart';

class _FakeWiki extends WikiService {
  WikiStatus s = WikiStatus.absent;
  int d = 0;
  int downloads = 0;
  @override
  WikiStatus get status => s;
  @override
  int get downloaded => d;
  @override
  int get total => 3208595489;
  @override
  int get received => d;
  @override
  String? get error => null;
  @override
  Future<void> download() async {
    downloads++;
    s = WikiStatus.downloading;
    d = 1600000000;
    notifyListeners();
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> delete() async {}
  @override
  Future<List<WikiFact>> onThisDay(
    int month,
    int day, {
    int limit = 30,
  }) async => const [
    WikiFact(title: 'Crimean War', kind: 'event', role: 'point', year: 1853),
    WikiFact(
      title: 'Marie Antoinette',
      kind: 'person',
      role: 'death',
      year: 1793,
    ),
  ];
  @override
  Future<WikiArticle?> article(String title) async =>
      WikiArticle(title: title, kind: 'person', lead: 'Queen of France.');
}

Widget _wrap(Widget w) => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(body: SingleChildScrollView(child: w)),
);

void main() {
  test('fact labels', () {
    const f = WikiFact(title: 'x', kind: 'event', role: 'birth', year: -44);
    expect(f.yearLabel, '44 BC');
    expect(f.roleLabel, 'Born');
    expect(
      const WikiArticle(
        title: 'Marie Antoinette',
        kind: 'person',
        lead: '',
      ).url,
      'https://en.wikipedia.org/wiki/Marie_Antoinette',
    );
  });

  testWidgets('the card offers the download and shows its progress', (
    tester,
  ) async {
    final wiki = _FakeWiki();
    await tester.pumpWidget(_wrap(WikiDownloadCard(wiki: wiki)));
    expect(find.textContaining('about 3.2 GB'), findsOneWidget);
    await tester.tap(find.text('Download'));
    await tester.pump();
    expect(wiki.downloads, 1);
    expect(find.text('1.60 GB of 3.21 GB'), findsOneWidget);
    expect(
      find.text('Data used since the app started: 1.60 GB'),
      findsOneWidget,
    );
    expect(find.text('Pause'), findsOneWidget);
  });

  testWidgets('More from Wikipedia lists the day and opens an article', (
    tester,
  ) async {
    final wiki = _FakeWiki()..s = WikiStatus.ready;
    await tester.pumpWidget(
      _wrap(WikiDaySection(wiki: wiki, month: 10, day: 16)),
    );
    await tester.pumpAndSettle();
    expect(find.text('More from Wikipedia'), findsOneWidget);
    expect(find.text('1793, Died'), findsOneWidget);
    await tester.tap(find.text('Marie Antoinette'));
    await tester.pumpAndSettle();
    expect(find.text('Queen of France.'), findsOneWidget);
    expect(find.text('Read on Wikipedia'), findsOneWidget);
  });

  testWidgets('nothing shows before the database is on the device', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(WikiDaySection(wiki: _FakeWiki(), month: 10, day: 16)),
    );
    expect(find.text('More from Wikipedia'), findsNothing);
  });
}
