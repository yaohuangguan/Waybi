import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/widgets/companion_search_prompt.dart';
import 'package:waybi_mobile/widgets/full_screen_search.dart';
import 'package:waybi_mobile/widgets/place_details_content.dart';
import 'package:waybi_mobile/widgets/trips_page.dart';
import 'package:waybi_mobile/widgets/route_preview_sheet.dart';
import 'package:waybi_mobile/services/google_place_picker.dart';

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
Map<String, dynamic> shortcut(String label, double lon) => {
  'label': label,
  'name': 'My $label',
  'address': '$label road',
  'latitude': -37.2,
  'longitude': lon,
  'provider': 'independent',
};
Map<String, dynamic> result(String name, double lon) => {
  'id': 'node/$name',
  'provider': 'osm',
  'name': name,
  'label': name,
  'address': 'Destination road',
  'latitude': -37.2,
  'longitude': lon,
  'resultType': 'cafe',
  'isPoi': true,
};
Future<void> edit(WidgetTester t, AppHarness h) async {
  final button = find.byTooltip('Edit shortcuts');
  final strip = find
      .byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.horizontal,
      )
      .first;
  for (var i = 0; i < 6 && button.evaluate().isEmpty; i++) {
    await t.drag(strip, const Offset(-260, 0));
    await h.frames();
  }
  await t.ensureVisible(button);
  await t.tap(button);
  await h.frames();
}

void main() {
  void googleSelection() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          GooglePlacePicker.channel,
          (_) async => jsonEncode({
            'status': 'selected',
            'id': 'google-id',
            'query': 'New office',
            'latitude': -37.2,
            'longitude': 174.92,
          }),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(GooglePlacePicker.channel, null),
    );
  }

  flow(
    'Google search navigates without storing its input coordinates in saved routes or favorites',
    (t, h) async {
      googleSelection();
      h.snappedDestinationLongitude = 174.9199;
      await h.boot(signedIn: true);
      await h.act(
        () => t
            .widget<CompanionSearchPrompt>(find.byType(CompanionSearchPrompt))
            .onSearch('New office'),
      );
      await h.until(
        () => find.byType(PlaceDetailsContent).evaluate().isNotEmpty,
        reason: 'Google selection should reach the real place card',
      );
      expect(details(t).selectedPlace.reference?.provider, 'google-ui-kit');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('waybi.recent.google'), isNull);
      await h.act(details(t).onFavorite);
      expect(h.savedPlaces, isEmpty);
      await h.act(details(t).onNavigate);
      await h.until(
        () => find.byType(RoutePreviewSheet).evaluate().isNotEmpty,
        reason:
            'Selected Google point should receive a Valhalla-compatible route',
      );
      final preview = t.widget<RoutePreviewSheet>(
        find.byType(RoutePreviewSheet),
      );
      await h.act(preview.onSave);
      final route =
          jsonDecode(prefs.getStringList('waybi.saved.routes')!.single) as Map;
      expect((route['destination'] as Map)['longitude'], 174.9199);
      expect(
        h.routeRequests.any(
          (request) => request.url.queryParameters['to'] == '174.92,-37.2',
        ),
        isTrue,
      );
    },
  );
  for (final matched in [true, false]) {
    flow(
      'Google Work selection saves only an independently verified shortcut: $matched',
      (t, h) async {
        googleSelection();
        h.searchPlaces.add(
          result(matched ? 'New office' : 'Another business', 174.92001),
        );
        await h.boot(signedIn: true);
        await edit(t, h);
        await t.tap(
          find.descendant(
            of: find.byKey(const ValueKey('Work')),
            matching: find.byTooltip('Set location'),
          ),
        );
        await h.until(
          () => find.byType(PlaceDetailsContent).evaluate().isNotEmpty,
          reason: 'Google Work selection should remain usable for navigation',
        );
        await h.frames(6);
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('waybi.quick_location.Work');
        if (matched) {
          expect((jsonDecode(saved!) as Map)['longitude'], 174.92001);
          expect(h.quickLocations.single['longitude'], 174.92001);
        } else {
          expect(saved, isNull);
          expect(h.quickLocations, isEmpty);
          expect(find.textContaining('To save Home or Work'), findsOneWidget);
        }
        expect(prefs.getStringList('waybi.recent.google'), isNull);
      },
    );
  }
  flow('shortcut ordering and removal are persisted and can be restored', (
    t,
    h,
  ) async {
    await h.boot();
    await edit(t, h);
    final list = t.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    list.onReorderItem!(0, 2);
    await h.frames();
    final work = find.byKey(const ValueKey('Work'));
    await t.tap(
      find.descendant(
        of: work,
        matching: find.byIcon(Icons.remove_circle_outline),
      ),
    );
    await h.frames();
    expect(find.text('+ Work'), findsOneWidget);
    await t.tap(find.text('+ Work'));
    await h.frames();
    await h.tapText('Done');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('waybi.quick_actions'), [
      'Frequent',
      'Home',
      'Restaurants',
      'Shopping',
      'Gas',
      'Work',
    ]);
    expect(find.byType(ReorderableListView), findsNothing);
    await edit(t, h);
    final again = t.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    expect(again.itemCount, 6);
    expect(
      t.getTopLeft(find.byKey(const ValueKey('Frequent'))).dy,
      lessThan(t.getTopLeft(find.byKey(const ValueKey('Home'))).dy),
    );
  });
  flow(
    'setting Home from search saves a usable guest shortcut and destination history',
    (t, h) async {
      h.searchPlaces.add(result('New home', 174.91));
      await h.boot();
      await edit(t, h);
      await t.tap(
        find.descendant(
          of: find.byKey(const ValueKey('Home')),
          matching: find.byTooltip('Set location'),
        ),
      );
      await h.frames();
      expect(find.byType(FullScreenSearch), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'New home');
      await h.until(
        () => find.widgetWithText(ListTile, 'New home').evaluate().isNotEmpty,
        reason: 'Search should return Home',
      );
      await t.tap(find.widgetWithText(ListTile, 'New home'));
      await h.frames();
      expect(details(t).selectedPlace.name, 'New home');
      final prefs = await SharedPreferences.getInstance();
      final saved =
          jsonDecode(prefs.getString('waybi.quick_location.Home')!) as Map;
      expect(saved['provider'], 'independent');
      expect(saved['longitude'], 174.91);
      final history = prefs.getStringList('waybi.recent.google')!;
      expect(jsonDecode(history.first)['name'], 'New home');
      expect(
        h.requests
            .where((r) => r.url.path == '/api/suggest')
            .every((r) => r.url.queryParameters['provider'] == 'independent'),
        isTrue,
      );
    },
  );
  flow(
    'signed-in Work search persists the account shortcut even if cloud saving fails',
    (t, h) async {
      h.searchPlaces.add(result('New office', 174.92));
      h.endpointFailures['/api/profile/quick-locations'] = 503;
      await h.boot(signedIn: true);
      final prompt = t.widget<CompanionSearchPrompt>(
        find.byType(CompanionSearchPrompt),
      );
      await h.act(() => prompt.onSearch('New office'));
      await h.until(
        () => find.widgetWithText(ListTile, 'New office').evaluate().isNotEmpty,
        reason: 'Full search should return office',
      );
      // Cancel ordinary search, then configure Work through the shortcut editor.
      Navigator.of(t.element(find.byType(FullScreenSearch))).pop();
      await h.frames();
      await edit(t, h);
      await t.tap(
        find.descendant(
          of: find.byKey(const ValueKey('Work')),
          matching: find.byTooltip('Set location'),
        ),
      );
      await h.frames();
      await t.enterText(find.byType(TextField).first, 'New office');
      await h.until(
        () => find.widgetWithText(ListTile, 'New office').evaluate().isNotEmpty,
        reason: 'Work query should return office',
      );
      await t.tap(find.widgetWithText(ListTile, 'New office'));
      await h.frames();
      expect(details(t).selectedPlace.name, 'New office');
      expect(
        h.requests.any((r) => r.url.path == '/api/profile/quick-locations'),
        isTrue,
      );
      final prefs = await SharedPreferences.getInstance();
      final saved =
          jsonDecode(prefs.getString('waybi.quick_location.Work')!) as Map;
      expect(prefs.getString('waybi.quick_location.owner_user_id'), 'driver');
      expect(saved['provider'], 'independent');
    },
  );
  flow(
    'map search suggestions use Waybi, select the result and deduplicate recent places',
    (t, h) async {
      h.searchPlaces.add(result('Harbour search', 174.914));
      await h.boot();
      await t.enterText(find.byType(TextField).first, 'Harbour');
      await h.until(
        () => find.text('Harbour search').evaluate().isNotEmpty,
        reason: 'Map suggestions should load',
      );
      await h.tapText('Harbour search');
      expect(details(t).selectedPlace.reference?.provider, 'osm');
      expect(details(t).selectedPlace.name, 'Harbour search');
      final prompt = t.widget<CompanionSearchPrompt>(
        find.byType(CompanionSearchPrompt),
      );
      final rows = await t.runAsync(() => prompt.loadSuggestions('Harbour'));
      await h.act(() => prompt.onSuggestionSelected(rows!.single));
      final recent = (await SharedPreferences.getInstance()).getStringList(
        'waybi.recent.google',
      )!;
      expect(recent, hasLength(1));
      expect(jsonDecode(recent.single)['longitude'], 174.914);
      final cached = prompt.cachedSuggestions!('Harbour');
      expect(cached.single.name, 'Harbour search');
      final frequent = find.widgetWithText(ActionChip, 'Frequent');
      await t.ensureVisible(frequent);
      await t.tap(frequent);
      await h.frames();
      expect(details(t).selectedPlace.name, 'Harbour search');
    },
  );
  flow(
    'a search candidate without coordinates opens full search and cancellation restores selection',
    (t, h) async {
      await h.boot();
      await h.select(name: 'Keep selected');
      final prompt = t.widget<CompanionSearchPrompt>(
        find.byType(CompanionSearchPrompt),
      );
      await h.act(
        () => prompt.onSuggestionSelected(
          const PlaceCandidate(
            name: 'Unresolved place',
            address: '',
            kind: PlaceKind.poi,
          ),
        ),
      );
      expect(find.byType(FullScreenSearch), findsOneWidget);
      expect(
        t.widget<FullScreenSearch>(find.byType(FullScreenSearch)).initialQuery,
        'Unresolved place',
      );
      Navigator.of(t.element(find.byType(FullScreenSearch))).pop();
      await h.frames();
      expect(details(t).selectedPlace.name, 'Keep selected');
    },
  );
  flow(
    'reverse lookup enriches map selections while a dropped pin keeps its identity',
    (t, h) async {
      h.reversePlaces.add({
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [174.91, -37.2],
        },
        'properties': {
          'name': 'Resolved café',
          'street': 'Harbour Road',
          'housenumber': '12',
          'city': 'Auckland',
          'country': 'New Zealand',
          'osm_key': 'amenity',
          'osm_value': 'cafe',
          'osm_type': 'N',
          'osm_id': 123,
        },
      });
      await h.boot();
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
      await h.until(
        () => details(t).selectedPlace.address.contains('Harbour Road'),
        reason: 'Reverse lookup should enrich the address',
      );
      expect(details(t).selectedPlace.name, 'Map café');
      expect(details(t).selectedPlace.reference?.provider, 'osm');
      await h.act(
        () => h.map.onMapPlace(
          const PlaceSummary(
            name: 'Dropped pin',
            address: '',
            location: GeoPoint(-37.2, 174.912),
            kind: PlaceKind.coordinate,
          ),
        ),
      );
      await h.until(
        () => details(t).selectedPlace.address.contains('Harbour Road'),
        reason: 'Pin address should resolve',
      );
      expect(details(t).selectedPlace.name, 'Dropped pin');
      expect(details(t).selectedPlace.reference, isNull);
    },
  );
  flow(
    'Smart Commute compares both directions with owned routing and clears stale watches',
    (t, h) async {
      h.quickLocations.addAll([
        shortcut('Home', 174.91),
        shortcut('Work', 174.92),
      ]);
      h.routeWatchRows.addAll([
        {'id': 'hw', 'label': 'home-work', 'status': 'clear', 'events': []},
        {'id': 'wh', 'label': 'work-home', 'status': 'clear', 'events': []},
      ]);
      await h.boot(signedIn: true, plus: true);
      await h.tapText('Trips');
      final page = t.widget<TripsPage>(find.byType(TripsPage));
      final snapshot = await t.runAsync(page.loader);
      expect(
        snapshot!.smartCommuteRoutes.keys,
        containsAll(['home-work', 'work-home']),
      );
      expect(
        snapshot.smartCommuteRoutes.values.every(
          (r) => r.provider == 'independent',
        ),
        isTrue,
      );
      expect(
        h.routeRequests.any(
          (r) =>
              r.url.queryParameters['from'] == '174.91,-37.2' &&
              r.url.queryParameters['to'] == '174.92,-37.2',
        ),
        isTrue,
      );
      expect(
        h.routeRequests.any(
          (r) =>
              r.url.queryParameters['from'] == '174.92,-37.2' &&
              r.url.queryParameters['to'] == '174.91,-37.2',
        ),
        isTrue,
      );
      h.routeWatchRows.clear();
      final cleared = await t.runAsync(page.loader);
      expect(cleared!.smartCommuteRoutes, isEmpty);
      expect(cleared.quickPlaces, hasLength(2));
    },
  );
  flow('Smart Commute keeps saved destinations usable during routing failure', (
    t,
    h,
  ) async {
    h.quickLocations.addAll([
      shortcut('Home', 174.91),
      shortcut('Work', 174.92),
    ]);
    h.routeWatchRows.add({
      'id': 'hw',
      'label': 'home-work',
      'status': 'unknown',
      'events': [],
    });
    h.routeFailure = true;
    await h.boot(signedIn: true, plus: true);
    await h.tapText('Trips');
    final page = t.widget<TripsPage>(find.byType(TripsPage));
    final snapshot = await t.runAsync(page.loader);
    expect(snapshot!.smartCommuteRoutes, isEmpty);
    expect(snapshot.quickPlaces.keys, containsAll(['Home', 'Work']));
    expect(snapshot.routeWatches['home-work']!.status, 'unknown');
    expect(
      h.routeRequests.every(
        (r) => r.url.queryParameters['provider'] == 'independent',
      ),
      isTrue,
    );
  });
}
