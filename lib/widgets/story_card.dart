import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/story.dart';
import 'item_actions.dart';
import 'person_sheet.dart';
import 'quote_card.dart';

/// Icon for each kind of story, shared by cards and list tiles.
IconData storyKindIcon(StoryKind kind) => switch (kind) {
  StoryKind.story => Icons.auto_stories_outlined,
  StoryKind.history => Icons.account_balance_outlined,
  StoryKind.study => Icons.science_outlined,
};

/// Full story with its lesson, source details and actions.
class StoryCard extends StatelessWidget {
  const StoryCard({super.key, required this.story, this.header});

  final Story story;
  final String? header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final category = QuoteCategory.byId(story.category);
    final meta = [
      if (story.people.isNotEmpty) story.people,
      if (story.date.isNotEmpty) story.date,
    ].join(', ');
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  storyKindIcon(story.kind),
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    header ?? '${story.kind.label}, ${category.label}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(story.title, style: theme.textTheme.headlineSmall),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(meta, style: theme.textTheme.bodySmall),
            ],
            if (story.people.isNotEmpty)
              WikipediaLink(
                name: story.people.split(',').first.split(' and ').first.trim(),
              ),
            const SizedBox(height: 16),
            SelectableText(
              story.text,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 20,
                    color: scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      story.lesson,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Detail(Icons.menu_book_outlined, story.source),
            if (story.location.isNotEmpty)
              Detail(Icons.place_outlined, story.location),
            if (story.basisNote.isNotEmpty)
              Detail(Icons.info_outline, story.basisNote),
            if (story.caveat.isNotEmpty)
              Detail(Icons.report_outlined, story.caveat),
            const SizedBox(height: 4),
            ItemActions(
              id: story.id,
              shareText: story.toShareText(),
              copiedMessage: 'Story copied',
            ),
          ],
        ),
      ),
    );
  }
}
