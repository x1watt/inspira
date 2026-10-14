import 'package:flutter/material.dart';

import '../screens/favorites_screen.dart';
import '../screens/profile_screen.dart';

/// Favorites and Me, at the top of every main tab so the bottom bar keeps
/// only the places to read and play.
class TopActions extends StatelessWidget {
  const TopActions({super.key, this.onImage = false});

  /// True over the feed's pictures: white icons on a dark circle.
  final bool onImage;

  static void _open(BuildContext context, String title, Widget body) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: body,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = onImage
        ? IconButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.35),
            foregroundColor: Colors.white,
            minimumSize: const Size(36, 36),
            padding: EdgeInsets.zero,
          )
        : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Favorites',
          style: style,
          icon: const Icon(Icons.star_rounded),
          onPressed: () => _open(context, 'Favorites', const FavoritesScreen()),
        ),
        if (onImage) const SizedBox(width: 6),
        IconButton(
          tooltip: 'Me',
          style: style,
          icon: const Icon(Icons.account_circle_rounded),
          onPressed: () => _open(context, 'Me', const ProfileScreen()),
        ),
      ],
    );
  }
}
