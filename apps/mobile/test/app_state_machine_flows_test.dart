import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart'
    show LatLng;
import 'package:http/http.dart' as http;
import 'package:waybi_mobile/data/transit_lane_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/drive/drive_engine.dart';
import 'package:waybi_mobile/providers/independent_map_renderer.dart';
import 'package:waybi_mobile/providers/independent_map_style.dart';
import 'package:waybi_mobile/widgets/drive_hud.dart';
import 'package:waybi_mobile/widgets/explore_search.dart';
import 'package:waybi_mobile/widgets/independent_navigation_overlay.dart';
import 'package:waybi_mobile/widgets/place_details_content.dart';
import 'package:waybi_mobile/widgets/profile_page.dart';
import 'package:waybi_mobile/widgets/route_preview_sheet.dart';
import 'package:waybi_mobile/widgets/transit_trip_overlay.dart';
import 'package:waybi_mobile/widgets/trips_page.dart';

import 'support/app_harness.dart';

/// Regression flows for the home page's trip state machine: every async
/// step is cancellable, superseded answers are ignored, and a failure always
/// leaves a usable state.
void flow(String name, Future<void> Function(WidgetTester, AppHarness) body) {
  testWidgets(name, (t) async {
    final h = AppHarness(t);
    await http.runWithClient(() async {
      await body(t, h);
      await h.dispose();
    }, () => h.client);
  });
}

PlaceDetailsContent details(WidgetTester t) =>
    t.widget(find.byType(PlaceDetailsContent));
RoutePreviewSheet preview(WidgetTester t) =>
    t.widget(find.byType(RoutePreviewSheet));

/// The home page's own back handler (the one wrapping its Scaffold).
bool homeCanPop(WidgetTester t) => t
    .widget<PopScope>(
      find.byWidgetPredicate((w) => w is PopScope && w.child is Scaffold),
    )
    .canPop;

Future<void> openPreview(WidgetTester t, AppHarness h) async {
  await h.select();
  await h.act(details(t).onNavigate);
  expect(find.byType(RoutePreviewSheet), findsOneWidget);
}

Future<void> settle(AppHarness h) async {
  await h.tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await h.frames(8);
}

/// Browse location is still running when a new fix moves the map's puck.
Future<void> expectBrowseLocationRunning(AppHarness h) async {
  h.gps.current = AppGps.position(longitude: 174.90008, time: DateTime.now());
  h.gps.positions.add(h.gps.current);
  await h.frames();
  expect(h.map.location, const GeoPoint(-37.2, 174.90008));
}

Map<String, dynamic> transitItinerary(String line, double to) => {
  'duration': 1260,
  'transfers': 0,
  'legs': [
    {
      'mode': 'BUS',
      'routeShortName': line,
      'headsign': 'City',
      'from': {'name': 'Airport', 'lat': -37.2, 'lon': 174.9},
      'to': {'name': 'City centre', 'lat': -37.2, 'lon': to},
      'intermediateStops': const [],
      'legGeometry': {
        'precision': 6,
        'points': encodePolyline([
          const GeoPoint(-37.2, 174.9),
          GeoPoint(-37.2, to),
        ]),
      },
    },
  ],
};

String encodePolyline(List<GeoPoint> points) {
  final out = StringBuffer();
  var lastLat = 0, lastLon = 0;
  void value(int delta) {
    var n = delta < 0 ? ~(delta << 1) : delta << 1;
    while (n >= 32) {
      out.writeCharCode((32 | (n & 31)) + 63);
      n >>= 5;
    }
    out.writeCharCode(n + 63);
  }

  for (final p in points) {
    final lat = (p.latitude * 1e6).round(), lon = (p.longitude * 1e6).round();
    value(lat - lastLat);
    value(lon - lastLon);
    lastLat = lat;
    lastLon = lon;
  }
  return out.toString();
}

class _StopFailsOnceDrive extends DriveEngine {
  _StopFailsOnceDrive(TransitLaneRepository lanes)
    : super(transitLaneRepository: lanes);
  var failures = 1;

  @override
  Future<void> stop() async {
    await super.stop();
    if (failures-- > 0) throw StateError('native stop failed');
  }
}

void main() {
  // The map style is cached process-wide; load it outside any one test's
  // fake clock so readyMap() works whichever test runs first.
  setUpAll(() async {
    await IndependentMapStyle.load(
      dark: false,
      language: 'en',
      center: const GeoPoint(-37.2, 174.9),
    );
  });
  group('starting navigation', () {
    flow('closing the preview during the start cancels it', (t, h) async {
      await h.boot();
      await openPreview(t, h);
      final sheet = preview(t);
      await h.act(() {
        sheet.onStart();
        sheet.onClose();
      });
      await settle(h);
      expect(h.map.navigating, isFalse);
      expect(h.drive.active, isFalse);
      expect(find.byType(IndependentNavigationOverlay), findsNothing);
      expect(find.byType(RoutePreviewSheet), findsNothing);
      await expectBrowseLocationRunning(h);
    });

    flow(
      'closing after the engine installed the route stops it instead of freezing guidance',
      (t, h) async {
        await h.boot();
        await openPreview(t, h);
        final sheet = preview(t);
        var closed = false;
        void closeOnceDriving() {
          if (!closed && h.drive.active) {
            closed = true;
            scheduleMicrotask(sheet.onClose);
          }
        }

        h.drive.addListener(closeOnceDriving);
        await h.act(sheet.onStart);
        await settle(h);
        h.drive.removeListener(closeOnceDriving);
        expect(closed, isTrue, reason: 'The engine should start driving');
        expect(find.byType(IndependentNavigationOverlay), findsNothing);
        expect(h.map.navigating, isFalse);
        expect(h.drive.active, isFalse);
        expect(h.drive.routed, isFalse);
        await expectBrowseLocationRunning(h);
        // A fresh start still works afterwards.
        await openPreview(t, h);
        await h.act(preview(t).onStart);
        await h.until(() => h.map.navigating, reason: 'restart navigation');
        expect(h.drive.routed, isTrue);
      },
    );

    flow('a failing engine stop still ends navigation', (t, h) async {
      await h.boot(engine: _StopFailsOnceDrive.new);
      await openPreview(t, h);
      await h.act(preview(t).onStart);
      await h.until(() => h.map.navigating, reason: 'navigation starts');
      final overlay = t.widget<IndependentNavigationOverlay>(
        find.byType(IndependentNavigationOverlay),
      );
      await h.act(overlay.onEnd);
      await settle(h);
      expect(find.byType(IndependentNavigationOverlay), findsNothing);
      expect(h.map.navigating, isFalse);
      expect(h.drive.active, isFalse);
      await expectBrowseLocationRunning(h);
      await openPreview(t, h);
      await h.act(preview(t).onStart);
      await h.until(() => h.map.navigating, reason: 'navigation restarts');
    });
  });

  group('route preview', () {
    flow('choosing another place while routing frees the new place card', (
      t,
      h,
    ) async {
      await h.boot();
      await h.select(name: 'First place');
      h.gatedPaths.add('/api/route-options');
      await h.act(details(t).onNavigate);
      expect(details(t).routeBusy, isTrue);
      await h.select(
        name: 'Second place',
        point: const GeoPoint(-37.2, 174.92),
      );
      expect(details(t).selectedPlace.name, 'Second place');
      expect(details(t).routeBusy, isFalse);
      h.gatedPaths.clear();
      for (final gate in h.gates) {
        if (!gate.gate.isCompleted) gate.gate.complete(null);
      }
      await settle(h);
      expect(find.byType(RoutePreviewSheet), findsNothing);
      expect(details(t).selectedPlace.name, 'Second place');
    });

    flow('adding a stop keeps the chosen travel mode', (t, h) async {
      await h.boot();
      await openPreview(t, h);
      await h.act(() => preview(t).onModeChanged(WaybiTravelMode.walk));
      expect(preview(t).selectedMode, WaybiTravelMode.walk);
      final add = h.act(preview(t).onAddStop);
      await add;
      expect(find.byType(BottomSheet), findsOneWidget);
      Navigator.of(t.element(find.byType(BottomSheet))).pop(
        const DestinationSuggestion(
          label: 'Stop',
          location: LatLng(latitude: -37.2, longitude: 174.905),
        ),
      );
      await settle(h);
      expect(preview(t).stopCount, 1);
      expect(preview(t).selectedMode, WaybiTravelMode.walk);
      expect(h.routeRequests.last.url.queryParameters['mode'], 'walk');
    });

    flow('a failed mode change keeps the loaded driving plan', (t, h) async {
      await h.boot();
      await openPreview(t, h);
      final id = preview(t).selectedRouteId;
      h.gatedPaths.add('/api/route-options');
      final change = h.act(
        () => preview(t).onModeChanged(WaybiTravelMode.bicycle),
      );
      await change;
      // While the bike plan loads, the driving plan stays on screen.
      expect(find.byType(RoutePreviewSheet), findsOneWidget);
      expect(preview(t).selectedMode, WaybiTravelMode.drive);
      await h.release(
        '/api/route-options',
        http.Response('{"error":"offline"}', 503),
      );
      await settle(h);
      expect(find.byType(RoutePreviewSheet), findsOneWidget);
      expect(preview(t).selectedMode, WaybiTravelMode.drive);
      expect(preview(t).selectedRouteId, id);
    });

    flow('Android back unwinds preview, then the place card', (t, h) async {
      await h.boot();
      expect(homeCanPop(t), isTrue);
      await openPreview(t, h);
      expect(homeCanPop(t), isFalse);
      await h.back();
      expect(find.byType(RoutePreviewSheet), findsNothing);
      expect(details(t).selectedPlace.name, 'Test destination');
      expect(h.map.routePaths, isEmpty);
      await h.back();
      expect(find.byType(PlaceDetailsContent), findsNothing);
      expect(h.map.selectedPlace, isNull);
      expect(homeCanPop(t), isTrue);
    });

    flow('Android back ends Just Drive', (t, h) async {
      await h.boot();
      await h.tapText('Start');
      await h.tapText('Just Drive');
      await h.frames(12);
      expect(find.byType(DriveHud), findsOneWidget);
      await h.back();
      await settle(h);
      expect(find.byType(DriveHud), findsNothing);
      expect(h.map.driving, isFalse);
    });

    flow('Android back asks before ending guidance', (t, h) async {
      await h.boot();
      await openPreview(t, h);
      await h.act(preview(t).onStart);
      await h.until(() => h.map.navigating, reason: 'navigation starts');
      await h.back();
      expect(find.text('End navigation?'), findsOneWidget);
      await h.tapText('Keep navigating');
      expect(h.map.navigating, isTrue);
      await h.back();
      await h.tapText('End');
      await settle(h);
      expect(h.map.navigating, isFalse);
      expect(find.byType(IndependentNavigationOverlay), findsNothing);
    });
  });

  group('public transport', () {
    flow('a late transit answer after closing the preview is ignored', (
      t,
      h,
    ) async {
      h.transitResponse = {
        'itineraries': [transitItinerary('Late bus', 174.91)],
      };
      await h.boot();
      await openPreview(t, h);
      h.gatedPaths.add('/api/v6/plan');
      await h.act(() => preview(t).onModeChanged(WaybiTravelMode.transit));
      await h.act(preview(t).onClose);
      expect(find.byType(RoutePreviewSheet), findsNothing);
      await h.release('/api/v6/plan');
      await settle(h);
      expect(find.byType(RoutePreviewSheet), findsNothing);
      expect(h.map.routePaths, isEmpty);
      expect(find.textContaining('Calculating public transport'), findsNothing);
    });

    flow('switching back to Drive while transit loads keeps Drive', (
      t,
      h,
    ) async {
      h.transitResponse = {
        'itineraries': [transitItinerary('Slow bus', 174.91)],
      };
      await h.boot();
      await openPreview(t, h);
      h.gatedPaths.add('/api/v6/plan');
      await h.act(() => preview(t).onModeChanged(WaybiTravelMode.transit));
      await h.act(() => preview(t).onModeChanged(WaybiTravelMode.drive));
      await h.release('/api/v6/plan');
      await settle(h);
      expect(preview(t).selectedMode, WaybiTravelMode.drive);
    });

    flow('no transit itineraries explains the dead end', (t, h) async {
      h.transitResponse = {'itineraries': []};
      await h.boot();
      await openPreview(t, h);
      await h.act(() => preview(t).onModeChanged(WaybiTravelMode.transit));
      await settle(h);
      expect(find.textContaining('Calculating public transport'), findsNothing);
      expect(find.textContaining('No public transport routes'), findsOneWidget);
      expect(preview(t).selectedMode, WaybiTravelMode.drive);
      expect(preview(t).busy, isFalse);
    });

    flow('a transit trip shows only its itinerary, then nothing', (t, h) async {
      h.transitResponse = {
        'itineraries': [
          transitItinerary('Bus 1', 174.91),
          transitItinerary('Bus 2', 174.912),
        ],
      };
      await h.boot();
      await openPreview(t, h);
      await h.act(() => preview(t).onModeChanged(WaybiTravelMode.transit));
      await h.until(
        () => preview(t).selectedMode == WaybiTravelMode.transit,
        reason: 'transit becomes selected',
      );
      expect(h.map.routePaths.length, greaterThan(1));
      await h.act(preview(t).onStart);
      expect(find.byType(TransitTripOverlay), findsOneWidget);
      expect(h.map.routePaths, hasLength(1));
      final trip = t.widget<TransitTripOverlay>(
        find.byType(TransitTripOverlay),
      );
      await h.act(trip.onEnd);
      expect(find.byType(TransitTripOverlay), findsNothing);
      expect(h.map.routePaths, isEmpty);
      expect(find.byType(RoutePreviewSheet), findsNothing);
    });
  });

  group('place card', () {
    flow('a failing ETA backs off instead of retrying on every fix', (
      t,
      h,
    ) async {
      h.routeFailure = true;
      await h.boot();
      await h.select();
      final before = h.routeRequests.length;
      final issue = details(t).quickRouteIssue;
      expect(issue, isNotNull);
      for (var i = 0; i < 20; i++) {
        h.gps.current = AppGps.position(longitude: 174.9, time: DateTime.now());
        h.gps.positions.add(h.gps.current);
        await h.tester.pump(const Duration(milliseconds: 300));
      }
      await h.frames();
      expect(h.routeRequests.length - before, lessThanOrEqualTo(1));
      expect(details(t).quickRouteIssue, issue);
      expect(details(t).quickRouteLoading, isFalse);
    });

    flow('an earlier place failing never overwrites the cached ETA', (
      t,
      h,
    ) async {
      await h.boot();
      await h.select(name: 'Cached place');
      final cached = details(t).quickRoute;
      expect(cached, isNotNull);
      h.gatedPaths.add('/api/route-options');
      await h.select(name: 'Slow place', point: const GeoPoint(-37.2, 174.93));
      await h.select(name: 'Cached place');
      expect(details(t).quickRoute, same(cached));
      await h.release(
        '/api/route-options',
        http.Response('{"error":"offline"}', 503),
      );
      await settle(h);
      expect(details(t).selectedPlace.name, 'Cached place');
      expect(details(t).quickRoute, same(cached));
      expect(details(t).quickRouteIssue, isNull);
    });

    flow('failed place details explain themselves and can be retried', (
      t,
      h,
    ) async {
      h.endpointFailures['/api/independent-place-details'] = 503;
      await h.boot();
      await h.select();
      expect(details(t).detailsError, isNotNull);
      expect(details(t).detailsLoading, isFalse);
      final before = h.requests
          .where((r) => r.url.path == '/api/independent-place-details')
          .length;
      h.endpointFailures.remove('/api/independent-place-details');
      await h.tapText('Retry');
      expect(
        h.requests
            .where((r) => r.url.path == '/api/independent-place-details')
            .length,
        before + 1,
      );
      expect(details(t).detailsError, isNull);
      expect(details(t).details, isNotNull);
    });

    flow('a route waiting for location still opens after reverse lookup', (
      t,
      h,
    ) async {
      h.reversePlaces.add({
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [174.91, -37.2],
        },
        'properties': {
          'name': 'Resolved café',
          'street': 'Harbour Road',
          'city': 'Auckland',
          'country': 'New Zealand',
          'osm_key': 'amenity',
          'osm_value': 'cafe',
          'osm_type': 'N',
          'osm_id': 77,
        },
      });
      h.gps.current = AppGps.position(accuracy: 900);
      await h.boot(initialFix: false);
      h.gatedPaths.add('/reverse');
      await h.act(
        () => h.map.onMapPlace(
          const PlaceSummary(
            name: 'Map café',
            address: '',
            location: GeoPoint(-37.2, 174.91),
            kind: PlaceKind.poi,
          ),
        ),
      );
      await h.act(details(t).onNavigate);
      expect(
        h.routeRequests.where(
          (r) => r.url.queryParameters['to'] == '174.91,-37.2',
        ),
        isEmpty,
      );
      await h.release('/reverse');
      await h.until(
        () => details(t).selectedPlace.address.contains('Harbour Road'),
        reason: 'reverse lookup enriches the selection',
      );
      h.gps.current = AppGps.position(time: DateTime.now());
      h.gps.positions.add(h.gps.current);
      await settle(h);
      expect(find.byType(RoutePreviewSheet), findsOneWidget);
    });
  });

  group('Drive Mode', () {
    flow('a failed start keeps browse location running', (t, h) async {
      await h.boot();
      await h.tapText('Start');
      h.gps.enabled = false;
      await h.tapText('Just Drive');
      await settle(h);
      expect(find.byType(DriveHud), findsNothing);
      // The restarted browse feed explains the real cause.
      expect(find.textContaining('Location services are off'), findsOneWidget);
      h.gps.enabled = true;
      await expectBrowseLocationRunning(h);
    });
  });

  group('startup and lifecycle', () {
    flow('a failing native map-language call still opens the map', (
      t,
      h,
    ) async {
      h.channelErrors['waybi/map_language'] = {'setLanguage'};
      await h.boot();
      // Past the settings spinner: the map page itself is showing.
      expect(find.byType(IndependentMapRenderer), findsOneWidget);
      expect(h.map.location, const GeoPoint(-37.2, 174.9));
    });

    flow('a normal trip restarts live traffic when it ends', (t, h) async {
      h.trafficAvailable = true;
      await h.boot(preferences: {'waybi.layers.traffic': true});
      await openPreview(t, h);
      await h.act(preview(t).onStart);
      await h.until(() => h.map.navigating, reason: 'navigation starts');
      final before = h.requests
          .where((r) => r.url.path == '/api/traffic-flow')
          .length;
      await h.act(
        t
            .widget<IndependentNavigationOverlay>(
              find.byType(IndependentNavigationOverlay),
            )
            .onEnd,
      );
      await settle(h);
      expect(h.map.navigating, isFalse);
      expect(
        h.requests.where((r) => r.url.path == '/api/traffic-flow').length,
        greaterThan(before),
      );
    });

    flow('inactive and repeated resumes do not refetch traffic or commutes', (
      t,
      h,
    ) async {
      h.trafficAvailable = true;
      await h.boot(
        preferences: {
          'waybi.layers.traffic': true,
          'waybi.quick_location.Home': jsonEncode({
            'name': 'Home',
            'address': 'Home road',
            'latitude': -37.2,
            'longitude': 174.95,
            'provider': 'independent',
          }),
        },
      );
      await settle(h);
      int traffic() =>
          h.requests.where((r) => r.url.path == '/api/traffic-flow').length;
      int commutes() => h.routeRequests
          .where((r) => r.url.queryParameters['to'] == '174.95,-37.2')
          .length;
      final trafficBefore = traffic();
      final commutesBefore = commutes();
      expect(commutesBefore, greaterThan(0));
      for (var i = 0; i < 3; i++) {
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await h.frames(2);
      }
      for (var i = 0; i < 3; i++) {
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await h.frames(2);
      }
      await settle(h);
      expect(traffic(), trafficBefore);
      expect(commutes() - commutesBefore, lessThanOrEqualTo(1));
    });

    flow('a still north-up map does not animate for compass readings', (
      t,
      h,
    ) async {
      await h.boot();
      await h.readyMap();
      await settle(h);
      final before = h.mapPlatform.moves.length;
      for (var degrees = 10.0; degrees < 200; degrees += 19) {
        await h.heading(degrees);
        await h.tester.pump(const Duration(milliseconds: 400));
      }
      await h.frames();
      expect(h.mapPlatform.moves.length - before, lessThanOrEqualTo(1));
    });
  });

  group('accounts', () {
    flow('signing out mid-sync never restores the old account shortcuts', (
      t,
      h,
    ) async {
      h.quickLocations.add({
        'label': 'Work',
        'name': 'Driver work',
        'address': 'Work road',
        'latitude': -37.2,
        'longitude': 174.92,
        'provider': 'independent',
      });
      h.holds['/api/profile/quick-locations'] = Completer<void>();
      await h.boot(
        signedIn: true,
        preferences: {
          'waybi.quick_location.owner_user_id': 'driver',
          'waybi.quick_location.Home': jsonEncode({
            'name': 'Driver home',
            'address': 'Home road',
            'latitude': -37.2,
            'longitude': 174.91,
            'provider': 'independent',
          }),
        },
      );
      await h.until(
        () =>
            h.requests.any((r) => r.url.path == '/api/profile/quick-locations'),
        reason: 'the local Home uploads to the account',
      );
      await h.tapText('Me');
      final profile = find.byType(ProfilePage);
      expect(profile, findsOneWidget);
      final account = t.widget<ProfilePage>(profile).account;
      await t.runAsync(account.signOut);
      Navigator.of(t.element(profile)).pop();
      await h.frames();
      h.holds.remove('/api/profile/quick-locations')!.complete();
      await settle(h);
      await h.tapText('Trips');
      final page = t.widget<TripsPage>(find.byType(TripsPage));
      final snapshot = await t.runAsync(page.loader);
      expect(snapshot!.signedIn, isFalse);
      expect(snapshot.quickPlaces, isEmpty);
    });

    flow('repeated account notifications do not re-route the commutes', (
      t,
      h,
    ) async {
      h.quickLocations.addAll([
        {
          'label': 'Home',
          'name': 'Driver home',
          'address': 'Home road',
          'latitude': -37.2,
          'longitude': 174.91,
          'provider': 'independent',
        },
        {
          'label': 'Work',
          'name': 'Driver work',
          'address': 'Work road',
          'latitude': -37.2,
          'longitude': 174.92,
          'provider': 'independent',
        },
      ]);
      await h.boot(signedIn: true);
      await settle(h);
      int commutes() => h.routeRequests
          .where(
            (r) =>
                r.url.queryParameters['to'] == '174.91,-37.2' ||
                r.url.queryParameters['to'] == '174.92,-37.2',
          )
          .length;
      final before = commutes();
      // Each favourite toggle refreshes the profile and notifies listeners.
      for (var i = 0; i < 3; i++) {
        await h.select(
          name: 'Favourite $i',
          point: GeoPoint(-37.2, 174.94 + i * .001),
        );
        await h.act(details(t).onFavorite);
        await settle(h);
      }
      expect(commutes(), before);
    });
  });
}
