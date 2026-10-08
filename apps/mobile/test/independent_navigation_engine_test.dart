import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/domain/road_event.dart';
import 'package:waybi_mobile/drive/drive_engine.dart';
import 'package:waybi_mobile/drive/navigation_language.dart';
import 'package:waybi_mobile/drive/voice_engine.dart';
import 'package:waybi_mobile/drive/route_progress_tracker.dart';
import 'package:waybi_mobile/providers/independent_navigation_engine.dart';

class SilentVoice extends VoiceEngine {
  @override
  Future<void> dispose() async {}
}

class FakeDrive extends DriveEngine {
  FakeDrive() : super(voiceEngine: SilentVoice());
  LatLng? fix;
  RouteProgressTracker? tracker;
  final spoken = <String>[];
  int stops = 0;
  RouteProgressTracker? trackerAtStart;
  @override
  LatLng? get snappedLocation => fix;
  @override
  void setRoute(RouteOption? route, {bool preserveAlerts = false}) {
    super.setRoute(route);
    tracker = route == null ? null : RouteProgressTracker(route.points);
  }

  @override
  Future<void> startLocal({Position? initialPosition}) async {
    trackerAtStart = tracker;
    active = true;
  }

  @override
  Future<void> speakMessage(String message) async {
    spoken.add(message);
  }

  @override
  Future<void> stop() async {
    stops++;
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
    latestPosition = Position(
      latitude: point.latitude,
      longitude: point.longitude,
      timestamp: now,
      accuracy: accuracy,
      altitude: 0,
      heading: 0,
      speed: speed / 3.6,
      speedAccuracy: 1,
      altitudeAccuracy: 1,
      headingAccuracy: 1,
    );
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
RouteOption makeRoute({
  List<GeoPoint> waypoints = const [],
  List<String> closureIds = const [],
}) => RouteOption(
  id: 'test',
  mode: WaybiTravelMode.drive,
  durationSeconds: 1000,
  distanceMeters: 1000,
  points: const [origin, middle, destination],
  provider: 'independent',
  traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
  trafficIntervals: const [],
  waypoints: waypoints,
  closureIds: closureIds,
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

  RoadEvent closure({
    RoadEventObservation observation = RoadEventObservation.official,
  }) => RoadEvent(
    id: 'official-closure',
    type: RoadEventType.roadClosure,
    location: middle,
    source: const RoadEventSource(
      provider: 'NZTA',
      country: 'NZ',
      sourceId: '1',
    ),
    observation: observation,
  );

  test('a known blocked route cannot start navigation', () async {
    final drive = FakeDrive();
    final nav = IndependentNavigationEngine(drive);
    addTearDown(() {
      nav.dispose();
      drive.dispose();
    });
    await expectLater(
      nav.start(makeRoute(closureIds: ['closure'])),
      throwsStateError,
    );
    expect(drive.active, isFalse);
  });

  test('a new official closure triggers rerouting while still on-route, inferred events do not', () async {
    final drive = FakeDrive();
    var now = DateTime.utc(2026, 10, 8);
    var requests = 0;
    final nav = IndependentNavigationEngine(
      drive,
      clock: () => now,
      reroute: (origin, previous, stops) async {
        requests++;
        return makeRoute();
      },
    );
    addTearDown(() {
      nav.dispose();
      drive.dispose();
    });
    await nav.start(makeRoute());
    drive.emit(origin, now);
    drive.roadEvents = [closure(observation: RoadEventObservation.inferred)];
    nav.checkClosureUpdates();
    await Future<void>.delayed(Duration.zero);
    expect(requests, 0);
    now = now.add(const Duration(seconds: 16));
    drive.roadEvents = [closure()];
    nav.checkClosureUpdates();
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
    expect(nav.offRoute, isFalse);
    expect(nav.error, isNull);
  });

  test('failed closure reroutes preserve guidance and warnings, with bounded retry until the closure clears', () async {
    final drive = FakeDrive()..navigationLanguage = 'zh';
    var now = DateTime.utc(2026, 10, 8);
    var requests = 0;
    final nav = IndependentNavigationEngine(
      drive,
      clock: () => now,
      reroute: (origin, previous, stops) async {
        requests++;
        return makeRoute(closureIds: ['official-closure']);
      },
    );
    addTearDown(() {
      nav.dispose();
      drive.dispose();
    });
    final route = makeRoute();
    await nav.start(route);
    drive.emit(origin, now);
    drive.roadEvents = [closure()];
    nav.checkClosureUpdates();
    await Future<void>.delayed(Duration.zero);
    expect(nav.route, same(route));
    expect(drive.active, isTrue);
    expect(nav.error, contains('前方封路'));
    now = now.add(const Duration(seconds: 16));
    drive.emit(origin, now);
    nav.checkClosureUpdates();
    expect(nav.error, contains('前方封路'));
    expect(requests, 1);
    now = now.add(const Duration(seconds: 46));
    nav.checkClosureUpdates();
    await Future<void>.delayed(Duration.zero);
    expect(requests, 2);
    now = now.add(const Duration(seconds: 16));
    drive.roadEvents = [];
    nav.checkClosureUpdates();
    expect(nav.error, isNull);
  });

  test('empty OSRM instruction still produces an English road prompt', () {
    const step = RouteStepInfo(
      instruction: '',
      distanceMeters: 120,
      location: GeoPoint(-36.85, 174.76),
      maneuverType: 'turn',
      maneuverModifier: 'right',
      roadName: 'Queen Street',
    );
    expect(routeStepInstruction(step, 'en'), 'Turn right onto Queen Street');
  });

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
    expect(drive.spoken, ['Head north', 'Turn right']);
    drive.notifyListeners();
    expect(drive.spoken, ['Head north', 'Turn right']);
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

  test(
    'navigation restarts an existing Drive stream with the new route',
    () async {
      final drive = FakeDrive()..active = true;
      final nav = IndependentNavigationEngine(drive);
      addTearDown(() {
        nav.dispose();
        drive.dispose();
      });
      final route = makeRoute();
      await nav.start(route);
      expect(drive.stops, 1);
      expect(drive.trackerAtStart, isNotNull);
      expect(nav.route, same(route));
      expect(nav.active, isTrue);
    },
  );

  test('returning to the route discards a pending recalculation', () async {
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
    final original = makeRoute();
    await nav.start(original);
    for (var i = 0; i < 3; i++) {
      now = now.add(const Duration(seconds: 2));
      drive.emit(const GeoPoint(-36.859, 174.7615), now);
    }
    expect(nav.rerouting, isTrue);
    now = now.add(const Duration(seconds: 1));
    drive.emit(origin, now);
    expect(nav.offRoute, isFalse);
    pending.complete(makeRoute());
    await Future<void>.delayed(Duration.zero);
    expect(nav.route, same(original));
    expect(nav.rerouting, isFalse);
  });

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
