import 'dart:async';
import 'dart:convert';

import 'package:waybi_mobile/data/explore_repository.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/providers/independent_routing_provider.dart';
import 'package:waybi_mobile/providers/place_search_providers.dart';

void main() {
  test(
    'selected driving mode never waits for optional walking or cycling',
    () async {
      final paths = <String>[];
      final provider = IndependentRoutingProvider(
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (!request.url.path.startsWith('/routed-car/')) {
            return Completer<http.Response>().future;
          }
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
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(provider.dispose);
      final plan = await provider.route(
        origin: const GeoPoint(-36.85, 174.76),
        destination: const GeoPoint(-36.86, 174.78),
        language: 'en',
        mode: WaybiTravelMode.drive,
      );
      expect(plan.options.single.mode, WaybiTravelMode.drive);
      expect(paths, hasLength(1));
    },
  );

  test('urgent reroute starts while an older preview is still waiting on the network', () async {
    final previewResponse = Completer<http.Response>();
    final previewStarted = Completer<void>();
    final body = jsonEncode({
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
        },
      ],
    });
    final provider = IndependentRoutingProvider(
      client: MockClient((request) async {
        if (request.url.queryParameters['alternatives'] == '3') {
          previewStarted.complete();
          return previewResponse.future;
        }
        expect(request.url.queryParameters['bearings'], '45,90;');
        return http.Response(body, 200);
      }),
    );
    addTearDown(provider.dispose);
    final preview = provider.route(
      origin: const GeoPoint(-36.85, 174.76),
      destination: const GeoPoint(-36.86, 174.78),
      language: 'en',
      mode: WaybiTravelMode.drive,
    );
    await previewStarted.future;
    final updated = await provider
        .reroute(
          origin: const GeoPoint(-36.851, 174.761),
          destination: const GeoPoint(-36.86, 174.78),
          mode: WaybiTravelMode.drive,
          language: 'en',
          headingDegrees: 45,
        )
        .timeout(const Duration(seconds: 3));
    expect(updated.mode, WaybiTravelMode.drive);
    expect(previewResponse.isCompleted, isFalse);
    previewResponse.complete(http.Response(body, 200));
    await preview;
  });

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
      final drive = plan.forMode(WaybiTravelMode.drive).single;
      expect(plan.provider, 'independent');
      expect(plan.trafficAvailable, isFalse);
      expect(drive.points.last, const GeoPoint(-36.86, 174.78));
      expect(drive.steps.single.location, const GeoPoint(-36.855, 174.77));
      provider.dispose();
    },
  );
  test(
    'Independent driving preview keeps only OSRM-provided alternatives',
    () async {
      final requests = <Uri>[];
      final provider = IndependentRoutingProvider(
        client: MockClient((request) async {
          requests.add(request.url);
          final isCar = request.url.path.startsWith('/routed-car/');
          if (isCar) {
            expect(request.url.queryParameters['alternatives'], '3');
            return http.Response(
              jsonEncode({
                'code': 'Ok',
                'routes': [
                  {
                    'distance': 4800,
                    'duration': 420,
                    'geometry': {
                      'coordinates': [
                        [174.766, -36.844],
                        [174.778, -36.870],
                      ],
                    },
                    'legs': const [],
                  },
                  {
                    'distance': 3800,
                    'duration': 480,
                    'geometry': {
                      'coordinates': [
                        [174.766, -36.844],
                        [174.774, -36.857],
                        [174.778, -36.870],
                      ],
                    },
                    'legs': const [],
                  },
                  {
                    'distance': 11000,
                    'duration': 1200,
                    'geometry': {
                      'coordinates': [
                        [174.766, -36.844],
                        [174.700, -36.900],
                        [174.778, -36.870],
                      ],
                    },
                    'legs': const [],
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'code': 'Ok',
              'routes': [
                {
                  'distance': 3000,
                  'duration': 900,
                  'geometry': {
                    'coordinates': [
                      [174.766, -36.844],
                      [174.778, -36.870],
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
        origin: const GeoPoint(-36.844, 174.766),
        destination: const GeoPoint(-36.870, 174.778),
        language: 'en',
      );
      final routes = plan.forMode(WaybiTravelMode.drive).toList();

      expect(routes, hasLength(2));
      expect(routes.map((route) => route.id).toSet(), hasLength(2));
      expect(
        requests.where((uri) => uri.path.startsWith('/routed-car/')),
        hasLength(1),
      );
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
        mode: WaybiTravelMode.drive,
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

      expect(plan.forMode(WaybiTravelMode.drive), isNotEmpty);
      expect(plan.forMode(WaybiTravelMode.walk), isNotEmpty);
      expect(plan.forMode(WaybiTravelMode.bicycle), isNotEmpty);
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
    expect(plan.options.single.mode, WaybiTravelMode.drive);
    provider.dispose();
  });
  test('Independent search declares independent source and rejects mislabeled content', () async {
    final provider = WorkerSearchProvider(
      mapCompatible: true,
      client: MockClient((request) async {
        expect(request.url.queryParameters['provider'], 'independent');
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
            {
              'id': 'o',
              'provider': 'osm',
              'name': 'Open cafe',
              'latitude': -36.851,
              'longitude': 174.761,
            },
            {
              'id': 'r',
              'provider': 'regional:test-addresses',
              'name': '42 Example Street',
              'isPoi': false,
              'latitude': -36.852,
              'longitude': 174.762,
            },
          ]),
          200,
        );
      }),
    );
    final results = await provider.search('Cafe', language: 'zh');
    expect(results, hasLength(3));
    expect(results.map((result) => result.reference?.provider).toSet(), {
      'geoapify',
      'osm',
      'regional:test-addresses',
    });
    provider.dispose();
  });
  test(
    'Waybi Explore uses cached independent places without invented ratings',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/explore');
        expect(request.url.queryParameters['provider'], 'osm');
        expect(request.url.queryParameters['category'], 'coffee');
        expect(request.url.queryParameters.containsKey('key'), false);
        return http.Response(
          jsonEncode([
            {
              'placeId': 'osm:node:123',
              'provider': 'osm',
              'name': 'Cafe',
              'primaryType': 'coffee',
              'latitude': -36.85,
              'longitude': 174.76,
            },
          ]),
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
    },
  );

  test('Independent fast search never returns Google-only places', () async {
    final provider = IndependentSearchProvider(
      useWorkerSuggestions: true,
      requestSpacing: Duration.zero,
      client: MockClient((request) async {
        expect(request.url.path, '/api/suggest');
        expect(request.url.queryParameters['provider'], 'independent');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode([
              {
                'id': '42-verissimo',
                'provider': 'geoapify',
                'name': '42 Verissimo Drive',
                'address':
                    '42 Verissimo Drive, Māngere, Auckland 2022, New Zealand',
                'isPoi': false,
                'latitude': -36.984,
                'longitude': 174.79,
              },
              {
                'id': 'google-only',
                'provider': 'google',
                'name': 'Should never cross into Independent',
                'latitude': -36.985,
                'longitude': 174.791,
              },
            ]),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(provider.dispose);

    final results = await provider.search(
      '42 verissimo',
      proximity: const GeoPoint(-36.85, 174.76),
      language: 'en',
    );

    expect(results, hasLength(1));
    expect(results.single.name, '42 Verissimo Drive');
    expect(results.single.reference?.provider, 'geoapify');
    expect(
      const ProviderPolicy(MapProvider.independent)
          .canDisplay(results.single.reference),
      isTrue,
    );
  });

  test(
    'worker-only Waybi search falls back inside the Worker boundary',
    () async {
      final urls = <Uri>[];
      final provider = IndependentSearchProvider(
        useWorkerSuggestions: true,
        workerOnly: true,
        requestSpacing: Duration.zero,
        client: MockClient((request) async {
          urls.add(request.url);
          if (request.url.path == '/api/suggest') {
            expect(request.url.queryParameters['provider'], 'independent');
            return http.Response(
              jsonEncode({'error': 'Independent place search unavailable'}),
              502,
            );
          }
          expect(request.url.path, '/api/search');
          return http.Response(
            jsonEncode([
              {
                'id': 'osm-fallback',
                'provider': 'osm',
                'name': 'Quiet Road',
                'isPoi': false,
                'latitude': -36.85,
                'longitude': 174.76,
              },
            ]),
            200,
          );
        }),
      );
      addTearDown(provider.dispose);

      final results = await provider.search(
        'quiet road',
        proximity: const GeoPoint(-36.85, 174.76),
        language: 'en',
      );

      expect(results.single.name, 'Quiet Road');
      expect(urls.map((url) => url.path), ['/api/suggest', '/api/search']);
      expect(urls.every((url) => url.host == 'waybi.co'), isTrue);
    },
  );

  test('shipping Waybi routing proxies reroutes through Waybi only', () async {
    final urls = <Uri>[];
    final provider = IndependentRoutingProvider(
      useWaybiProxy: true,
      proxyBaseUrl: 'https://waybi.test',
      client: MockClient((request) async {
        urls.add(request.url);
        expect(request.url.path, '/api/route-options');
        expect(request.url.queryParameters['provider'], 'independent');
        expect(request.url.queryParameters['mode'], 'drive');
        return http.Response(
          jsonEncode({
            'provider': 'independent',
            'trafficAvailable': false,
            'stopsApplied': 0,
            'options': [
              {
                'id': 'drive-0',
                'mode': 'drive',
                'durationSeconds': 120,
                'distanceMeters': 1800,
                'coordinates': [
                  [174.76, -36.85],
                  [174.78, -36.86],
                ],
                'provider': 'independent',
                'traffic': {'normal': 0, 'slow': 0, 'trafficJam': 0},
                'trafficIntervals': const [],
                'steps': [
                  {
                    'distance': 1800,
                    'duration': 120,
                    'name': 'Waybi Road',
                    'maneuver': 'depart',
                    'modifier': '',
                    'instruction': 'Head south',
                    'location': [174.76, -36.85],
                  },
                ],
              },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(provider.dispose);

    final route = await provider.reroute(
      origin: const GeoPoint(-36.85, 174.76),
      destination: const GeoPoint(-36.86, 174.78),
      mode: WaybiTravelMode.drive,
      language: 'en',
      headingDegrees: 45,
    );

    expect(urls, hasLength(1));
    expect(urls.single.host, 'waybi.test');
    expect(urls.single.queryParameters['alternatives'], 'false');
    expect(urls.single.queryParameters['heading'], '45.0');
    expect(route.provider, 'independent');
    expect(route.waypoints, const [
      GeoPoint(-36.85, 174.76),
      GeoPoint(-36.86, 174.78),
    ]);
  });
}
