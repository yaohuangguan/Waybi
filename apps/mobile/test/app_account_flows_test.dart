import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_preference.dart';
import 'package:waybi_mobile/widgets/place_details_content.dart';
import 'package:waybi_mobile/widgets/profile_page.dart';
import 'package:waybi_mobile/widgets/route_preview_sheet.dart';

import 'support/app_harness.dart';

PlaceDetailsContent place(WidgetTester t) =>
    t.widget<PlaceDetailsContent>(find.byType(PlaceDetailsContent));
RoutePreviewSheet route(WidgetTester t) =>
    t.widget<RoutePreviewSheet>(find.byType(RoutePreviewSheet));
void appTest(
  String name,
  Future<void> Function(WidgetTester, AppHarness) body,
) {
  testWidgets(name, (t) async {
    final h = AppHarness(t);
    await http.runWithClient(() async {
      await body(t, h);
      await h.dispose();
    }, () => h.client);
  });
}

void main() {
  appTest(
    'guest favorite and private review lead to sign in without losing the selected place',
    (t, h) async {
      await h.boot();
      await h.select();
      await h.act(place(t).onFavorite);
      expect(find.byType(ProfilePage), findsOneWidget);
      Navigator.of(t.element(find.byType(ProfilePage))).pop();
      await h.frames();
      expect(place(t).selectedPlace.name, 'Test destination');
      await h.act(place(t).onReview);
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(
        h.requests.where((r) => r.url.path == '/api/profile/reviews'),
        isEmpty,
      );
      Navigator.of(t.element(find.byType(ProfilePage))).pop();
      await h.frames();
    },
  );
  appTest(
    'signed in favorites toggle and a failed update preserves the existing state',
    (t, h) async {
      await h.boot(signedIn: true);
      await h.select();
      await h.act(place(t).onFavorite);
      expect(place(t).isFavorite, isTrue);
      expect(h.savedPlaces.single['placeId'], 'coords:-37.20000,174.91000');
      await h.act(place(t).onFavorite);
      expect(place(t).isFavorite, isFalse);
      h.endpointFailures['/api/profile/places'] = 503;
      await h.act(place(t).onFavorite);
      expect(place(t).isFavorite, isFalse);
      expect(find.textContaining('Temporarily unavailable'), findsWidgets);
      expect(place(t).selectedPlace.name, 'Test destination');
    },
  );
  appTest(
    'a saved OSM favorite reopens on Waybi with its original provider reference',
    (t, h) async {
      h.savedPlaces.add({
        'placeId': 'osm:node:123',
        'name': 'Saved cafe',
        'latitude': -37.2,
        'longitude': 174.91,
        'isFavorite': true,
      });
      await h.boot(signedIn: true);
      await t.tap(find.byTooltip('Saved places'));
      await h.frames();
      await h.tapText('Saved cafe');
      expect(place(t).selectedPlace.reference?.provider, 'osm');
      expect(place(t).selectedPlace.reference?.id, 'node:123');
      expect(place(t).selectedPlace.name, 'Saved cafe');
      await h.act(place(t).onNavigate);
      expect(route(t).plan.provider, 'independent');
    },
  );
  appTest(
    'cancelling a typed private review closes safely and never sends a review',
    (t, h) async {
      await h.boot(signedIn: true);
      await h.select();
      await h.act(place(t).onReview);
      await t.enterText(find.byType(TextField).last, 'Do not save this');
      await h.tapText('Cancel');
      expect(find.byType(AlertDialog), findsNothing);
      expect(h.reviews, isEmpty);
      expect(
        h.requests.where((r) => r.url.path == '/api/profile/reviews'),
        isEmpty,
      );
      expect(place(t).selectedPlace.name, 'Test destination');
    },
  );
  appTest(
    'a private review is saved, restores its text, and reports a failed edit',
    (t, h) async {
      await h.boot(signedIn: true);
      await h.select();
      await h.act(place(t).onReview);
      await t.enterText(find.byType(TextField).last, '  Easy access  ');
      await h.tapText('Save');
      expect(h.reviews.single['comment'], 'Easy access');
      expect(h.reviews.single['rating'], 5);
      await h.act(place(t).onReview);
      expect(find.text('Easy access'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, 'Changed');
      h.endpointFailures['/api/profile/reviews'] = 503;
      await h.tapText('Save');
      expect(h.reviews.single['comment'], 'Easy access');
      expect(find.textContaining('Temporarily unavailable'), findsWidgets);
    },
  );
  appTest(
    'saving a selected route replaces duplicates, caps history and reopens on Waybi',
    (t, h) async {
      await h.boot(
        preferences: {
          'waybi.saved.routes': [
            'damaged',
            for (var i = 0; i < 21; i++)
              jsonEncode({
                'destination': {
                  'name': 'Previous $i',
                  'latitude': -37.2,
                  'longitude': 174.91,
                },
                'provider': 'independent',
              }),
          ],
        },
      );
      await h.select(name: 'Saved destination');
      await h.act(place(t).onNavigate);
      route(t).onFilterChanged!(RouteFilter.shortest);
      await h.frames();
      expect(route(t).selectedRouteId, 'drive-short');
      await h.act(route(t).onSave);
      await h.act(route(t).onSave);
      final records = (await SharedPreferences.getInstance()).getStringList(
        'waybi.saved.routes',
      )!;
      expect(records, hasLength(20));
      expect(
        records.where((r) => r.contains('Saved destination')),
        hasLength(1),
      );
      expect((jsonDecode(records.first) as Map)['provider'], 'independent');
      route(t).onClose();
      await h.frames();
      await t.tap(find.byTooltip('Saved places'));
      await h.frames();
      await h.tapText('Saved destination');
      expect(place(t).selectedPlace.name, 'Saved destination');
    },
  );
  appTest(
    'all six road report types use the current GPS and failures preserve the map',
    (t, h) async {
      await h.boot();
      const choices = {
        'Crash / hazard': 'incident',
        'Roadworks': 'roadworks',
        'Road closed': 'roadClosure',
        'Heavy traffic': 'congestion',
        'Flooding': 'flooding',
        'Slip / debris': 'slip',
      };
      for (final choice in choices.entries) {
        await t.tap(find.byTooltip('Report road issue'));
        await h.frames();
        await h.tapText(choice.key);
        final request = h.requests.lastWhere(
          (r) => r.url.path == '/api/road-reports' && r.method == 'POST',
        );
        final body = jsonDecode(request.body) as Map;
        expect(body['type'], choice.value);
        expect(body['latitude'], -37.2);
        expect(body['longitude'], 174.9);
        expect(find.text('Road report submitted'), findsWidgets);
        ScaffoldMessenger.of(t.element(find.byType(Scaffold).first))
            .removeCurrentSnackBar();
        await h.frames();
      }
      h.reportStatus = 503;
      await t.tap(find.byTooltip('Report road issue'));
      await h.frames();
      await h.tapText('Road closed');
      expect(
        find.textContaining('Could not submit road report'),
        findsOneWidget,
      );
      expect(h.map.location, const GeoPoint(-37.2, 174.9));
    },
  );
  appTest(
    'road reports without location explain the problem without sending a request',
    (t, h) async {
      h.permission = 4;
      await h.boot();
      await t.tap(find.byTooltip('Report road issue'));
      await h.frames();
      expect(
        find.textContaining('Current location is required'),
        findsOneWidget,
      );
      expect(
        h.requests.where((r) => r.url.path == '/api/road-reports'),
        isEmpty,
      );
    },
  );
  appTest(
    'legacy home shortcut remains usable on Waybi and requests independent routes',
    (t, h) async {
      await h.boot(
        preferences: {
          'waybi.quick_location.Home': jsonEncode({
            'name': 'My home',
            'address': 'Destination road',
            'latitude': -37.2,
            'longitude': 174.91,
            'provider': 'google',
          }),
          'waybi.quick_location.Work': 'corrupt',
        },
      );
      final chip = find.widgetWithText(ActionChip, 'Home');
      await t.ensureVisible(chip);
      await t.tap(chip);
      await h.frames();
      expect(place(t).selectedPlace.name, 'My home');
      await h.act(place(t).onNavigate);
      expect(route(t).plan.provider, 'independent');
      expect(
        h.routeRequests.every(
          (r) => r.url.queryParameters['provider'] == 'independent',
        ),
        isTrue,
      );
      expect(h.requests.any((r) => r.url.host.contains('google')), isFalse);
    },
  );
}
