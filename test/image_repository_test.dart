import 'package:flutter_test/flutter_test.dart';
import 'package:inspira/data/image_repository.dart';
import 'package:inspira/models/quote.dart';
import 'package:inspira/models/story.dart';

Story _story(String id, String kind, String basis) => Story.fromJson({
  'id': id,
  'category': 'team',
  'kind': kind,
  'title': 't',
  'text': 'x',
  'lesson': 'l',
  'source': 's',
  'basis': basis,
});

void main() {
  final repo = ImageRepository.fromJson({
    'avatars': {'Seneca': 'avatars/seneca.webp'},
    'wikipedia': {'Seneca': 'https://en.wikipedia.org/wiki/Seneca_the_Younger'},
    'art': [
      {
        'file': 'art/team1.webp',
        'title': 'Rowers',
        'pools': ['team'],
      },
      {
        'file': 'art/team2.webp',
        'pools': ['team'],
      },
      {
        'file': 'art/fable.webp',
        'pools': ['fable'],
      },
      {
        'file': 'art/study.webp',
        'pools': ['study'],
      },
      {
        'file': 'art/event.webp',
        'stories': ['story-a'],
      },
    ],
  });

  test('avatars and art per item', () {
    expect(repo.avatarFor('Seneca'), 'assets/images/avatars/seneca.webp');
    expect(repo.avatarFor('Nobody'), isNull);
    expect(repo.wikipediaFor('Seneca'), endsWith('Seneca_the_Younger'));
    expect(repo.wikipediaFor('Nobody'), isNull);
    expect(
      repo.artForStory(_story('story-a', 'history', 'documented'))!.asset,
      'assets/images/art/event.webp',
    );
    expect(
      repo.artForStory(_story('story-b', 'story', 'fable'))!.asset,
      'assets/images/art/fable.webp',
    );
    expect(
      repo.artForStory(_story('story-c', 'study', 'study'))!.asset,
      'assets/images/art/study.webp',
    );
    final q = Quote.fromJson({
      'id': 'q1',
      'category': 'team',
      'text': 't',
      'author': 'a',
      'reference': 'r',
    });
    final art = repo.artForQuote(q)!;
    expect(art.asset, startsWith('assets/images/art/team'));
    expect(repo.artForQuote(q), same(art)); // stable
    expect(repo.allArt, hasLength(5));
  });
}
