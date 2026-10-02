import 'dart:convert';

import 'package:http/http.dart' as http;

import 'geometry.dart';
import 'layers.dart';

class SafetyCamera {
  const SafetyCamera({
    required this.id,
    required this.name,
    required this.region,
    required this.suburb,
    required this.location,
    required this.type,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String name;
  final String region;
  final String suburb;
  final String location;
  final String type;
  final double latitude;
  final double longitude;

  GeoPoint get point => GeoPoint(latitude, longitude);

  factory SafetyCamera.fromJson(Map<String, dynamic> json) => SafetyCamera(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    region: json['region']?.toString() ?? '',
    suburb: json['suburb']?.toString() ?? '',
    location: json['location']?.toString() ?? '',
    type: json['type']?.toString() ?? '',
    latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
    longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
  );
}

class SafetyCameraSnapshot {
  const SafetyCameraSnapshot({
    required this.cameras,
    this.syncStatus = 'unknown',
    this.sourceUpdatedAt,
    this.checkedAt,
  });

  final List<SafetyCamera> cameras;
  final String syncStatus;
  final DateTime? sourceUpdatedAt;
  final DateTime? checkedAt;
}

abstract interface class SafetyCameraLayerSource
    implements MapLayerSource<SafetyCameraSnapshot> {}

/// Default camera source shipped with Kiwi Lens Map.
///
/// It uses the public Kiwi Lens camera endpoint so a standalone map gets the
/// official camera positions without requiring the host app to build another
/// adapter. Hosts can replace this source with their own implementation.
class KiwiLensSafetyCameraSource implements SafetyCameraLayerSource {
  KiwiLensSafetyCameraSource({
    http.Client? client,
    this.baseUrl = 'https://kiwi-lens.nzs.workers.dev',
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final String baseUrl;

  @override
  Future<SafetyCameraSnapshot> load(MapBounds bounds) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/api/cameras'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Camera feed unavailable: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final cameras = (body['cameras'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SafetyCamera.fromJson)
        .where(
          (camera) => camera.point.isValid && bounds.contains(camera.point),
        )
        .toList(growable: false);
    return SafetyCameraSnapshot(
      cameras: cameras,
      syncStatus: body['syncStatus']?.toString() ?? 'unknown',
      sourceUpdatedAt: DateTime.tryParse(
        body['sourceUpdatedAt']?.toString() ?? '',
      ),
      checkedAt: DateTime.tryParse(body['checkedAt']?.toString() ?? ''),
    );
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
