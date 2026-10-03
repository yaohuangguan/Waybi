import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/map_provider.dart';

class QuickLocationStore {
  Future<void> save(
    String label,
    PlaceSummary place,
    MapProvider provider,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'waybi.quick_location.$label',
      jsonEncode({
        'name': place.name,
        'address': place.address,
        'latitude': place.location.latitude,
        'longitude': place.location.longitude,
        'provider': provider.name,
      }),
    );
  }

  Future<Map<String, ({PlaceSummary place, MapProvider provider})>>
  load() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, ({PlaceSummary place, MapProvider provider})>{};
    for (final label in ['Home', 'Work']) {
      final value = prefs.getString('waybi.quick_location.$label');
      if (value == null) continue;
      try {
        final item = jsonDecode(value) as Map<String, dynamic>;
        final point = GeoPoint(
          (item['latitude'] as num).toDouble(),
          (item['longitude'] as num).toDouble(),
        );
        if (!point.isValid) continue;
        result[label] = (
          place: PlaceSummary(
            name: item['name']?.toString() ?? label,
            address: item['address']?.toString() ?? '',
            location: point,
          ),
          provider: MapProvider.values.firstWhere(
            (provider) => provider.name == item['provider'],
            orElse: () => MapProvider.google,
          ),
        );
      } catch (_) {
        /* Ignore a damaged old shortcut without blocking startup. */
      }
    }
    return result;
  }
}
