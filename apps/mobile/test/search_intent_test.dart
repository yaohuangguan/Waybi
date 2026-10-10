import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/providers/place_search_providers.dart';

const auckland = GeoPoint(-36.85, 174.76);

void main() {
  test(
    'exact-query cache keeps city-first ranking after later prefix searches',
    () async {
      final city = {
        'id': 'city',
        'provider': 'osm',
        'name': 'Christchurch',
        'resultType': 'city',
        'isPoi': false,
        'latitude': -43.53,
        'longitude': 172.64,
      };
      final shop = {
        'id': 'shop',
        'provider': 'osm',
        'name': 'Christchurch Shop',
        'isPoi': true,
        'latitude': -36.85,
        'longitude': 174.76,
      };
      final provider = WorkerSearchProvider(
        mapCompatible: true,
        client: MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.url.queryParameters['q'] == 'christchurch'
                  ? [city, shop]
                  : [shop],
            ),
            200,
          ),
        ),
      );
      addTearDown(provider.dispose);
      await provider.search(
        'christchurch',
        proximity: auckland,
        language: 'en',
      );
      await provider.search('christ', proximity: auckland, language: 'en');
      expect(
        provider
            .cachedSuggestions(
              'christchurch',
              proximity: auckland,
              language: 'en',
            )
            .first
            .name,
        'Christchurch',
      );
    },
  );

  test('direct open-data fallback distinguishes Christ Church from Christchurch city', () async {
    final requests = <Uri>[];
    final provider = IndependentSearchProvider(
      requestSpacing: Duration.zero,
      client: MockClient((request) async {
        requests.add(request.url);
        final local = request.url.queryParameters.containsKey('bbox');
        return http.Response(
          jsonEncode({
            'features': [
              {
                'properties': {
                  'name': local ? 'Christ Church' : 'Christchurch',
                  'osm_type': 'N',
                  'osm_id': local ? 1 : 2,
                  'osm_key': local ? 'amenity' : 'place',
                  'osm_value': local ? 'place_of_worship' : 'city',
                  'country': 'New Zealand',
                },
                'geometry': {
                  'coordinates': local ? [174.76, -36.85] : [172.64, -43.53],
                },
              },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(provider.dispose);
    final results = await provider.search(
      'christchurch',
      proximity: auckland,
      language: 'en',
    );
    expect(results.first.name, 'Christchurch');
    expect(results.last.name, 'Christ Church');
    expect(requests, hasLength(2));
    expect(requests.last.queryParameters.containsKey('bbox'), false);
  });
}
