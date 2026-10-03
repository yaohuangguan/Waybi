import 'package:shared_preferences/shared_preferences.dart';

/// Copy legacy keys once; retain the originals for rollback and older builds.
Future<void> migrateWaybiPreferences(SharedPreferences prefs) async {
  if (prefs.getBool('waybi.brand_migrated.v1') == true) return;
  for (final key in prefs.getKeys().toList()) {
    if (!key.startsWith('kiwi.') && !key.startsWith('tasman.')) continue;
    final newKey = 'waybi.${key.substring(key.indexOf('.') + 1)}';
    if (prefs.containsKey(newKey)) continue;
    final value = prefs.get(key);
    if (value is bool) {
      await prefs.setBool(newKey, value);
    } else if (value is String) {
      await prefs.setString(newKey, value);
    } else if (value is int) {
      await prefs.setInt(newKey, value);
    } else if (value is double) {
      await prefs.setDouble(newKey, value);
    } else if (value is List<String>) {
      await prefs.setStringList(newKey, value);
    }
  }
  await prefs.setBool('waybi.brand_migrated.v1', true);
}
