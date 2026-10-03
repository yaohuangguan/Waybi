import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/data/brand_migration.dart';

void main() {
  test(
    'brand migration keeps settings, saved lists and existing Waybi choices',
    () async {
      SharedPreferences.setMockInitialValues({
        'kiwi.app.language': 'zh',
        'tasman.appearance': 'dark',
        'kiwi.nav.keep_screen_awake': true,
        'kiwi.quick_actions': ['home', 'work'],
        'kiwi.map.provider': 'google',
        'waybi.map.provider': 'independent',
      });
      final prefs = await SharedPreferences.getInstance();
      await migrateWaybiPreferences(prefs);
      expect(prefs.getString('waybi.app.language'), 'zh');
      expect(prefs.getString('waybi.appearance'), 'dark');
      expect(prefs.getBool('waybi.nav.keep_screen_awake'), true);
      expect(prefs.getStringList('waybi.quick_actions'), ['home', 'work']);
      expect(prefs.getString('waybi.map.provider'), 'independent');
      expect(prefs.getString('kiwi.app.language'), 'zh');
      await prefs.setString('waybi.app.language', 'en');
      await migrateWaybiPreferences(prefs);
      expect(prefs.getString('waybi.app.language'), 'en');
    },
  );
}
