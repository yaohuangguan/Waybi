import 'package:shared_preferences/shared_preferences.dart';

class SearchHistoryStore {
  static const _key = 'waybi.search.recent_queries.v1';
  static const maxItems = 6;

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const <String>[])
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(maxItems)
        .toList(growable: false);
  }

  Future<List<String>> remember(String query) async {
    final value = query.trim();
    if (value.runes.length < 2) return load();
    final previous = await load();
    final next = <String>[
      value,
      ...previous.where((item) => item.toLowerCase() != value.toLowerCase()),
    ].take(maxItems).toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, next);
    return next;
  }

  Future<List<String>> remove(String query) async {
    final previous = await load();
    final next = previous
        .where((item) => item.toLowerCase() != query.trim().toLowerCase())
        .toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, next);
    return next;
  }
}
