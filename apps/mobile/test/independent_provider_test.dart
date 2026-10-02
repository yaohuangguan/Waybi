import 'dart:convert';

import 'package:kiwi_lens_mobile/data/explore_repository.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiwi_lens_mobile/domain/map_provider.dart';
import 'package:kiwi_lens_mobile/domain/route_option.dart';
import 'package:kiwi_lens_mobile/providers/independent_routing_provider.dart';
import 'package:kiwi_lens_mobile/providers/place_search_providers.dart';

void main() {
  test(
    'Independent routes normalize geometry and maneuver coordinates',
    () async {
      final provider = IndependentRoutingProvider(
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
      expect(plan.provider, 'independent');
      expect(plan.trafficAvailable, isFalse);
      expect(drive.points.last, const GeoPoint(-36.86, 174.78));
      expect(drive.steps.single.location, const GeoPoint(-36.855, 174.77));
      provider.dispose();
    },
  );
  test(
    'rerouting requests only the active mode and keeps waypoint order',
    () async {
      final requests = <Uri>[];
      final provider = IndependentRoutingProvider(
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
      expect(
        requests.single.queryParameters.containsKey('access_token'),
        isFalse,
      );
      expect(requests.single.path, startsWith('/routed-car/route/v1/'));
      expect(route.waypoints.length, 3);
      expect(route.steps.single.durationSeconds, 80);
      expect(route.steps.single.maneuverModifier, 'right');
      expect(route.steps.single.roadName, 'Queen Street');
      expect(route.steps.single.lanes.last.recommended, isTrue);
      provider.dispose();
    },
  );
  test(
    'Independent preview exposes drive, walk and bike route modes',
    () async {
      final paths = <String>[];
      final provider = IndependentRoutingProvider(
        client: MockClient((request) async {
          paths.add(request.url.path);
          return http.Response(
            jsonEncode({
              'code': 'Ok',
              'routes': [
                {
                  'distance': 1000,
                  'duration': 100,
                  'geometry': {
                    'coordinates': [
                      [174.76, -36.85],
                      [174.78, -36.86],
                    ],
                  },
                  'legs': const [],
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

      expect(plan.forMode(KiwiTravelMode.drive), isNotEmpty);
      expect(plan.forMode(KiwiTravelMode.walk), isNotEmpty);
      expect(plan.forMode(KiwiTravelMode.bicycle), isNotEmpty);
      expect(paths.any((path) => path.startsWith('/routed-car/')), isTrue);
      expect(paths.any((path) => path.startsWith('/routed-foot/')), isTrue);
      expect(paths.any((path) => path.startsWith('/routed-bike/')), isTrue);
      provider.dispose();
    },
  );

  test('optional transport failure does not hide the driving route', () async {
    final provider = IndependentRoutingProvider(
      client: MockClient((request) async {
        if (!request.url.path.startsWith('/routed-car/')) {
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
  test('Independent search declares independent source and rejects mislabeled content', () async {
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
  });
  test('Practice Explore uses keyless Photon without Google content or invented ratings', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'photon.komoot.io');
      expect(request.url.queryParameters['q'], 'cafe');
      expect(double.parse(request.url.queryParameters['lat']!), -36.85);
      expect(request.url.queryParameters.containsKey('key'), false);
      return http.Response(
        jsonEncode({
          'features': [
            {
              'properties': {
                'osm_id': 123,
                'osm_type': 'N',
                'name': 'Cafe',
                'osm_value': 'cafe',
              },
              'geometry': {
                'coordinates': [174.76, -36.85],
              },
            },
          ],
        }),
        200,
      );
    });
    final repository = ExploreRepository(client: client);
    final places = await repository.fetch(
      latitude: -36.85,
      longitude: 174.76,
      category: 'coffee',
      language: 'zh',
      mapCompatible: true,
    );
    expect(places.single.provider, 'osm');
    expect(places.single.rating, isNull);
    expect(places.single.openNow, isNull);
    expect(places.single.photoUrl, isNull);
    repository.dispose();
  });
}
