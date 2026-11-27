import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart'
    show LatLng;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/app/place_selection_controller.dart';
import 'package:waybi_mobile/app/route_preview_controller.dart';
import 'package:waybi_mobile/app/trip_state.dart';
import 'package:waybi_mobile/data/parking_repository.dart';
import 'package:waybi_mobile/data/place_details_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/road_event.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/domain/route_preference.dart';
import 'package:waybi_mobile/domain/safety_camera.dart';
import 'package:waybi_mobile/widgets/explore_search.dart'
    show DestinationSuggestion;

const here = GeoPoint(-37.2, 174.9);
const cafe = PlaceSummary(
  name: 'Cafe',
  address: 'Harbour Road',
  location: GeoPoint(-37.2, 174.91),
);
const museum = PlaceSummary(
  name: 'Museum',
  address: 'Museum Road',
  location: GeoPoint(-37.2, 174.93),
);
const carPark = ParkingPlace(
  id: 'p1',
  name: 'Harbour car park',
  address: 'Quay Street',
  location: GeoPoint(-37.2, 174.909),
  distanceMeters: 90,
  source: 'AT',
);
const stop = DestinationSuggestion(
  label: 'Bakery',
  location: LatLng(latitude: -37.2, longitude: 174.905),
);

RouteOption route(
  String id, {
  WaybiTravelMode mode = WaybiTravelMode.drive,
  int seconds = 600,
  int metres = 1000,
  List<String> closureIds = const [],
  List<GeoPoint> points = const [here, GeoPoint(-37.2, 174.91)],
}) => RouteOption(
  id: id,
  mode: mode,
  durationSeconds: seconds,
  distanceMeters: metres,
  points: points,
  provider: 'independent',
  traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
  trafficIntervals: const [],
  closureIds: closureIds,
);

RoutePlan planOf(List<RouteOption> routes, {int stopsApplied = 0}) => RoutePlan(
  options: routes,
  trafficAvailable: true,
  provider: 'independent',
  stopsApplied: stopsApplied,
);

/// An official closure on the default route's line.
const closure = RoadEvent(
  id: 'closed',
  type: RoadEventType.roadClosure,
  location: GeoPoint(-37.2, 174.905),
  source: RoadEventSource(provider: 'NZTA', country: 'NZ', sourceId: 'c'),
);

typedef PlanRequest = ({
  GeoPoint origin,
  GeoPoint destination,
  List<GeoPoint> stops,
  WaybiTravelMode mode,
  double? heading,
  List<RouteExclusion> avoid,
});

class Rig {
  Rig() {
    places = PlaceSelectionController(
      fetchDetails: (place) async =>
          PlaceDetails.fromJson({'name': place.name}),
      reverse: (_, _) async => null,
      route: (_, _) async => route('eta'),
      language: () => language,
      quickRouteSuppressed: () => false,
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
          }) {
            final request = (
              origin: origin,
              destination: destination,
              stops: stops,
              mode: mode,
              heading: headingDegrees,
              avoid: avoid,
            );
            plans.add(request);
            return onPlan(request);
          },
      transit: ({required origin, required destination}) {
        transitRequests.add(origin);
        return onTransit();
      },
      parking: (destination) {
        parkingRequests.add(destination);
        return onParking();
      },
      routeLocation: () => location,
      gpsLocation: () => gps,
      heading: () => heading,
      cameras: () => cameras,
      roadEvents: () => events,
      cameraDataReady: () => cameras.isNotEmpty,
      setDriveRoute: driveRoutes.add,
      navigationOwnsRoute: () => navigationOwnsRoute,
      driveActive: () => driveActive,
      notice: notice,
      language: () => language,
      showRoute: () async => shown++,
      beforeLoad: () => beforeLoads++,
      onLoadStarted: loadStarts.add,
      recoverLocation: () => recoveries++,
      clock: () => now,
    );
  }

  final trip = TripMachine();
  final notice = ValueNotifier<String?>(null);
  late final PlaceSelectionController places;
  late final RoutePreviewController preview;

  GeoPoint? location = here;
  GeoPoint? gps = here;
  double? heading = 90;
  List<SafetyCamera> cameras = const [];
  List<RoadEvent> events = const [];
  bool navigationOwnsRoute = false;
  bool driveActive = false;
  String language = 'en';
  DateTime now = DateTime(2026, 11, 27, 9);

  final plans = <PlanRequest>[];
  final transitRequests = <GeoPoint>[];
  final parkingRequests = <GeoPoint>[];
  final driveRoutes = <RouteOption?>[];
  final loadStarts = <WaybiTravelMode>[];
  int shown = 0, beforeLoads = 0, recoveries = 0;

  Future<RoutePlan> Function(PlanRequest request) onPlan = (request) async =>
      planOf([
        route('${request.mode.name}-fast', mode: request.mode),
        route('${request.mode.name}-short', mode: request.mode, seconds: 700),
      ]);
  Future<RoutePlan> Function() onTransit = () async =>
      planOf([route('bus', mode: WaybiTravelMode.transit, seconds: 1500)]);
  Future<List<ParkingPlace>> Function() onParking = () async => const [carPark];

  void select(
    PlaceSummary place, {
    SelectionSource source = SelectionSource.search,
  }) {
    preview.beginPlace();
    places.select(place, source, originMap: MapProvider.independent);
  }

  Future<void> previewed(
    PlaceSummary place, {
    WaybiTravelMode mode = WaybiTravelMode.drive,
  }) async {
    select(place);
    await preview.load(mode: mode);
  }

  bool previewDisposed = false;

  void dispose() {
    if (!previewDisposed) preview.dispose();
    places.dispose();
    trip.dispose();
    notice.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Rig rig;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    rig = Rig();
  });
  tearDown(() => rig.dispose());

  group('loading a preview', () {
    test('plans from here, picks the recommended open route and fits the '
        'camera', () async {
      rig.events = const [closure];
      rig.onPlan = (request) async => planOf([
        route('closed'),
        route(
          'open',
          seconds: 900,
          points: const [here, GeoPoint(-37.21, 174.91)],
        ),
        route('walk', mode: WaybiTravelMode.walk),
      ]);
      await rig.previewed(cafe);
      await pumpEventQueue();

      expect(rig.beforeLoads, 1);
      expect(rig.loadStarts, [WaybiTravelMode.drive]);
      expect(rig.plans.single.origin, here);
      expect(rig.plans.single.destination, cafe.location);
      expect(rig.plans.single.heading, 90);
      expect(rig.plans.single.avoid, isEmpty);
      final preview = rig.preview;
      expect(preview.plan!.options, hasLength(3));
      expect(preview.mode, WaybiTravelMode.drive);
      // The closed route is ranked last; the start defaults to the open one.
      expect(preview.selectedRouteId, 'open');
      expect(preview.selectedRoute!.id, 'open');
      expect(preview.filteredRoutes.map((r) => r.id), ['open', 'closed']);
      expect(preview.closuresByRoute['closed'], hasLength(1));
      expect(preview.closuresByRoute['open'], isEmpty);
      expect(preview.needsRecovery(route('closed')), isTrue);
      expect(rig.driveRoutes.last!.id, 'open');
      expect(rig.shown, 1);
      expect(rig.trip.value, const TripPreviewing());
      expect(rig.parkingRequests, [cafe.location]);
      expect(preview.parkingPlaces, [carPark]);
      expect(preview.parkingLoading, isFalse);
      expect(preview.cameraSummaries['open']!.count, 0);
      expect(preview.preferenceSummaries.keys, ['closed', 'open']);
    });

    test('a walking preview has no heading, parking or drive route', () async {
      await rig.previewed(cafe, mode: WaybiTravelMode.walk);
      expect(rig.plans.single.mode, WaybiTravelMode.walk);
      expect(rig.plans.single.heading, isNull);
      expect(rig.parkingRequests, isEmpty);
      expect(rig.driveRoutes.last, isNull);
      expect(rig.preview.selectedRouteId, 'walk-fast');
      expect(rig.preview.filteredRoutes, hasLength(2));
    });

    test('without a location it waits for one, then previews on the next '
        'fix', () async {
      rig.location = null;
      rig.select(cafe);
      await rig.preview.load(mode: WaybiTravelMode.bicycle);
      expect(rig.plans, isEmpty);
      expect(rig.preview.hasPending, isTrue);
      expect(rig.recoveries, 1);
      expect(rig.notice.value, contains('Getting your location'));

      // Still no fix: nothing happens and the preview keeps waiting.
      rig.preview.retryPending();
      expect(rig.preview.hasPending, isTrue);

      rig.location = here;
      rig.preview.retryPending();
      await pumpEventQueue();
      expect(rig.preview.hasPending, isFalse);
      expect(rig.plans.single.mode, WaybiTravelMode.bicycle);
      expect(rig.preview.plan, isNotNull);
    });

    test('a waiting preview is dropped for another place, Drive or a '
        'transit trip', () async {
      rig.location = null;
      for (final cancel in <void Function()>[
        () => rig.select(museum),
        () => rig.driveActive = true,
        () {
          rig.trip
            ..dispatch(const PreviewSettled(hasPlan: true))
            ..dispatch(const StartRequested())
            ..dispatch(const TransitTripStarted());
        },
      ]) {
        rig.driveActive = false;
        rig.trip.dispatch(const TransitTripEnded());
        rig.select(cafe);
        await rig.preview.load();
        expect(rig.preview.hasPending, isTrue);
        cancel();
        rig.location = here;
        rig.preview.retryPending();
        expect(rig.preview.hasPending, isFalse);
        rig.location = null;
      }
      await pumpEventQueue();
      expect(rig.plans, isEmpty);
    });

    test('an explicit deferral and cancellation', () {
      rig.select(cafe);
      rig.preview.deferUntilLocated(rig.places.selected!, WaybiTravelMode.walk);
      expect(rig.preview.hasPending, isTrue);
      rig.preview.cancelPending();
      expect(rig.preview.hasPending, isFalse);
    });

    test('a waiting preview stays while a trip is starting', () async {
      rig.location = null;
      rig.select(cafe);
      await rig.preview.load();
      rig.trip
        ..dispatch(const PreviewSettled(hasPlan: true))
        ..dispatch(const StartRequested());
      rig.location = here;
      rig.preview.retryPending();
      expect(rig.preview.hasPending, isTrue);
    });

    test('a cross-Tasman drive is refused without a request', () async {
      rig.select(
        const PlaceSummary(
          name: 'Sydney',
          address: '',
          location: GeoPoint(-33.87, 151.21),
        ),
      );
      rig.trip.dispatch(const PreviewRequested());
      await rig.preview.load();
      expect(rig.plans, isEmpty);
      expect(rig.notice.value, isNotNull);
      expect(rig.trip.value, const TripPlaceSelected());
    });

    test('load without a selected place does nothing', () async {
      await rig.preview.load();
      expect(rig.plans, isEmpty);
      expect(rig.trip.value, const TripIdle());
    });

    test('a reload keeps the plan on screen until it is replaced, and a '
        'failed reload leaves it usable', () async {
      await rig.previewed(cafe);
      final first = rig.preview.plan;
      final gate = Completer<RoutePlan>();
      rig.onPlan = (_) => gate.future;
      final reload = rig.preview.addStop(stop);
      await pumpEventQueue();
      expect(rig.preview.stops, [stop]);
      expect(rig.plans.last.stops, [const GeoPoint(-37.2, 174.905)]);
      expect(rig.preview.plan, same(first));
      expect(rig.trip.value, const TripPreviewing(PreviewActivity.reloading));
      expect(rig.trip.value.previewLoading, isTrue);
      gate.completeError(StateError('Route service unavailable'));
      await reload;
      expect(rig.preview.plan, same(first));
      expect(rig.notice.value, isNotNull);
      expect(rig.trip.value, const TripPreviewing());
    });

    test('a first load that fails returns to the place card', () async {
      rig.onPlan = (_) async => throw StateError('offline');
      await rig.previewed(cafe);
      expect(rig.preview.plan, isNull);
      expect(rig.trip.value, const TripPlaceSelected());
      expect(rig.notice.value, isNotNull);
    });

    test('a late answer after another place or a closed preview is '
        'dropped', () async {
      final gate = Completer<RoutePlan>();
      rig.onPlan = (_) => gate.future;
      rig.select(cafe);
      final load = rig.preview.load();
      rig.select(museum);
      gate.complete(planOf([route('late')]));
      await load;
      expect(rig.preview.plan, isNull);
      expect(rig.shown, 0);
      expect(rig.trip.value, const TripPlaceSelected());

      final second = Completer<RoutePlan>();
      rig.onPlan = (_) => second.future;
      final again = rig.preview.load();
      rig.preview.clear();
      second.completeError(StateError('late failure'));
      await again;
      expect(rig.preview.plan, isNull);
      expect(rig.notice.value, isNull);
      expect(rig.trip.value, const TripIdle());
    });

    test('a manual origin routes from the link without a heading', () async {
      rig.select(museum);
      rig.preview.applyLink(
        origin: const DestinationSuggestion(
          label: 'Hotel',
          location: LatLng(latitude: -37.21, longitude: 174.92),
        ),
        stops: const [stop],
        mode: WaybiTravelMode.drive,
      );
      expect(rig.preview.manualOrigin!.label, 'Hotel');
      expect(rig.preview.origin, const GeoPoint(-37.21, 174.92));
      expect(rig.preview.headingDegrees, isNull);
      rig.location = null;
      await rig.preview.load();
      expect(rig.plans.single.origin, const GeoPoint(-37.21, 174.92));
      expect(rig.plans.single.heading, isNull);
      expect(rig.plans.single.stops, hasLength(1));
    });

    test('a link supersedes a preview in flight', () async {
      final gate = Completer<RoutePlan>();
      rig.onPlan = (_) => gate.future;
      rig.select(cafe);
      final load = rig.preview.load();
      rig.preview.applyLink(
        origin: null,
        stops: const [],
        mode: WaybiTravelMode.walk,
      );
      gate.complete(planOf([route('late')]));
      await load;
      expect(rig.preview.plan, isNull);
      expect(rig.preview.mode, WaybiTravelMode.walk);
    });
  });

  group('modes, routes and filters', () {
    test('switching to a mode in the plan selects its first route', () async {
      rig.onPlan = (_) async =>
          planOf([route('drive'), route('walk', mode: WaybiTravelMode.walk)]);
      await rig.previewed(cafe);
      await rig.preview.selectMode(WaybiTravelMode.walk);
      expect(rig.preview.mode, WaybiTravelMode.walk);
      expect(rig.preview.selectedRouteId, 'walk');
      expect(rig.driveRoutes.last, isNull);
      await rig.preview.selectMode(WaybiTravelMode.drive);
      expect(rig.preview.selectedRouteId, 'drive');
      expect(rig.driveRoutes.last!.id, 'drive');
      expect(rig.plans, hasLength(1));
    });

    test('a mode missing from the plan is planned', () async {
      await rig.previewed(cafe);
      await rig.preview.selectMode(WaybiTravelMode.bicycle);
      expect(rig.plans.last.mode, WaybiTravelMode.bicycle);
      expect(rig.preview.mode, WaybiTravelMode.bicycle);
    });

    test('selectMode without a plan does nothing', () async {
      await rig.preview.selectMode(WaybiTravelMode.walk);
      expect(rig.plans, isEmpty);
    });

    test('transit is merged into the plan from the GPS fix', () async {
      rig.location = const GeoPoint(-37.2, 174.901);
      await rig.previewed(cafe);
      await rig.preview.selectMode(WaybiTravelMode.transit);
      expect(rig.transitRequests, [here]);
      expect(rig.preview.plan!.options.map((r) => r.id), [
        'drive-fast',
        'drive-short',
        'bus',
      ]);
      expect(rig.preview.mode, WaybiTravelMode.transit);
      expect(rig.preview.selectedRouteId, 'bus');
      expect(rig.notice.value, isNull);
      expect(rig.trip.value, const TripPreviewing());
      // A second visit reuses the merged itineraries.
      await rig.preview.selectMode(WaybiTravelMode.drive);
      await rig.preview.selectMode(WaybiTravelMode.transit);
      expect(rig.transitRequests, hasLength(1));
    });

    test('no itinerary and failures explain themselves', () async {
      await rig.previewed(cafe);
      rig.onTransit = () async => planOf(const []);
      await rig.preview.selectMode(WaybiTravelMode.transit);
      expect(rig.notice.value, contains('No public transport routes'));
      expect(rig.preview.mode, WaybiTravelMode.drive);

      rig.onTransit = () async =>
          throw StateError('No public-transport route available');
      expect(await rig.preview.loadTransit(), isEmpty);
      expect(rig.notice.value, contains('No public transport routes'));

      rig.onTransit = () async => throw StateError('timeout');
      expect(await rig.preview.loadTransit(), isEmpty);
      expect(
        rig.notice.value,
        contains('Could not calculate public transport'),
      );
      expect(rig.trip.value, const TripPreviewing());
      expect(RoutePreviewController.isNoTransitRoute(StateError('x')), isFalse);
    });

    test('a transit answer after the preview closed revives nothing', () async {
      await rig.previewed(cafe);
      final gate = Completer<RoutePlan>();
      rig.onTransit = () => gate.future;
      final selection = rig.preview.selectMode(WaybiTravelMode.transit);
      expect(rig.notice.value, contains('Calculating'));
      expect(
        rig.trip.value,
        const TripPreviewing(PreviewActivity.loadingTransit),
      );
      rig.preview.closeToPlace();
      gate.complete(planOf([route('bus', mode: WaybiTravelMode.transit)]));
      await selection;
      expect(rig.preview.plan, isNull);
      expect(rig.notice.value, isNull);
      expect(rig.trip.value, const TripPlaceSelected());
    });

    test('the last tapped mode wins over a slow transit answer', () async {
      await rig.previewed(cafe);
      final gate = Completer<RoutePlan>();
      rig.onTransit = () => gate.future;
      final transit = rig.preview.selectMode(WaybiTravelMode.transit);
      await rig.preview.selectMode(WaybiTravelMode.drive);
      gate.complete(planOf([route('bus', mode: WaybiTravelMode.transit)]));
      await transit;
      expect(rig.preview.mode, WaybiTravelMode.drive);
    });

    test('transit needs a place, an origin and a plan', () async {
      expect(await rig.preview.loadTransit(), isEmpty);
      rig.select(cafe);
      expect(await rig.preview.loadTransit(), isEmpty);
      expect(rig.transitRequests, isEmpty);
    });

    test(
      'choosing a route or filter moves the drive route and camera',
      () async {
        rig.onPlan = (_) async => planOf([
          route('quick', seconds: 500, metres: 3000),
          route('short', seconds: 800, metres: 900),
        ]);
        await rig.previewed(cafe);
        rig.preview.selectRoute(rig.preview.plan!.options.last);
        expect(rig.preview.selectedRouteId, 'short');
        expect(rig.driveRoutes.last!.id, 'short');
        rig.preview.selectFilter(RouteFilter.fastest);
        expect(rig.preview.filter, RouteFilter.fastest);
        expect(rig.preview.selectedRouteId, 'quick');
        rig.preview.selectFilter(RouteFilter.shortest);
        expect(rig.preview.selectedRouteId, 'short');
        expect(rig.driveRoutes.last!.id, 'short');
        expect(rig.shown, 4);
        // With camera data, "with cameras" can leave no route at all.
        rig.cameras = const [
          SafetyCamera(
            id: 'far',
            name: 'Far camera',
            region: 'Auckland',
            suburb: 'City',
            location: 'Elsewhere',
            type: 'Spot speed',
            latitude: -36.8,
            longitude: 174.7,
          ),
        ];
        rig.preview.refreshSummaries();
        rig.preview.selectFilter(RouteFilter.withCameras);
        expect(rig.preview.filteredRoutes, isEmpty);
        expect(rig.preview.selectedRoute, isNull);
      },
    );

    test('paths are reused until the selection changes', () async {
      expect(rig.preview.paths, isEmpty);
      await rig.previewed(cafe);
      final paths = rig.preview.paths;
      expect(paths.map((p) => (p.id, p.active)), [
        ('drive-fast', true),
        ('drive-short', false),
      ]);
      expect(rig.preview.paths, same(paths));
      rig.preview.selectRoute(rig.preview.plan!.options.last);
      expect(rig.preview.paths, isNot(same(paths)));
      expect(rig.preview.paths.last.active, isTrue);
    });

    test('closures are cached per route and events for 30 seconds', () async {
      final line = route('line');
      rig.events = const [closure];
      final first = rig.preview.closuresOn(line);
      expect(first, hasLength(1));
      expect(rig.preview.closuresOn(line), same(first));
      rig.now = rig.now.add(const Duration(seconds: 31));
      expect(rig.preview.closuresOn(line), isNot(same(first)));
      for (var i = 0; i < 14; i++) {
        rig.preview.closuresOn(route('r$i'));
      }
      // The oldest entries were evicted and are measured again.
      expect(rig.preview.closuresOn(route('r0')), hasLength(1));
    });
  });

  group('detours', () {
    test('switches to a clear alternative without a request', () async {
      rig.onPlan = (_) async => planOf([
        route('blocked', seconds: 400, closureIds: const ['x']),
        route('clear', seconds: 900),
      ]);
      await rig.previewed(cafe);
      rig.preview.selectFilter(RouteFilter.recommended);
      rig.preview.selectRoute(rig.preview.plan!.options.first);
      expect(rig.preview.needsRecovery(rig.preview.selectedRoute!), isTrue);
      await rig.preview.recoverBlockedRoute();
      expect(rig.preview.selectedRouteId, 'clear');
      expect(rig.preview.recoveryMessage, contains('clear alternative'));
      expect(rig.plans, hasLength(1));
    });

    test(
      'asks for a detour that avoids the closure and keeps other modes',
      () async {
        rig.events = const [closure];
        rig.onPlan = (_) async => planOf([
          route('closed'),
          route('walk', mode: WaybiTravelMode.walk),
        ]);
        await rig.previewed(cafe);
        final gate = Completer<RoutePlan>();
        rig.onPlan = (request) => gate.future;
        final detour = rig.preview.recoverBlockedRoute();
        expect(
          rig.trip.value,
          const TripPreviewing(PreviewActivity.findingDetour),
        );
        expect(rig.trip.value.busy, isTrue);
        expect(rig.preview.recoveryMessage, contains('Finding a route'));
        // A second tap while searching does nothing.
        await rig.preview.recoverBlockedRoute();
        expect(rig.plans, hasLength(2));
        expect(rig.plans.last.avoid, isNotEmpty);
        expect(rig.plans.last.mode, WaybiTravelMode.drive);
        gate.complete(
          planOf([
            route('detour', points: const [here, GeoPoint(-37.19, 174.91)]),
            route('still-closed', closureIds: const ['x']),
          ]),
        );
        await detour;
        expect(rig.preview.plan!.options.map((r) => r.id), ['detour', 'walk']);
        expect(rig.preview.selectedRouteId, 'detour');
        expect(rig.preview.recoveryMessage, contains('Detour ready'));
        expect(rig.driveRoutes.last!.id, 'detour');
        expect(rig.trip.value, const TripPreviewing());
      },
    );

    test('a detour hidden by the filter says so', () async {
      rig.events = const [closure];
      // A camera on the closed road: only it passes "with cameras".
      rig.cameras = const [
        SafetyCamera(
          id: 'on-route',
          name: 'Harbour camera',
          region: 'Auckland',
          suburb: 'City',
          location: 'Harbour Road',
          type: 'Spot speed',
          latitude: -37.2,
          longitude: 174.907,
        ),
      ];
      rig.onPlan = (_) async => planOf([
        route('closed'),
        route('clear', points: const [here, GeoPoint(-37.19, 174.91)]),
      ]);
      await rig.previewed(cafe);
      expect(rig.preview.cameraSummaries['closed']!.count, 1);
      rig.preview.selectFilter(RouteFilter.withCameras);
      expect(rig.preview.selectedRoute!.id, 'closed');
      rig.onPlan = (_) async => planOf([
        route('detour', points: const [here, GeoPoint(-37.19, 174.91)]),
      ]);
      await rig.preview.recoverBlockedRoute();
      expect(rig.preview.selectedRouteId, isNull);
      expect(rig.preview.recoveryMessage, contains('Change your filter'));
    });

    test('no verified detour keeps the plan and explains', () async {
      rig.events = const [closure];
      rig.onPlan = (_) async => planOf([route('closed')]);
      await rig.previewed(cafe);
      rig.onPlan = (_) async => planOf([route('also-closed')]);
      await rig.preview.recoverBlockedRoute();
      expect(rig.preview.plan!.options.single.id, 'closed');
      expect(rig.preview.recoveryMessage, contains('No verified detour'));
      expect(rig.trip.value, const TripPreviewing());
    });

    test('waits for a location before searching', () async {
      rig.events = const [closure];
      rig.onPlan = (_) async => planOf([route('closed')]);
      await rig.previewed(cafe);
      rig.location = null;
      await rig.preview.recoverBlockedRoute();
      expect(
        rig.preview.recoveryMessage,
        contains('Waiting for your location'),
      );
      expect(rig.recoveries, 1);
      expect(rig.plans, hasLength(1));
    });

    test('a detour answer after the preview closed is dropped', () async {
      rig.events = const [closure];
      rig.onPlan = (_) async => planOf([route('closed')]);
      await rig.previewed(cafe);
      final gate = Completer<RoutePlan>();
      rig.onPlan = (_) => gate.future;
      final detour = rig.preview.recoverBlockedRoute();
      rig.preview.closeToPlace();
      gate.completeError(StateError('late'));
      await detour;
      expect(rig.preview.recoveryMessage, isNull);
      expect(rig.trip.value, const TripPlaceSelected());
    });

    test('nothing to recover without a plan', () async {
      await rig.preview.recoverBlockedRoute();
      expect(rig.plans, isEmpty);
    });
  });

  group('parking', () {
    test('a failed or superseded parking lookup leaves no car parks', () async {
      rig.onParking = () async => throw StateError('parking offline');
      await rig.previewed(cafe);
      await pumpEventQueue();
      expect(rig.preview.parkingPlaces, isEmpty);
      expect(rig.preview.parkingLoading, isFalse);

      final gate = Completer<List<ParkingPlace>>();
      rig.onParking = () => gate.future;
      await rig.preview.load();
      expect(rig.preview.parkingLoading, isTrue);
      rig.select(museum);
      gate.complete(const [carPark]);
      await pumpEventQueue();
      expect(rig.preview.parkingPlaces, isEmpty);
      expect(rig.preview.parkingLoading, isFalse);
    });

    test(
      'a car park leads the preview; the destination can be restored',
      () async {
        await rig.previewed(cafe);
        await rig.preview.addStop(stop);
        await rig.preview.selectParking(carPark);
        expect(rig.preview.selectedParking, carPark);
        expect(rig.preview.parkingOriginalPlace, cafe);
        expect(rig.places.selected!.place.name, carPark.name);
        expect(rig.preview.stops, isEmpty);
        expect(rig.plans.last.destination, carPark.location);
        // A car park preview does not look up parking again.
        expect(rig.parkingRequests, hasLength(2));
        // Choosing another car park keeps the original destination.
        await rig.preview.selectParking(carPark);
        expect(rig.preview.parkingOriginalPlace, cafe);

        await rig.preview.restoreDirectDestination();
        expect(rig.preview.selectedParking, isNull);
        expect(rig.preview.parkingOriginalPlace, isNull);
        expect(rig.places.selected!.place, cafe);
        expect(rig.plans.last.destination, cafe.location);
        await rig.preview.restoreDirectDestination();
        expect(rig.plans, hasLength(5));
      },
    );

    test('selecting parking needs a destination', () async {
      await rig.preview.selectParking(carPark);
      expect(rig.preview.selectedParking, isNull);
    });

    test('after parking, the destination is walked from here', () async {
      rig.select(cafe);
      rig.preview.applyLink(
        origin: const DestinationSuggestion(
          label: 'Hotel',
          location: LatLng(latitude: -37.21, longitude: 174.92),
        ),
        stops: const [stop],
        mode: WaybiTravelMode.drive,
      );
      rig.preview.targetParking(cafe, carPark);
      expect(rig.trip.value, const TripPlaceSelected());
      expect(rig.preview.selectedParking, carPark);
      expect(rig.places.selected!.place.name, carPark.name);
      expect(rig.preview.stops, isEmpty);
      await rig.preview.continueOnFoot();
      expect(rig.preview.manualOrigin, isNull);
      expect(rig.preview.selectedParking, isNull);
      expect(rig.plans.single.mode, WaybiTravelMode.walk);
      expect(rig.plans.single.origin, here);
      expect(rig.plans.single.destination, cafe.location);
      await rig.preview.continueOnFoot();
      expect(rig.plans, hasLength(1));
    });

    test('a dismissed parking leg forgets its target', () {
      rig.preview.targetParking(cafe, carPark);
      rig.preview.forgetParkingTarget();
      expect(rig.preview.selectedParking, isNull);
      expect(rig.preview.parkingOriginalPlace, isNull);
    });
  });

  group('closing and handing off', () {
    test('closing to the place card keeps the place and its origin', () async {
      await rig.previewed(cafe);
      await rig.preview.addStop(stop);
      rig.preview.selectFilter(RouteFilter.shortest);
      rig.preview.closeToPlace();
      expect(rig.preview.plan, isNull);
      expect(rig.preview.mode, WaybiTravelMode.drive);
      expect(rig.preview.filter, RouteFilter.recommended);
      expect(rig.preview.stops, isEmpty);
      expect(rig.preview.parkingPlaces, isEmpty);
      expect(rig.places.selected!.place, cafe);
      expect(rig.driveRoutes.last, isNull);
      expect(rig.trip.value, const TripPlaceSelected());
    });

    test('clearing drops the place, but never a route guidance owns', () async {
      await rig.previewed(cafe);
      await rig.preview.selectParking(carPark);
      rig.navigationOwnsRoute = true;
      final routes = rig.driveRoutes.length;
      rig.preview.clear();
      expect(rig.driveRoutes, hasLength(routes));
      expect(rig.places.selected, isNull);
      expect(rig.preview.selectedParking, isNull);
      expect(rig.trip.value, const TripIdle());
      rig.preview.releaseDriveRoute();
      expect(rig.driveRoutes, hasLength(routes));
      rig.navigationOwnsRoute = false;
      rig.preview.releaseDriveRoute();
      expect(rig.driveRoutes.last, isNull);
    });

    test(
      'guidance keeps the mode and car park; transit keeps nothing',
      () async {
        await rig.previewed(cafe);
        await rig.preview.selectParking(carPark);
        rig.preview.handOffToGuidance();
        expect(rig.preview.plan, isNull);
        expect(rig.preview.selectedRouteId, isNull);
        expect(rig.preview.selectedParking, carPark);
        expect(rig.preview.mode, WaybiTravelMode.drive);

        rig.select(museum);
        expect(rig.preview.selectedParking, isNull);
        await rig.preview.load(mode: WaybiTravelMode.walk);
        final gate = Completer<RoutePlan>();
        rig.onPlan = (_) => gate.future;
        final reload = rig.preview.load(mode: WaybiTravelMode.walk);
        rig.preview.handOffToTransit();
        gate.complete(planOf([route('late')]));
        await reload;
        expect(rig.preview.plan, isNull);
        expect(rig.preview.recoveryMessage, isNull);
        expect(rig.preview.parkingPlaces, isEmpty);
        expect(rig.driveRoutes.last, isNull);
      },
    );

    test('engine camera changes recount the plan only', () async {
      rig.preview.refreshSummaries();
      expect(rig.preview.cameraSummaries, isEmpty);
      rig.onPlan = (_) async =>
          planOf([route('drive'), route('walk', mode: WaybiTravelMode.walk)]);
      await rig.previewed(cafe);
      rig.cameras = const [
        SafetyCamera(
          id: 'on-route',
          name: 'Harbour camera',
          region: 'Auckland',
          suburb: 'City',
          location: 'Harbour Road',
          type: 'Spot speed',
          latitude: -37.2,
          longitude: 174.905,
        ),
      ];
      var notified = 0;
      rig.preview.addListener(() => notified++);
      rig.preview.refreshSummaries();
      expect(notified, 0);
      expect(rig.preview.cameraSummaries['walk']!.count, 0);
      expect(rig.preview.preferenceSummaries.keys, ['drive']);
    });

    test('a disposed controller ignores late answers', () async {
      final gate = Completer<RoutePlan>();
      rig.onPlan = (_) => gate.future;
      rig.select(cafe);
      final load = rig.preview.load();
      rig.preview.dispose();
      rig.previewDisposed = true;
      gate.complete(planOf([route('late')]));
      await load;
      expect(rig.preview.plan, isNull);
      expect(rig.shown, 0);
    });
  });

  group('saved routes', () {
    test(
      'saves the selected route with Waybi geometry for Google points',
      () async {
        final place = const PlaceSummary(
          name: 'Picked',
          address: '',
          location: GeoPoint(-37.2001, 174.9101),
        );
        rig.preview.rememberSessionCoordinate(place.location);
        expect(await rig.preview.saveCurrentRoute(), isFalse);
        await rig.previewed(place);
        await rig.preview.addStop(stop);
        expect(await rig.preview.saveCurrentRoute(), isTrue);
        expect(await rig.preview.saveCurrentRoute(), isTrue);
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getStringList('waybi.saved.routes')!;
        expect(saved, hasLength(1));
        final record = jsonDecode(saved.single) as Map<String, dynamic>;
        expect(record['destination'], {
          'name': 'Picked',
          'latitude': -37.2,
          'longitude': 174.91,
        });
        expect(record['mode'], 'drive');
        expect(record['stops'], [
          {'label': 'Bakery', 'latitude': -37.2, 'longitude': 174.905},
        ]);
        expect(record['savedAt'], rig.now.toIso8601String());
      },
    );

    test('keeps the last 20 and survives damaged records', () async {
      SharedPreferences.setMockInitialValues({
        'waybi.saved.routes': [
          'not json',
          for (var i = 0; i < 20; i++)
            jsonEncode({
              'destination': {'name': 'Old $i'},
            }),
        ],
      });
      await rig.previewed(cafe);
      expect(await rig.preview.saveCurrentRoute(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('waybi.saved.routes')!;
      expect(saved, hasLength(20));
      expect(jsonDecode(saved.first)['destination']['name'], 'Cafe');
    });
  });
}
