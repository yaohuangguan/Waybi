import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiwi_lens_mobile/domain/map_provider.dart';
import 'package:kiwi_lens_mobile/domain/route_option.dart';
import 'package:kiwi_lens_mobile/providers/mapbox_routing_provider.dart';
import 'package:kiwi_lens_mobile/providers/place_search_providers.dart';
import 'package:kiwi_lens_mobile/data/explore_repository.dart';

void main() {
  test(
    'Mapbox suggestions retrieve into a neutral POI with street address',
    () async {
      final paths = <String>[];
      final provider = MapboxSearchProvider(
        'test-token',
        client: MockClient((request) async {
          paths.add(request.url.path);
          expect(request.url.queryParameters['access_token'], 'test-token');
          if (request.url.path.endsWith('/suggest')) {
            expect(request.url.queryParameters['country'], 'NZ');
            expect(request.url.queryParameters['language'], 'zh');
            return http.Response(
              jsonEncode({
                'suggestions': [
                  {
                    'mapbox_id': 'place-1',
                    'name': 'Cordis Auckland',
                    'full_address':
                        'Cordis Auckland, 83 Symonds Street, Grafton, Auckland',
                    'feature_type': 'poi',
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'features': [
                {
                  'geometry': {
                    'coordinates': [174.764, -36.856],
                  },
                  'properties': {
                    'name': 'Cordis Auckland',
                    'full_address':
                        'Cordis Auckland, 83 Symonds Street, Grafton, Auckland',
                    'feature_type': 'poi',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final suggestions = await provider.search(
        'Cordis',
        proximity: const GeoPoint(-36.85, 174.76),
        language: 'zh',
      );
      expect(
        suggestions.single.secondaryAddress,
        '83 Symonds Street, Grafton, Auckland',
      );
      final place = await provider.resolve(
        suggestions.single.reference!,
        language: 'zh',
      );
      expect(place.location, const GeoPoint(-36.856, 174.764));
      expect(place.reference!.provider, 'mapbox');
      expect(place.address, '83 Symonds Street, Grafton, Auckland');
      expect(paths, [
        '/search/searchbox/v1/suggest',
        '/search/searchbox/v1/retrieve/place-1',
      ]);
      provider.dispose();
    },
  );

  test('Mapbox routes normalize geometry and maneuver coordinates', () async {
    final provider = MapboxRoutingProvider(
      'test-token',
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'routes': [
              {
                'duration': 720,
                'distance': 4800,
                'geometry': {
                  'coordinates': [
                    [174.76, -36.85],
                    [174.78, -36.86],
                  ],
                },
                'legs': [
                  {
                    'steps': [
                      {
                        'distance': 500,
                        'maneuver': {
                          'instruction': 'Turn right',
                          'location': [174.77, -36.855],
                        },
                      },
                    ],
                  },
                ],
              },
            ],
          }),
          200,
        ),
      ),
    );

    final plan = await provider.route(
      origin: const GeoPoint(-36.85, 174.76),
      destination: const GeoPoint(-36.86, 174.78),
      language: 'en',
    );
    final drive = plan.forMode(KiwiTravelMode.drive).single;
    expect(plan.provider, 'mapbox');
    expect(plan.trafficAvailable, isFalse);
    expect(drive.points.last, const GeoPoint(-36.86, 174.78));
    expect(drive.steps.single.location, const GeoPoint(-36.855, 174.77));
    provider.dispose();
  });
  test(
    'rerouting requests only the active mode and keeps waypoint order',
    () async {
      final requests = <Uri>[];
      final provider = MapboxRoutingProvider(
        'test-token',
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({
              'code': 'Ok',
              'routes': [
                {
                  'distance': 1000,
                  'duration': 80,
                  'geometry': {
                    'coordinates': [
                      [174.76, -36.85],
                      [174.78, -36.86],
                    ],
                  },
                  'legs': [
                    {
                      'steps': [
                        {
                          'distance': 1000,
                          'duration': 80,
                          'name': 'Queen Street',
                          'maneuver': {
                            'type': 'turn',
                            'modifier': 'right',
                            'instruction': 'Turn right',
                            'location': [174.76, -36.85],
                          },
                          'intersections': [
                            {
                              'lanes': [
                                {
                                  'indications': ['straight'],
                                  'valid': false,
                                },
                                {
                                  'indications': ['right'],
                                  'valid': true,
                                },
                              ],
                            },
                          ],
                        },
                      ],
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );
      final route = await provider.reroute(
        origin: const GeoPoint(-36.85, 174.76),
        destination: const GeoPoint(-36.86, 174.78),
        mode: KiwiTravelMode.drive,
        stops: const [GeoPoint(-36.855, 174.77)],
        language: 'zh',
      );
      expect(requests.length, 1);
      expect(
        requests.single.path,
        contains('/driving/174.76,-36.85;174.77,-36.855;174.78,-36.86'),
      );
      expect(requests.single.queryParameters['alternatives'], 'false');
      expect(requests.single.queryParameters['language'], 'zh');
      expect(route.waypoints.length, 3);
      expect(route.steps.single.durationSeconds, 80);
      expect(route.steps.single.maneuverModifier, 'right');
      expect(route.steps.single.roadName, 'Queen Street');
      expect(route.steps.single.lanes.last.recommended, isTrue);
      provider.dispose();
    },
  );
  test('optional transport failure does not hide the driving route', () async {
    final provider = MapboxRoutingProvider(
      'test-token',
      client: MockClient((request) async {
        if (!request.url.path.contains('/driving/')) {
          throw StateError('optional network error');
        }
        return http.Response(
          jsonEncode({
            'routes': [
              {
                'distance': 1000,
                'duration': 80,
                'geometry': {
                  'coordinates': [
                    [174.76, -36.85],
                    [174.78, -36.86],
                  ],
                },
              },
            ],
          }),
          200,
        );
      }),
    );
    final plan = await provider.route(
      origin: const GeoPoint(-36.85, 174.76),
      destination: const GeoPoint(-36.86, 174.78),
      language: 'en',
    );
    expect(plan.options.single.mode, KiwiTravelMode.drive);
    provider.dispose();
  });
  test(
    'Mapbox search declares independent source and rejects mislabeled content',
    () async {
      final provider = WorkerSearchProvider(
        mapCompatible: true,
        client: MockClient((request) async {
          expect(request.url.queryParameters['provider'], 'geoapify');
          return http.Response(
            jsonEncode([
              {
                'id': 'g',
                'provider': 'google',
                'name': 'Google place',
                'latitude': -36.85,
                'longitude': 174.76,
              },
              {
                'id': 'a',
                'provider': 'geoapify',
                'name': 'Cafe',
                'latitude': -36.85,
                'longitude': 174.76,
              },
            ]),
            200,
          );
        }),
      );
      final results = await provider.search('Cafe', language: 'zh');
      expect(results.single.name, 'Cafe');
      expect(results.single.reference?.provider, 'geoapify');
      provider.dispose();
    },
  );
  test(
    'Mapbox Explore excludes Google content from an outdated backend',
    () async {
      final repository = ExploreRepository(
        client: MockClient((request) async {
          expect(request.url.queryParameters['provider'], 'geoapify');
          return http.Response(
            jsonEncode([
              {
                'placeId': 'g',
                'provider': 'google',
                'name': 'Google place',
                'latitude': -36.85,
                'longitude': 174.76,
              },
              {
                'placeId': 'a',
                'provider': 'geoapify',
                'name': 'Cafe',
                'latitude': -36.85,
                'longitude': 174.76,
              },
            ]),
            200,
          );
        }),
      );
      final results = await repository.fetch(
        latitude: -36.85,
        longitude: 174.76,
        category: 'coffee',
        language: 'en',
        mapCompatible: true,
      );
      expect(results.single.name, 'Cafe');
      repository.dispose();
    },
  );
}
