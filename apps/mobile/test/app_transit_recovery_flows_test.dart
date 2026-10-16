
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/widgets/place_details_content.dart';
import 'package:waybi_mobile/widgets/route_preview_sheet.dart';
import 'package:waybi_mobile/widgets/transit_trip_overlay.dart';
import 'package:waybi_mobile/widgets/independent_navigation_overlay.dart';

import 'support/app_harness.dart';

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
String encoded(List<GeoPoint> points) {
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

Map<String, dynamic> transit() => {
  'itineraries': [
    {
      'duration': 1260,
      'transfers': 0,
      'legs': [
        {
          'mode': 'BUS',
          'routeShortName': 'AirportLink',
          'headsign': 'City',
          'from': {'name': 'Airport'},
          'to': {'name': 'City centre'},
          'intermediateStops': [
            {'name': 'Middle stop'},
          ],
          'legGeometry': {
            'precision': 6,
            'points': encoded(const [
              GeoPoint(-37.2, 174.9),
              GeoPoint(-37.2, 174.91),
            ]),
          },
        },
      ],
    },
  ],
};
void main() {
  for (final language in ['en', 'zh']) {
    flow(
      '$language transit loads the independent itinerary, starts, recenters and ends without drive guidance',
      (t, h) async {
        h.transitResponse = transit();
        await h.boot(preferences: {'waybi.app.language': language});
        await h.select();
        await h.act(details(t).onNavigate);
        await h.act(() => preview(t).onModeChanged(WaybiTravelMode.transit));
        await h.until(
          () => preview(t).selectedMode == WaybiTravelMode.transit,
          reason: 'Transit itinerary should become selected',
        );
        expect(
          preview(t).plan.forMode(WaybiTravelMode.transit).single.provider,
          'motis',
        );
        final r = h.requests.lastWhere((r) => r.url.path == '/api/v6/plan');
        expect(r.url.queryParameters['language'], language);
        await h.act(preview(t).onStart);
        expect(find.byType(TransitTripOverlay), findsOneWidget);
        expect(h.map.navigating, isFalse);
        expect(h.map.driving, isFalse);
        final trip = t.widget<TransitTripOverlay>(
          find.byType(TransitTripOverlay),
        );
        expect(trip.route.transit.single.lineName, 'AirportLink');
        await h.act(h.map.onUserPan);
        expect(h.map.following, isFalse);
        await h.act(trip.onRecenter);
        expect(h.map.following, isTrue);
        await h.act(trip.onEnd);
        expect(find.byType(TransitTripOverlay), findsNothing);
        expect(h.map.navigating, isFalse);
        expect(h.map.driving, isFalse);
      },
    );
    flow(
      '$language transit network failure retains the selected driving route and can retry',
      (t, h) async {
        await h.boot(preferences: {'waybi.app.language': language});
        await h.select();
        await h.act(details(t).onNavigate);
        final id = preview(t).selectedRouteId;
        await h.act(() => preview(t).onModeChanged(WaybiTravelMode.transit));
        expect(
          find.textContaining(
            language == 'zh'
                ? '公交路线计算失败'
                : 'Could not calculate public transport',
          ),
          findsOneWidget,
        );
        expect(preview(t).selectedMode, WaybiTravelMode.drive);
        expect(preview(t).selectedRouteId, id);
        h.transitResponse = transit();
        await h.act(() => preview(t).onModeChanged(WaybiTravelMode.transit));
        expect(preview(t).selectedMode, WaybiTravelMode.transit);
      },
    );
    flow(
      '$language adding a preview stop keeps Waybi search and routing in the selected language',
      (t, h) async {
        h.searchPlaces.add({
          'provider': 'osm',
          'id': 'node/stop',
          'name': 'Coffee stop',
          'label': 'Coffee stop',
          'address': 'Stop road',
          'latitude': -37.2,
          'longitude': 174.905,
        });
        await h.boot(preferences: {'waybi.app.language': language});
        await h.select();
        await h.act(details(t).onNavigate);
        await h.act(preview(t).onAddStop);
        await t.enterText(find.byType(TextField).last, 'Coffee');
        await h.until(
          () => find
              .widgetWithText(ListTile, 'Coffee stop')
              .evaluate()
              .isNotEmpty,
          reason: 'Stop search should show its result',
        );
        await t.tap(find.widgetWithText(ListTile, 'Coffee stop'));
        await h.frames();
        expect(preview(t).stopCount, 1);
        final search = h.requests.lastWhere(
          (r) => r.url.path == '/api/suggest',
        );
        expect(search.url.queryParameters['provider'], 'independent');
        expect(search.url.queryParameters['lang'], language);
        expect(
          h.routeRequests.last.url.queryParameters['stops'],
          contains('174.905,-37.2'),
        );
      },
    );
  }
  flow(
    'ETA sharing uses the active route and falls back to clipboard if native sharing is unavailable',
    (t, h) async {
      String copied = '';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await h.boot();
      await h.select(name: 'Harbour destination');
      await h.act(details(t).onNavigate);
      await h.act(preview(t).onStart);
      await h.until(() => h.map.navigating, reason: 'Guidance should start');
      final nav = t.widget<IndependentNavigationOverlay>(
        find.byType(IndependentNavigationOverlay),
      );
      await h.act(nav.onShare);
      expect(copied, contains('Waybi trip to Harbour destination'));
      expect(copied, contains('Remaining: 1.1 km'));
      expect(copied, contains('ETA: 20'));
      expect(find.text('ETA snapshot copied to clipboard'), findsOneWidget);
    },
  );
  flow(
    'browse location services failure gives a settings action and a fresh fix clears the notice',
    (t, h) async {
      await h.boot();
      h.gps.positions.addError(const LocationServiceDisabledException());
      await h.frames();
      expect(find.textContaining('Location services are off'), findsOneWidget);
      final action = find.text('Open settings');
      await t.tap(action);
      await h.frames();
      h.gps.emit();
      await h.frames();
      expect(find.textContaining('Location services are off'), findsNothing);
      expect(h.map.location, isNotNull);
    },
  );
  flow(
    'location controls switch compass mode and resume follow after map panning',
    (t, h) async {
      await h.boot();
      final location = find.byTooltip('Switch to heading-up');
      await t.tap(location);
      await h.frames();
      expect(h.map.following, isTrue);
      await h.act(h.map.onUserPan);
      expect(h.map.following, isFalse);
      final button = find.byTooltip('Return to my location');
      await t.tap(button);
      await h.frames();
      expect(h.map.following, isTrue);
    },
  );
}
