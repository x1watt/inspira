import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/category.dart';
import '../models/story.dart';
import '../widgets/story_list.dart';

/// Stories of one category, or of all when [category] is null, with a kind
/// filter and search.
class StoryListScreen extends StatefulWidget {
  const StoryListScreen({super.key, this.category, this.initialQuery = ''});

  final QuoteCategory? category;

  /// Starts with this search, for example a person's name.
  final String initialQuery;

  @override
  State<StoryListScreen> createState() => _StoryListScreenState();
}

class _StoryListScreenState extends State<StoryListScreen> {
  Timer? _debounce;
  late String _query = widget.initialQuery;
  late final _search = TextEditingController(text: widget.initialQuery);
  StoryKind? _kind;
  List<Story>? _results;

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

  void _setKind(StoryKind? kind) => setState(() {
    _kind = kind;
    _results = null;
  });

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).stories;
    _results ??= repo.filter(
      query: _query,
      category: widget.category?.id,
      kind: _kind,
    );
    return Scaffold(
      appBar: AppBar(title: Text(widget.category?.label ?? 'All stories')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SearchBar(
              controller: _search,
              hintText: 'Search stories, people or sources',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: _onChanged,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final k in <StoryKind?>[null, ...StoryKind.values])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(k == null ? 'All' : _plural(k)),
                      selected: _kind == k,
                      onSelected: (_) => _setKind(k),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_results!.length} stories',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Expanded(child: StoryList(stories: _results!)),
        ],
      ),
    );
  }

  static String _plural(StoryKind k) => switch (k) {
    StoryKind.story => 'Stories',
    StoryKind.history => 'History',
    StoryKind.study => 'Studies',
  };
}
