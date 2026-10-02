import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiwi_lens_mobile/domain/map_provider.dart';
import 'package:kiwi_lens_mobile/providers/place_search_providers.dart';
import 'package:kiwi_lens_mobile/widgets/full_screen_search.dart';

void main() {
  test('two-character Chinese searches identify app, preserve UTF-8 and cache repeated queries', () async {
    var requests = 0;
    final provider = IndependentSearchProvider(
      requestSpacing: Duration.zero,
      client: MockClient((request) async {
        requests++;
        expect(request.headers['User-Agent'], startsWith('KiwiLens/'));
        expect(request.url.queryParameters['q'], 'cafe');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'features': [
                {
                  'properties': {
                    'osm_id': 123,
                    'osm_type': 'N',
                    'name': '咖啡馆',
                    'osm_value': 'cafe',
                  },
                  'geometry': {
                    'coordinates': [174.7634, -36.8485],
                  },
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final first = await provider.search('咖啡', language: 'zh');
    final second = await provider.search('咖啡', language: 'zh');
    expect(first.single.name, '咖啡馆');
    expect(second.single.location, const GeoPoint(-36.8485, 174.7634));
    expect(first.single.reference!.provider, 'osm');
    expect(requests, 1);
    provider.dispose();
  });

  test('brand search retries without generic category words and prefers the nearby name match', () async {
    final queries = <String>[];
    final provider = IndependentSearchProvider(
      requestSpacing: Duration.zero,
      client: MockClient((request) async {
        final query = request.url.queryParameters['q']!;
        queries.add(query);
        final features = query == 'taiping asian supermarket'
            ? [
                {
                  'properties': {
                    'osm_id': 1,
                    'osm_type': 'N',
                    'name': 'NJK Asian Supermarket',
                    'osm_value': 'supermarket',
                  },
                  'geometry': {
                    'coordinates': [174.7767, -36.8683],
                  },
                },
              ]
            : [
                {
                  'properties': {
                    'osm_id': 2,
                    'osm_type': 'N',
                    'name': 'Taiping',
                    'osm_value': 'town',
                  },
                  'geometry': {
                    'coordinates': [100.7439, 4.8547],
                  },
                },
                {
                  'properties': {
                    'osm_id': 3,
                    'osm_type': 'N',
                    'name': 'Tai Ping',
                    'osm_value': 'supermarket',
                  },
                  'geometry': {
                    'coordinates': [174.7759, -36.8710],
                  },
                },
              ];
        return http.Response(jsonEncode({'features': features}), 200);
      }),
    );

    final results = await provider.search(
      'taiping asian supermarket',
      proximity: const GeoPoint(-36.8485, 174.7633),
      language: 'en',
    );

    expect(queries, ['taiping asian supermarket', 'taiping']);
    expect(results.first.name, 'Tai Ping');
    expect(results.first.location, const GeoPoint(-36.8710, 174.7759));
    provider.dispose();
  });

  testWidgets(
    'keyboard submit searches immediately and an error can be retried',
    (tester) async {
      var requests = 0;
      final provider = IndependentSearchProvider(
        requestSpacing: Duration.zero,
        client: MockClient((_) async {
          requests++;
          if (requests == 1) return http.Response('unavailable', 503);
          return http.Response(
            jsonEncode({
              'features': [
                {
                  'properties': {
                    'osm_id': 123,
                    'osm_type': 'N',
                    'name': 'Aotea Square',
                  },
                  'geometry': {
                    'coordinates': [174.7634, -36.8518],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: FullScreenSearch(
            provider: provider,
            resolve: (candidate) async =>
                candidate.toPlace(candidate.location!),
            language: 'zh',
            recent: const [],
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Aotea');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('搜索暂不可用'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Aotea Square'), findsOneWidget);
      expect(requests, 2);
      provider.dispose();
    },
  );
}
