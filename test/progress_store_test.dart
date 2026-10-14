import 'package:flutter_test/flutter_test.dart';
import 'package:inspira/data/progress_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late DateTime now;
  Future<ProgressStore> load() => ProgressStore.load(now: () => now);

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    now = DateTime(2026, 10, 1, 9);
  });

  test('goal reached extends the streak and celebrates once', () async {
    final p = await load();
    expect(p.award(40, 'team'), isEmpty);
    final m = p.award(20, 'team');
    expect(m.whereType<GoalReached>().single.streak, 1);
    expect(p.award(10, 'team').whereType<GoalReached>(), isEmpty);

    now = now.add(const Duration(days: 1));
    expect(p.currentStreak, 1);
    p.award(50, 'family');
    expect(p.currentStreak, 2);
  });

  test('missed day breaks the streak unless a freeze covers it', () async {
    final p = await load();
    for (var i = 0; i < 7; i++) {
      p.award(50, 'team');
      now = now.add(const Duration(days: 1));
    }
    expect(p.streak, 7);
    expect(p.freezes, 1);

    now = now.add(const Duration(days: 1)); // one day missed
    expect(p.currentStreak, 7);
    p.award(50, 'team');
    expect(p.streak, 8);
    expect(p.freezes, 0);

    now = now.add(const Duration(days: 3)); // two days missed, no freeze
    expect(p.currentStreak, 0);
    p.award(50, 'team');
    expect(p.streak, 1);
  });

  test('levels and level up', () async {
    expect(ProgressStore.levelFor(0), 1);
    expect(ProgressStore.levelFor(50), 2);
    expect(ProgressStore.levelFor(499), 4);
    expect(ProgressStore.levelFor(500), 5);
    expect(ProgressStore.levelFor(800), 6);
    expect(ProgressStore.levelStart(6), 800);
    final p = await load();
    final m = p.award(55, 'strategy');
    expect(m.whereType<LevelUp>().single.level, 2);
  });

  test('quiz review boxes and combo', () async {
    final p = await load();
    expect(p.answerQuiz('a', correct: false), 0);
    expect(p.dueReviews(), ['a']);
    expect(p.answerQuiz('a', correct: true), 10);
    expect(p.dueReviews(), isEmpty); // box 2, due tomorrow
    now = now.add(const Duration(days: 1));
    expect(p.dueReviews(), ['a']);
    p.answerQuiz('b', correct: true);
    expect(p.answerQuiz('c', correct: true), 20); // third in a row
  });

  test('state survives a reload', () async {
    final p = await load();
    p.award(60, 'relations');
    p.setDailyGoal(100);
    await Future<void>.delayed(Duration.zero);
    final q = await load();
    expect(q.xp, 60);
    expect(q.dailyGoal, 100);
    expect(q.currentStreak, 1);
  });
}
