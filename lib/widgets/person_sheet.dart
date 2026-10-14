import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_scope.dart';

/// Opens [url] in the browser; shows a message when that is not possible.
Future<void> openLink(BuildContext context, String url) async {
  final ok = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Could not open $url')));
  }
}

/// Portrait, Wikipedia link and "more from this person" for [name].
Future<void> showPersonSheet(
  BuildContext context,
  String name, {
  required String browseLabel,
  required VoidCallback onBrowse,
  String wikiLabel = 'Read about the author on Wikipedia',
}) {
  final images = AppScope.of(context).images;
  final avatar = images.avatarFor(name);
  final wiki = images.wikipediaFor(name);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 48,
              foregroundImage: avatar == null ? null : AssetImage(avatar),
              child: const Icon(Icons.person, size: 48),
            ),
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              style: Theme.of(sheet).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (wiki != null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => openLink(context, wiki),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(wikiLabel),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(sheet).pop();
                  onBrowse();
                },
                icon: const Icon(Icons.search),
                label: Text(browseLabel),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Small "Wikipedia" link for detail cards; nothing when there is no page.
class WikipediaLink extends StatelessWidget {
  const WikipediaLink({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final url = AppScope.of(context).images.wikipediaFor(name);
    if (url == null) return const SizedBox.shrink();
    return TextButton.icon(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onPressed: () => openLink(context, url),
      icon: const Icon(Icons.open_in_new, size: 16),
      label: Text('$name on Wikipedia'),
    );
  }
}
