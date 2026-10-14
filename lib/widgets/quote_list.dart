import 'package:flutter/material.dart';

import '../models/quote.dart';
import '../screens/quote_screen.dart';

/// Compact quote tile; tapping opens the full card.
class QuoteTile extends StatelessWidget {
  const QuoteTile({super.key, required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(quote.text, maxLines: 3, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '${quote.byline}, ${quote.reference}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => QuoteScreen(quote: quote))),
    );
  }
}

/// Lazy list of quote tiles.
class QuoteList extends StatelessWidget {
  const QuoteList({super.key, required this.quotes});

  final List<Quote> quotes;

  @override
  Widget build(BuildContext context) {
    if (quotes.isEmpty) return const Center(child: Text('No quotes found'));
    return ListView.separated(
      itemCount: quotes.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => QuoteTile(quote: quotes[i]),
    );
  }
}
