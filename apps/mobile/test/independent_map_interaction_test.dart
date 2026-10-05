import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/map_layer_settings.dart';
import 'package:waybi_mobile/domain/safety_camera.dart';
import 'package:waybi_mobile/domain/traffic_flow.dart';
import 'package:waybi_mobile/domain/road_event.dart';
import 'package:waybi_mobile/providers/independent_map_renderer.dart';
import 'package:waybi_mobile/providers/provider_contracts.dart';
import 'package:waybi_mobile/providers/location_marker_art.dart';

class RecordingMapPlatform extends ml.MapLibrePlatform {
  int builds = 0;
  bool initialized = false;
  EdgeInsets padding = EdgeInsets.zero;
  final updates = <String>[];
  final sources = <String, Map<String, dynamic>>{};
  final moves = <ml.CameraUpdate>[];
  List<Map<String, dynamic>> features = [];
  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    void Function(int) onCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestures,
  ) {
    builds++;
    if (!initialized) {
      initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => onCreated(0));
    }
    return const ColoredBox(color: Colors.grey);
  }

  @override
  Future<void> initPlatform(int id) async {}
  @override
  Future<ml.CameraPosition?> updateMapOptions(
    Map<String, dynamic> options,
  ) async => null;
  @override
  Future<bool?> moveCamera(ml.CameraUpdate cameraUpdate) async {
    moves.add(cameraUpdate);
    return true;
  }

  @override
  Future<bool> easeCamera(
    ml.CameraUpdate cameraUpdate, {
    Duration? duration,
    ml.CameraAnimationInterpolation? interpolation,
  }) async {
    moves.add(cameraUpdate);
    return true;
  }

  @override
  Future<void> updateContentInsets(EdgeInsets insets, bool animated) async {
    padding = insets;
  }

  @override
  Future<void> setGeoJsonSource(String id, Map<String, dynamic> data) async {
    updates.add(id);
    sources[id] = data;
  }

  @override
  Future<List> queryRenderedFeaturesInRect(
    Rect rect,
    List<String> layers,
    String? filter,
  ) async => features;
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  testWidgets(
    'native camera frames do not rebuild map; pinch pauses follow; GPS only updates the puck',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final platform = RecordingMapPlatform();
      final original = ml.MapLibrePlatform.createInstance;
      ml.MapLibrePlatform.createInstance = () => platform;
      addTearDown(() => ml.MapLibrePlatform.createInstance = original);
      var following = true;
      var bottom = 215.0;
      var location = const GeoPoint(-36.8485, 174.7633);
      var panCalls = 0;
      RoadEvent? tappedEvent;
      const report = RoadEvent(
        id: 'report-1',
        type: RoadEventType.roadClosure,
        location: GeoPoint(-36.849, 174.764),
        source: RoadEventSource(
          provider: 'Waybi drivers',
          country: 'GLOBAL',
          sourceId: 'report-1',
        ),
      );
      MapRenderer? renderer;
      StateSetter? update;
      PlaceSummary? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, state) {
              update = state;
              return Scaffold(
                body: IndependentMapRenderer(
                  initialViewport: MapViewportState(center: location, zoom: 17),
                  layers: const MapLayerSettings(traffic: true),
                  locationMarker: LocationMarkerStyle.kiwi,
                  locationEnabled: true,
                  following: following,
                  moving: true,
                  language: 'zh',
                  location: location,
                  heading: 45,
                  contentPadding: EdgeInsets.fromLTRB(16, 180, 16, bottom),
                  cameras: const [
                    SafetyCamera(
                      id: 'cam-1',
                      name: 'Queen Street camera',
                      region: 'Auckland',
                      suburb: 'City Centre',
                      location: 'Queen Street',
                      type: 'Fixed speed camera',
                      latitude: -36.849,
                      longitude: 174.764,
                    ),
                  ],
                  onCamera: (_) {},
                  roadEvents: const [report],
                  onRoadEvent: (event) => tappedEvent = event,
                  trafficSegments: const [
                    TrafficFlowSegment(
                      id: 'nzta:traffic:2',
                      motorway: 'Northern Motorway',
                      name: 'Oteha Valley Rd - Upper Harb Hwy',
                      direction: 'Southbound',
                      congestion: 'Heavy',
                      level: TrafficFlowLevel.heavy,
                      start: GeoPoint(-36.84, 174.75),
                      end: GeoPoint(-36.85, 174.76),
                      geometryQuality: 'road-matched',
                      geometry: [
                        GeoPoint(-36.84, 174.75),
                        GeoPoint(-36.845, 174.752),
                        GeoPoint(-36.85, 174.76),
                      ],
                    ),
                  ],
                  routePaths: const [
                    MapRoutePath(
                      id: 'route-1',
                      active: true,
                      points: [
                        GeoPoint(-36.8485, 174.7633),
                        GeoPoint(-36.8518, 174.7634),
                      ],
                    ),
                    MapRoutePath(
                      id: 'route-2',
                      points: [
                        GeoPoint(-36.8485, 174.7633),
                        GeoPoint(-36.8520, 174.7650),
                      ],
                    ),
                    MapRoutePath(
                      id: 'route-3',
                      points: [
                        GeoPoint(-36.8485, 174.7633),
                        GeoPoint(-36.8522, 174.7618),
                      ],
                    ),
                  ],
                  selectedPlace: null,
                  explorePlaces: const [],
                  onExplorePlace: (_) {},
                  onReady: (map) => renderer = map,
                  onViewportChanged: (_) {},
                  onMapPlace: (place) => selected = place,
                  onBlankTap: () {},
                  onUserPan: () {
                    panCalls++;
                    state(() => following = false);
                  },
                  styleLoader: ({required dark, required language}) async =>
                      '{"version":8,"sources":{},"layers":[]}',
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (final style in LocationMarkerStyle.values) {
          await LocationMarkerArt.practicePng(style);
        }
        await LocationMarkerArt.glowPng();
        for (final kind in CameraKind.values) {
          await LocationMarkerArt.cameraPng(kind);
        }
        await LocationMarkerArt.finishFlagPng();
      });
      await tester.runAsync(() async {
        platform.onMapStyleLoadedPlatform.call(null);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(renderer, isNotNull);
      final map = tester.widget<ml.MapLibreMap>(find.byType(ml.MapLibreMap));
      expect(map.attributionButtonMargins, const Point(8, 8));
      final pins = platform.sources['waybi-pins']!['features'] as List;
      final eventPin = pins.firstWhere(
        (feature) => feature['id'] == 'event:report-1',
      );
      expect(eventPin['properties']['icon'], 'waybi-event-roadClosure');
      platform.features = [Map<String, dynamic>.from(eventPin as Map)];
      map.onMapClick!(
        Point<double>(190, 400),
        const ml.LatLng(-36.849, 174.764),
      );
      await tester.pumpAndSettle();
      expect(tappedEvent, report);
      platform.features = [];
      final camera = pins.firstWhere(
        (feature) => feature['id'] == 'camera:cam-1',
      );
      expect(camera['properties']['kind'], 'camera');
      expect(
        camera['properties']['icon'].toString(),
        startsWith('waybi-camera-'),
      );
      expect(
        pins.any(
          (feature) =>
              feature['id'] == 'destination' &&
              feature['properties']['kind'] == 'destination',
        ),
        isTrue,
      );
      final traffic =
          platform.sources['waybi-traffic']!['features'] as List<dynamic>;
      expect(traffic, hasLength(1));
      expect(traffic.single['properties']['level'], 'heavy');
      final routes =
          platform.sources['waybi-route']!['features'] as List<dynamic>;
      expect(routes, hasLength(3));
      expect(
        routes.where((feature) => feature['properties']['active'] == true),
        hasLength(1),
      );
      final builds = platform.builds;
      platform.updates.clear();
      for (var i = 0; i < 120; i++) {
        platform.onCameraMovePlatform.call(
          const ml.CameraPosition(target: ml.LatLng(-36.85, 174.76), zoom: 15),
        );
        await tester.pump(const Duration(milliseconds: 8));
      }
      expect(platform.builds, builds);
      expect(platform.updates, isEmpty);
      // iOS can send the exact final bearing only with its idle event.
      platform.onCameraIdlePlatform.call(
        const ml.CameraPosition(
          target: ml.LatLng(-36.85, 174.76),
          zoom: 15,
          bearing: 95,
        ),
      );
      await tester.pump();
      expect(renderer!.viewport.bearing, 95);
      expect(platform.builds, builds);
      final a = await tester.startGesture(const Offset(60, 340), pointer: 1);
      final b = await tester.startGesture(const Offset(320, 500), pointer: 2);
      await a.moveTo(const Offset(140, 380));
      await b.moveTo(const Offset(240, 450));
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      expect(following, false);
      expect(panCalls, 1);
      expect(renderer!.viewport.zoom, 15);
      platform.moves.clear();
      platform.updates.clear();
      update!(() => location = const GeoPoint(-36.8486, 174.7634));
      await tester.pumpAndSettle();
      expect(platform.moves, isEmpty);
      expect(platform.updates, ['waybi-driver']);
      expect(renderer!.viewport.zoom, 15);
      update!(() {
        following = true;
        bottom = 370;
      });
      await tester.pumpAndSettle();
      expect(platform.padding.bottom, 370);
      expect(platform.moves, isNotEmpty);
      final features = platform.sources['waybi-driver']!['features'] as List;
      expect(features.single['geometry']['coordinates'], [174.7634, -36.8486]);
      expect(features.single['properties']['heading'], 45);
      // The renderer queries visible tile POIs, not an external geocoder per tap.
      platform.features = [
        {
          'id': 123,
          'properties': {'name': 'Aotea Square', 'class': 'park'},
          'geometry': {
            'type': 'Point',
            'coordinates': [174.7634, -36.8518],
          },
        },
      ];
      map.onMapClick!(
        const Point(150, 300),
        const ml.LatLng(-36.8518, 174.7634),
      );
      await tester.pumpAndSettle();
      expect(selected!.name, 'Aotea Square');
      expect(selected!.reference!.provider, 'osm');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
