import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/map_provider.dart';

class QuickLocationStore {
  static const _ownerKey = 'waybi.quick_location.owner_user_id';

  Future<String?> ownerUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ownerKey);
  }

  Future<void> save(
    String label,
    PlaceSummary place,
    MapProvider provider, {
    String? ownerUserId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final storedOwner = prefs.getString(_ownerKey);
    final nextOwner = ownerUserId == null || ownerUserId.isEmpty
        ? null
        : ownerUserId;
    final switchingAccounts = storedOwner != null && storedOwner != nextOwner;
    if (switchingAccounts) {
      await prefs.remove('waybi.quick_location.Home');
      await prefs.remove('waybi.quick_location.Work');
    }
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
    if (nextOwner == null) {
      await prefs.remove(_ownerKey);
    } else {
      await prefs.setString(_ownerKey, nextOwner);
    }
  }

  Future<Map<String, ({PlaceSummary place, MapProvider provider})>> load({
    String? ownerUserId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final storedOwner = prefs.getString(_ownerKey);
    if (storedOwner != null && storedOwner != ownerUserId) return {};

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
