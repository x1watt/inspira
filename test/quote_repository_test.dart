import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inspira/data/favorites_store.dart';
import 'package:inspira/data/quote_repository.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Map<String, dynamic> _q(
  String id,
  String category,
  String text, {
  String author = 'Seneca',
  String? speaker,
}) => {
  'id': id,
  'category': category,
  'text': text,
  'author': author,
  'speaker': ?speaker,
  'reference': 'Letters',
  'locator': 'Letter 3',
  'date': 'c. AD 64',
  'year': 64,
  'location': 'Rome',
  'confidence': 'verified',
};

void main() {
  final raw = jsonEncode([
    _q('a', 'relations', 'Friendship is a sheltering tree.'),
    _q(
      'b',
      'strategy',
      'All warfare is based on deception.',
      author: 'Sun Tzu',
    ),
    _q('c', 'family', 'Honor thy father.', speaker: 'Cato'),
    _q('d', 'team', 'Union gives strength.', author: 'Aesop'),
  ]);

  test('parses and groups by category', () {
    final repo = QuoteRepository(parseQuotes(raw));
    expect(repo.quotes, hasLength(4));
    expect(repo.countIn('strategy'), 1);
    expect(repo.byId('c')!.byline, 'Cato, in Seneca');
    expect(repo.byId('a')!.citation, 'Letters, Letter 3, c. AD 64');
  });

  test('quote of the day is stable within a day', () {
    final repo = QuoteRepository(parseQuotes(raw));
    final morning = DateTime(2026, 10, 13, 7);
    final evening = DateTime(2026, 10, 13, 23);
    expect(repo.quoteOfDay(morning)!.id, repo.quoteOfDay(evening)!.id);
    expect(
      repo.quoteForPage(morning, 3)!.id,
      repo.quoteForPage(evening, 3)!.id,
    );
  });

  test('search matches all words, optionally in one category', () {
    final repo = QuoteRepository(parseQuotes(raw));
    expect(repo.search('warfare sun').map((q) => q.id), ['b']);
    expect(repo.search('aesop').map((q) => q.id), ['d']);
    expect(repo.search('is', category: 'relations').map((q) => q.id), ['a']);
    expect(repo.search('nothing here'), isEmpty);
  });

  test('favorites toggle and persist', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = await FavoritesStore.load();
    store.toggle('a');
    store.toggle('b');
    store.toggle('a');
    expect(store.ids, ['b']);
    await Future<void>.delayed(Duration.zero);
    final reloaded = await FavoritesStore.load();
    expect(reloaded.contains('b'), isTrue);
    expect(reloaded.contains('a'), isFalse);
  });
}
