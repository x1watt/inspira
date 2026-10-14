import 'package:flutter/material.dart';

import '../models/story.dart';
import '../screens/story_screen.dart';
import 'story_card.dart';

/// Compact story tile; tapping opens the full story.
class StoryTile extends StatelessWidget {
  const StoryTile({super.key, required this.story});

  final Story story;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(storyKindIcon(story.kind)),
      title: Text(story.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(story.lesson, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => StoryScreen(story: story))),
    );
  }
}

/// Lazy list of story tiles.
class StoryList extends StatelessWidget {
  const StoryList({super.key, required this.stories});

  final List<Story> stories;

  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) return const Center(child: Text('No stories found'));
    return ListView.separated(
      itemCount: stories.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => StoryTile(story: stories[i]),
    );
  }
}
