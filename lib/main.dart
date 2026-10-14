import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'data/favorites_store.dart';
import 'data/image_repository.dart';
import 'data/progress_store.dart';
import 'data/quote_repository.dart';
import 'data/story_repository.dart';
import 'screens/categories_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/feed_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/stories_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InspiraApp());
}

class InspiraApp extends StatefulWidget {
  const InspiraApp({super.key, this.load});

  /// Overrides loading, for tests.
  final Future<AppData> Function()? load;

  @override
  State<InspiraApp> createState() => _InspiraAppState();
}

class _InspiraAppState extends State<InspiraApp> {
  late final Future<AppData> _load = widget.load?.call() ?? _loadAll();

  static Future<AppData> _loadAll() async {
    final (quotes, stories, favorites, images, progress) = await (
      QuoteRepository.load(rootBundle),
      StoryRepository.load(rootBundle),
      FavoritesStore.load(),
      ImageRepository.load(rootBundle),
      ProgressStore.load(),
    ).wait;
    return AppData(
      quotes: quotes,
      stories: stories,
      favorites: favorites,
      images: images,
      progress: progress,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inspira',
      debugShowCheckedModeBanner: false,
      theme: blackTheme(),
      // AppScope wraps the Navigator so pushed routes can reach it too.
      builder: (context, navigator) => FutureBuilder(
        future: _load,
        builder: (context, snap) {
          if (snap.hasError) {
            return Scaffold(
              body: Center(
                child: Text('Could not load content: ${snap.error}'),
              ),
            );
          }
          if (!snap.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return AppScope(data: snap.data!, child: navigator!);
        },
      ),
      home: const _Shell(),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _tab = 0;

  static const _titles = ['', 'Quotes', 'Stories', 'Favorites', 'Me'];

  @override
  Widget build(BuildContext context) {
    final feed = _tab == 0;
    return Scaffold(
      // The feed is full screen; the other tabs get a normal app bar.
      appBar: feed ? null : AppBar(title: Text(_titles[_tab])),
      body: IndexedStack(
        index: _tab,
        children: [
          FeedScreen(active: feed),
          const CategoriesScreen(),
          const StoriesScreen(),
          const FavoritesScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle),
            label: 'Feed',
          ),
          NavigationDestination(
            icon: Icon(Icons.format_quote_outlined),
            label: 'Quotes',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            label: 'Stories',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_border),
            label: 'Favorites',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_fire_department_outlined),
            label: 'Me',
          ),
        ],
      ),
    );
  }
}
