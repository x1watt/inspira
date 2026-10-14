import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Favorite quote ids. Kept in memory; writes go to shared_preferences
/// asynchronously and are not awaited by the UI.
class FavoritesStore extends ChangeNotifier {
  FavoritesStore._(this._prefs, this._ids);

  static const _key = 'favorites';

  static Future<FavoritesStore> load([SharedPreferencesAsync? prefs]) async {
    final p = prefs ?? SharedPreferencesAsync();
    final ids = await p.getStringList(_key) ?? const <String>[];
    return FavoritesStore._(p, ids.toList());
  }

  final SharedPreferencesAsync _prefs;

  /// Most recently added last.
  final List<String> _ids;

  List<String> get ids => List.unmodifiable(_ids);

  bool contains(String id) => _ids.contains(id);

  void toggle(String id) {
    if (!_ids.remove(id)) _ids.add(id);
    notifyListeners();
    _prefs.setStringList(_key, _ids.toList());
  }
}
