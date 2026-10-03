import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_map/waybi_map.dart';
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
    final stack = WaybiMapStack(
      safetyCameras: _FakeCameraSource(),
      traffic: _FakeTrafficSource(),
      roadIntelligence: _FakeRoadIntelligenceSource(),
    );
    expect(stack.safetyCameras, isNotNull);
    expect(stack.traffic, isNotNull);
    expect(stack.roadIntelligence, isNotNull);
    expect(
      stack.layers
          .singleWhere((layer) => layer.id == 'traffic')
          .enabledByDefault,
      isFalse,
    );
    expect(
      stack.layers
          .singleWhere((layer) => layer.id == 'road-intelligence')
          .b2bEntitlement,
      'road-intelligence',
    );
  });

  test(
    'default camera source loads and clips Waybi camera positions',
    () async {
      final source = WaybiSafetyCameraSource(
        baseUrl: 'https://example.test',
        client: MockClient((request) async {
          expect(request.url.path, '/api/cameras');
          return http.Response(
            jsonEncode({
              'syncStatus': 'live',
              'sourceUpdatedAt': '2026-10-03T10:00:00+13:00',
              'cameras': [
                {
                  'id': 'akl',
                  'name': 'Auckland camera',
                  'region': 'Auckland',
                  'suburb': 'Newmarket',
                  'location': 'SH1',
                  'type': 'Spot speed',
                  'latitude': -36.87,
                  'longitude': 174.78,
                },
                {
                  'id': 'wlg',
                  'name': 'Wellington camera',
                  'region': 'Wellington',
                  'suburb': 'Ngauranga',
                  'location': 'SH1',
                  'type': 'Spot speed',
                  'latitude': -41.24,
                  'longitude': 174.81,
                },
              ],
            }),
            200,
          );
        }),
      );
      const bounds = MapBounds(
        southWest: GeoPoint(-37.2, 174.4),
        northEast: GeoPoint(-36.5, 175.2),
      );

      final snapshot = await source.load(bounds);

      expect(snapshot.syncStatus, 'live');
      expect(snapshot.cameras.map((camera) => camera.id), ['akl']);
      source.dispose();
    },
  );

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

class _FakeCameraSource implements SafetyCameraLayerSource {
  @override
  Future<SafetyCameraSnapshot> load(MapBounds bounds) async =>
      const SafetyCameraSnapshot(cameras: [], syncStatus: 'live');
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
