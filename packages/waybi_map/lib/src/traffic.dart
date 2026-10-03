import 'geometry.dart';
import 'layers.dart';

abstract interface class TrafficFlowLayerSource
    implements MapLayerSource<TrafficFlowSnapshot> {}

enum TrafficFlowLevel { free, moderate, heavy, unknown }

class TrafficFlowSegment {
  const TrafficFlowSegment({
    required this.id,
    required this.motorway,
    required this.name,
    required this.direction,
    required this.congestion,
    required this.level,
    required this.start,
    required this.end,
    this.geometry = const [],
    this.geometryQuality = 'unmatched',
  });

  final String id;
  final String motorway;
  final String name;
  final String direction;
  final String congestion;
  final TrafficFlowLevel level;
  final GeoPoint start;
  final GeoPoint end;
  final List<GeoPoint> geometry;
  final String geometryQuality;
  bool get hasRoadGeometry => geometryQuality == 'road-matched' && geometry.length >= 2 && geometry.every((p) => p.isValid);

  factory TrafficFlowSegment.fromJson(Map<String, dynamic> json) {
    final start = json['start'] as Map<String, dynamic>? ?? const {};
    final end = json['end'] as Map<String, dynamic>? ?? const {};
    final level = switch (json['level']?.toString()) {
      'free' => TrafficFlowLevel.free,
      'moderate' => TrafficFlowLevel.moderate,
      'heavy' => TrafficFlowLevel.heavy,
      _ => TrafficFlowLevel.unknown,
    };
    return TrafficFlowSegment(
      geometryQuality: json['geometryQuality']?.toString() ?? 'unmatched',
      geometry: ((json['geometry'] as Map<String, dynamic>?)?['coordinates'] as List? ?? const [])
          .whereType<List>().where((p) => p.length >= 2 && p[0] is num && p[1] is num)
          .map((p) => GeoPoint((p[1] as num).toDouble(), (p[0] as num).toDouble())).toList(growable: false),
      id: json['id']?.toString() ?? '',
      motorway: json['motorway']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      direction: json['direction']?.toString() ?? '',
      congestion: json['congestion']?.toString() ?? '',
      level: level,
      start: GeoPoint(
        (start['latitude'] as num?)?.toDouble() ?? 0,
        (start['longitude'] as num?)?.toDouble() ?? 0,
      ),
      end: GeoPoint(
        (end['latitude'] as num?)?.toDouble() ?? 0,
        (end['longitude'] as num?)?.toDouble() ?? 0,
      ),
    );
  }
}

class TrafficFlowSnapshot {
  const TrafficFlowSnapshot({
    required this.segments,
    required this.syncStatus,
    this.sourceUpdatedAt,
    this.checkedAt,
    this.tileOverlay,
    this.coverage = 'published-nzta-sections',
  });

  final List<TrafficFlowSegment> segments;
  final String syncStatus;
  final DateTime? sourceUpdatedAt;
  final DateTime? checkedAt;
  final TrafficTileOverlay? tileOverlay;
  final String coverage;
}

/// Provider-neutral raster traffic capability; keys never reach the client.
class TrafficTileOverlay {
  const TrafficTileOverlay({required this.provider, required this.tileTemplate, required this.attribution});
  final String provider, tileTemplate, attribution;
}
