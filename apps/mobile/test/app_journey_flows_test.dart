import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart'
    show LatLng;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/widgets/discover_page.dart';
import 'package:waybi_mobile/widgets/explore_page.dart';
import 'package:waybi_mobile/widgets/explore_search.dart';
import 'package:waybi_mobile/widgets/full_screen_search.dart';
import 'package:waybi_mobile/widgets/independent_navigation_overlay.dart';
import 'package:waybi_mobile/widgets/place_details_content.dart';
import 'package:waybi_mobile/widgets/route_preview_sheet.dart';
import 'package:waybi_mobile/widgets/trips_page.dart';
import 'package:waybi_mobile/widgets/journey_summary_sheet.dart';

import 'support/app_harness.dart';

PlaceDetailsContent details(WidgetTester t) =>
    t.widget<PlaceDetailsContent>(find.byType(PlaceDetailsContent));
RoutePreviewSheet preview(WidgetTester t) =>
    t.widget<RoutePreviewSheet>(find.byType(RoutePreviewSheet));
IndependentNavigationOverlay nav(WidgetTester t) =>
    t.widget<IndependentNavigationOverlay>(
      find.byType(IndependentNavigationOverlay),
    );
void flow(String label, Future<void> Function(WidgetTester, AppHarness) body) {
  testWidgets(label, (t) async {
    final h = AppHarness(t);
    await http.runWithClient(() async {
      await body(t, h);
      await h.dispose();
    }, () => h.client);
  });
}

Future<void> begin(WidgetTester t, AppHarness h) async {
  await h.select();
  await h.act(details(t).onNavigate);
  await h.act(preview(t).onStart);
  await h.until(
    () => h.map.navigating,
    reason: 'Navigation should be active before moving',
  );
}

Future<void> moveAndEnd(WidgetTester t, AppHarness h) async {
  final at = DateTime.now();
  for (var i = 1; i <= 2; i++) {
    h.gps.current = AppGps.position(
      longitude: 174.9 + i * .0002,
      speed: 8,
      time: at.add(Duration(seconds: i * 2)),
    );
    h.gps.positions.add(h.gps.current);
    await h.frames();
  }
  await h.act(nav(t).onEnd);
  await h.frames();
  expect(h.map.navigating, isFalse);
}

void main() {
  flow(
    'signed-in journeys save measured movement and never the full planned route',
    (t, h) async {
      await h.boot(
        signedIn: true,
        preferences: {'waybi.notifications.safety_cameras': true},
      );
      await begin(t, h);
      await moveAndEnd(t, h);
      final recorded = h.requests
          .where((r) => r.url.path == '/api/profile/routes')
          .toList();
      expect(recorded, hasLength(1));
      final payload = jsonDecode(recorded.single.body) as Map;
      expect(payload['journeyId'], startsWith('wb_'));
      expect(payload['distanceMeters'], inInclusiveRange(10, 100));
      expect(payload['destinationName'], 'Test destination');
      expect(h.recordedJourneys, hasLength(1));
      expect(
        (await SharedPreferences.getInstance()).getKeys().where(
          (k) => k.startsWith('waybi.companion.outbox.v1.driver.'),
        ),
        isEmpty,
      );
      expect(h.calls.any((c) => c.method == 'show'), isTrue);
    },
  );
  flow('guest journeys persist actual movement for later account import', (
    t,
    h,
  ) async {
    await h.boot();
    await begin(t, h);
    await moveAndEnd(t, h);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('waybi.companion.guest.v1.trips'), 1);
    expect(
      prefs.getInt('waybi.companion.guest.v1.distance'),
      inInclusiveRange(10, 100),
    );
    expect(
      h.requests.where((r) => r.url.path == '/api/profile/routes'),
      isEmpty,
    );
  });
  flow('offline journey upload retains its original outbox record', (
    t,
    h,
  ) async {
    h.endpointFailures['/api/profile/routes'] = 503;
    await h.boot(signedIn: true);
    await begin(t, h);
    await moveAndEnd(t, h);
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((k) => k.startsWith('waybi.companion.outbox.v1.driver.'))
        .toList();
    expect(keys, hasLength(1));
    final stored = jsonDecode(prefs.getString(keys.single)!) as Map;
    final attempted = jsonDecode(
      h.requests.lastWhere((r) => r.url.path == '/api/profile/routes').body,
    ) as Map;
    expect(stored, attempted);
    expect(h.map.driving, isFalse);
    expect(h.recordedJourneys, isEmpty);
  });
  flow(
    'Trips retries idempotent journey records and leaves other accounts and damaged records alone',
    (t, h) async {
      const first = {
        'journeyId': 'pending-a',
        'destinationName': 'Recorded office',
        'latitude': -37.2,
        'longitude': 174.91,
        'mode': 'drive',
        'distanceMeters': 120,
        'durationSeconds': 30,
      };
      const second = {
        'journeyId': 'pending-b',
        'destinationName': 'Recorded cafe',
        'latitude': -37.2,
        'longitude': 174.92,
        'mode': 'walk',
        'distanceMeters': 80,
        'durationSeconds': 90,
      };
      await h.boot(
        signedIn: true,
        preferences: {
          'waybi.companion.outbox.v1.driver.a': jsonEncode(first),
          'waybi.companion.outbox.v1.driver.b': jsonEncode(second),
          'waybi.companion.outbox.v1.driver.z': 'damaged',
          'waybi.companion.outbox.v1.other.a': jsonEncode(first),
        },
      );
      await h.tapText('Trips');
      final snapshot = await t.runAsync(
        t.widget<TripsPage>(find.byType(TripsPage)).loader,
      );
      expect(snapshot!.lifetimeTripCount, 2);
      expect(h.recordedJourneys, containsAll(['pending-a', 'pending-b']));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('waybi.companion.outbox.v1.driver.a'), isFalse);
      expect(prefs.containsKey('waybi.companion.outbox.v1.driver.b'), isFalse);
      expect(prefs.getString('waybi.companion.outbox.v1.driver.z'), 'damaged');
      expect(prefs.containsKey('waybi.companion.outbox.v1.other.a'), isTrue);
    },
  );
  flow(
    'guest import retries with the same identity and clears local totals only after confirmation',
    (t, h) async {
      h.endpointFailures['/api/profile/companion/import'] = 503;
      await h.boot(
        signedIn: true,
        preferences: {
          'waybi.companion.guest.v1.trips': 2,
          'waybi.companion.guest.v1.distance': 200,
          'waybi.companion.guest.v1.duration': 60,
        },
      );
      await h.tapText('Trips');
      final page = t.widget<TripsPage>(find.byType(TripsPage));
      final prefs = await SharedPreferences.getInstance();
      final importId = prefs.getString('waybi.companion.guest.v1.import_id');
      expect(importId, isNotNull);
      expect(prefs.getInt('waybi.companion.guest.v1.trips'), 2);
      h.endpointFailures.remove('/api/profile/companion/import');
      final snapshot = await t.runAsync(page.loader);
      await h.frames();
      expect(snapshot!.lifetimeTripCount, 2);
      expect(prefs.containsKey('waybi.companion.guest.v1.trips'), isFalse);
      expect(prefs.containsKey('waybi.companion.guest.v1.import_id'), isFalse);
      final ids = h.requests
          .where((r) => r.url.path == '/api/profile/companion/import')
          .map((r) => (jsonDecode(r.body) as Map)['importId'])
          .toSet();
      expect(ids, {importId});
      expect(h.importedJourneys, hasLength(1));
    },
  );
  flow(
    'legacy account history remains usable without lifetime totals and ignores incomplete route rows',
    (t, h) async {
      h.serverHasLifetimeTotals = false;
      h.routeHistory.addAll([
        {
          'destinationName': 'Old office',
          'latitude': -37.2,
          'longitude': 174.91,
          'mode': 'drive',
          'distanceMeters': 1000,
          'durationSeconds': 600,
          'startedAt': 1700000000000,
        },
        {
          'latitude': -37.2,
          'longitude': 174.92,
          'distanceMeters': 500,
          'durationSeconds': 300,
          'createdAt': '2026-10-15T20:00:00Z',
        },
        {'latitude': 'broken', 'longitude': 174.91},
      ]);
      await h.boot(
        signedIn: true,
        preferences: {
          'waybi.companion.guest.v1.trips': 1,
          'waybi.companion.guest.v1.distance': 50,
        },
      );
      await h.tapText('Trips');
      final snapshot = await t.runAsync(
        t.widget<TripsPage>(find.byType(TripsPage)).loader,
      );
      expect(snapshot!.lifetimeTripCount, isNull);
      expect(snapshot.guestTripCount, 1);
      expect(snapshot.history, hasLength(2));
      expect(snapshot.history.every((row) => row.createdAt != null), isTrue);
      expect(
        h.requests.where((r) => r.url.path == '/api/profile/companion/import'),
        isEmpty,
      );
    },
  );
  flow(
    'navigation adds a recent stop using Waybi and preserves guidance if updating it fails',
    (t, h) async {
      await h.boot(
        preferences: {
          'waybi.recent.google': [
            jsonEncode({
              'label': 'Stop cafe',
              'name': 'Stop cafe',
              'address': 'Test road',
              'latitude': -37.2,
              'longitude': 174.903,
            }),
          ],
        },
      );
      await begin(t, h);
      await h.act(nav(t).onSearchAlongRoute);
      expect(find.byType(FullScreenSearch), findsOneWidget);
      await h.tapText('Stop cafe');
      await h.frames();
      expect(
        h.routeRequests.last.url.queryParameters['stops'],
        contains('174.903,-37.2'),
      );
      expect(
        nav(t).engine.remainingStops,
        contains(const GeoPoint(-37.2, 174.903)),
      );
      final previous = nav(t).engine.route;
      h.routeFailure = true;
      await h.act(nav(t).onSearchAlongRoute);
      await h.tapText('Stop cafe');
      await h.frames();
      expect(nav(t).engine.route, same(previous));
      expect(h.map.navigating, isTrue);
      expect(find.textContaining('Could not add this stop'), findsOneWidget);
      expect(
        h.routeRequests.every(
          (r) => r.url.queryParameters['provider'] == 'independent',
        ),
        isTrue,
      );
    },
  );
  flow('preview stops survive route recalculation and saving', (t, h) async {
    await h.boot();
    await h.select();
    await h.act(details(t).onNavigate);
    await h.act(preview(t).onAddStop);
    final search = t.widget<ExploreSearch>(find.byType(ExploreSearch));
    await h.act(
      () => search.onSelected(
        const DestinationSuggestion(
          label: 'Added stop',
          location: LatLng(latitude: -37.2, longitude: 174.903),
        ),
      ),
    );
    expect(preview(t).stopCount, 1);
    expect(
      h.routeRequests.last.url.queryParameters['stops'],
      contains('174.903,-37.2'),
    );
    await h.act(preview(t).onSave);
    final stored = jsonDecode(
      (await SharedPreferences.getInstance())
          .getStringList('waybi.saved.routes')!
          .first,
    ) as Map;
    expect((stored['stops'] as List).single['label'], 'Added stop');
  });
  flow(
    'parking selection can return to the direct destination and continues on foot after parking nearby',
    (t, h) async {
      h.parkingAvailable = true;
      h.routeDistanceMeters = 60;
      await h.boot(signedIn: true, plus: true);
      await h.select(name: 'Office', point: const GeoPoint(-37.2, 174.9005));
      await h.act(details(t).onNavigate);
      await h.frames();
      await h.act(
        () => preview(t).onParkingSelected!(preview(t).parkingPlaces.first),
      );
      expect(preview(t).finalDestinationTitle, 'Office');
      await h.act(preview(t).onDirectDestination!);
      expect(preview(t).destinationTitle, 'Office');
      await h.act(
        () => preview(t).onParkingSelected!(preview(t).parkingPlaces.first),
      );
      await h.act(preview(t).onStart);
      await h.until(
        () => h.map.navigating,
        reason: 'Parking route should start',
      );
      await h.act(nav(t).onEnd);
      await h.frames();
      expect(
        (await SharedPreferences.getInstance()).getString(
          'waybi.plus.parked_car.v1',
        ),
        isNotNull,
      );
      expect(find.text('Continue on foot'), findsOneWidget);
      if (find.byType(JourneySummarySheet).evaluate().isNotEmpty) {
        Navigator.of(t.element(find.byType(JourneySummarySheet))).pop();
        await h.frames();
      }
      await h.tapText('Continue on foot');
      expect(preview(t).selectedMode, WaybiTravelMode.walk);
      expect(preview(t).destinationTitle, 'Office');
      preview(t).onClose();
      await h.frames();
      await t.tap(find.byTooltip('Parked just now'));
      await h.frames();
      expect(details(t).selectedPlace.name, startsWith('Parked car'));
    },
  );
  flow(
    'ending a parking route far from the car park does not create a false parked-car record',
    (t, h) async {
      h.parkingAvailable = true;
      await h.boot(signedIn: true, plus: true);
      await h.select(name: 'Office');
      await h.act(details(t).onNavigate);
      await h.frames();
      await h.act(
        () => preview(t).onParkingSelected!(preview(t).parkingPlaces.first),
      );
      await h.act(preview(t).onStart);
      await h.until(
        () => h.map.navigating,
        reason: 'Parking route should start',
      );
      await h.act(nav(t).onEnd);
      await h.frames();
      expect(
        (await SharedPreferences.getInstance()).getString(
          'waybi.plus.parked_car.v1',
        ),
        isNull,
      );
      expect(find.byTooltip('Parked just now'), findsNothing);
    },
  );
  flow(
    'Discover direction search selects only Waybi-compatible nearby places',
    (t, h) async {
      h.explorePlaces.add({
        'placeId': 'node:77',
        'provider': 'osm',
        'name': 'Fixture cafe',
        'address': 'Nearby road',
        'primaryType': 'cafe',
        'latitude': -37.21,
        'longitude': 174.92,
      });
      await h.boot();
      await h.tapText('Discover');
      Navigator.of(t.element(find.byType(DiscoverPage)))
          .pop(DiscoverAction.direction(const GeoPoint(-37.205, 174.918)));
      await h.frames();
      expect(find.byType(ExplorePage), findsOneWidget);
      await h.tapText('Fixture cafe');
      await h.frames();
      expect(details(t).selectedPlace.reference?.provider, 'osm');
      expect(details(t).selectedPlace.name, 'Fixture cafe');
      expect(
        h.requests
            .where((r) => r.url.path == '/api/explore')
            .every((r) => r.url.queryParameters['provider'] == 'osm'),
        isTrue,
      );
    },
  );
}
