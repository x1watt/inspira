import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/progress_store.dart';
import '../models/category.dart';
import 'credits_screen.dart';

/// Streak, daily goal, levels per category and quiz record.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final progress = AppScope.of(context).progress;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: progress,
      builder: (context, _) {
        final accuracy = progress.quizTotal == 0
            ? null
            : (100 * progress.quizRight / progress.quizTotal).round();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.local_fire_department_rounded,
                          size: 48,
                          color: progress.goalReachedToday
                              ? Colors.orange
                              : theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${progress.currentStreak} day streak',
                                style: theme.textTheme.headlineSmall,
                              ),
                              Text(
                                progress.goalReachedToday
                                    ? 'Goal reached today'
                                    : '${progress.dailyGoal - progress.todayXp} '
                                          'XP to go today',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        Tooltip(
                          message:
                              'Streak freezes protect a missed day. '
                              'You earn one every 7 days.',
                          child: Chip(
                            avatar: const Icon(Icons.ac_unit, size: 18),
                            label: Text('${progress.freezes}'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _Calendar(progress: progress),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Daily goal', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (progress.todayXp / progress.dailyGoal).clamp(
                        0.0,
                        1.0,
                      ),
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${progress.todayXp} of ${progress.dailyGoal} XP '
                      'today, ${progress.xp} XP in total',
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: [
                        for (final g in ProgressStore.goals)
                          ButtonSegment(
                            value: g,
                            label: Text(switch (g) {
                              20 => 'Casual',
                              50 => 'Regular',
                              _ => 'Serious',
                            }),
                          ),
                      ],
                      selected: {progress.dailyGoal},
                      onSelectionChanged: (s) => progress.setDailyGoal(s.first),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Levels', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final c in QuoteCategory.all)
                      _LevelRow(category: c, progress: progress),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              child: ListTile(
                leading: const Icon(Icons.quiz_outlined),
                title: const Text('Quiz record'),
                subtitle: Text(
                  accuracy == null
                      ? 'Answer the quick checks in the feed'
                      : '${progress.quizRight} of ${progress.quizTotal} right '
                            '($accuracy percent)',
                ),
              ),
            ),
            Card(
              elevation: 0,
              child: ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Image credits'),
                subtitle: const Text(
                  'Public domain art from Wikimedia Commons',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CreditsScreen()),
                ),
              ),
            ),
            const Card(
              elevation: 0,
              child: ListTile(
                leading: Icon(Icons.public_rounded),
                title: Text('Map data'),
                subtitle: Text(
                  'Wikipedia places from Wikidata (CC0) and Wikipedia; some '
                  'points from GeoNames (geonames.org, CC BY 4.0). Map tiles '
                  'from OpenStreetMap contributors and Esri.',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({required this.category, required this.progress});

  final QuoteCategory category;
  final ProgressStore progress;

  @override
  Widget build(BuildContext context) {
    final xp = progress.categoryXp[category.id] ?? 0;
    final level = ProgressStore.levelFor(xp);
    final start = ProgressStore.levelStart(level);
    final end = ProgressStore.levelStart(level + 1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(category.icon, size: 20),
          const SizedBox(width: 10),
          SizedBox(width: 92, child: Text(category.label)),
          Expanded(
            child: LinearProgressIndicator(
              value: (xp - start) / (end - start),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Text('Lv $level'),
        ],
      ),
    );
  }
}

/// The last 5 weeks; filled days are days the goal was reached.
class _Calendar extends StatelessWidget {
  const _Calendar({required this.progress});

  final ProgressStore progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = progress.today;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var d = today - 34; d <= today; d++)
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: progress.goalDays.contains(d)
                  ? Colors.orange
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
              border: d == today
                  ? Border.all(color: scheme.primary, width: 2)
                  : null,
            ),
          ),
      ],
    );
  }
}
