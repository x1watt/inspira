import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';

/// share_plus has no real share sheet on Linux; copy covers it there.
bool get canShare => !kIsWeb && defaultTargetPlatform != TargetPlatform.linux;

/// Favorite, copy and share buttons for a quote or a story.
class ItemActions extends StatelessWidget {
  const ItemActions({
    super.key,
    required this.id,
    required this.shareText,
    required this.copiedMessage,
  });

  final String id;
  final String shareText;
  final String copiedMessage;

  @override
  Widget build(BuildContext context) {
    final favorites = AppScope.of(context).favorites;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ListenableBuilder(
          listenable: favorites,
          builder: (context, _) {
            final fav = favorites.contains(id);
            return IconButton(
              tooltip: fav ? 'Remove from favorites' : 'Add to favorites',
              icon: Icon(fav ? Icons.star : Icons.star_border),
              onPressed: () => favorites.toggle(id),
            );
          },
        ),
        IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy_outlined),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: shareText));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(copiedMessage)));
          },
        ),
        if (canShare)
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: () =>
                SharePlus.instance.share(ShareParams(text: shareText)),
          ),
      ],
    );
  }
}
