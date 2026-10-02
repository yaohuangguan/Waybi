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
  });

  final String id;
  final String motorway;
  final String name;
  final String direction;
  final String congestion;
  final TrafficFlowLevel level;
  final GeoPoint start;
  final GeoPoint end;

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
  });

  final List<TrafficFlowSegment> segments;
  final String syncStatus;
  final DateTime? sourceUpdatedAt;
  final DateTime? checkedAt;
}
