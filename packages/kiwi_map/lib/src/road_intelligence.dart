import 'geometry.dart';
import 'layers.dart';

/// Provider-neutral overlay contract. Kiwi Lens can feed this from its own
/// Road Intelligence API; a B2B consumer can provide another implementation
/// without coupling the map renderer to authentication or HTTP.
abstract interface class RoadIntelligenceLayerSource
    implements MapLayerSource<RoadIntelligenceLayerSnapshot> {}

class RoadIntelligenceLayerSnapshot {
  const RoadIntelligenceLayerSnapshot({
    required this.features,
    this.sourceStatus = 'unknown',
    this.updatedAt,
  });

  final List<RoadIntelligenceFeature> features;
  final String sourceStatus;
  final DateTime? updatedAt;

  /// Decodes the stable event shape returned by Kiwi Lens Road Intelligence.
  /// Transport/authentication deliberately remain the caller's responsibility.
  factory RoadIntelligenceLayerSnapshot.fromApiJson(Map<String, dynamic> json) {
    final features = (json['events'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RoadIntelligenceFeature.fromApiJson)
        .whereType<RoadIntelligenceFeature>()
        .toList(growable: false);
    final sources = (json['sources'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final stale = sources.any((source) => source['stale'] == true);
    return RoadIntelligenceLayerSnapshot(
      features: features,
      sourceStatus: stale ? 'stale' : 'live',
      updatedAt: DateTime.tryParse(json['generatedAt']?.toString() ?? ''),
    );
  }
}

enum RoadIntelligenceFeatureKind {
  safetyCamera,
  incident,
  roadworks,
  roadClosure,
  congestion,
  flooding,
  slip,
  other,
}

class RoadIntelligenceFeature {
  const RoadIntelligenceFeature({
    required this.id,
    required this.kind,
    required this.location,
    this.geometry = const [],
    this.label = '',
    this.severity = '',
    this.metadata = const {},
  });

  final String id;
  final RoadIntelligenceFeatureKind kind;
  final GeoPoint location;
  final List<GeoPoint> geometry;
  final String label;
  final String severity;
  final Map<String, Object?> metadata;

  static RoadIntelligenceFeature? fromApiJson(Map<String, dynamic> json) {
    final locationJson = json['location'];
    if (locationJson is! Map<String, dynamic>) return null;
    final latitude = (locationJson['latitude'] as num?)?.toDouble();
    final longitude = (locationJson['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) return null;
    final location = GeoPoint(latitude, longitude);
    if (!location.isValid) return null;

    final geometry = (json['geometry'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((point) {
          final lat = (point['latitude'] as num?)?.toDouble();
          final lon = (point['longitude'] as num?)?.toDouble();
          return lat == null || lon == null ? null : GeoPoint(lat, lon);
        })
        .whereType<GeoPoint>()
        .where((point) => point.isValid)
        .toList(growable: false);

    return RoadIntelligenceFeature(
      id: json['id']?.toString() ?? '',
      kind: switch (json['type']?.toString()) {
        'safetyCamera' => RoadIntelligenceFeatureKind.safetyCamera,
        'incident' => RoadIntelligenceFeatureKind.incident,
        'roadworks' => RoadIntelligenceFeatureKind.roadworks,
        'roadClosure' => RoadIntelligenceFeatureKind.roadClosure,
        'congestion' => RoadIntelligenceFeatureKind.congestion,
        'flooding' => RoadIntelligenceFeatureKind.flooding,
        'slip' => RoadIntelligenceFeatureKind.slip,
        _ => RoadIntelligenceFeatureKind.other,
      },
      location: location,
      geometry: geometry,
      label: json['roadName']?.toString() ?? '',
      severity: json['severity']?.toString() ?? '',
      metadata:
          (json['metadata'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry<String, Object?>(key, value),
          ) ??
          const {},
    );
  }
}
