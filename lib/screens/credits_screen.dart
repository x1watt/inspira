import 'package:flutter/material.dart';

import '../app_scope.dart';

/// Every bundled artwork with its title, artist and Commons page.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final art = AppScope.of(context).images.allArt;
    return Scaffold(
      appBar: AppBar(title: const Text('Image credits')),
      body: ListView.separated(
        itemCount: art.length + 1,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i == 0) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'All pictures are public domain or CC0 works from '
                'Wikimedia Commons. Portraits come from the same source.',
              ),
            );
          }
          final a = art[i - 1];
          return ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                a.asset,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                cacheWidth: 96,
              ),
            ),
            title: Text(
              a.title.isEmpty ? 'Untitled' : a.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [a.artist, a.year, a.url].where((s) => s.isNotEmpty).join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      ),
    );
  }
}
