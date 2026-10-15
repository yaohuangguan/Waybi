import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:waybi_map/waybi_map.dart';

void main() {
  test(
    'viewport copies preserve omitted camera values and geographic identity',
    () {
      const point = GeoPoint(-36.85, 174.76);
      const original = MapViewportState(
        center: point,
        zoom: 16,
        bearing: 90,
        pitch: 45,
      );
      final moved = original.copyWith(
        center: const GeoPoint(-37, 175),
        zoom: 17,
      );
      expect(moved.center, const GeoPoint(-37, 175));
      expect([moved.zoom, moved.bearing, moved.pitch], [17, 90, 45]);
      expect(point.hashCode, const GeoPoint(-36.85, 174.76).hashCode);
      final restored = GeoPoint(point.latitude, point.longitude);
      expect({point, restored}, hasLength(1));
      expect(point == 'wrong type', isFalse);
    },
  );
  test(
    'bounds reject inverted and invalid latitude and include edge points',
    () {
      const bounds = MapBounds(
        southWest: GeoPoint(-37, 174),
        northEast: GeoPoint(-36, 175),
      );
      expect(bounds.isValid, isTrue);
      expect(bounds.contains(bounds.southWest), isTrue);
      expect(bounds.contains(bounds.northEast), isTrue);
      expect(bounds.contains(const GeoPoint(-35, 174.5)), isFalse);
      expect(
        const MapBounds(
          southWest: GeoPoint(-36, 174),
          northEast: GeoPoint(-37, 175),
        ).isValid,
        isFalse,
      );
      expect(
        const MapBounds(
          southWest: GeoPoint(-91, 174),
          northEast: GeoPoint(-37, 175),
        ).isValid,
        isFalse,
      );
      expect(const MapLayerStatus(state: 'live').isLive, isTrue);
      expect(const MapLayerStatus(state: 'stale').isStale, isTrue);
      expect(const MapLayerStatus().isLive, isFalse);
    },
  );
  test('road intelligence validates each geometry point and preserves event metadata', () {
    final snapshot = RoadIntelligenceLayerSnapshot.fromApiJson({
      'events': [
        for (final type in [
          'safetyCamera',
          'incident',
          'roadworks',
          'roadClosure',
          'congestion',
          'flooding',
          'slip',
          'unknown',
        ])
          {
            'id': type,
            'type': type,
            'location': {'latitude': -36.85, 'longitude': 174.76},
            'geometry': [
              {'latitude': -36.85, 'longitude': 174.76},
              {'latitude': -36.86, 'longitude': 174.77},
              {'latitude': -91, 'longitude': 174},
              {'latitude': -36},
            ],
            'metadata': {'verified': true},
            'roadName': 'SH1',
            'severity': 'major',
          },
        {
          'location': {'latitude': 99, 'longitude': 174},
        },
        {
          'location': {'latitude': -36},
        },
        {'location': null},
      ],
      'sources': [
        {'stale': true},
      ],
      'generatedAt': '2026-10-16T00:00:00Z',
    });
    expect(snapshot.sourceStatus, 'stale');
    expect(snapshot.features, hasLength(8));
    expect(
      snapshot.features.map((e) => e.kind).toSet(),
      RoadIntelligenceFeatureKind.values.toSet(),
    );
    for (final event in snapshot.features) {
      expect(event.geometry, [
        const GeoPoint(-36.85, 174.76),
        const GeoPoint(-36.86, 174.77),
      ]);
      expect(event.metadata, {'verified': true});
      expect(event.label, 'SH1');
    }
  });
  test(
    'traffic advertises road geometry only for validated matching paths',
    () {
      for (final quality in ['road-matched', 'unmatched']) {
        final segment = TrafficFlowSegment.fromJson({
          'id': 'sh1',
          'geometryQuality': quality,
          'geometry': {
            'coordinates': [
              [174, -36],
              [174.1, -36.1],
              ['bad'],
              null,
            ],
          },
        });
        expect(segment.hasRoadGeometry, quality == 'road-matched');
        expect(segment.geometry, hasLength(2));
      }
      final overlay = TrafficTileOverlay(
        provider: 'waybi',
        tileTemplate: 'https://example.invalid/{z}/{x}/{y}',
        attribution: 'Traffic source',
      );
      expect(overlay.attribution, 'Traffic source');
      final snapshot = TrafficFlowSnapshot(
        segments: [],
        syncStatus: 'stale',
        tileOverlay: overlay,
      );
      expect(snapshot.tileOverlay, same(overlay));
    },
  );
  test('default camera stack uses a bounded replaceable owned client and reports feed failures', () async {
    final client = MockClient((_) async => http.Response('{}', 503));
    await http.runWithClient(() async {
      final stack = WaybiMapStack();
      expect(stack.layers.map((e) => e.id), [
        'safety-cameras',
        'traffic',
        'road-intelligence',
      ]);
      final source = stack.safetyCameras as WaybiSafetyCameraSource;
      await expectLater(
        source.load(
          const MapBounds(
            southWest: GeoPoint(-37, 174),
            northEast: GeoPoint(-36, 175),
          ),
        ),
        throwsStateError,
      );
      source.dispose();
    }, () => client);
  });
}
