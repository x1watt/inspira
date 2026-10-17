import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspira/data/wiki/wiki_service.dart';
import 'package:inspira/data/wiki_place_repository.dart';
import 'package:inspira/widgets/wiki_widgets.dart';

class _FakeWiki extends WikiService {
  WikiStatus s = WikiStatus.absent;
  int d = 0;
  int downloads = 0;
  bool places = false;
  @override
  WikiStatus get status => s;
  @override
  bool get articlesReady => s == WikiStatus.ready || places;
  @override
  bool get placesReady => places;
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
  Future<WikiArticle?> article(String title) async => WikiArticle(
    title: title,
    kind: 'person',
    lead: title == 'Marie Antoinette'
        ? 'Queen of France, wife of Louis XVI.'
        : 'King of France.',
    related: const ['Louis XVI', 'Kingdom of France (987-1792)', 'Vienna'],
  );
  @override
  Future<WikiArticle?> placeArticle(WikiPlace place) => article(place.title);
  @override
  Future<List<WikiPlace>> placesIn(
    List<int> cells, {
    int? perCell,
    String? cat,
  }) async => const [];
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
    expect(find.textContaining('about 3.5 GB'), findsOneWidget);
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
    // offline: the lead names Louis XVI (a link), the rest are related
    expect(find.text('Queen of France, wife of Louis XVI.'), findsOneWidget);
    expect(find.text('Vienna'), findsOneWidget);
    expect(find.text('Louis XVI'), findsNothing);
    expect(find.textContaining('Wikipedia', findRichText: true), findsWidgets);
    expect(find.text('Read on Wikipedia'), findsNothing);
    await tester.tap(find.text('Vienna'));
    await tester.pumpAndSettle();
    expect(find.text('King of France.'), findsWidgets);
  });

  testWidgets('the card offers the places file as an update', (tester) async {
    // articles there, the places file not yet: an update of about 320 MB
    final updating = _UpdateWiki()..d = 3208595489;
    await tester.pumpWidget(_wrap(WikiDownloadCard(wiki: updating)));
    expect(find.textContaining('About 320 MB more'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
  });

  testWidgets('the links file is offered as an update', (tester) async {
    final wiki = _FakeWiki()
      ..places = true
      ..d = 3249500970;
    await tester.pumpWidget(_wrap(WikiDownloadCard(wiki: wiki)));
    expect(
      find.textContaining('External links of the articles'),
      findsOneWidget,
    );
    expect(find.text('Update'), findsOneWidget);
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

/// The articles are on the device, the places file is not.
class _UpdateWiki extends _FakeWiki {
  @override
  bool get articlesReady => true;
}
