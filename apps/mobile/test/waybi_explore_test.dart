import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/data/explore_repository.dart';
import 'package:waybi_mobile/theme/waybi_theme.dart';
import 'package:waybi_mobile/widgets/explore_page.dart';

void main() {
  test('Waybi discovery requests independent nearby categories and parses licensed photos', () async {
    final repository = ExploreRepository(
      client: MockClient((request) async {
        expect(request.url.queryParameters['provider'], 'osm');
        expect(request.url.queryParameters['category'], 'parks');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode([
              {
                'placeId': 'osm:way:1',
                'provider': 'osm',
                'name': '公园',
                'primaryType': 'parks',
                'latitude': -36.85,
                'longitude': 174.76,
                'photoUrl': 'https://upload.wikimedia.org/photo.jpg',
                'photoCredit': {'author': 'Author', 'license': 'CC BY 4.0'},
              },
            ]),
          ),
          200,
        );
      }),
    );
    final places = await repository.fetch(
      latitude: -36.85,
      longitude: 174.76,
      category: 'parks',
      language: 'zh',
      mapCompatible: true,
    );
    expect(places.single.name, '公园');
    expect(places.single.photoUrl, startsWith('https://upload.wikimedia.org/'));
    expect(places.single.photoCredit?['author'], 'Author');
    repository.dispose();
  });
  testWidgets(
    'Chinese Explore shows category art and opens credits without supplier banners',
    (tester) async {
      final repository = ExploreRepository(
        client: MockClient(
          (request) async => http.Response.bytes(
            utf8.encode(
              jsonEncode([
                {
                  'placeId': 'osm:way:1',
                  'provider': 'osm',
                  'name': 'Albert Park',
                  'primaryType': 'parks',
                  'latitude': -36.85,
                  'longitude': 174.76,
                },
              ]),
            ),
            200,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: WaybiTheme.lightFor('zh'),
          home: ExplorePage(
            currentLocation: const LatLng(latitude: -36.85, longitude: 174.76),
            language: 'zh',
            mapCompatible: true,
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Albert Park'), findsOneWidget);
      expect(find.text('公园与绿地'), findsWidgets);
      expect(find.text('跟着 Waybi，去发现'), findsOneWidget);
      expect(find.textContaining('contributors'), findsNothing);
      expect(find.textContaining('Geoapify'), findsNothing);
      await tester.tap(find.byTooltip('数据与图片来源'));
      await tester.pumpAndSettle();
      expect(find.text('© OpenStreetMap · ODbL'), findsOneWidget);
    },
  );
}
