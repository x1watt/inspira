import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../widgets/quote_list.dart';
import '../widgets/story_list.dart';

/// Favorite quotes and stories, most recently added first.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.favorites,
      builder: (context, _) {
        final tiles = <Widget>[
          for (final id in scope.favorites.ids.reversed)
            if (scope.repository.byId(id) case final q?)
              QuoteTile(quote: q)
            else if (scope.stories.byId(id) case final s?)
              StoryTile(story: s),
        ];
        if (tiles.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Tap the star on a quote or story to keep it here.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: tiles.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) => tiles[i],
        );
      },
    );
  }
}
