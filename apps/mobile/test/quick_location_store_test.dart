import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/data/quick_location_store.dart';
import 'package:waybi_mobile/domain/map_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Independent Home and Work survive a new store instance', () async {
    SharedPreferences.setMockInitialValues({});
    final store = QuickLocationStore();
    await store.save(
      'Home',
      const PlaceSummary(
        name: 'Home',
        address: 'Queen Street',
        location: GeoPoint(-36.85, 174.76),
      ),
      MapProvider.independent,
    );
    await store.save(
      'Work',
      const PlaceSummary(
        name: 'Work',
        address: 'Albert Street',
        location: GeoPoint(-36.86, 174.77),
      ),
      MapProvider.independent,
    );
    final restored = await QuickLocationStore().load();
    expect(restored.keys, containsAll(['Home', 'Work']));
    expect(restored['Home']!.place.location, const GeoPoint(-36.85, 174.76));
    expect(restored['Work']!.place.address, 'Albert Street');
    expect(
      restored.values.every((item) => item.provider == MapProvider.independent),
      isTrue,
    );
  });

  test(
    'legacy Google shortcut loads and corrupt coordinates do not break startup',
    () async {
      SharedPreferences.setMockInitialValues({
        'waybi.quick_location.Home':
            '{"name":"Home","latitude":-36.85,"longitude":174.76}',
        'waybi.quick_location.Work': '{"latitude":999,"longitude":174.77}',
      });
      final restored = await QuickLocationStore().load();
      expect(restored.keys, ['Home']);
      expect(restored['Home']!.provider, MapProvider.google);
    },
  );
}
