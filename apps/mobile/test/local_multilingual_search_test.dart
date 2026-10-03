import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/providers/place_search_providers.dart';
import 'package:waybi_mobile/widgets/full_screen_search.dart';

const auckland = GeoPoint(-36.8485, 174.7633);
Map<String, Object> feature(
  String name,
  int id,
  double lon,
  double lat, {
  String type = 'supermarket',
}) => {
  'properties': {
    'name': name,
    'osm_id': id,
    'osm_type': 'N',
    'osm_key': 'shop',
    'osm_value': type,
    'housenumber': '33-47',
    'street': 'Northside Drive',
  },
  'geometry': {
    'coordinates': [lon, lat],
  },
};
http.Response response(List<Map<String, Object>> features) =>
    http.Response.bytes(utf8.encode(jsonEncode({'features': features})), 200);

void main() {
  test(
    '福地 queries its verified local trading name and returns the Westgate POI',
    () async {
      final queries = <String>[];
      final provider = IndependentSearchProvider(
        requestSpacing: Duration.zero,
        client: MockClient((r) async {
          queries.add(r.url.queryParameters['q']!);
          expect(r.url.queryParameters['bbox'], isNotNull);
          return response([
            feature(
              'Foodies Heaven',
              2,
              174.76057,
              -36.86474,
              type: 'restaurant',
            ),
            feature(
              'Foodie Asian Supermarket',
              12157396838,
              174.6048637,
              -36.8114218,
            ),
          ]);
        }),
      );
      addTearDown(provider.dispose);
      final results = await provider.search(
        '福地',
        proximity: auckland,
        language: 'zh',
      );
      expect(queries, ['Foodie Asian Supermarket']);
      expect(results.first.name, 'Foodie Asian Supermarket');
      expect(results.first.kind, PlaceKind.poi);
      expect(results.first.location, const GeoPoint(-36.8114218, 174.6048637));
    },
  );

  test('Chinese partial names outrank unrelated nearby places', () async {
    final provider = IndependentSearchProvider(
      requestSpacing: Duration.zero,
      client: MockClient(
        (r) async => response([
          feature('白牡丹', 1, 174.7634, -36.8485),
          feature('万福商店', 2, 174.765, -36.85),
        ]),
      ),
    );
    addTearDown(provider.dispose);
    final results = await provider.search(
      '万福',
      proximity: auckland,
      language: 'zh',
    );
    expect(results.first.name, '万福商店');
  });

  test(
    'a missing local Chinese POI cannot silently become a Japanese destination',
    () async {
      final provider = IndependentSearchProvider(
        requestSpacing: Duration.zero,
        client: MockClient(
          (r) async => response(
            r.url.queryParameters.containsKey('bbox')
                ? []
                : [feature('万福', 3, 139.76, 35.68)],
          ),
        ),
      );
      addTearDown(provider.dispose);
      expect(
        await provider.search('万福', proximity: auckland, language: 'zh'),
        isEmpty,
      );
      final wider = await provider.searchFurther(
        '万福',
        proximity: auckland,
        language: 'zh',
      );
      expect(wider.single.location, const GeoPoint(35.68, 139.76));
    },
  );

  test(
    'local bounding and Chinese names also work outside New Zealand',
    () async {
      final provider = IndependentSearchProvider(
        requestSpacing: Duration.zero,
        client: MockClient((r) async {
          expect(r.url.queryParameters['q'], '福地');
          expect(r.url.queryParameters['bbox'], isNotNull);
          return response([feature('福地', 4, 151.20, -33.86)]);
        }),
      );
      addTearDown(provider.dispose);
      final results = await provider.search(
        '福地',
        proximity: const GeoPoint(-33.86, 151.20),
        language: 'zh',
      );
      expect(results.single.name, '福地');
    },
  );

  testWidgets('wider results require the visible Search further action', (
    tester,
  ) async {
    final provider = IndependentSearchProvider(
      requestSpacing: Duration.zero,
      client: MockClient(
        (r) async => response(
          r.url.queryParameters.containsKey('bbox')
              ? []
              : [feature('万福', 5, 139.76, 35.68)],
        ),
      ),
    );
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: FullScreenSearch(
          provider: provider,
          resolve: (p) async => p.toPlace(p.location!),
          language: 'zh',
          recent: const [],
          currentLocation: auckland,
          initialQuery: '万福',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('附近优先'), findsOneWidget);
    expect(find.text('万福'), findsOneWidget); // Editable input only.
    await tester.tap(find.text('搜索更远的地点'));
    await tester.pumpAndSettle();
    expect(find.text('所有地区'), findsOneWidget);
    expect(find.text('万福'), findsNWidgets(2));
  });
}
