import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inspira/data/story_repository.dart';
import 'package:inspira/models/story.dart';

Map<String, dynamic> _s(
  String id,
  String category,
  String kind,
  String title,
) => {
  'id': id,
  'category': category,
  'kind': kind,
  'title': title,
  'text': 'Text of $title.',
  'lesson': 'Lesson of $title.',
  'people': 'Someone',
  'source': 'A source',
  'basis': kind == 'study' ? 'study' : 'fable',
};

void main() {
  final repo = StoryRepository(
    parseStories(
      jsonEncode([
        _s('story-a', 'team', 'story', 'The bundle of sticks'),
        _s('story-b', 'team', 'study', 'Ringelmann rope pulling'),
        _s('story-c', 'family', 'history', 'The Gracchi brothers'),
      ]),
    ),
  );

  test('filters by category, kind and words', () {
    expect(repo.countIn('team'), 2);
    expect(repo.filter(category: 'team', kind: StoryKind.study), [
      repo.byId('story-b'),
    ]);
    expect(repo.filter(query: 'STICKS bundle'), [repo.byId('story-a')]);
    expect(repo.filter(query: 'gracchi', category: 'team'), isEmpty);
  });

  test('story of the day is stable within a day', () {
    final a = repo.storyOfDay(DateTime(2026, 10, 13, 8));
    final b = repo.storyOfDay(DateTime(2026, 10, 13, 23));
    expect(a, same(b));
    expect(repo.byId('story-a')!.basisNote, 'Fable');
  });
}
