import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/category.dart';
import '../widgets/story_card.dart';
import 'story_list_screen.dart';
import 'story_screen.dart';

/// Story of the day, then the categories.
class StoriesScreen extends StatefulWidget {
  const StoriesScreen({super.key});

  @override
  State<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends State<StoriesScreen> {
  final _today = DateTime.now();

  void _open(BuildContext context, QuoteCategory? category) =>
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StoryListScreen(category: category)),
      );

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).stories;
    final daily = repo.storyOfDay(_today);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (daily != null)
          Card(
            elevation: 0,
            color: theme.colorScheme.secondaryContainer,
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              leading: Icon(storyKindIcon(daily.kind)),
              title: Text(
                'Story of the day',
                style: theme.textTheme.labelLarge,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(daily.title, style: theme.textTheme.titleMedium),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => StoryScreen(story: daily)),
              ),
            ),
          ),
        for (final c in QuoteCategory.all)
          Card(
            elevation: 0,
            child: ListTile(
              leading: Icon(c.icon),
              title: Text(c.label),
              subtitle: Text(c.blurb),
              trailing: Text('${repo.countIn(c.id)}'),
              onTap: () => _open(context, c),
            ),
          ),
        Card(
          elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Search all stories'),
            subtitle: const Text('Stories, history and studies'),
            trailing: Text('${repo.stories.length}'),
            onTap: () => _open(context, null),
          ),
        ),
      ],
    );
  }
}
