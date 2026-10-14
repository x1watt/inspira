import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/category.dart';
import '../models/quote.dart';
import '../widgets/quote_list.dart';

/// Quotes of one category, or of all when [category] is null, with search.
class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key, this.category, this.initialQuery = ''});

  final QuoteCategory? category;

  /// Starts with this search, for example a person's name.
  final String initialQuery;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  Timer? _debounce;
  late String _query = widget.initialQuery;
  late final _search = TextEditingController(text: widget.initialQuery);
  List<Quote>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _query = value.trim();
        _results = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).repository;
    final id = widget.category?.id;
    _results ??= _query.isEmpty
        ? (id == null ? repo.quotes : repo.inCategory(id))
        : repo.search(_query, category: id);
    return Scaffold(
      appBar: AppBar(title: Text(widget.category?.label ?? 'All quotes')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SearchBar(
              controller: _search,
              hintText: 'Search words, author or book',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: _onChanged,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_results!.length} quotes',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Expanded(child: QuoteList(quotes: _results!)),
        ],
      ),
    );
  }
}
