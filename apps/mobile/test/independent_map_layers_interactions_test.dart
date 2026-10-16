import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/map_layer_settings.dart';
import 'package:waybi_mobile/domain/safety_camera.dart';
import 'package:waybi_mobile/domain/traffic_flow.dart';
import 'package:waybi_mobile/domain/road_event.dart';
import 'package:waybi_mobile/domain/transit_lane.dart';
import 'package:waybi_mobile/domain/transit_review_corridor.dart';
import 'package:waybi_mobile/providers/independent_map_renderer.dart';
import 'package:waybi_mobile/providers/provider_contracts.dart';
import 'package:waybi_mobile/providers/location_marker_art.dart';

import 'support/recording_map_platform.dart';

const points = [
  GeoPoint(-36.85, 174.76),
  GeoPoint(-36.851, 174.76),
  GeoPoint(-36.852, 174.76),
];
const lane = TransitLane(
  id: 'lane',
  roadName: 'Bus road',
  kind: 'Bus',
  schedule: TransitSchedule(days: [], windows: [], known: false),
  points: points,
);
const corridor = TransitReviewCorridor(
  id: 'review',
  city: 'Auckland',
  roadName: 'Check signs',
  authority: 'Council',
  ruleSummary: 'Check signs',
  ruleSummaryZh: '查看路牌',
  ruleSource: 'https://example.test/rules',
  geometrySource: 'Council centreline',
  points: points,
);
const camera = SafetyCamera(
  id: 'cam',
  name: 'Camera',
  region: 'Auckland',
  suburb: 'CBD',
  location: 'Road',
  type: 'Fixed speed camera',
  latitude: -36.85,
  longitude: 174.76,
);
const event = RoadEvent(
  id: 'event',
  type: RoadEventType.roadClosure,
  location: GeoPoint(-36.85, 174.76),
  source: RoadEventSource(provider: 'NZTA', country: 'NZ', sourceId: 'event'),
  geometry: points,
  metadata: {'geometryType': 'LINESTRING'},
);
const flow = TrafficFlowSegment(
  id: 'flow',
  motorway: 'SH1',
  name: 'Road',
  direction: 'South',
  congestion: 'Heavy',
  level: TrafficFlowLevel.heavy,
  start: GeoPoint(-36.85, 174.76),
  end: GeoPoint(-36.852, 174.76),
  geometryQuality: 'road-matched',
  geometry: points,
);

class Fixture {
  Fixture(this.t);
  final WidgetTester t;
  final platform = RecordingMapPlatform();
  MapRenderer? renderer;
  StateSetter? update;
  bool traffic = true;
  bool active = false;
  TrafficTileOverlay? overlay;
  int styleCalls = 0;
  bool failStyle = false;
  final selected = <String>[];
  Future<void> pump() async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 30));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(t.takeException(), isNull);
  }

  Future<void> boot() async {
    final original = ml.MapLibrePlatform.createInstance;
    ml.MapLibrePlatform.createInstance = () => platform;
    addTearDown(() => ml.MapLibrePlatform.createInstance = original);
    await t.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, s) {
            update = s;
            return Scaffold(
              body: IndependentMapRenderer(
                initialViewport: const MapViewportState(
                  center: GeoPoint(-36.85, 174.76),
                  zoom: 16,
                ),
                layers: MapLayerSettings(traffic: traffic, transitLanes: true),
                locationMarker: LocationMarkerStyle.kiwi,
                locationEnabled: true,
                following: false,
                moving: active,
                navigating: active,
                driving: active,
                heading: 0,
                contentPadding: EdgeInsets.zero,
                language: 'en',
                location: const GeoPoint(-36.85, 174.76),
                cameras: const [camera],
                onCamera: (_) => selected.add('camera'),
                roadEvents: const [event],
                onRoadEvent: (_) => selected.add('event'),
                transitLanes: const [lane],
                onTransitLane: (_) => selected.add('lane'),
                transitReviewCorridors: const [corridor],
                onTransitReviewCorridor: (_) => selected.add('review'),
                trafficSegments: const [flow],
                trafficTileOverlay: overlay,
                trafficFresh: true,
                routePaths: active
                    ? const [
                        MapRoutePath(id: 'route', points: points, active: true),
                      ]
                    : const [],
                selectedPlace: const PlaceSummary(
                  name: 'Selected',
                  address: 'Road',
                  location: GeoPoint(-36.851, 174.76),
                ),
                explorePlaces: const [
                  PlaceSummary(
                    name: 'Explore',
                    address: 'Road',
                    location: GeoPoint(-36.852, 174.76),
                  ),
                ],
                onExplorePlace: (_) => selected.add('explore'),
                onReady: (r) => renderer = r,
                onViewportChanged: (_) {},
                onMapPlace: (p) => selected.add(p.name),
                onBlankTap: () => selected.add('blank'),
                onUserPan: () => selected.add('pan'),
                onGestureChanged: (v) => selected.add('gesture:$v'),
                styleLoader:
                    ({
                      required dark,
                      required language,
                      required center,
                    }) async {
                      styleCalls++;
                      if (failStyle) throw StateError('Style unavailable');
                      return '{"version":8,"sources":{},"layers":[]}';
                    },
              ),
            );
          },
        ),
      ),
    );
    await pump();
    if (failStyle) return;
    await t.runAsync(() async {
      for (final style in LocationMarkerStyle.values) {
        await LocationMarkerArt.practicePng(style);
      }
      await LocationMarkerArt.glowPng();
      await LocationMarkerArt.finishFlagPng();
      for (final kind in CameraKind.values) {
        await LocationMarkerArt.cameraPng(kind);
      }
    });
    final native = t.widget<ml.MapLibreMap>(find.byType(ml.MapLibreMap));
    await t.runAsync(() async {
      native.onStyleLoadedCallback!();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    for (var i = 0; i < 40 && renderer == null; i++) {
      await pump();
    }
    expect(renderer, isNotNull);
  }

  Future<void> tap(String id) async {
    platform.features = [
      {
        'id': id,
        'properties': {'kind': 'overlay'},
      },
    ];
    t.widget<ml.MapLibreMap>(find.byType(ml.MapLibreMap)).onMapClick!(
      const Point<double>(100, 150),
      const ml.LatLng(-36.85, 174.76),
    );
    await pump();
  }
}

void main() {
  testWidgets(
    'overlay map taps reach the correct camera, lane, review, event and explore actions',
    (t) async {
      final f = Fixture(t);
      await f.boot();
      for (final id in [
        'camera:cam',
        'transit:lane',
        'review:review',
        'event:event',
        'explore:0',
      ]) {
        await f.tap(id);
      }
      expect(f.selected, ['camera', 'lane', 'review', 'event', 'explore']);
      final eventFeatures =
          f.platform.sources['waybi-road-events']!['features'] as List;
      expect(eventFeatures.any((v) => v['id'] == 'event:event'), isTrue);
      final pins = f.platform.sources['waybi-pins']!['features'] as List;
      expect(pins.any((v) => v['id'] == 'selected'), isTrue);
      expect(pins.any((v) => v['id'] == 'explore:0'), isTrue);
      await f.tap('camera:missing');
      expect(f.selected.last, 'blank');
      await t.pumpWidget(const SizedBox());
      await f.pump();
    },
  );
  testWidgets(
    'fitting a route clears deck insets and selecting a place restores its content padding',
    (t) async {
      final f = Fixture(t);
      await f.boot();
      final focus = f.renderer as PlaceFocusMapRenderer;
      await t.runAsync(() => focus.focusPlace(points[1], bottomInset: 320));
      await f.pump();
      expect(f.platform.padding.bottom, 320);
      await t.runAsync(() => focus.clearContentPadding());
      await f.pump();
      expect(f.platform.padding.bottom, isNot(320));
      final count = f.platform.moves.length;
      await t.runAsync(
        () => (f.renderer as RouteMapRenderer).fitRoute([
          points.first,
        ], bottomInset: 250),
      );
      expect(f.platform.moves, hasLength(count));
      await t.runAsync(
        () =>
            (f.renderer as RouteMapRenderer).fitRoute(points, bottomInset: 250),
      );
      expect(f.platform.padding, EdgeInsets.zero);
      expect(f.platform.moves.length, count + 1);
      expect(f.platform.moves.last.toJson(), contains('newLatLngBounds'));
      await t.pumpWidget(const SizedBox());
      await f.pump();
    },
  );
  testWidgets(
    'route traffic stays on the active route and raster layers are replaced and removed correctly',
    (t) async {
      final f = Fixture(t)
        ..active = true
        ..overlay = const TrafficTileOverlay(
          provider: 'test',
          tileTemplate: 'https://traffic.example.test/{z}/{x}/{y}.png',
          attribution: 'Traffic source',
        );
      await f.boot();
      final traffic =
          f.platform.sources['waybi-route-traffic']!['features'] as List;
      expect(traffic.any((v) => v['id'] == 'route-flow'), isTrue);
      expect(
        f.platform.operations.any((v) => v.contains('addRasterLayer')),
        isTrue,
      );
      f.update!(
        () => f.overlay = const TrafficTileOverlay(
          provider: 'test',
          tileTemplate: 'https://traffic.example.test/new/{z}/{x}/{y}.png',
          attribution: 'Traffic source',
        ),
      );
      await f.pump();
      expect(
        f.platform.operations.where((v) => v.contains('removeLayer')),
        isNotEmpty,
      );
      f.update!(() => f.traffic = false);
      await f.pump();
      expect(f.platform.sources['waybi-traffic']!['features'], isEmpty);
      expect(
        f.platform.operations.where((v) => v.contains('removeSource')),
        isNotEmpty,
      );
      await t.pumpWidget(const SizedBox());
      await f.pump();
    },
  );
  testWidgets('failed map styling offers an explicit reload action', (t) async {
    final f = Fixture(t)..failStyle = true;
    await f.boot();
    expect(find.text('Reload map'), findsOneWidget);
    final before = f.styleCalls;
    f.failStyle = false;
    await t.tap(find.text('Reload map'));
    await f.pump();
    expect(f.styleCalls, before + 1);
    expect(find.byType(ml.MapLibreMap), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await f.pump();
  });
  testWidgets(
    'English names and long-press pins remain selectable after native feature queries',
    (t) async {
      final f = Fixture(t);
      await f.boot();
      f.platform.features = [
        {
          'id': 123,
          'properties': {'name:en': 'English café', 'class': 'cafe'},
          'geometry': {
            'type': 'Point',
            'coordinates': [174.76, -36.85],
          },
        },
      ];
      final native = t.widget<ml.MapLibreMap>(find.byType(ml.MapLibreMap));
      native.onMapClick!(
        const Point<double>(100, 150),
        const ml.LatLng(-36.85, 174.76),
      );
      await f.pump();
      expect(f.selected.last, 'English café');
      native.onMapLongClick!(
        const Point<double>(100, 150),
        const ml.LatLng(-36.85, 174.76),
      );
      await f.pump();
      expect(f.selected.last, 'Dropped pin');
      final gesture = await t.startGesture(
        t.getCenter(find.byType(ml.MapLibreMap)),
      );
      await gesture.cancel();
      await f.pump();
      expect(f.selected, contains('gesture:false'));
      await t.pumpWidget(const SizedBox());
      await f.pump();
    },
  );
}
