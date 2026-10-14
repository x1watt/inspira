import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/quote.dart';
import 'item_actions.dart';
import 'person_sheet.dart';

/// Full quote with its source details and actions.
class QuoteCard extends StatelessWidget {
  const QuoteCard({super.key, required this.quote, this.header});

  final Quote quote;
  final String? header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final category = QuoteCategory.byId(quote.category);
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
                Icon(category.icon, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  header ?? category.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SelectableText(
              quote.text,
              style: theme.textTheme.titleLarge?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 20),
            Text(
              quote.byline,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (quote.authorLifespan.isNotEmpty)
              Text(quote.authorLifespan, style: theme.textTheme.bodySmall),
            Wrap(
              children: [
                if (quote.speaker case final speaker?)
                  WikipediaLink(name: speaker),
                WikipediaLink(name: quote.author),
              ],
            ),
            const SizedBox(height: 12),
            Detail(Icons.menu_book_outlined, quote.citation),
            if (quote.location.isNotEmpty)
              Detail(Icons.place_outlined, quote.location),
            if (quote.translation.isNotEmpty &&
                quote.originalLanguage != 'English')
              Detail(
                Icons.translate,
                'From ${quote.originalLanguage}, tr. ${quote.translation}',
              ),
            Detail(
              quote.isVerified ? Icons.verified_outlined : Icons.info_outline,
              quote.isVerified
                  ? 'Checked word for word against the source text'
                  : 'Attributed; not checked against a source text',
            ),
            const SizedBox(height: 4),
            ItemActions(
              id: quote.id,
              shareText: quote.toShareText(),
              copiedMessage: 'Quote copied',
            ),
          ],
        ),
      ),
    );
  }
}

/// Small icon and text line for source details.
class Detail extends StatelessWidget {
  const Detail(this.icon, this.text, {super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
