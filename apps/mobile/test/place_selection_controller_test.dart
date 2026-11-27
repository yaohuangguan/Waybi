import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/app/place_selection_controller.dart';
import 'package:waybi_mobile/data/http_guard.dart';
import 'package:waybi_mobile/data/place_details_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';

const here = GeoPoint(-37.2, 174.9);
const cafe = PlaceSummary(
  name: 'Cafe',
  address: 'Harbour Road',
  location: GeoPoint(-37.2, 174.91),
);
const park = PlaceSummary(
  name: 'Park',
  address: 'Park Road',
  location: GeoPoint(-37.2, 174.93),
);

RouteOption route(String id) => RouteOption(
  id: id,
  mode: WaybiTravelMode.drive,
  durationSeconds: 600,
  distanceMeters: 1000,
  points: const [here, GeoPoint(-37.2, 174.91)],
  provider: 'independent',
  traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
  trafficIntervals: const [],
);

void main() {
  late DateTime now;
  late bool suppressed;
  late List<GeoPoint> routed;
  late Map<GeoPoint, Completer<RouteOption>> held;
  late Object? routeError;
  late Object? detailsError;
  late PlaceSummary? reversed;
  late Completer<PlaceSummary?>? reverseGate;

  PlaceSelectionController controller({String language = 'en'}) {
    final places = PlaceSelectionController(
      fetchDetails: (place) async {
        if (detailsError != null) throw detailsError!;
        return PlaceDetails.fromJson({'name': place.name});
      },
      reverse: (point, preferredName) async {
        if (reverseGate != null) return reverseGate!.future;
        return reversed;
      },
      route: (origin, destination) {
        routed.add(destination);
        final gate = held[destination];
        if (gate != null) return gate.future;
        if (routeError != null) return Future.error(routeError!);
        return Future.value(route('${destination.longitude}'));
      },
      language: () => language,
      quickRouteSuppressed: () => suppressed,
      clock: () => now,
    );
    addTearDown(places.dispose);
    return places;
  }

  setUp(() {
    now = DateTime(2026, 11, 27, 8);
    suppressed = false;
    routed = [];
    held = {};
    routeError = null;
    detailsError = null;
    reversed = null;
    reverseGate = null;
  });

  test(
    'selecting loads details; a failure explains itself and retries',
    () async {
      final places = controller(language: 'zh');
      detailsError = StateError('offline');
      places.select(
        cafe,
        SelectionSource.search,
        originMap: MapProvider.independent,
      );
      expect(places.selected!.place, cafe);
      expect(places.detailsLoading, isTrue);
      await pumpEventQueue();
      expect(places.detailsLoading, isFalse);
      expect(places.detailsError, isNotNull);
      detailsError = null;
      places.retryDetails();
      await pumpEventQueue();
      expect(places.detailsError, isNull);
      expect(places.details?.name, 'Cafe');

      final seeded = PlaceDetails.fromJson({'name': 'Seeded'});
      places.select(
        park,
        SelectionSource.explore,
        originMap: MapProvider.independent,
        seedDetails: seeded,
      );
      expect(places.details, same(seeded));
      places.clear();
      expect(places.selected, isNull);
      expect(places.details, isNull);
      places.retryDetails();
    },
  );

  test('map taps without an address are reverse geocoded, unless the user '
      'moved on', () async {
    final places = controller();
    reversed = const PlaceSummary(
      name: 'Resolved',
      address: '12 Harbour Road',
      location: GeoPoint(-37.2, 174.91),
      category: 'cafe',
      reference: ProviderReference('osm', 'node:1'),
    );
    const pin = PlaceSummary(
      name: 'Dropped pin',
      address: '',
      location: GeoPoint(-37.2, 174.91),
      kind: PlaceKind.coordinate,
    );
    places.select(pin, SelectionSource.map, originMap: MapProvider.independent);
    await pumpEventQueue();
    expect(places.selected!.place.name, 'Resolved');
    expect(places.selected!.place.reference?.provider, 'osm');

    places.select(
      pin,
      SelectionSource.longPress,
      originMap: MapProvider.independent,
    );
    await pumpEventQueue();
    expect(
      places.selected!.place.name,
      'Dropped pin',
      reason: 'a pin keeps its name',
    );
    expect(places.selected!.place.reference, isNull);

    reverseGate = Completer();
    places.select(pin, SelectionSource.map, originMap: MapProvider.independent);
    places.select(
      cafe,
      SelectionSource.search,
      originMap: MapProvider.independent,
    );
    reverseGate!.complete(reversed);
    await pumpEventQueue();
    expect(places.selected!.place, cafe, reason: 'stale lookup ignored');

    reverseGate = Completer();
    places.select(pin, SelectionSource.map, originMap: MapProvider.independent);
    reverseGate!.completeError(StateError('offline'));
    await pumpEventQueue();
    expect(places.selected!.place, pin);
  });

  test('the drive ETA is cached for five minutes within 300 m', () async {
    final places = controller();
    await places.loadQuickRoute(here);
    expect(routed, isEmpty, reason: 'nothing selected');
    places.select(
      cafe,
      SelectionSource.search,
      originMap: MapProvider.independent,
    );
    await places.loadQuickRoute(null);
    suppressed = true;
    await places.loadQuickRoute(here);
    expect(routed, isEmpty);
    suppressed = false;
    await places.loadQuickRoute(here);
    expect(places.quickRoute, isNotNull);
    expect(routed, hasLength(1));
    await places.loadQuickRoute(here);
    expect(routed, hasLength(1), reason: 'fresh');
    // Re-selecting the same place shows the cached ETA without a request.
    places.select(
      cafe,
      SelectionSource.search,
      originMap: MapProvider.independent,
    );
    await places.loadQuickRoute(here);
    expect(places.quickRoute, isNotNull);
    expect(routed, hasLength(1));
    await places.loadQuickRoute(const GeoPoint(-37.2, 174.8));
    expect(routed, hasLength(2), reason: 'moved more than 300 m');
    now = now.add(const Duration(minutes: 6));
    await places.loadQuickRoute(const GeoPoint(-37.2, 174.8));
    expect(routed, hasLength(3), reason: 'older than five minutes');
  });

  test('failures back off and respect Retry-After', () async {
    final places = controller();
    places.select(
      cafe,
      SelectionSource.search,
      originMap: MapProvider.independent,
    );
    routeError = StateError('offline');
    await places.loadQuickRoute(here);
    final issue = places.quickRouteIssue;
    expect(issue, isNotNull);
    for (var i = 0; i < 20; i++) {
      await places.loadQuickRoute(here);
    }
    expect(routed, hasLength(1));
    expect(places.quickRouteIssue, issue);
    now = now.add(const Duration(seconds: 16));
    await places.loadQuickRoute(here);
    expect(routed, hasLength(2));
    now = now.add(const Duration(seconds: 16));
    await places.loadQuickRoute(here);
    expect(routed, hasLength(2), reason: 'second failure waits 30 s');
    expect(PlaceSelectionController.backoff(1, StateError('x')).inSeconds, 15);
    expect(PlaceSelectionController.backoff(9, StateError('x')).inSeconds, 300);
    expect(
      PlaceSelectionController.backoff(
        1,
        RateLimitedException(const Duration(minutes: 2)),
      ),
      const Duration(minutes: 2),
    );
  });

  test('an earlier place never overwrites the card of the next one', () async {
    final places = controller();
    places.select(
      cafe,
      SelectionSource.search,
      originMap: MapProvider.independent,
    );
    held[cafe.location] = Completer();
    final slow = places.loadQuickRoute(here);
    expect(places.quickRouteLoading, isTrue);
    await places.loadQuickRoute(here);
    expect(routed, hasLength(1), reason: 'one request per place at a time');
    places.select(
      park,
      SelectionSource.search,
      originMap: MapProvider.independent,
    );
    await places.loadQuickRoute(here);
    final parkRoute = places.quickRoute;
    expect(parkRoute, isNotNull);
    held[cafe.location]!.completeError(StateError('offline'));
    await slow;
    expect(places.quickRoute, same(parkRoute));
    expect(places.quickRouteIssue, isNull);
  });

  test('cross-Tasman destinations are explained without routing', () async {
    final places = controller();
    places.select(
      const PlaceSummary(
        name: 'Sydney',
        address: 'NSW',
        location: GeoPoint(-33.87, 151.21),
      ),
      SelectionSource.search,
      originMap: MapProvider.independent,
    );
    await places.loadQuickRoute(here);
    expect(routed, isEmpty);
    expect(places.quickRouteIssue, isNotNull);
    expect(PlaceSelectionController.routeKey(cafe), '-37.20000,174.91000');
    expect(
      PlaceSelectionController.routeKey(
        const PlaceSummary(
          name: 'x',
          address: '',
          location: here,
          reference: ProviderReference('osm', 'way:7'),
        ),
      ),
      'osm:way:7',
    );
    places.replace(
      const SelectedPlace(
        cafe,
        SelectionSource.map,
        originMap: MapProvider.independent,
      ),
    );
    expect(places.selected!.place, cafe);
  });
}
