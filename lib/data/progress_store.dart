import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Day number since the epoch for the local calendar day of [t].
int dayNumber(DateTime t) =>
    DateTime.utc(t.year, t.month, t.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

/// Something worth celebrating, returned by [ProgressStore.award].
sealed class Milestone {
  const Milestone();
}

class GoalReached extends Milestone {
  const GoalReached(this.streak);
  final int streak;
}

class LevelUp extends Milestone {
  const LevelUp(this.category, this.level);
  final String category;
  final int level;
}

/// XP, levels, daily goal, streak, quiz review schedule and feed
/// preferences. Kept in memory; every change is written to
/// shared_preferences without awaiting (docs/performance.md, rule 6).
class ProgressStore extends ChangeNotifier {
  ProgressStore._(this._prefs, this._now, Map<String, dynamic> j) {
    xp = j['xp'] as int? ?? 0;
    categoryXp.addAll(_intMap(j['categoryXp']));
    dailyGoal = j['dailyGoal'] as int? ?? 50;
    _xpDay = j['xpDay'] as int? ?? -1;
    _todayXp = j['todayXp'] as int? ?? 0;
    streak = j['streak'] as int? ?? 0;
    freezes = j['freezes'] as int? ?? 0;
    _lastGoalDay = j['lastGoalDay'] as int?;
    goalDays.addAll([for (final d in j['goalDays'] as List? ?? []) d as int]);
    seen.addAll([for (final s in j['seen'] as List? ?? []) s as String]);
    for (final e in (j['affinity'] as Map? ?? {}).entries) {
      affinity[e.key as String] = (e.value as num).toDouble();
    }
    for (final e in (j['review'] as Map? ?? {}).entries) {
      final v = e.value as List;
      _review[e.key as String] = (box: v[0] as int, due: v[1] as int);
    }
    quizRight = j['quizRight'] as int? ?? 0;
    quizTotal = j['quizTotal'] as int? ?? 0;
  }

  static const _key = 'progress';
  static const goals = [20, 50, 100];
  static const _seenCap = 4000;
  static const _boxDays = [0, 1, 3, 7, 21];
  static const maxFreezes = 2;

  static Future<ProgressStore> load({
    SharedPreferencesAsync? prefs,
    DateTime Function()? now,
  }) async {
    final p = prefs ?? SharedPreferencesAsync();
    final raw = await p.getString(_key);
    return ProgressStore._(
      p,
      now ?? DateTime.now,
      raw == null ? const {} : jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  final SharedPreferencesAsync _prefs;
  final DateTime Function() _now;

  late int xp;
  final categoryXp = <String, int>{};
  late int dailyGoal;
  late int _xpDay;
  late int _todayXp;

  /// Days in a row the daily goal was reached, as of the last goal day.
  late int streak;
  late int freezes;
  int? _lastGoalDay;

  /// Days on which the goal was reached (last 60), for the calendar.
  final goalDays = SplayTreeSet<int>();

  /// Card ids already shown, oldest first.
  final seen = <String>{};

  /// Feed weights per category and per kind (`quote`, `story`, `history`,
  /// `study`); 1.0 when missing.
  final affinity = <String, double>{};
  final _review = <String, ({int box, int due})>{};
  late int quizRight;
  late int quizTotal;

  /// Right answers in a row in this session.
  int combo = 0;

  int get today => dayNumber(_now());

  int get todayXp => _xpDay == today ? _todayXp : 0;

  bool get goalReachedToday => _lastGoalDay == today;

  /// The streak as the user sees it now: still alive when the goal was
  /// reached today or yesterday, or when freezes cover the missed days.
  int get currentStreak {
    final last = _lastGoalDay;
    if (last == null) return 0;
    final missed = today - last - 1;
    return missed <= freezes ? streak : 0;
  }

  static int levelFor(int xp) {
    const steps = [50, 150, 300, 500];
    var level = 1;
    for (final s in steps) {
      if (xp < s) return level;
      level++;
    }
    return level + (xp - 500) ~/ 300;
  }

  /// XP where [level] starts.
  static int levelStart(int level) {
    const starts = [0, 50, 150, 300, 500];
    return level <= 5 ? starts[level - 1] : 500 + (level - 5) * 300;
  }

  int levelOf(String category) => levelFor(categoryXp[category] ?? 0);

  double weight(String key) => affinity[key] ?? 1.0;

  /// Adds XP and returns what it unlocked.
  List<Milestone> award(int amount, String category) {
    final d = today;
    if (_xpDay != d) {
      _xpDay = d;
      _todayXp = 0;
    }
    final before = levelOf(category);
    xp += amount;
    _todayXp += amount;
    categoryXp[category] = (categoryXp[category] ?? 0) + amount;
    final result = <Milestone>[];
    final after = levelOf(category);
    if (after > before) result.add(LevelUp(category, after));
    if (!goalReachedToday && _todayXp >= dailyGoal) {
      _reachGoal(d);
      result.add(GoalReached(streak));
    }
    _changed();
    return result;
  }

  void _reachGoal(int d) {
    final last = _lastGoalDay;
    if (last == null) {
      streak = 1;
    } else {
      final missed = d - last - 1;
      if (missed <= 0) {
        streak++;
      } else if (missed <= freezes) {
        freezes -= missed;
        streak++;
      } else {
        streak = 1;
      }
    }
    if (streak % 7 == 0 && freezes < maxFreezes) freezes++;
    _lastGoalDay = d;
    goalDays.add(d);
    while (goalDays.length > 60) {
      goalDays.remove(goalDays.first);
    }
  }

  void setDailyGoal(int goal) {
    dailyGoal = goal;
    _changed();
  }

  void markSeen(String id) {
    if (!seen.remove(id) && seen.length >= _seenCap) seen.remove(seen.first);
    seen.add(id);
    // Saved with the next XP change; one lost id after a crash is harmless
    // and saves encoding the whole list on every swipe.
  }

  /// Nudges the feed toward (positive) or away from a category and kind.
  /// Weights stay between 0.3 and 3 so nothing disappears.
  void nudge(String category, String kind, double delta) {
    for (final k in [category, kind]) {
      affinity[k] = (weight(k) + delta).clamp(0.3, 3.0);
    }
  }

  /// Records a quiz answer, moves the item between review boxes and
  /// returns the XP earned (10, doubled from the third right answer in a
  /// row).
  int answerQuiz(String id, {required bool correct}) {
    quizTotal++;
    final box = _review[id]?.box ?? 1;
    if (correct) {
      quizRight++;
      combo++;
      final next = (box + 1).clamp(1, 5);
      _review[id] = (box: next, due: today + _boxDays[next - 1]);
    } else {
      combo = 0;
      _review[id] = (box: 1, due: today);
    }
    _changed();
    return correct ? (combo >= 3 ? 20 : 10) : 0;
  }

  /// Ids whose review is due, most overdue first.
  List<String> dueReviews() {
    final d = today;
    final due = [
      for (final e in _review.entries)
        if (e.value.due <= d) e,
    ]..sort((a, b) => a.value.due.compareTo(b.value.due));
    return [for (final e in due) e.key];
  }

  bool hasReview(String id) => _review.containsKey(id);

  void _changed() {
    notifyListeners();
    _prefs.setString(_key, jsonEncode(_toJson()));
  }

  Map<String, dynamic> _toJson() => {
    'xp': xp,
    'categoryXp': categoryXp,
    'dailyGoal': dailyGoal,
    'xpDay': _xpDay,
    'todayXp': _todayXp,
    'streak': streak,
    'freezes': freezes,
    'lastGoalDay': _lastGoalDay,
    'goalDays': goalDays.toList(),
    'seen': seen.toList(),
    'affinity': affinity,
    'review': {
      for (final e in _review.entries) e.key: [e.value.box, e.value.due],
    },
    'quizRight': quizRight,
    'quizTotal': quizTotal,
  };

  static Map<String, int> _intMap(Object? m) => {
    for (final e in (m as Map? ?? {}).entries) e.key as String: e.value as int,
  };
}
