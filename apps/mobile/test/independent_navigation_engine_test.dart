import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:kiwi_lens_mobile/domain/map_provider.dart';
import 'package:kiwi_lens_mobile/domain/route_option.dart';
import 'package:kiwi_lens_mobile/drive/drive_engine.dart';
import 'package:kiwi_lens_mobile/drive/voice_engine.dart';
import 'package:kiwi_lens_mobile/drive/route_progress_tracker.dart';
import 'package:kiwi_lens_mobile/providers/independent_navigation_engine.dart';

class SilentVoice extends VoiceEngine {
  @override
  Future<void> dispose() async {}
}

class FakeDrive extends DriveEngine {
  FakeDrive() : super(voiceEngine: SilentVoice());
  LatLng? fix;
  RouteProgressTracker? tracker;
  final spoken = <String>[];
  @override
  LatLng? get snappedLocation => fix;
  @override
  void setRoute(RouteOption? route, {bool preserveAlerts = false}) {
    super.setRoute(route);
    tracker = route == null ? null : RouteProgressTracker(route.points);
  }

  @override
  Future<void> startLocal() async {
    active = true;
  }

  @override
  Future<void> speakMessage(String message) async {
    spoken.add(message);
  }

  @override
  Future<void> stop() async {
    active = false;
    setRoute(null);
  }

  void emit(
    GeoPoint point,
    DateTime now, {
    double speed = 40,
    double accuracy = 10,
  }) {
    fix = LatLng(latitude: point.latitude, longitude: point.longitude);
    speedKph = speed;
    locationAccuracyMeters = accuracy;
    locationRevision++;
    routeProgress = tracker?.update(
      point,
      time: now,
      accuracyMeters: accuracy,
      speedKph: speed,
    );
    notifyListeners();
  }
}

const origin = GeoPoint(-36.86, 174.76);
const middle = GeoPoint(-36.855, 174.76);
const destination = GeoPoint(-36.85, 174.76);
RouteOption makeRoute({List<GeoPoint> waypoints = const []}) => RouteOption(
  id: 'test',
  mode: KiwiTravelMode.drive,
  durationSeconds: 1000,
  distanceMeters: 1000,
  points: const [origin, middle, destination],
  provider: 'independent',
  traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
  trafficIntervals: const [],
  waypoints: waypoints,
  steps: const [
    RouteStepInfo(
      instruction: 'Head north',
      distanceMeters: 500,
      location: origin,
      durationSeconds: 10,
      alongRouteMeters: 0,
      maneuverType: 'depart',
    ),
    RouteStepInfo(
      instruction: 'Turn right',
      distanceMeters: 500,
      location: middle,
      durationSeconds: 990,
      alongRouteMeters: 500,
      maneuverType: 'turn',
      maneuverModifier: 'right',
    ),
    RouteStepInfo(
      instruction: 'You have arrived',
      distanceMeters: 0,
      location: destination,
      alongRouteMeters: 1000,
      maneuverType: 'arrive',
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('near turn speaks once and ETA uses remaining step durations', () async {
    final drive = FakeDrive();
    final nav = IndependentNavigationEngine(drive);
    addTearDown(() {
      nav.dispose();
      drive.dispose();
    });
    await nav.start(makeRoute());
    final now = DateTime(2026, 9, 30);
    drive.emit(const GeoPoint(-36.8552, 174.76), now);
    expect(nav.nextStep?.instruction, 'Turn right');
    expect(nav.distanceToStepMeters, lessThan(55));
    expect(drive.spoken, ['Turn right']);
    drive.notifyListeners();
    expect(drive.spoken, ['Turn right']);
    drive.emit(middle, now.add(const Duration(seconds: 1)));
    expect(nav.remainingDistanceMeters, closeTo(500, 1));
    expect(nav.remainingSeconds, closeTo(990, 1));
  });

  test('arrival requires two close, slow accurate fixes', () async {
    final drive = FakeDrive();
    final nav = IndependentNavigationEngine(drive);
    addTearDown(() {
      nav.dispose();
      drive.dispose();
    });
    await nav.start(makeRoute());
    final now = DateTime(2026, 9, 30);
    drive.emit(destination, now, speed: 50);
    expect(nav.arrived, isFalse);
    drive.emit(destination, now.add(const Duration(seconds: 1)), speed: 0);
    expect(nav.arrived, isFalse);
    drive.emit(destination, now.add(const Duration(seconds: 2)), speed: 0);
    expect(nav.arrived, isTrue);
    expect(nav.remainingSeconds, 0);
    expect(nav.remainingDistanceMeters, 0);
    expect(
      drive.spoken.where((text) => text == 'You have arrived'),
      isEmpty,
      reason:
          'The host announces arrival after confirming the exact destination',
    );
  });

  test(
    'sustained deviation reroutes once and preserves unvisited stops',
    () async {
      final drive = FakeDrive();
      var now = DateTime(2026, 9, 30);
      final pending = Completer<RouteOption>();
      var requests = 0;
      List<GeoPoint>? stops;
      final nav = IndependentNavigationEngine(
        drive,
        clock: () => now,
        reroute: (point, previous, remaining) {
          requests++;
          stops = remaining;
          return pending.future;
        },
      );
      addTearDown(() {
        nav.dispose();
        drive.dispose();
      });
      await nav.start(
        makeRoute(waypoints: const [origin, middle, destination]),
      );
      drive.emit(origin, now);
      for (var i = 0; i < 4; i++) {
        now = now.add(const Duration(seconds: 2));
        drive.emit(const GeoPoint(-36.859, 174.7615), now);
      }
      expect(requests, 1);
      expect(stops, [middle]);
      expect(nav.rerouting, isTrue);
      expect(nav.nextStep?.instruction, 'Turn right');
      pending.complete(makeRoute());
      await Future<void>.delayed(Duration.zero);
      expect(nav.rerouting, isFalse);
      expect(nav.offRoute, isFalse);
    },
  );

  test('a stopped trip ignores a late reroute response', () async {
    final drive = FakeDrive();
    var now = DateTime(2026, 9, 30);
    final pending = Completer<RouteOption>();
    final nav = IndependentNavigationEngine(
      drive,
      clock: () => now,
      reroute: (_, _, _) => pending.future,
    );
    addTearDown(() {
      nav.dispose();
      drive.dispose();
    });
    await nav.start(makeRoute());
    for (var i = 0; i < 3; i++) {
      now = now.add(const Duration(seconds: 2));
      drive.emit(const GeoPoint(-36.859, 174.7615), now);
    }
    expect(nav.rerouting, isTrue);
    await nav.stop();
    pending.complete(makeRoute());
    await Future<void>.delayed(Duration.zero);
    expect(nav.route, isNull);
    expect(nav.active, isFalse);
    expect(drive.routed, isFalse);
  });

  test(
    'failed reroute keeps original route and retries after cooldown',
    () async {
      final drive = FakeDrive();
      var now = DateTime(2026, 9, 30);
      var attempts = 0;
      final nav = IndependentNavigationEngine(
        drive,
        clock: () => now,
        reroute: (_, _, _) async {
          attempts++;
          throw StateError('offline');
        },
      );
      addTearDown(() {
        nav.dispose();
        drive.dispose();
      });
      final route = makeRoute();
      await nav.start(route);
      for (var i = 0; i < 3; i++) {
        now = now.add(const Duration(seconds: 2));
        drive.emit(const GeoPoint(-36.859, 174.7615), now);
      }
      await Future<void>.delayed(Duration.zero);
      expect(nav.route, same(route));
      expect(nav.error, isNotNull);
      now = now.add(const Duration(seconds: 1));
      drive.emit(const GeoPoint(-36.859, 174.7615), now);
      expect(attempts, 1);
      now = now.add(const Duration(seconds: 15));
      drive.emit(const GeoPoint(-36.859, 174.7615), now);
      await Future<void>.delayed(Duration.zero);
      expect(attempts, 2);
    },
  );
}
