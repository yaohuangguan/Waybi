import 'package:kiwi_map/kiwi_map.dart';
import 'package:test/test.dart';

void main() {
  test('core map contracts stay provider independent', () {
    const point = GeoPoint(-36.8485, 174.7633);
    const viewport = MapViewportState(center: point, zoom: 16);
    expect(point.isValid, isTrue);
    expect(viewport.copyWith(zoom: 17).zoom, 17);
  });

  test('traffic segments decode independently from the app', () {
    final segment = TrafficFlowSegment.fromJson({
      'id': 'sh1-1',
      'motorway': 'SH1',
      'name': 'A - B',
      'direction': 'Southbound',
      'congestion': 'Heavy',
      'level': 'heavy',
      'start': {'latitude': -36.8, 'longitude': 174.7},
      'end': {'latitude': -36.9, 'longitude': 174.8},
    });
    expect(segment.level, TrafficFlowLevel.heavy);
    expect(segment.start.isValid, isTrue);
  });

  test('map core composes optional B2B layers without renderer coupling', () {
    final stack = KiwiMapStack(
      traffic: _FakeTrafficSource(),
      roadIntelligence: _FakeRoadIntelligenceSource(),
    );
    expect(stack.traffic, isNotNull);
    expect(stack.roadIntelligence, isNotNull);
    expect(
      stack.layers
          .singleWhere((layer) => layer.id == 'road-intelligence')
          .b2bEntitlement,
      'road-intelligence',
    );
  });

  test('Road Intelligence API payload decodes as an optional map overlay', () {
    final snapshot = RoadIntelligenceLayerSnapshot.fromApiJson({
      'generatedAt': '2026-10-03T10:00:00+13:00',
      'sources': [
        {'stale': false},
      ],
      'events': [
        {
          'id': 'nzta:camera:1',
          'type': 'safetyCamera',
          'location': {'latitude': -36.85, 'longitude': 174.76},
          'geometry': <Object>[],
          'roadName': 'SH1',
          'severity': 'advisory',
          'metadata': {'cameraType': 'Spot speed'},
        },
      ],
    });

    expect(snapshot.sourceStatus, 'live');
    expect(
      snapshot.features.single.kind,
      RoadIntelligenceFeatureKind.safetyCamera,
    );
    expect(snapshot.features.single.location, const GeoPoint(-36.85, 174.76));
  });
}

class _FakeTrafficSource implements TrafficFlowLayerSource {
  @override
  Future<TrafficFlowSnapshot> load(MapBounds bounds) async =>
      const TrafficFlowSnapshot(segments: [], syncStatus: 'live');
}

class _FakeRoadIntelligenceSource implements RoadIntelligenceLayerSource {
  @override
  Future<RoadIntelligenceLayerSnapshot> load(MapBounds bounds) async =>
      const RoadIntelligenceLayerSnapshot(features: [], sourceStatus: 'live');
}
