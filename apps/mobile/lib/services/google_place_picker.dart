import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/api_config.dart';
import '../domain/map_provider.dart';

class GooglePickerResult {
  const GooglePickerResult({
    required this.query,
    this.place,
    this.cancelled = false,
  });
  final String query;
  final PlaceSummary? place;
  final bool cancelled;
}

/// Only the official UI Kit result is accepted on Waybi Map. This bridge does
/// not turn ordinary Places API content into map-compatible search results.
class GooglePlacePicker {
  static const channel = MethodChannel('waybi/google_place_picker');
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  static Future<GooglePickerResult> open({
    required String query,
    required String language,
    GeoPoint? near,
  }) async {
    if (!supported) return GooglePickerResult(query: query);
    final uri = Uri.parse('$workerBaseUrl/api/search/google').replace(
      queryParameters: {
        'q': query,
        'lang': language,
        if (near != null) 'near': '${near.longitude},${near.latitude}',
      },
    );
    try {
      final raw = await channel.invokeMethod<String>('open', {
        'url': uri.toString(),
        'language': language,
      });
      if (raw == null) return GooglePickerResult(query: query, cancelled: true);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final input = (data['query'] as String? ?? query).trim();
      if (data['status'] != 'selected') return GooglePickerResult(query: input);
      final id = data['id'], lat = data['latitude'], lng = data['longitude'];
      if (id is! String ||
          id.isEmpty ||
          id.length > 256 ||
          lat is! num ||
          lng is! num ||
          !GeoPoint(lat.toDouble(), lng.toDouble()).isValid ||
          input.isEmpty ||
          input.length > 120) {
        return GooglePickerResult(query: query);
      }
      return GooglePickerResult(
        query: input,
        place: PlaceSummary(
          // Retain the user's own query; Google's names, addresses, photos and
          // reviews stay in the attributed UI component and are never scraped.
          name: input,
          location: GeoPoint(lat.toDouble(), lng.toDouble()),
          reference: ProviderReference('google-ui-kit', id),
        ),
      );
    } catch (_) {
      return GooglePickerResult(query: query);
    }
  }
}
