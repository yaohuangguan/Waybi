import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/widgets/explore_search.dart';

const origin = LatLng(latitude: -37.2, longitude: 174.9);
Map<String, Object> row(String name, {double longitude = 174.901}) => {
  'name': name,
  'label': name,
  'address': '$name, Auckland',
  'latitude': -37.2,
  'longitude': longitude,
  'isPoi': true,
};
Future<void> frames(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 350));
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 15)),
  );
  await t.pump();
  expect(t.takeException(), isNull);
}

void main() {
  for (final language in ['en', 'zh']) {
    testWidgets(
      '$language address search falls back, deduplicates and selects an origin without changing the destination',
      (t) async {
        final requests = <http.Request>[];
        final origins = <DestinationSuggestion?>[];
        final destinations = <DestinationSuggestion>[];
        final focus = <bool>[];
        final client = MockClient((r) async {
          requests.add(r);
          if (r.url.path == '/api/reverse') {
            return http.Response('{"label":"Airport Road"}', 200);
          }
          if (r.url.path == '/api/suggest') return http.Response('{}', 503);
          return http.Response(
            jsonEncode([
              row('Origin café'),
              row('Origin café'),
              {'latitude': 'invalid'},
              42,
            ]),
            200,
          );
        });
        await http.runWithClient(() async {
          await t.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ExploreSearch(
                  currentLocation: origin,
                  language: language,
                  onSelected: destinations.add,
                  onOriginSelected: origins.add,
                  onFocusChanged: focus.add,
                ),
              ),
            ),
          );
          await frames(t);
          expect(
            t
                .widget<TextField>(find.byType(TextField).first)
                .decoration!
                .hintText,
            'Airport Road',
          );
          await t.enterText(find.byType(TextField).first, 'Origin');
          await frames(t);
          expect(find.widgetWithText(ListTile, 'Origin café'), findsOneWidget);
          await t.tap(find.widgetWithText(ListTile, 'Origin café'));
          await frames(t);
          expect(origins.single!.name, 'Origin café');
          expect(destinations, isEmpty);
          expect(focus, contains(true));
          final clear = find.descendant(
            of: find.byType(TextField).first,
            matching: find.byIcon(Icons.close_rounded),
          );
          await t.tap(clear);
          await frames(t);
          expect(origins.last, isNull);
          final before = requests
              .where((r) => r.url.path == '/api/suggest')
              .length;
          await t.enterText(find.byType(TextField).last, 'Destination');
          await frames(t);
          expect(
            requests.where((r) => r.url.path == '/api/suggest').length,
            before,
            reason: 'An unavailable suggestions endpoint should have a short cooldown',
          );
          await t.tap(find.widgetWithText(ListTile, 'Origin café'));
          await frames(t);
          expect(destinations.single.location.longitude, 174.901);
          expect(
            requests
                .where((r) => r.url.path == '/api/search')
                .every((r) => r.url.queryParameters['lang'] == language),
            isTrue,
          );
          await t.pumpWidget(const SizedBox());
        }, () => client);
      },
    );
    testWidgets(
      '$language search errors are readable and clearing restores recent results',
      (t) async {
        final client = MockClient(
          (r) async => http.Response('unavailable', 500),
        );
        await http.runWithClient(() async {
          await t.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ExploreSearch(
                  currentLocation: null,
                  language: language,
                  destinationOnly: true,
                  onSelected: (_) {},
                  recent: const [
                    DestinationSuggestion(
                      label: 'Recent destination',
                      location: origin,
                    ),
                  ],
                ),
              ),
            ),
          );
          await t.enterText(find.byType(TextField), 'Broken');
          await frames(t);
          expect(
            find.text(
              language == 'zh' ? '地址搜索暂不可用' : 'Address search is unavailable',
            ),
            findsOneWidget,
          );
          await t.tap(find.byKey(const Key('destinationClearButton')));
          await frames(t);
          expect(find.text('Recent destination'), findsOneWidget);
          expect(
            find.text(
              language == 'zh' ? '地址搜索暂不可用' : 'Address search is unavailable',
            ),
            findsNothing,
          );
          await t.pumpWidget(const SizedBox());
        }, () => client);
      },
    );
  }
  testWidgets(
    'empty suggestion results fall back for this query without downgrading the next query',
    (t) async {
      final paths = <String>[];
      final client = MockClient((r) async {
        paths.add(r.url.path);
        final data = r.url.path == '/api/suggest'
            ? []
            : [row('Recovered address')];
        return http.Response(jsonEncode(data), 200, request: r);
      });
      await http.runWithClient(() async {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ExploreSearch(
                currentLocation: null,
                destinationOnly: true,
                initialQuery: 'First query',
                onSelected: (_) {},
              ),
            ),
          ),
        );
        await frames(t);
        expect(find.text('Recovered address'), findsOneWidget);
        await t.enterText(find.byType(TextField), 'Second query');
        await frames(t);
        expect(paths, [
          '/api/suggest',
          '/api/search',
          '/api/suggest',
          '/api/search',
        ]);
        await t.pumpWidget(const SizedBox());
      }, () => client);
    },
  );
  testWidgets(
    'a stale response cannot replace newer search results or a cleared query',
    (t) async {
      final old = Completer<http.Response>();
      final client = MockClient((r) async {
        if (r.url.queryParameters['q'] == 'Old') return old.future;
        return http.Response(jsonEncode([row('New place')]), 200, request: r);
      });
      await http.runWithClient(() async {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ExploreSearch(
                currentLocation: null,
                destinationOnly: true,
                onSelected: (_) {},
              ),
            ),
          ),
        );
        await t.enterText(find.byType(TextField), 'Old');
        await frames(t);
        await t.enterText(find.byType(TextField), 'New');
        await frames(t);
        old.complete(http.Response(jsonEncode([row('Old place')]), 200));
        await frames(t);
        expect(find.text('New place'), findsOneWidget);
        expect(find.text('Old place'), findsNothing);
        await t.tap(find.byKey(const Key('destinationClearButton')));
        await t.enterText(find.byType(TextField), 'a');
        await frames(t);
        expect(find.byType(ListTile), findsNothing);
        await t.pumpWidget(const SizedBox());
      }, () => client);
    },
  );
  testWidgets(
    'current position labels refresh after movement and recover from missing location',
    (t) async {
      final points = <String>[];
      final client = MockClient((r) async {
        points.add(r.url.queryParameters['at']!);
        return http.Response(
          jsonEncode({'label': 'Road ${points.length}'}),
          200,
        );
      });
      await http.runWithClient(() async {
        Future<void> show(LatLng? point) async {
          await t.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ExploreSearch(currentLocation: point, onSelected: (_) {}),
              ),
            ),
          );
          await frames(t);
        }

        await show(origin);
        await show(const LatLng(latitude: -37.2, longitude: 174.9001));
        expect(points, hasLength(1));
        await show(const LatLng(latitude: -37.2, longitude: 174.91));
        expect(points, hasLength(2));
        expect(
          t
              .widget<TextField>(find.byType(TextField).first)
              .decoration!
              .hintText,
          'Road 2',
        );
        await show(null);
        expect(
          t
              .widget<TextField>(find.byType(TextField).first)
              .decoration!
              .hintText,
          'Locating current position…',
        );
        await show(const LatLng(latitude: -37.2, longitude: 174.92));
        expect(points, hasLength(3));
        await t.pumpWidget(const SizedBox());
      }, () => client);
    },
  );
  testWidgets(
    'recent address rows format POIs, short and long distances and locality only once',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExploreSearch(
              currentLocation: origin,
              destinationOnly: true,
              onSelected: (_) {},
              recent: const [
                DestinationSuggestion(
                  label: '12 Road, Auckland',
                  name: '12 Road',
                  address: '12 Road, Auckland',
                  isPoi: false,
                  location: origin,
                ),
                DestinationSuggestion(
                  label: 'Middle café',
                  name: 'Middle café',
                  address: 'Middle café',
                  location: LatLng(latitude: -37.2, longitude: 174.95),
                ),
                DestinationSuggestion(
                  label: 'Far destination',
                  address: 'Far road',
                  location: LatLng(latitude: -37.2, longitude: 175.2),
                ),
              ],
            ),
          ),
        ),
      );
      await t.pump();
      expect(find.text('12 Road'), findsOneWidget);
      expect(find.text('Auckland'), findsOneWidget);
      expect(find.text('0 m'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^4\.\d km$')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^27 km$')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
}
