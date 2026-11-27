import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart' show JourneyMemory;
import 'package:waybi_mobile/app/journey_store.dart';
import 'package:waybi_mobile/app/navigation_session_controller.dart';
import 'package:waybi_mobile/app/offline_corridor.dart';
import 'package:waybi_mobile/app/place_selection_controller.dart';
import 'package:waybi_mobile/app/road_alerts.dart';
import 'package:waybi_mobile/app/route_preview_controller.dart';
import 'package:waybi_mobile/app/trip_state.dart';
import 'package:waybi_mobile/data/account_repository.dart';
import 'package:waybi_mobile/data/navigation_feedback_repository.dart';
import 'package:waybi_mobile/data/navigation_reward_repository.dart';
import 'package:waybi_mobile/data/parking_repository.dart';
import 'package:waybi_mobile/data/place_details_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/navigation_camera_mode.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/domain/transit_lane.dart';
import 'package:waybi_mobile/drive/drive_engine.dart';
import 'package:waybi_mobile/drive/journey_tracker.dart';
import 'package:waybi_mobile/drive/navigation_location_filter.dart';
import 'package:waybi_mobile/drive/route_camera_matcher.dart';
import 'package:waybi_mobile/drive/route_progress_tracker.dart';
import 'package:waybi_mobile/drive/system_navigation.dart';
import 'package:waybi_mobile/drive/voice_engine.dart';
import 'package:waybi_mobile/drive/voice_utterance.dart';
import 'package:waybi_mobile/providers/independent_navigation_engine.dart';
import 'package:waybi_mobile/services/external_navigation_inbox.dart';

const here = GeoPoint(-37.2, 174.9);
const cafe = PlaceSummary(
  name: 'Cafe',
  address: 'Harbour Road',
  location: GeoPoint(-37.2, 174.91),
);
const carPark = ParkingPlace(
  id: 'p1',
  name: 'Harbour car park',
  address: 'Quay Street',
  location: GeoPoint(-37.2, 174.9099),
  distanceMeters: 90,
  source: 'AT',
);

RouteOption route(
  String id, {
  WaybiTravelMode mode = WaybiTravelMode.drive,
  int metres = 1000,
  GeoPoint to = const GeoPoint(-37.2, 174.91),
  List<String> closureIds = const [],
}) => RouteOption(
  id: id,
  mode: mode,
  durationSeconds: 600,
  distanceMeters: metres,
  points: [here, to],
  provider: 'independent',
  traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
  trafficIntervals: const [],
  closureIds: closureIds,
);

RoutePlan planOf(List<RouteOption> routes) => RoutePlan(
  options: routes,
  trafficAvailable: true,
  provider: 'independent',
  stopsApplied: 0,
);

class SilentVoice extends VoiceEngine {
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class FakeDrive extends DriveEngine {
  FakeDrive() : super(voiceEngine: SilentVoice());

  bool reliable = true;
  bool startActive = true;
  Object? startError;
  Object? stopError;
  Completer<void>? startGate;
  Completer<List<TransitLaneMatch>>? laneGate;
  List<TransitLaneMatch> lanes = const [];
  int starts = 0, stops = 0;
  final prompts = <VoiceUtterance>[];
  final keepAwake = <bool>[];

  @override
  bool get hasReliableLocation => reliable;

  @override
  Future<List<TransitLaneMatch>> transitMatchesForRoute(RouteOption route) =>
      laneGate?.future ?? Future.value(lanes);

  @override
  Future<void> startLocal({Position? initialPosition}) async {
    starts++;
    await startGate?.future;
    if (startError != null) throw startError!;
    active = startActive;
  }

  @override
  Future<void> stop() async {
    stops++;
    active = false;
    if (stopError != null) throw stopError!;
  }

  @override
  Future<void> speakUtterance(VoiceUtterance prompt) async =>
      prompts.add(prompt);

  @override
  Future<void> setKeepScreenAwake(bool value) async => keepAwake.add(value);

  void tick() => notifyListeners();
}

class RecordingSystem extends SystemNavigation {
  final calls = <String>[];
  final states = <Map<String, Object?>>[];
  bool failStop = false;
  bool running = false;

  @override
  Future<void> start(Map<String, Object?> state) async {
    running = true;
    calls.add('start');
    states.add(state);
  }

  /// Like the real surface, an update after stop is ignored.
  @override
  Future<void> update(Map<String, Object?> state, {bool force = false}) async {
    if (!running) return;
    calls.add(force ? 'update!' : 'update');
    states.add(state);
  }

  @override
  Future<void> stop() async {
    running = false;
    calls.add('stop');
    if (failStop) throw StateError('surface');
  }
}

class FakeGuidance extends IndependentNavigationEngine {
  FakeGuidance(super.drive);
  Object? stopError;

  /// Thrown after the route was installed (a half-started engine).
  Object? startErrorAfterRoute;

  @override
  Future<void> start(RouteOption route, {Position? initialPosition}) async {
    await super.start(route, initialPosition: initialPosition);
    final error = startErrorAfterRoute;
    if (error != null) throw error;
  }

  @override
  Future<void> stop() async {
    if (stopError != null) {
      final error = stopError!;
      stopError = null;
      throw error;
    }
    await super.stop();
  }
}

class FakeJourneys extends JourneyStore {
  FakeJourneys()
    : super(
        AccountRepository(
          client: MockClient((_) async => http.Response('{}', 500)),
        ),
      );
  final account = <Map<String, Object>>[];
  final guest = <JourneySummary>[];
  bool fail = false;

  @override
  Future<void> queueAccountJourney({
    required String destinationName,
    required double latitude,
    required double longitude,
    required String mode,
    required int distanceMeters,
    required int durationSeconds,
  }) async {
    if (fail) throw StateError('disk full');
    account.add({
      'name': destinationName,
      'mode': mode,
      'distance': distanceMeters,
    });
  }

  @override
  Future<void> recordGuestJourney(JourneySummary summary) async {
    if (fail) throw StateError('disk full');
    guest.add(summary);
  }
}

class FakeRewards extends NavigationRewardRepository {
  FakeRewards()
    : super(client: MockClient((_) async => http.Response('{}', 500)));
  final completed = <JourneySummary>[];

  @override
  Future<String?> countryAt(GeoPoint point) async => 'NZ';

  @override
  Future<JourneyMemory?> complete(
    JourneySummary summary, {
    Future<String?>? country,
  }) async {
    completed.add(summary);
    throw StateError('reward service down');
  }
}

class FakeFeedback extends NavigationFeedbackRepository {
  FakeFeedback()
    : super(client: MockClient((_) async => http.Response('{}', 500)));
  int flushes = 0;

  @override
  Future<void> flush() async => flushes++;
}

/// The controller with fake engines; the rig is also the page (TripHost).
class Rig implements TripHost {
  Rig({ExternalNavigationInbox? inbox}) {
    guidance = FakeGuidance(drive);
    places = PlaceSelectionController(
      fetchDetails: (place) async =>
          PlaceDetails.fromJson({'name': place.name}),
      reverse: (_, _) async => null,
      route: (_, _) async => route('eta'),
      language: () => language,
      quickRouteSuppressed: () => true,
    );
    preview = RoutePreviewController(
      trip: trip,
      places: places,
      planner:
          ({
            required origin,
            required destination,
            required stops,
            required mode,
            required headingDegrees,
            required avoid,
          }) async =>
              planOf([route('${mode.name}-1', mode: mode, to: destination)]),
      transit: ({required origin, required destination}) async =>
          planOf([route('bus', mode: WaybiTravelMode.transit)]),
      parking: (_) async => const [],
      routeLocation: () => location,
      gpsLocation: () => location,
      heading: () => null,
      cameras: () => const [],
      roadEvents: () => const [],
      cameraDataReady: () => false,
      setDriveRoute: drive.setRoute,
      navigationOwnsRoute: () => guidance.route != null,
      driveActive: () => drive.active,
      notice: notice,
      language: () => language,
      showRoute: () async {},
    );
    nav = NavigationSessionController(
      trip: trip,
      preview: preview,
      places: places,
      drive: drive,
      guidance: guidance,
      system: system,
      host: this,
      notice: notice,
      roadAlerts: RoadAlerts(
        settings: () => (cameras: false, incidents: false, community: false),
        language: () => language,
        present: ({required id, required title, required body}) async => true,
        requestPermission: () async {},
      ),
      journeys: journeys,
      rewards: rewards,
      feedback: feedback,
      parking: (destination) async {
        parkingLookups++;
        if (parkingFails) throw StateError('parking offline');
        return const [carPark];
      },
      fetchDetails: (place) async {
        if (detailsFail) throw StateError('details offline');
        return PlaceDetails.fromJson({'name': place.name});
      },
      isPlus: () => plus,
      hasAccount: () => account,
      language: () => language,
      inbox: inbox ?? ExternalNavigationInbox(const MethodChannel('test/no')),
      requestNotificationPermission: () async => notificationRequests++,
      clock: () => now,
    );
    nav.addListener(() => notified++);
  }

  final trip = TripMachine();
  final notice = ValueNotifier<String?>(null);
  final drive = FakeDrive();
  late final FakeGuidance guidance;
  final system = RecordingSystem();
  final journeys = FakeJourneys();
  final rewards = FakeRewards();
  final feedback = FakeFeedback();
  late final PlaceSelectionController places;
  late final RoutePreviewController preview;
  late final NavigationSessionController nav;

  bool plus = false;
  bool account = false;
  bool parkingFails = false;
  bool detailsFail = false;
  String language = 'en';
  DateTime now = DateTime.now();
  int parkingLookups = 0, notificationRequests = 0, notified = 0;

  // TripHost
  final calls = <String>[];
  GeoPoint? location = here;
  Position? reliablePosition;
  bool permission = true;
  bool ready = true;
  bool confirm = true;
  final confirmations = <String>[];
  Future<PlaceSummary?> Function(String query, String purpose)? search;
  final searches = <String>[];
  final errors = <String>[];
  final summaries = <JourneySummary>[];
  final frames = <VoidCallback>[];
  void Function()? onStartBrowse;

  @override
  void resetTripCamera({required bool drive}) =>
      calls.add(drive ? 'reset(drive)' : 'reset');
  @override
  void followTrip([NavigationCameraMode? mode]) =>
      calls.add('follow(${mode?.name})');
  @override
  void setTripCameraMode(NavigationCameraMode mode) =>
      calls.add('mode(${mode.name})');
  @override
  void refreshTripMap() => calls.add('refresh');
  @override
  void resumeTrafficRefresh() => calls.add('traffic');
  @override
  GeoPoint? get browseLocation => location;
  @override
  Position? get lastReliablePosition => reliablePosition;
  @override
  Future<bool> ensureLocationPermission() async => permission;
  @override
  Future<void> pauseBrowseLocation() async => calls.add('pause');
  @override
  Future<void> startBrowseLocation() async {
    calls.add('browse');
    onStartBrowse?.call();
  }

  @override
  Future<void> clearPreview() async {
    calls.add('clear');
    preview.clear();
  }

  @override
  void showJourneySummary(
    JourneySummary summary,
    Future<JourneyMemory?>? reward,
  ) => summaries.add(summary);
  @override
  bool get handOffReady => ready;
  @override
  void popToHome() => calls.add('pop');
  @override
  Future<bool> confirmSwitchTrip(String destination) async {
    confirmations.add(destination);
    return confirm;
  }

  @override
  Future<PlaceSummary?> searchHandOffTarget(
    String query,
    String purpose,
    bool Function() current,
  ) {
    searches.add('$purpose: $query');
    return search?.call(query, purpose) ?? Future.value(null);
  }

  @override
  void showHandOffError(String message) => errors.add(message);
  @override
  void selectHandOffPlace(PlaceSummary place) => select(place);
  @override
  void afterFrame(VoidCallback callback) => frames.add(callback);

  void select(PlaceSummary place) {
    preview.beginPlace();
    places.select(
      place,
      SelectionSource.search,
      originMap: MapProvider.independent,
    );
  }

  Future<void> previewed(
    PlaceSummary place, {
    WaybiTravelMode mode = WaybiTravelMode.drive,
  }) async {
    select(place);
    await preview.load(mode: mode);
  }

  Future<void> navigating({PlaceSummary place = cafe}) async {
    await previewed(place);
    await nav.start();
  }

  /// Runs the post-frame callbacks the controller scheduled.
  Future<void> frame() async {
    final pending = [...frames];
    frames.clear();
    for (final callback in pending) {
      callback();
    }
    await pumpEventQueue();
  }

  bool disposed = false;
  void dispose() {
    if (!disposed) nav.dispose();
    guidance.dispose();
    preview.dispose();
    places.dispose();
    trip.dispose();
    notice.dispose();
    drive.dispose();
  }
}

NavigationLocationFix fixAt(GeoPoint point, DateTime time) =>
    NavigationLocationFix(
      point: point,
      accuracyMeters: 5,
      speedMetresPerSecond: 10,
      timestamp: time,
    );

Position positionAt(DateTime time) => Position(
  latitude: here.latitude,
  longitude: here.longitude,
  timestamp: time,
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 90,
  headingAccuracy: 1,
  speed: 10,
  speedAccuracy: 1,
);

/// Drives the journey to [target]: a fix on the way, then two at the
/// destination 1 s apart (arrival).
Future<void> arrive(Rig rig, GeoPoint target) async {
  final start = DateTime.now().add(const Duration(seconds: 1));
  for (final (point, seconds) in [
    (const GeoPoint(-37.2, 174.9004), 0),
    (target, 20),
    (target, 21),
  ]) {
    final time = start.add(Duration(seconds: seconds));
    rig.now = time;
    rig.nav.onLocationFix(fixAt(point, time), positionAt(time));
  }
  await pumpEventQueue();
}

const busLane = TransitLaneMatch(
  lane: TransitLane(
    id: 'bus',
    roadName: 'Queen Street',
    kind: 'Bus',
    schedule: TransitSchedule(
      days: [1, 2, 3, 4, 5, 6, 7],
      windows: [
        [0, 1440],
      ],
      known: true,
    ),
    points: [here, GeoPoint(-37.2, 174.91)],
    wholeRoad: true,
  ),
  startMeters: 0,
  endMeters: 900,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Rig rig;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    rig = Rig();
  });
  tearDown(() => rig.dispose());

  group('starting guidance', () {
    test('starts the selected route and hands the preview over', () async {
      rig.reliablePosition = positionAt(DateTime.now());
      await rig.navigating();
      expect(rig.trip.value, const TripNavigating());
      expect(rig.guidance.active, isTrue);
      expect(rig.nav.activeRoute!.id, 'drive-1');
      expect(rig.nav.destination, cafe);
      expect(rig.nav.destinationTitle, 'Cafe');
      expect(rig.places.selected, isNull);
      expect(rig.preview.plan, isNull);
      expect(rig.preview.mode, WaybiTravelMode.drive);
      expect(rig.calls, [
        'mode(headingUpFlat)',
        'pause',
        'reset',
        'follow(headingUpFlat)',
        'refresh',
      ]);
      expect(rig.system.calls, ['start']);
      expect(rig.system.states.single['destination'], 'Cafe');
      expect(rig.feedback.flushes, 1);
      expect(rig.notice.value, isNull);
      expect(rig.nav.remainingMeters, 1000);
      expect(rig.nav.tripSnapshot(), contains('Waybi trip to Cafe'));
      expect(rig.nav.tripSnapshot(), contains('Remaining: 1.0 km'));
    });

    test('a blocked route looks for a detour instead', () async {
      rig.select(cafe);
      rig.preview.applyLink(
        origin: null,
        stops: const [],
        mode: WaybiTravelMode.drive,
      );
      final blocked = RoutePreviewController(
        trip: rig.trip,
        places: rig.places,
        planner:
            ({
              required origin,
              required destination,
              required stops,
              required mode,
              required headingDegrees,
              required avoid,
            }) async => planOf([
              route('closed', closureIds: const ['x']),
            ]),
        transit: ({required origin, required destination}) async =>
            planOf(const []),
        parking: (_) async => const [],
        routeLocation: () => here,
        gpsLocation: () => here,
        heading: () => null,
        cameras: () => const [],
        roadEvents: () => const [],
        cameraDataReady: () => false,
        setDriveRoute: (_) {},
        navigationOwnsRoute: () => false,
        driveActive: () => false,
        notice: rig.notice,
        language: () => 'en',
        showRoute: () async {},
      );
      addTearDown(blocked.dispose);
      final nav = NavigationSessionController(
        trip: rig.trip,
        preview: blocked,
        places: rig.places,
        drive: rig.drive,
        guidance: rig.guidance,
        system: rig.system,
        host: rig,
        notice: rig.notice,
        roadAlerts: RoadAlerts(
          settings: () => (cameras: false, incidents: false, community: false),
          language: () => 'en',
        ),
        journeys: rig.journeys,
        rewards: rig.rewards,
        feedback: rig.feedback,
        parking: (_) async => const [],
        fetchDetails: (place) async => PlaceDetails.fromJson({}),
        isPlus: () => false,
        hasAccount: () => false,
        language: () => 'en',
        inbox: ExternalNavigationInbox(const MethodChannel('test/blocked')),
      );
      addTearDown(nav.dispose);
      await blocked.load();
      await nav.start();
      expect(blocked.recoveryMessage, contains('No verified detour'));
      expect(rig.guidance.route, isNull);
      expect(rig.trip.value, const TripPreviewing());
    });

    test('nothing starts without a route or while busy', () async {
      await rig.nav.start();
      rig.select(cafe);
      await rig.nav.start();
      expect(rig.trip.value, const TripPlaceSelected());
      await rig.preview.load();
      rig.trip.dispatch(const StartRequested());
      await rig.nav.start();
      expect(rig.drive.starts, 0);
    });

    test('a bus-only road refuses the start and keeps the preview', () async {
      rig.drive.lanes = const [busLane];
      await rig.navigating();
      expect(rig.notice.value, contains('Bus-only access on Queen Street'));
      expect(rig.trip.value, const TripPreviewing());
      expect(rig.drive.starts, 0);
      expect(rig.calls.last, 'browse');
    });

    test('no location permission returns to the preview', () async {
      rig.permission = false;
      await rig.navigating();
      expect(rig.trip.value, const TripPreviewing());
      expect(rig.guidance.route, isNull);
      expect(rig.calls, ['mode(headingUpFlat)', 'browse']);
    });

    test(
      'closing the preview while lanes are matched cancels the start',
      () async {
        rig.drive.laneGate = Completer();
        await rig.previewed(cafe);
        final start = rig.nav.start();
        expect(rig.trip.value, const TripStarting());
        expect(rig.trip.value.busy, isTrue);
        rig.preview.closeToPlace();
        rig.drive.laneGate!.complete(const []);
        await start;
        expect(rig.trip.value, const TripPlaceSelected());
        expect(rig.drive.starts, 0);
      },
    );

    test('backing out while the engine starts stops it again', () async {
      rig.drive.startGate = Completer();
      await rig.previewed(cafe);
      final start = rig.nav.start();
      await pumpEventQueue();
      expect(rig.drive.starts, 1);
      rig.preview.clear();
      rig.drive.startGate!.complete();
      await start;
      expect(rig.guidance.route, isNull);
      expect(rig.drive.active, isFalse);
      expect(rig.trip.value, const TripIdle());
      expect(rig.system.calls, isEmpty);
    });

    test('an engine failure explains itself and leaves no half-started '
        'guidance', () async {
      rig.drive.startError = StateError('GPS offline');
      await rig.navigating();
      expect(rig.notice.value, startsWith('Could not start navigation.'));
      expect(rig.guidance.route, isNull);
      expect(rig.trip.value, const TripPreviewing());
      expect(rig.calls.last, 'browse');
    });

    test('a half-started engine is stopped again', () async {
      rig.guidance.startErrorAfterRoute = StateError('voice failed');
      await rig.navigating();
      expect(rig.guidance.route, isNull);
      expect(rig.drive.active, isFalse);
      expect(rig.notice.value, startsWith('Could not start navigation.'));
      expect(rig.trip.value, const TripPreviewing());
    });

    test(
      'a half-started engine that cannot stop is left to the page',
      () async {
        rig.guidance.startErrorAfterRoute = StateError('voice failed');
        rig.guidance.stopError = StateError('engine stuck');
        await rig.navigating();
        expect(rig.trip.value, const TripPreviewing());
      },
    );

    test('a disposed session never starts the engine', () async {
      rig.select(cafe);
      await rig.preview.load();
      rig.nav.dispose();
      rig.disposed = true;
      await rig.nav.start();
      expect(rig.drive.starts, 0);
      expect(rig.guidance.route, isNull);
    });

    test('Android asks for notification permission first', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await rig.navigating();
      expect(rig.notificationRequests, 1);
    });
  });

  group('during guidance', () {
    test(
      'engine ticks update the Lock Screen surface; resume forces it',
      () async {
        await rig.navigating();
        rig.drive.tick();
        rig.guidance.offRoute = true;
        rig.drive.tick();
        expect(rig.system.calls, ['start', 'update', 'update']);
        expect(rig.system.states.last['instruction'], 'Updating route...');
        expect(rig.system.states.last['maneuver'], 'arrow.triangle.swap');
        rig.drive.reliable = false;
        rig.nav.onResumed();
        expect(rig.system.calls.last, 'update!');
        expect(
          rig.system.states.last['instruction'],
          'Waiting for accurate GPS',
        );
        expect(rig.system.states.last['distance'], '—');
        rig.language = 'zh';
        expect(rig.nav.systemState()['instruction'], '正在等待准确定位');
      },
    );

    test('maneuver symbols follow the next step', () async {
      await rig.navigating();
      final state = rig.nav.systemState();
      expect(state['maneuver'], 'arrow.up');
      expect(state['seconds'], 600);
      expect(state['gpsReliable'], isTrue);
    });

    test('not navigating, resume and fixes do nothing', () async {
      rig.nav.onResumed();
      rig.nav.onLocationFix(fixAt(cafe.location, rig.now), positionAt(rig.now));
      expect(rig.system.calls, isEmpty);
      expect(rig.nav.remainingMeters, isNull);
      expect(rig.nav.tripSnapshot(), contains('Remaining: unknown'));
    });

    test('a stale fix is not used for arrival', () async {
      await rig.navigating();
      final old = rig.now.subtract(const Duration(minutes: 1));
      rig.nav.onLocationFix(fixAt(cafe.location, old), positionAt(old));
      expect(rig.trip.value, const TripNavigating());
    });

    test(
      'arriving ends the trip with a summary, a reward and the prompt',
      () async {
        await rig.navigating();
        await arrive(rig, cafe.location);
        expect(rig.trip.value, const TripIdle());
        expect(rig.summaries.single.arrived, isTrue);
        expect(rig.rewards.completed, hasLength(1));
        expect(rig.journeys.guest.single.distanceMeters, greaterThan(0));
        expect(rig.drive.prompts.last.text, isNotEmpty);
        expect(rig.system.calls.last, 'stop');
        expect(rig.calls.sublist(rig.calls.length - 3), [
          'follow(northUpFlat)',
          'traffic',
          'browse',
        ]);
        expect(rig.nav.activeRoute, isNull);
        expect(rig.nav.destinationTitle, 'Destination');
      },
    );

    test('a signed-in journey is queued for the account', () async {
      rig.account = true;
      await rig.navigating();
      await arrive(rig, cafe.location);
      expect(rig.journeys.account.single['name'], 'Cafe');
      expect(rig.journeys.account.single['mode'], 'drive');
    });

    test('ending always ends, whatever fails', () async {
      rig.journeys.fail = true;
      rig.system.failStop = true;
      await rig.navigating();
      final start = DateTime.now().add(const Duration(seconds: 1));
      rig.now = start;
      rig.nav.onLocationFix(
        fixAt(const GeoPoint(-37.2, 174.9004), start),
        positionAt(start),
      );
      final later = start.add(const Duration(seconds: 10));
      rig.now = later;
      rig.nav.onLocationFix(
        fixAt(const GeoPoint(-37.2, 174.905), later),
        positionAt(later),
      );
      rig.guidance.stopError = StateError('engine stuck');
      await rig.nav.stop(showSummary: false);
      expect(rig.trip.value, const TripIdle());
      expect(rig.drive.active, isFalse);
      expect(rig.summaries, isEmpty);
      expect(rig.journeys.guest, isEmpty);
      // Stopping again is a no-op.
      await rig.nav.stop();
      expect(rig.summaries, isEmpty);
    });

    test('a failing fallback stop still leaves guidance', () async {
      await rig.navigating();
      rig.guidance.stopError = StateError('engine stuck');
      rig.drive.stopError = StateError('feed stuck');
      await rig.nav.stop();
      expect(rig.trip.value, const TripIdle());
      expect(rig.summaries.single.arrived, isFalse);
    });

    test(
      'the Plus offline corridor is saved and dropped when Plus lapses',
      () async {
        rig.plus = true;
        await rig.navigating();
        await pumpEventQueue();
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(offlineCorridorKey), isNotNull);
        expect(rig.nav.offlineReady, isTrue);
        final cachedAt = rig.nav.corridorCachedAt;
        expect(cachedAt, isNotNull);
        rig.now = rig.now.add(const Duration(seconds: 5));
        rig.drive.tick();
        await pumpEventQueue();
        expect(rig.nav.corridorCachedAt, cachedAt);
        rig.now = rig.now.add(const Duration(seconds: 40));
        rig.drive.tick();
        await pumpEventQueue();
        expect(rig.nav.corridorCachedAt, isNot(cachedAt));
        rig.plus = false;
        rig.drive.tick();
        await pumpEventQueue();
        expect(rig.nav.offlineReady, isFalse);
      },
    );

    test(
      'the remaining distance follows drive progress without the engine',
      () async {
        await rig.navigating();
        rig.drive.active = false;
        expect(rig.guidance.active, isFalse);
        expect(rig.nav.remainingMeters, isNull);
        final route = rig.nav.activeRoute!;
        final length = RouteProgressTracker.geometryLength(route.points);
        rig.drive.routeProgress = RouteProjection(
          alongMeters: length / 4,
          offsetMeters: 0,
          bearingDegrees: 90,
        );
        expect(rig.nav.remainingMeters, closeTo(750, .001));
        // Guidance that lost its route ends through the drive engine.
        await rig.guidance.stop();
        final stops = rig.drive.stops;
        await rig.nav.stop();
        expect(rig.drive.stops, stops + 1);
        expect(rig.trip.value, const TripIdle());
      },
    );

    test('a route without length counts its whole distance', () async {
      final point = RoutePreviewController(
        trip: rig.trip,
        places: rig.places,
        planner: ({
          required origin,
          required destination,
          required stops,
          required mode,
          required headingDegrees,
          required avoid,
        }) async => planOf([route('loop', to: here)]),
        transit: ({required origin, required destination}) async =>
            planOf(const []),
        parking: (_) async => const [],
        routeLocation: () => here,
        gpsLocation: () => here,
        heading: () => null,
        cameras: () => const [],
        roadEvents: () => const [],
        cameraDataReady: () => false,
        setDriveRoute: rig.drive.setRoute,
        navigationOwnsRoute: () => rig.guidance.route != null,
        driveActive: () => rig.drive.active,
        notice: rig.notice,
        language: () => 'en',
        showRoute: () async {},
      );
      addTearDown(point.dispose);
      final nav = NavigationSessionController(
        trip: rig.trip,
        preview: point,
        places: rig.places,
        drive: rig.drive,
        guidance: rig.guidance,
        system: rig.system,
        host: rig,
        notice: rig.notice,
        roadAlerts: RoadAlerts(
          settings: () => (cameras: false, incidents: false, community: false),
          language: () => 'en',
        ),
        journeys: rig.journeys,
        rewards: rig.rewards,
        feedback: rig.feedback,
        parking: (_) async => const [],
        fetchDetails: (place) async => PlaceDetails.fromJson({}),
        isPlus: () => false,
        hasAccount: () => false,
        language: () => 'en',
        inbox: ExternalNavigationInbox(const MethodChannel('test/loop')),
      );
      addTearDown(nav.dispose);
      rig.nav.dispose();
      rig.disposed = true;
      rig.select(cafe);
      await point.load();
      await nav.start();
      expect(nav.activeRoute!.id, 'loop');
      rig.drive.active = false;
      rig.drive.routeProgress = const RouteProjection(
        alongMeters: 0,
        offsetMeters: 0,
        bearingDegrees: 0,
      );
      expect(nav.remainingMeters, 1000);
      // The default inbox is the app's.
      final defaults = NavigationSessionController(
        trip: rig.trip,
        preview: point,
        places: rig.places,
        drive: rig.drive,
        guidance: rig.guidance,
        system: rig.system,
        host: rig,
        notice: rig.notice,
        roadAlerts: RoadAlerts(
          settings: () => (cameras: false, incidents: false, community: false),
          language: () => 'en',
        ),
        journeys: rig.journeys,
        rewards: rig.rewards,
        feedback: rig.feedback,
        parking: (_) async => const [],
        fetchDetails: (place) async => PlaceDetails.fromJson({}),
        isPlus: () => false,
        hasAccount: () => false,
        language: () => 'en',
      );
      defaults.dispose();
    });

    test('a JustDrive engine that stops on its own ends Drive', () async {
      await rig.nav.startDrive();
      expect(rig.trip.value, const TripJustDrive());
      rig.drive.active = false;
      rig.drive.tick();
      expect(rig.trip.value, const TripIdle());
    });
  });

  group('arrival and parking', () {
    test('Plus prefetches parking and details, then shows the arrival '
        'panel', () async {
      rig.plus = true;
      await rig.previewed(cafe);
      final near = RoutePreviewController(
        trip: rig.trip,
        places: rig.places,
        planner: ({
          required origin,
          required destination,
          required stops,
          required mode,
          required headingDegrees,
          required avoid,
        }) async => planOf([route('near', metres: 250, to: destination)]),
        transit: ({required origin, required destination}) async =>
            planOf(const []),
        parking: (_) async => const [],
        routeLocation: () => here,
        gpsLocation: () => here,
        heading: () => null,
        cameras: () => const [],
        roadEvents: () => const [],
        cameraDataReady: () => false,
        setDriveRoute: rig.drive.setRoute,
        navigationOwnsRoute: () => rig.guidance.route != null,
        driveActive: () => rig.drive.active,
        notice: rig.notice,
        language: () => 'en',
        showRoute: () async {},
      );
      addTearDown(near.dispose);
      final nav = NavigationSessionController(
        trip: rig.trip,
        preview: near,
        places: rig.places,
        drive: rig.drive,
        guidance: rig.guidance,
        system: rig.system,
        host: rig,
        notice: rig.notice,
        roadAlerts: RoadAlerts(
          settings: () => (cameras: false, incidents: false, community: false),
          language: () => 'en',
        ),
        journeys: rig.journeys,
        rewards: rig.rewards,
        feedback: rig.feedback,
        parking: (_) async => const [carPark],
        fetchDetails: (place) async => PlaceDetails.fromJson({'name': 'Cafe'}),
        isPlus: () => rig.plus,
        hasAccount: () => false,
        language: () => 'en',
        inbox: ExternalNavigationInbox(const MethodChannel('test/near')),
      );
      addTearDown(nav.dispose);
      rig.nav.dispose();
      rig.disposed = true;
      await near.load();
      await nav.start();
      expect(rig.trip.value, const TripNavigating(arrival: true));
      await pumpEventQueue();
      expect(nav.arrivalParking, [carPark]);
      expect(nav.arrivalDetails, isNotNull);
      expect(nav.arrivalPrefetching, isFalse);
      // Plus lapsing hides the panel.
      rig.plus = false;
      rig.drive.tick();
      expect(rig.trip.value, const TripNavigating());
    });

    test('arrival prefetching survives failing lookups', () async {
      rig.plus = true;
      rig.parkingFails = true;
      rig.detailsFail = true;
      await rig.navigating();
      expect(rig.trip.value, const TripNavigating());
      // 1000 m away: no prefetch yet.
      expect(rig.parkingLookups, 0);
      expect(rig.nav.arrivalParking, isEmpty);
    });

    test('routing to an arrival car park, parking, and walking on', () async {
      rig.plus = true;
      await rig.navigating();
      await rig.nav.routeToArrivalParking(carPark);
      expect(rig.trip.value, const TripNavigating());
      expect(rig.nav.destination!.name, carPark.name);
      expect(rig.preview.parkingOriginalPlace, cafe);
      expect(rig.summaries, isEmpty);

      await arrive(rig, carPark.location);
      expect(rig.trip.value, const TripParkingLeg());
      await pumpEventQueue();
      expect(rig.nav.parkedCar!.name, carPark.name);
      expect(rig.nav.parkedCarLabel(), 'Parked just now');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(NavigationSessionController.parkedCarKey),
        isNotNull,
      );

      rig.nav.dismissParkingLeg();
      expect(rig.trip.value, const TripIdle());
      expect(rig.preview.selectedParking, isNull);
    });

    test(
      'ending near the chosen car park also starts the parking leg',
      () async {
        await rig.previewed(cafe);
        await rig.preview.selectParking(carPark);
        await rig.nav.start();
        rig.location = carPark.location;
        await rig.nav.stop(showSummary: false);
        expect(rig.trip.value, const TripParkingLeg());
        // Without Plus the car is not remembered.
        await pumpEventQueue();
        expect(rig.nav.parkedCar, isNull);
      },
    );

    test('no arrival parking without a destination or while ending', () async {
      await rig.nav.routeToArrivalParking(carPark);
      expect(rig.trip.value, const TripIdle());
    });

    test('a parked car is restored for 72 hours with its age', () async {
      final parkedAt = rig.now.subtract(const Duration(minutes: 30));
      SharedPreferences.setMockInitialValues({
        NavigationSessionController.parkedCarKey: jsonEncode({
          'address': 'Quay Street',
          'latitude': -37.2,
          'longitude': 174.9099,
          'parkedAt': parkedAt.toIso8601String(),
        }),
        'waybi.nav.keep_screen_awake': false,
      });
      expect(rig.nav.parkedCarLabel(), 'Parked car');
      await rig.nav.restoreSettings(await SharedPreferences.getInstance());
      expect(rig.nav.parkedCar!.name, 'Parked car');
      expect(rig.nav.parkedCarLabel(), 'Parked 30 min ago');
      rig.now = parkedAt.add(const Duration(hours: 5));
      expect(rig.nav.parkedCarLabel(), 'Parked 5 h ago');
      rig.now = parkedAt.add(const Duration(days: 2));
      expect(rig.nav.parkedCarLabel(), 'Parked 2 d ago');
      expect(rig.nav.keepScreenAwake, isFalse);
      expect(rig.drive.keepAwake, [false]);
    });

    test('a stale or damaged parked car record is dropped', () async {
      for (final record in [
        jsonEncode({
          'latitude': -37.2,
          'longitude': 174.9,
          'parkedAt': rig.now
              .subtract(const Duration(days: 4))
              .toIso8601String(),
        }),
        'not json',
      ]) {
        SharedPreferences.setMockInitialValues({
          NavigationSessionController.parkedCarKey: record,
        });
        final prefs = await SharedPreferences.getInstance();
        await rig.nav.restoreSettings(prefs);
        expect(
          prefs.getString(NavigationSessionController.parkedCarKey),
          isNull,
        );
        expect(rig.nav.parkedCar, isNull);
      }
      expect(rig.nav.keepScreenAwake, isTrue);
    });

    test('keeping the screen awake is saved and applied', () async {
      await rig.nav.setKeepScreenAwake(false);
      expect(rig.nav.keepScreenAwake, isFalse);
      expect(rig.drive.keepAwake, [false]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('waybi.nav.keep_screen_awake'), isFalse);
    });
  });

  group('Just Drive', () {
    test('opens after clearing the preview and closes again', () async {
      await rig.previewed(cafe);
      await rig.nav.startDrive();
      expect(rig.trip.value, const TripJustDrive());
      expect(rig.places.selected, isNull);
      expect(rig.calls, [
        'clear',
        'reset(drive)',
        'pause',
        'follow(headingUpFlat)',
        'refresh',
      ]);
      rig.calls.clear();
      await rig.nav.stopDrive();
      expect(rig.trip.value, const TripIdle());
      expect(rig.calls, ['mode(northUpFlat)', 'traffic', 'browse']);
    });

    test('waits for a first GPS fix', () async {
      rig.location = null;
      await rig.nav.startDrive();
      expect(rig.notice.value, contains('Waiting for your current GPS'));
      expect(rig.trip.value, const TripIdle());
      expect(rig.calls, ['browse', 'browse']);
    });

    test('starts once tracking finds the fix', () async {
      rig.location = null;
      rig.onStartBrowse = () => rig.location = here;
      await rig.nav.startDrive();
      expect(rig.trip.value, const TripJustDrive());
    });

    test('a failed or refused engine start returns to the map', () async {
      rig.drive.startError = StateError('no feed');
      await rig.nav.startDrive();
      expect(rig.trip.value, const TripIdle());
      expect(rig.notice.value, startsWith('Could not start Drive Mode.'));
      expect(rig.calls.last, 'browse');

      rig.drive.startError = null;
      rig.drive.startActive = false;
      await rig.nav.startDrive();
      expect(rig.trip.value, const TripIdle());
    });

    test('is not offered during guidance or a transit trip', () async {
      await rig.navigating();
      await rig.nav.startDrive();
      expect(rig.trip.value, const TripNavigating());
      // Stopping Drive ends guidance too.
      await rig.nav.stopDrive();
      expect(rig.trip.value, const TripIdle());
      expect(rig.summaries, hasLength(1));
    });
  });

  group('public transport', () {
    test('a transit trip shows only its itinerary', () async {
      await rig.previewed(cafe);
      await rig.preview.selectMode(WaybiTravelMode.transit);
      rig.calls.clear();
      await rig.nav.start();
      expect(rig.trip.value, const TripTransit());
      expect(rig.nav.transitRoute!.id, 'bus');
      expect(rig.nav.destinationTitle, 'Cafe');
      final paths = rig.nav.transitPaths;
      expect(paths.single.id, 'bus');
      expect(rig.nav.transitPaths, same(paths));
      expect(rig.preview.plan, isNull);
      expect(rig.places.selected, isNull);
      expect(rig.drive.prompts, hasLength(1));
      expect(rig.calls, [
        'mode(headingUpFlat)',
        'follow(null)',
        'refresh',
        'browse',
      ]);

      await rig.nav.startDrive();
      expect(rig.trip.value, const TripTransit());
      await rig.nav.stopTransit();
      expect(rig.trip.value, const TripIdle());
      expect(rig.nav.transitRoute, isNull);
      expect(rig.nav.transitPaths, isEmpty);
      await rig.nav.stopTransit();
      expect(rig.trip.value, const TripIdle());
    });
  });

  group('navigation links', () {
    const channel = MethodChannel('test/nav-links');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late ExternalNavigationInbox inbox;

    Future<void> link(String value) async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        messenger.setMockMethodCallHandler(channel, (_) async => null);
        return value;
      });
      await inbox.start();
    }

    setUp(() {
      rig.dispose();
      inbox = ExternalNavigationInbox(channel);
      rig = Rig(inbox: inbox);
    });
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      inbox.dispose();
    });

    test('a coordinate link previews the place', () async {
      await link('waybi://navigate?destination=-37.2,174.91&name=Cafe');
      expect(rig.frames, hasLength(1));
      await rig.frame();
      expect(rig.calls, ['pop']);
      expect(rig.places.selected!.place.name, 'Cafe');
      expect(rig.places.selected!.place.kind, PlaceKind.coordinate);
      expect(rig.trip.value, const TripPreviewing());
    });

    test('a place link only shows the place', () async {
      await link('geo-navigation:///place?coordinate=-37.2,174.91');
      await rig.frame();
      expect(rig.places.selected, isNotNull);
      expect(rig.trip.value, const TripPlaceSelected());
    });

    test('waits until the page is ready and no trip is starting', () async {
      rig.ready = false;
      await link('waybi://navigate?destination=-37.2,174.91');
      expect(rig.frames, isEmpty);
      rig.ready = true;
      await rig.previewed(cafe);
      rig.trip.dispatch(const StartRequested());
      rig.nav.scheduleHandOff();
      expect(rig.frames, isEmpty);
      rig.trip.dispatch(const StartAborted());
      await Future<void>.delayed(const Duration(milliseconds: 260));
      expect(rig.frames, hasLength(1));
    });

    test('an invalid link explains; an unrelated one is ignored', () async {
      await link('waybi://navigate?destination=999,999');
      await rig.frame();
      expect(rig.errors.single, contains('invalid destination'));
      await link('https://example.com/');
      await rig.frame();
      expect(rig.errors, hasLength(1));
      expect(rig.calls, isEmpty);
    });

    test('text locations are resolved by searching, in order', () async {
      rig.search = (query, purpose) async => PlaceSummary(
        name: query,
        address: '$query Road',
        location: query == 'Home'
            ? const GeoPoint(-37.21, 174.92)
            : const GeoPoint(-37.2, 174.905),
      );
      await link(
        'waybi://navigate?destination=Museum&source=Home&waypoint=Bakery&mode=walk',
      );
      await rig.frame();
      await pumpEventQueue();
      expect(rig.searches, [
        'Choose destination: Museum',
        'Choose starting point: Home',
        'Choose stop 1: Bakery',
      ]);
      expect(rig.preview.manualOrigin!.label, 'Home');
      expect(rig.preview.stops.single.label, 'Bakery');
      expect(rig.places.selected!.place.name, 'Museum');
      expect(rig.preview.mode, WaybiTravelMode.walk);
      expect(rig.preview.plan, isNotNull);
    });

    test('a cancelled search drops the link', () async {
      for (final value in [
        'waybi://navigate?destination=Museum',
        'waybi://navigate?destination=-37.2,174.91&source=Home',
        'waybi://navigate?destination=-37.2,174.91&waypoint=Bakery',
      ]) {
        await link(value);
        await rig.frame();
      }
      expect(rig.searches, hasLength(3));
      expect(rig.places.selected, isNull);
    });

    test('without a location the preview waits for one', () async {
      rig.location = null;
      await link('waybi://navigate?destination=-37.2,174.91');
      await rig.frame();
      expect(rig.preview.hasPending, isTrue);
      expect(rig.notice.value, contains('Waiting for your location'));
    });

    test('a failing search reports the link could not be opened', () async {
      rig.search = (_, _) async => throw StateError('search offline');
      await link('waybi://navigate?destination=Museum');
      await rig.frame();
      expect(rig.errors.single, contains('Could not open this destination'));
    });

    test('a newer link supersedes one still resolving', () async {
      final first = Completer<PlaceSummary?>();
      rig.search = (_, _) => first.future;
      await link('waybi://navigate?destination=Museum');
      await rig.frame();
      await link('waybi://navigate?destination=-37.2,174.91&name=Cafe');
      await rig.frame();
      first.complete(
        const PlaceSummary(
          name: 'Museum',
          address: '',
          location: GeoPoint(-37.2, 174.93),
        ),
      );
      await pumpEventQueue();
      expect(rig.places.selected!.place.name, 'Cafe');
    });

    test('a running trip ends only when the person agrees', () async {
      await rig.navigating();
      rig.confirm = false;
      await link('waybi://navigate?destination=-37.2,174.93&name=Museum');
      await rig.frame();
      expect(rig.confirmations, ['Museum']);
      expect(rig.trip.value, const TripNavigating());

      rig.confirm = true;
      await link('waybi://navigate?destination=-37.2,174.93&name=Museum');
      await rig.frame();
      await pumpEventQueue();
      expect(rig.summaries, isEmpty);
      expect(rig.places.selected!.place.name, 'Museum');
      expect(rig.trip.value, const TripPreviewing());
    });

    test('a link replaces a transit trip or Just Drive', () async {
      await rig.previewed(cafe);
      await rig.preview.selectMode(WaybiTravelMode.transit);
      await rig.nav.start();
      await link('waybi://navigate?destination=-37.2,174.93&name=Museum');
      await rig.frame();
      expect(rig.trip.value, const TripPreviewing());

      await rig.nav.startDrive();
      expect(rig.trip.value, const TripJustDrive());
      await link('waybi://navigate?destination=-37.2,174.93&name=Museum');
      await rig.frame();
      expect(rig.trip.value, const TripPreviewing());
      expect(rig.drive.active, isFalse);
    });

    test('a disposed session ignores scheduled links', () async {
      await link('waybi://navigate?destination=-37.2,174.91');
      rig.nav.dispose();
      rig.disposed = true;
      await rig.frame();
      expect(rig.places.selected, isNull);
      rig.nav.scheduleHandOff();
    });
  });
}
