import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:waybi_mobile/domain/map_layer_settings.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/domain/safety_camera.dart';
import 'package:waybi_mobile/domain/traffic_flow.dart';
import 'package:waybi_mobile/domain/transit_lane.dart';
import 'package:waybi_mobile/drive/drive_engine.dart';
import 'package:waybi_mobile/drive/drive_trail.dart';
import 'package:waybi_mobile/drive/navigation_location_filter.dart';
import 'package:waybi_mobile/drive/route_progress_tracker.dart';
import 'package:waybi_mobile/drive/voice_engine.dart';
import 'package:waybi_mobile/providers/independent_map_renderer.dart';
import 'package:waybi_mobile/providers/independent_navigation_engine.dart';
import 'package:waybi_mobile/providers/location_marker_art.dart';

import 'support/recording_map_platform.dart';

/// Records the bytes each source upload would send over the platform channel.
class MeasuringMapPlatform extends RecordingMapPlatform {
  int bytes = 0;
  int uploads = 0;
  final perSource = <String, int>{};
  @override
  Future<void> setGeoJsonSource(String id, Map<String, dynamic> data) async {
    final size = jsonEncode(data).length;
    bytes += size;
    uploads++;
    perSource[id] = (perSource[id] ?? 0) + size;
    await super.setGeoJsonSource(id, data);
  }
}

class _Voice extends VoiceEngine {
  @override
  Future<void> dispose() async {}
}

/// GPS-driven DriveEngine without platform plugins.
class _Drive extends DriveEngine {
  _Drive() : super(voiceEngine: _Voice());
  LatLng? fix;
  RouteProgressTracker? tracker;
  @override
  LatLng? get snappedLocation => fix;
  @override
  void setRoute(RouteOption? route, {bool preserveAlerts = false}) {
    super.setRoute(route);
    tracker = route == null ? null : RouteProgressTracker(route.points);
  }

  @override
  Future<void> startLocal({Position? initialPosition}) async => active = true;
  @override
  Future<List<TransitLaneMatch>> transitMatchesForRoute(
    RouteOption route,
  ) async => const [];
  @override
  Future<void> speakMessage(String message) async {}
  @override
  Future<void> stop() async {
    active = false;
    setRoute(null);
  }

  void emit(GeoPoint point, DateTime now) {
    fix = LatLng(latitude: point.latitude, longitude: point.longitude);
    latestPosition = Position(
      latitude: point.latitude,
      longitude: point.longitude,
      timestamp: now,
      accuracy: 5,
      altitude: 0,
      heading: 0,
      speed: 100 / 3.6,
      speedAccuracy: 1,
      altitudeAccuracy: 1,
      headingAccuracy: 1,
    );
    speedKph = 100;
    locationAccuracyMeters = 5;
    locationRevision++;
    routeProgress = tracker?.update(
      point,
      time: now,
      accuracyMeters: 5,
      speedKph: 100,
    );
    notifyListeners();
  }
}

/// 4,000 points, ~100 m apart: a 400 km drive (Auckland–Wellington scale).
List<GeoPoint> longRoute() => [
  for (var i = 0; i < 4000; i++)
    GeoPoint(-36.85 - i * .0009, 174.76 + math.sin(i / 40) * .01),
];

void main() {
  testWidgets('400 km navigation: per-fix map cost', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final points = longRoute();
    final route = RouteOption(
      id: 'long',
      mode: WaybiTravelMode.drive,
      durationSeconds: 4 * 3600,
      distanceMeters: 400000,
      points: points,
      provider: 'independent',
      traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
      trafficIntervals: const [],
      steps: [
        for (var i = 0; i < 40; i++)
          RouteStepInfo(
            instruction: 'Continue $i',
            distanceMeters: 10000,
            durationSeconds: 360,
            location: points[i * 100],
            alongRouteMeters: i * 10000.0,
            maneuverType: i == 0 ? 'depart' : 'continue',
          ),
      ],
    );
    // 74 NZTA traffic sections: half follow the route, half are elsewhere.
    final traffic = [
      for (var i = 0; i < 74; i++)
        TrafficFlowSegment(
          id: 'traffic-$i',
          motorway: 'SH1',
          name: 'Section $i',
          direction: 'Southbound',
          congestion: 'Heavy',
          level: TrafficFlowLevel.values[i % 3],
          start: i.isEven ? points[i * 50] : GeoPoint(-41.2 + i * .001, 174.8),
          end: i.isEven
              ? points[i * 50 + 20]
              : GeoPoint(-41.21 + i * .001, 174.81),
          geometryQuality: 'road-matched',
          geometry: i.isEven
              ? points.sublist(i * 50, i * 50 + 21)
              : [
                  GeoPoint(-41.2 + i * .001, 174.8),
                  GeoPoint(-41.21 + i * .001, 174.81),
                ],
        ),
    ];
    final drive = _Drive();
    var now = DateTime(2026, 11, 26, 9);
    final engine = IndependentNavigationEngine(drive, clock: () => now);
    addTearDown(() {
      engine.dispose();
      drive.dispose();
    });
    await engine.start(route);
    final platform = MeasuringMapPlatform();
    final original = ml.MapLibrePlatform.createInstance;
    ml.MapLibrePlatform.createInstance = () => platform;
    addTearDown(() => ml.MapLibrePlatform.createInstance = original);
    StateSetter? update;
    List<MapRoutePath>? override;
    var location = points.first;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, state) {
            update = state;
            return IndependentMapRenderer(
              initialViewport: MapViewportState(center: location, zoom: 16),
              layers: const MapLayerSettings(traffic: true),
              locationMarker: LocationMarkerStyle.kiwi,
              locationEnabled: true,
              following: true,
              navigating: true,
              driving: true,
              moving: true,
              language: 'en',
              location: location,
              cameras: const <SafetyCamera>[],
              onCamera: (_) {},
              roadEvents: const [],
              onRoadEvent: (_) {},
              trafficSegments: traffic,
              // main.dart reads the engine getter on every rebuild.
              routePaths: override ?? engine.displayPaths,
              selectedPlace: null,
              explorePlaces: const [],
              onExplorePlace: (_) {},
              onReady: (_) {},
              onViewportChanged: (_) {},
              onMapPlace: (_) {},
              onBlankTap: () {},
              onUserPan: () {},
              styleLoader: ({
                required dark,
                required language,
                required center,
              }) async => '{"version":8,"sources":{},"layers":[]}',
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
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
    final map = tester.widget<ml.MapLibreMap>(find.byType(ml.MapLibreMap));
    await tester.runAsync(() async {
      map.onStyleLoadedCallback?.call();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(platform.sources['waybi-route'], isNotNull);
    platform.bytes = 0;
    platform.uploads = 0;
    platform.perSource.clear();
    final filtersBefore = platform.operations
        .where((op) => op.contains('setFilter'))
        .length;
    // Five minutes at 100 km/h, one fix per second, two rebuilds per fix
    // (main.dart rebuilds on the position and on the navigation update).
    const fixes = int.fromEnvironment('WAYBI_BENCH_FIXES', defaultValue: 300);
    final stopwatch = Stopwatch()..start();
    for (var i = 1; i <= fixes; i++) {
      now = now.add(const Duration(seconds: 1));
      // ~27.8 m per second along the 100 m-spaced polyline.
      final along = i * 27.8 / 100;
      final index = along.floor();
      final t = along - index;
      final a = points[index], b = points[index + 1];
      location = GeoPoint(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );
      drive.emit(location, now);
      update!(() {});
      await tester.pump();
      update!(() {});
      await tester.pump();
    }
    stopwatch.stop();
    final filters =
        platform.operations.where((op) => op.contains('setFilter')).length -
        filtersBefore;
    final perFixMs = stopwatch.elapsedMicroseconds / fixes / 1000;
    final kbPerFix = platform.bytes / fixes / 1024;
    debugPrint(
      'WAYBI_BENCH fixes=$fixes ms/fix=${perFixMs.toStringAsFixed(2)} '
      'uploads=${platform.uploads} KB/fix=${kbPerFix.toStringAsFixed(1)} '
      'setFilter=$filters perSource=${platform.perSource}',
    );
    // Before caching: ~277 ms and ~152 KB per fix (the whole route and all
    // route traffic re-sent on every rebuild). Timing is machine-dependent;
    // the transferred bytes are not.
    expect(
      platform.perSource['waybi-route'],
      isNull,
      reason: 'The 4,000-point route is sent once, not per fix',
    );
    expect(kbPerFix, lessThan(8));
    expect(filters, lessThanOrEqualTo(4 * 12));
    expect(engine.displayRevision, lessThanOrEqualTo(fixes + 2));
    expect(engine.displayPathsListenable.value, same(engine.displayPaths));

    // Just Drive: frozen trail chunks are sent once; the live end alone moves.
    final trail = DriveTrail(chunkPoints: 4);
    var t = DateTime(2026, 11, 26, 12);
    void step(int i) {
      t = t.add(const Duration(seconds: 1));
      trail.add(
        NavigationLocationFix(
          point: GeoPoint(-36.85 - i * .0002, 174.76),
          accuracyMeters: 5,
          speedMetresPerSecond: 20,
          timestamp: t,
        ),
      );
    }

    for (var i = 0; i < 5; i++) {
      step(i);
    }
    override = trail.paths;
    update!(() {});
    await tester.pump();
    await tester.pump();
    final staticTrail = platform.sources['waybi-route']!['features'] as List;
    expect(staticTrail, isNotEmpty);
    expect(
      (platform.sources['waybi-route-head']!['features'] as List).single['id'],
      'drive-trail:live',
    );
    platform.updates.clear();
    step(5);
    override = trail.paths;
    update!(() {});
    await tester.pump();
    await tester.pump();
    expect(platform.updates, isNot(contains('waybi-route')));
    expect(platform.updates, contains('waybi-route-head'));
    expect(engine.remainingDistanceMeters, lessThan(400000));
  });
}
