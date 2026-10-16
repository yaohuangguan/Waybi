import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/map_layer_settings.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/domain/road_event.dart';
import 'package:waybi_mobile/domain/transit_lane.dart';
import 'package:waybi_mobile/domain/transit_review_corridor.dart';
import 'package:waybi_mobile/widgets/arrival_experience_panel.dart';
import 'package:waybi_mobile/widgets/discover_page.dart';
import 'package:waybi_mobile/widgets/full_screen_search.dart';
import 'package:waybi_mobile/widgets/independent_navigation_overlay.dart';
import 'package:waybi_mobile/widgets/map_layer_sheet.dart';
import 'package:waybi_mobile/widgets/place_details_content.dart';
import 'package:waybi_mobile/widgets/profile_page.dart';
import 'package:waybi_mobile/widgets/road_event_details_sheet.dart';
import 'package:waybi_mobile/widgets/route_preview_sheet.dart';
import 'package:waybi_mobile/widgets/trips_page.dart';

import 'support/app_harness.dart';

PlaceDetailsContent details(WidgetTester t) =>
    t.widget<PlaceDetailsContent>(find.byType(PlaceDetailsContent));
RoutePreviewSheet preview(WidgetTester t) =>
    t.widget<RoutePreviewSheet>(find.byType(RoutePreviewSheet));
IndependentNavigationOverlay guidance(WidgetTester t) =>
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

Future<void> startNavigation(WidgetTester t, AppHarness h) async {
  await h.select();
  await h.act(details(t).onNavigate);
  await h.act(preview(t).onStart);
  await h.until(
    () => h.map.navigating,
    reason: 'Waybi navigation should start',
  );
}

void closePage<T>(WidgetTester t, Type type, [T? result]) {
  Navigator.of(t.element(find.byType(type))).pop<T>(result);
}

void main() {
  flow(
    'external directions preserve explicit origin, ordered stops and travel mode',
    (t, h) async {
      await h.boot();
      await h.handoff(
        'geo-navigation:///directions?source=-37.201,174.899&destination=-37.2,174.91&waypoint=-37.2,174.902&waypoint=-37.2,174.904&mode=walk',
      );
      expect(preview(t).customOrigin, isTrue);
      expect(preview(t).selectedMode, WaybiTravelMode.walk);
      expect(preview(t).stopCount, 2);
      expect(preview(t).plan.stopsApplied, 2);
      final request = h.routeRequests.last.url.queryParameters;
      expect(request['from'], '174.899,-37.201');
      expect(request['to'], '174.91,-37.2');
      expect(request['stops'], contains('174.902,-37.2'));
      expect(request['stops'], contains('174.904,-37.2'));
    },
  );
  flow(
    'system place links select a place without starting navigation and malformed links preserve it',
    (t, h) async {
      await h.boot();
      await h.handoff('geo-navigation:///place?coordinate=-37.2,174.91');
      expect(details(t).selectedPlace.location, const GeoPoint(-37.2, 174.91));
      expect(find.byType(RoutePreviewSheet), findsNothing);
      expect(h.map.navigating, isFalse);
      await h.handoff('waybi://navigate?destination=91,174');
      expect(find.textContaining('invalid destination'), findsOneWidget);
      expect(details(t).selectedPlace.location, const GeoPoint(-37.2, 174.91));
      await h.handoff(
        'com.googleusercontent.apps.example:/oauthredirect?code=example',
      );
      expect(details(t).selectedPlace.location, const GeoPoint(-37.2, 174.91));
    },
  );
  flow(
    'external destination replacement respects cancellation while Just Drive is active',
    (t, h) async {
      await h.boot();
      await h.tapText('Start');
      await h.tapText('Just Drive');
      await h.until(
        () => h.map.driving,
        reason: 'Just Drive should finish starting',
      );
      expect(h.map.driving, isTrue);
      const link =
          'waybi://navigate?destination=-37.2,174.92&name=New%20destination';
      await h.handoff(link);
      await h.tapText('Keep current trip');
      expect(h.map.driving, isTrue);
      expect(h.map.navigating, isFalse);
      await h.handoff(link);
      await h.tapText('Switch');
      await h.until(
        () => !h.map.driving,
        reason: 'Confirmed replacement should stop Just Drive',
      );
      expect(h.map.driving, isFalse);
      expect(preview(t).destinationTitle, 'New destination');
    },
  );
  flow(
    'external replacement stops active guidance only after user confirmation',
    (t, h) async {
      await h.boot();
      await startNavigation(t, h);
      const link = 'waybi://navigate?destination=-37.2,174.92&name=Next';
      await h.handoff(link);
      await h.tapText('Keep current trip');
      expect(h.map.navigating, isTrue);
      await h.handoff(link);
      await h.tapText('Switch');
      await h.until(
        () => !h.map.navigating,
        reason: 'Confirmed destination replacement should stop the previous guidance',
      );
      expect(h.map.navigating, isFalse);
      expect(preview(t).destinationTitle, 'Next');
      expect(h.calls.where((c) => c.method == 'stop'), isNotEmpty);
    },
  );
  flow(
    'cancelling text resolution does not silently choose a search result or discard the selected place',
    (t, h) async {
      await h.boot();
      await h.select(name: 'Stable place');
      await h.handoff('waybi://navigate?destination=Airport');
      expect(find.byType(FullScreenSearch), findsOneWidget);
      closePage(t, FullScreenSearch);
      await h.frames();
      expect(details(t).selectedPlace.name, 'Stable place');
      expect(find.byType(RoutePreviewSheet), findsNothing);
    },
  );
  for (final language in ['en', 'zh']) {
    flow(
      'cold-start handoff waits for $language onboarding before opening its route',
      (t, h) async {
        await h.boot(
          preferences: {
            'waybi.onboarding.core.v1': false,
            'waybi.app.language': language,
          },
        );
        await h.handoff(
          'waybi://navigate?destination=-37.2,174.91&name=Welcome',
        );
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byType(RoutePreviewSheet), findsNothing);
        await h.tapText(language == 'zh' ? '开始探索' : 'Start exploring');
        await h.frames();
        expect(
          (await SharedPreferences.getInstance()).getBool(
            'waybi.onboarding.core.v1',
          ),
          isTrue,
        );
        expect(preview(t).destinationTitle, 'Welcome');
      },
    );
  }
  flow(
    'profile preferences persist into the Waybi map and preserve native navigation settings',
    (t, h) async {
      await h.boot();
      await h.tapText('Me');
      final profile = t.widget<ProfilePage>(find.byType(ProfilePage));
      await h.act(() => profile.onVoiceChanged(true));
      await h.act(() => profile.onLanesChanged(false));
      await h.act(() => profile.onKeepScreenAwakeChanged!(false));
      await h.act(() => profile.onLanguageChanged('en-AU'));
      await h.act(
        () => profile.onLocationMarkerChanged(LocationMarkerStyle.classic),
      );
      await h.act(() => profile.onAppLanguageChanged('zh'));
      closePage(t, ProfilePage);
      await h.frames();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('waybi.voice.enabled'), isTrue);
      expect(prefs.getBool('waybi.nav.lanes'), isFalse);
      expect(prefs.getBool('waybi.nav.keep_screen_awake'), isFalse);
      expect(prefs.getString('waybi.voice.language'), 'en-AU');
      expect(prefs.getString('waybi.app.language'), 'zh');
      expect(h.map.locationMarker, LocationMarkerStyle.classic);
      expect(h.map.language, 'zh');
      expect(find.textContaining('Google 地图标签'), findsNothing);
    },
  );
  flow(
    'map layer changes reach MapLibre and persist camera and road preferences',
    (t, h) async {
      await h.boot();
      await t.tap(find.byTooltip('Map layers'));
      await h.frames();
      final sheet = t.widget<MapLayerSheet>(find.byType(MapLayerSheet));
      await h.act(
        () => sheet.onChanged(
          const MapLayerSettings(
            cameras: false,
            traffic: true,
            roadEvents: false,
            transitLanes: false,
            style: BaseMapStyle.terrain,
            alertOther: true,
          ),
        ),
      );
      closePage(t, MapLayerSheet);
      await h.frames();
      expect(h.map.layers.style, BaseMapStyle.terrain);
      expect(h.map.layers.cameras, isFalse);
      expect(h.map.layers.traffic, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('waybi.layers.style'), 'terrain');
      expect(prefs.getBool('waybi.layers.cameras'), isFalse);
      expect(prefs.getBool('waybi.layers.road_events'), isFalse);
      expect(prefs.getBool('waybi.alerts.other_camera'), isTrue);
    },
  );
  for (final language in ['en', 'zh']) {
    flow(
      'camera and transit details expose official geometry and review limitations in $language',
      (t, h) async {
        await h.boot(preferences: {'waybi.app.language': language});
        await h.act(() => h.map.onCamera(h.drive.cameras.single));
        expect(find.text('-37.200000, 174.905000'), findsOneWidget);
        Navigator.of(t.element(find.text('GPS'))).pop();
        await h.frames();
        const lane = TransitLane(
          id: 'fixture-lane',
          roadName: 'Fixture road',
          kind: 'Bus',
          schedule: TransitSchedule(
            days: [1, 2, 3, 4, 5, 6, 7],
            windows: [
              [0, 1440],
            ],
            known: true,
          ),
          points: [GeoPoint(-37.2, 174.9), GeoPoint(-37.2, 174.91)],
        );
        await h.act(() => h.map.onTransitLane!(lane));
        expect(
          find.text(language == 'zh' ? '当前生效' : 'Operating now'),
          findsOneWidget,
        );
        Navigator.of(t.element(find.text('Fixture road'))).pop();
        await h.frames();
        const corridor = TransitReviewCorridor(
          id: 'review',
          city: 'Wellington',
          roadName: 'Review road',
          authority: 'Council',
          ruleSummary: 'Check signs',
          ruleSummaryZh: '查看路牌',
          ruleSource: 'https://example.test/rules',
          geometrySource: 'Council street centreline',
          points: [GeoPoint(-37.2, 174.9), GeoPoint(-37.2, 174.91)],
        );
        await h.act(() => h.map.onTransitReviewCorridor!(corridor));
        expect(
          find.text(language == 'zh' ? '查看路牌' : 'Check signs'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            language == 'zh' ? '不会据此封禁路线' : 'not used for route blocking',
          ),
          findsOneWidget,
        );
        Navigator.of(t.element(find.text('Review road'))).pop();
        await h.frames();
      },
    );
  }
  flow(
    'Plus navigation caches the forward corridor and displays nearby arrival parking',
    (t, h) async {
      h.routeDistanceMeters = 250;
      h.parkingAvailable = true;
      await h.boot(signedIn: true, plus: true);
      await h.select(point: const GeoPoint(-37.2, 174.902));
      await h.act(details(t).onNavigate);
      await h.act(preview(t).onStart);
      await h.until(
        () => h.map.navigating,
        reason: 'Plus guidance should start',
      );
      await h.frames();
      final cached = (await SharedPreferences.getInstance()).getString(
        'waybi.navigation.offline_corridor.v1',
      );
      expect(cached, isNotNull);
      final corridor = jsonDecode(cached!) as Map;
      expect(corridor['aheadMeters'], 6000);
      expect(corridor['geometry'], hasLength(greaterThanOrEqualTo(2)));
      expect(corridor['steps'], isNotEmpty);
      expect(
        guidance(t).engine.remainingDistanceMeters,
        lessThanOrEqualTo(300),
      );
      expect(guidance(t).arrivalPanel, isNotNull);
      await t.tap(find.byKey(const Key('arrivalSummary')));
      await h.frames();
      expect(find.byType(ArrivalExperiencePanel), findsOneWidget);
      final arrival = t.widget<ArrivalExperiencePanel>(
        find.byType(ArrivalExperiencePanel),
      );
      expect(arrival.parkingPlaces.single.name, 'Nearby car park');
      await h.act(
        () => arrival.onParkingSelected(arrival.parkingPlaces.single),
      );
      await h.until(
        () => h.map.navigating,
        reason: 'Arrival parking should replace the active route',
      );
      expect(guidance(t).destination, 'Nearby car park');
    },
  );
  flow(
    'Trips loads account shortcuts and route watch saves independent geometry',
    (t, h) async {
      h.quickLocations.add({
        'label': 'Home',
        'name': 'My home',
        'address': 'Destination road',
        'latitude': -37.2,
        'longitude': 174.91,
        'provider': 'independent',
      });
      h.recentDestinations.add({
        'label': 'Recent stop',
        'latitude': -37.2,
        'longitude': 174.915,
      });
      h.quickLocations.add({
        'label': 'Work',
        'name': 'My work',
        'address': 'Work road',
        'latitude': -37.2,
        'longitude': 174.92,
        'provider': 'independent',
      });
      await h.boot(signedIn: true, plus: true);
      await h.tapText('Trips');
      final page = t.widget<TripsPage>(find.byType(TripsPage));
      final snapshot = await t.runAsync(page.loader);
      expect(snapshot!.quickPlaces['Home']!.name, 'My home');
      expect(snapshot.recent.single.name, 'Recent stop');
      await t.runAsync(
        () => page.onRouteWatchChanged!('home-work', null, true),
      );
      await h.frames();
      final saved = h.requests.lastWhere(
        (r) => r.url.path == '/api/route-watches' && r.method == 'POST',
      );
      final body = jsonDecode(saved.body) as Map;
      expect(body['routeProvider'], 'independent');
      expect(
        h.routeRequests.every(
          (r) => r.url.queryParameters['provider'] == 'independent',
        ),
        isTrue,
        reason:
            'Smart Commute and Route Watch must explicitly use Waybi routing',
      );
      expect(body['routePoints'], hasLength(greaterThanOrEqualTo(2)));
      closePage(
        t,
        TripsPage,
        const TripsResult.select(
          TripDestination(
            name: 'Recent stop',
            location: GeoPoint(-37.2, 174.915),
          ),
        ),
      );
      await h.frames();
      expect(details(t).selectedPlace.name, 'Recent stop');
    },
  );
  flow(
    'route-watch alerts deduplicate watches and acknowledge valid account alerts',
    (t, h) async {
      h.routeWatchAlerts.addAll([
        for (var i = 0; i < 6; i++)
          {
            'id': 'a$i',
            'routeWatchId': 'w$i',
            'label': 'Commute $i',
            'status': i == 0 ? 'disrupted' : 'warning',
            'events': [
              {'roadName': 'Fixture road', 'impact': 'Closed'},
            ],
          },
        {'id': 'duplicate', 'routeWatchId': 'w0', 'events': []},
        {'id': 'missing-watch', 'routeWatchId': '', 'events': []},
      ]);
      await h.boot(
        signedIn: true,
        plus: true,
        preferences: {'waybi.notifications.saved_route_disruptions': true},
      );
      await h.frames();
      expect(h.calls.where((c) => c.method == 'show'), hasLength(4));
      final read = h.requests.lastWhere(
        (r) => r.url.path == '/api/route-watch-alerts/read',
      );
      expect(
        (jsonDecode(read.body) as Map)['ids'],
        containsAll(['a0', 'a5', 'duplicate']),
      );
    },
  );
  flow('Discover opens Trips and returns a destination to the Waybi map', (
    t,
    h,
  ) async {
    await h.boot();
    await h.tapText('Discover');
    closePage(t, DiscoverPage, DiscoverAction.trips);
    await h.frames();
    expect(find.byType(TripsPage), findsOneWidget);
    closePage(
      t,
      TripsPage,
      const TripsResult.select(
        TripDestination(name: 'From Trips', location: GeoPoint(-37.2, 174.91)),
      ),
    );
    await h.frames();
    expect(details(t).selectedPlace.name, 'From Trips');
    details(t).onClose();
    await h.frames();
    await h.tapText('Discover');
    closePage(
      t,
      DiscoverPage,
      DiscoverAction.place(
        const TripDestination(
          name: 'Discover memory',
          location: GeoPoint(-37.2, 174.915),
        ),
      ),
    );
    await h.frames();
    expect(details(t).selectedPlace.name, 'Discover memory');
  });
  flow('Discover road actions focus the event and retain road layers', (
    t,
    h,
  ) async {
    await h.boot();
    await h.tapText('Discover');
    const event = RoadEvent(
      id: 'official',
      type: RoadEventType.roadworks,
      location: GeoPoint(-37.21, 174.92),
      severity: RoadEventSeverity.warning,
      roadName: 'Fixture works',
      source: RoadEventSource(
        provider: 'NZTA',
        country: 'NZ',
        sourceId: 'fixture',
      ),
      metadata: {'description': 'Maintenance'},
    );
    closePage(t, DiscoverPage, DiscoverAction.road(event));
    await h.frames();
    expect(find.byType(RoadEventDetailsSheet), findsOneWidget);
    expect(h.map.following, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'waybi.layers.road_events',
      ),
      isTrue,
    );
    closePage(t, RoadEventDetailsSheet);
    await h.frames();
  });
}
