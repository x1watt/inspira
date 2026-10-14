import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/quote.dart';
import '../widgets/quote_card.dart';

class QuoteScreen extends StatelessWidget {
  const QuoteScreen({super.key, required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(QuoteCategory.byId(quote.category).label)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: QuoteCard(quote: quote),
          ),
        ),
      ),
    );
  }
}
