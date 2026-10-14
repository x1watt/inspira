import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/category.dart';
import 'category_screen.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  void _open(BuildContext context, QuoteCategory? category) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => CategoryScreen(category: category)));

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).repository;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
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
            title: const Text('Search all quotes'),
            subtitle: const Text('By words, author or book'),
            trailing: Text('${repo.quotes.length}'),
            onTap: () => _open(context, null),
          ),
        ),
      ],
    );
  }
}
