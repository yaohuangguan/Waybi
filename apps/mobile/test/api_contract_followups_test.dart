import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/data/account_repository.dart';
import 'package:waybi_mobile/data/explore_repository.dart';
import 'package:waybi_mobile/data/http_guard.dart';
import 'package:waybi_mobile/data/nzta_traffic_road_event_provider.dart';
import 'package:waybi_mobile/data/parking_repository.dart';
import 'package:waybi_mobile/data/place_details_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/road_event.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/providers/independent_routing_provider.dart';
import 'package:waybi_mobile/providers/place_search_providers.dart';

const token =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

http.Response limited({String code = 'RATE_LIMITED', int status = 429}) =>
    http.Response(
      jsonEncode({
        'error': 'Too many requests',
        'code': code,
        'retryAfter': 60,
      }),
      status,
      headers: {'retry-after': '60'},
    );

Map<String, dynamic> profileJson({bool appleActive = false}) => {
  'user': {'id': 'u1', 'email': 'driver@example.test', 'providers': []},
  'subscription': {
    'plan': 'plus',
    'source': 'apple',
    'appleSubscriptionActive': appleActive,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('error codes and back-off', () {
    test('generic 5xx bodies keep their code and request id', () {
      final error = apiError(
        http.Response(
          jsonEncode({
            'error': 'Internal error',
            'code': 'INTERNAL_ERROR',
            'requestId': 'req-1',
          }),
          500,
        ),
        fallback: 'Unavailable',
      );
      expect(error.message, 'Internal error');
      expect(error.code, 'INTERNAL_ERROR');
      expect(error.requestId, 'req-1');
      expect(
        () => apiError(limited(), fallback: 'x'),
        throwsA(
          isA<RateLimitedException>()
              .having((e) => e.code, 'code', ApiErrorCode.rateLimited)
              .having((e) => e.message, 'message', 'Too many requests'),
        ),
      );
      expect(
        () => throwIfRateLimited(
          http.Response(
            '{"error":"busy","code":"SEARCH_BUSY"}',
            503,
            headers: {'retry-after': '2'},
          ),
        ),
        throwsA(
          isA<RateLimitedException>()
              .having((e) => e.code, 'code', ApiErrorCode.searchBusy)
              .having((e) => e.retryAfter, 'retry', const Duration(seconds: 2)),
        ),
      );
    });

    test('a gate fails fast until Retry-After has passed', () {
      var now = DateTime(2026);
      final gate = RateLimitGate(clock: () => now);
      gate.check();
      gate.observe(http.Response('{}', 200));
      expect(
        () => gate.observe(limited()),
        throwsA(isA<RateLimitedException>()),
      );
      expect(gate.remaining, const Duration(seconds: 60));
      now = now.add(const Duration(seconds: 59));
      expect(
        gate.check,
        throwsA(
          isA<RateLimitedException>()
              .having((e) => e.retryAfter, 'left', const Duration(seconds: 1))
              .having((e) => e.code, 'code', ApiErrorCode.rateLimited),
        ),
      );
      now = now.add(const Duration(seconds: 1));
      expect(gate.remaining, isNull);
      gate.check();
    });

    test('search stops at a 429 and does not hammer the fallback', () async {
      final paths = <String>[];
      final search = WorkerSearchProvider(
        client: MockClient((request) async {
          paths.add(request.url.path);
          return limited();
        }),
      );
      await expectLater(
        search.search('Queen Street', language: 'en'),
        throwsA(isA<RateLimitedException>()),
      );
      await expectLater(
        search.search('Queen St', language: 'en'),
        throwsA(isA<RateLimitedException>()),
      );
      expect(paths, ['/api/suggest'], reason: 'One request, then fail fast');
    });

    test('a busy /api/search queue backs off as well', () async {
      final paths = <String>[];
      final search = WorkerSearchProvider(
        client: MockClient((request) async {
          paths.add(request.url.path);
          return request.url.path == '/api/suggest'
              ? http.Response('{"error":"unavailable"}', 503)
              : limited(code: ApiErrorCode.searchBusy, status: 503);
        }),
      );
      await expectLater(
        search.search('Ponsonby', language: 'en'),
        throwsA(
          isA<RateLimitedException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.searchBusy,
          ),
        ),
      );
      expect(paths, ['/api/suggest', '/api/search']);
    });

    test(
      'independent search and reverse skip the Worker while limited',
      () async {
        var calls = 0;
        final search = IndependentSearchProvider(
          workerOnly: true,
          requestSpacing: Duration.zero,
          client: MockClient((request) async {
            calls++;
            return limited();
          }),
        );
        expect(
          await search.reverseNear(
            const GeoPoint(-36.85, 174.76),
            language: 'en',
          ),
          isNull,
        );
        expect(
          await search.reverseNear(
            const GeoPoint(-36.85, 174.76),
            language: 'en',
          ),
          isNull,
        );
        expect(calls, 1);
      },
    );

    test(
      'route previews, quick routes and reroutes share the routing back-off',
      () async {
        var calls = 0;
        final routes = IndependentRoutingProvider(
          useWaybiProxy: true,
          proxyBaseUrl: 'https://waybi.test',
          client: MockClient((_) async {
            calls++;
            return limited();
          }),
        );
        for (var i = 0; i < 3; i++) {
          await expectLater(
            routes.route(
              origin: const GeoPoint(-36.85, 174.76),
              destination: const GeoPoint(-36.86, 174.78),
              language: 'en',
              mode: WaybiTravelMode.drive,
            ),
            throwsA(isA<RateLimitedException>()),
          );
        }
        await expectLater(
          routes.reroute(
            origin: const GeoPoint(-36.85, 174.76),
            destination: const GeoPoint(-36.86, 174.78),
            mode: WaybiTravelMode.drive,
            language: 'en',
          ),
          throwsA(isA<RateLimitedException>()),
        );
        expect(calls, 1);
      },
    );
  });

  group('Google budget fallbacks', () {
    test('only Google-shaped or Google-tagged ids go to Google details', () {
      expect(isGooglePlaceId('ChIJN1t_tDeuEmsRUsoyG83frY4'), isTrue);
      expect(isGooglePlaceId('osm:node:123'), isFalse);
      expect(isGooglePlaceId('wikipedia:en:1'), isFalse);
      expect(isGooglePlaceId('51d5b1c3e5a1b8654059f5e2d3c4b5a6c0'), isFalse);
      expect(isGooglePlaceId('short'), isFalse);
      expect(isGooglePlaceId(''), isFalse);
      expect(isGooglePlaceId('test-parking', provider: 'google'), isTrue);
      expect(
        isGooglePlaceId('ChIJN1t_tDeuEmsRUsoyG83frY4', provider: 'osm'),
        isFalse,
      );
      const google = ExplorePlace(
        placeId: 'ChIJN1t_tDeuEmsRUsoyG83frY4',
        name: 'Cafe',
        address: '',
        primaryType: 'cafe',
        rating: null,
        userRatingCount: null,
        priceLevel: null,
        openNow: null,
        latitude: -36.85,
        longitude: 174.76,
        photoName: 'places/ChIJN1t/photos/abc',
        photoAttribution: '',
      );
      expect(google.isGoogle, isTrue);
      expect(google.photoUrl, contains('/api/place-photo'));
      const osm = ExplorePlace(
        placeId: 'osm:node:1',
        name: 'Park',
        address: '',
        primaryType: 'park',
        rating: null,
        userRatingCount: null,
        priceLevel: null,
        openNow: null,
        latitude: -36.85,
        longitude: 174.76,
        photoName: 'File:Park.jpg',
        photoAttribution: '',
        provider: 'osm',
      );
      expect(osm.isGoogle, isFalse);
      expect(osm.photoUrl, isNull);
      expect(
        const PlacePhoto(
          name: 'places/a/photos/b',
          attribution: '',
        ).viaGoogleProxy,
        isTrue,
      );
      expect(
        const PlacePhoto(
          name: '',
          attribution: '',
          directUrl: 'https://x',
        ).viaGoogleProxy,
        isFalse,
      );
    });

    test(
      'an exhausted Google budget falls back to independent details',
      () async {
        final paths = <String>[];
        final details = PlaceDetailsRepository(
          client: MockClient((request) async {
            paths.add(request.url.path);
            if (request.url.path == '/api/place-details') {
              return http.Response(
                jsonEncode({
                  'error': 'Daily limit reached',
                  'code': 'GOOGLE_BUDGET_EXHAUSTED',
                  'retryAfter': 3600,
                }),
                503,
                headers: {'retry-after': '3600'},
              );
            }
            expect(request.url.path, '/api/independent-place-details');
            return http.Response(
              jsonEncode({'placeId': 'osm', 'name': 'Sky Tower', 'photos': []}),
              200,
            );
          }),
        );
        const fallback = PlaceSummary(
          name: 'Sky Tower',
          location: GeoPoint(-36.8485, 174.7622),
        );
        final first = await details.fetch(
          'ChIJN1t_tDeuEmsRUsoyG83frY4',
          fallback: fallback,
        );
        expect(first.name, 'Sky Tower');
        final second = await details.fetch(
          'ChIJN1t_tDeuEmsRUsoyG83frY4',
          fallback: fallback,
        );
        expect(second.name, 'Sky Tower');
        expect(paths, [
          '/api/place-details',
          '/api/independent-place-details',
          '/api/independent-place-details',
        ]);
        await expectLater(
          details.fetch('ChIJN1t_tDeuEmsRUsoyG83frY4'),
          throwsA(
            isA<RateLimitedException>().having(
              (e) => e.code,
              'code',
              ApiErrorCode.googleBudgetExhausted,
            ),
          ),
        );
        final osm = await details.fetch('osm:node:1', fallback: fallback);
        expect(osm.name, 'Sky Tower');
        await expectLater(
          details.fetch('osm:node:1'),
          throwsA(isA<ApiException>()),
        );
      },
    );

    test(
      'OpenStreetMap car parks are not labelled or looked up as Google',
      () async {
        final parking = ParkingRepository(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/query')) {
              return http.Response('{"features":[]}', 200);
            }
            return http.Response(
              jsonEncode([
                {
                  'placeId': 'osm:way:42',
                  'provider': 'osm',
                  'name': 'Civic car park',
                  'address': 'Auckland',
                  'latitude': -36.8484,
                  'longitude': 174.7634,
                },
              ]),
              200,
            );
          }),
        );
        final places = await parking.nearby(
          destination: const GeoPoint(-36.8485, 174.7633),
          allowGoogleFallback: true,
        );
        expect(places.single.source, 'OpenStreetMap');
        expect(places.single.googlePlaceId, isNull);
        expect(places.single.toPlaceSummary().reference, isNull);
      },
    );
  });

  group('road events', () {
    final now = DateTime.now();
    Map<String, dynamic> closure(String id, Duration startsIn) => {
      'id': id,
      'type': 'roadClosure',
      'location': {'latitude': -36.85, 'longitude': 174.76},
      'source': {'provider': 'NZTA', 'country': 'NZ', 'sourceId': id},
      'validFrom': now.add(startsIn).toUtc().toIso8601String(),
      'validUntil': now
          .add(startsIn + const Duration(hours: 6))
          .toUtc()
          .toIso8601String(),
    };

    for (final shape in ['old', 'new']) {
      test('$shape response keeps closures starting within 12 h', () async {
        final provider = NztaTrafficRoadEventProvider(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'syncStatus': 'live',
                if (shape == 'new') 'scheduledWindowHours': 12,
                'events': [
                  closure('active', const Duration(hours: -1)),
                  closure('tonight', const Duration(minutes: 15)),
                  closure('tomorrow', const Duration(hours: 13)),
                ],
              }),
              200,
            ),
          ),
        );
        final events = await provider.load();
        expect(events.map((e) => e.id), ['active', 'tonight']);
        final tonight = events.last;
        expect(tonight.isCurrent(now), isFalse, reason: 'Not shown as active');
        expect(tonight.isUpcoming(now), isTrue);
        expect(events.first.isUpcoming(now), isFalse);
      });
    }

    test('a shorter server window is respected', () async {
      final provider = NztaTrafficRoadEventProvider(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'scheduledWindowHours': 1,
              'events': [closure('later', const Duration(hours: 3))],
            }),
            200,
          ),
        ),
      );
      expect(await provider.load(), isEmpty);
    });

    test('isCurrentOrUpcoming honours the window and expiry', () {
      final event = RoadEvent(
        id: 'e',
        type: RoadEventType.roadClosure,
        location: const GeoPoint(-36.85, 174.76),
        source: const RoadEventSource(
          provider: 'NZTA',
          country: 'NZ',
          sourceId: 'e',
        ),
        validFrom: now.add(const Duration(hours: 2)),
        validUntil: now.add(const Duration(hours: 4)),
      );
      expect(event.isCurrentOrUpcoming(now), isTrue);
      expect(
        event.isCurrentOrUpcoming(now, window: const Duration(hours: 1)),
        isFalse,
      );
      expect(
        event.isCurrentOrUpcoming(now.add(const Duration(hours: 5))),
        isFalse,
      );
    });
  });

  group('account', () {
    test(
      'profile and deletion report a renewing App Store subscription',
      () async {
        FlutterSecureStorage.setMockInitialValues({'waybi_session': token});
        var deleteResponse = http.Response(
          jsonEncode({
            'error': 'Your subscription could not be cancelled.',
            'code': 'SUBSCRIPTION_CANCEL_FAILED',
          }),
          503,
        );
        final account = AccountRepository(
          client: MockClient((request) async {
            if (request.url.path == '/api/auth/delete') return deleteResponse;
            if (request.url.path == '/api/auth/logout') {
              return http.Response('{}', 200);
            }
            if (request.url.path == '/api/route-watches') {
              return http.Response(
                jsonEncode({
                  'error': 'At most 8 route watches are supported',
                  'code': 'ROUTE_WATCH_LIMIT',
                }),
                409,
              );
            }
            return http.Response(
              jsonEncode(profileJson(appleActive: true)),
              200,
            );
          }),
        );
        addTearDown(account.dispose);
        await account.restore();
        expect(account.profile!.appleSubscriptionActive, isTrue);
        await expectLater(
          account.saveRouteWatch(
            label: 'home',
            originName: 'Work',
            originLatitude: -36.85,
            originLongitude: 174.76,
            destinationName: 'Home',
            latitude: -36.9,
            longitude: 174.8,
            routeProvider: 'independent',
            routePoints: const [],
            durationSeconds: 600,
            distanceMeters: 8000,
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.code, 'code', ApiErrorCode.routeWatchLimit)
                .having((e) => e.statusCode, 'status', 409),
          ),
        );
        await expectLater(
          account.deleteAccount(email: 'driver@example.test'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              ApiErrorCode.subscriptionCancelFailed,
            ),
          ),
        );
        expect(account.signedIn, isTrue);
        deleteResponse = http.Response(
          jsonEncode({
            'ok': true,
            'appleSubscriptionActive': true,
            'stripeSubscriptionsCancelled': 1,
          }),
          200,
        );
        final result = await account.deleteAccount(
          email: 'driver@example.test',
        );
        expect(result.appleSubscriptionActive, isTrue);
        expect(result.stripeSubscriptionsCancelled, 1);
        expect(account.signedIn, isFalse);
        expect(const AccountDeletionResult().appleSubscriptionActive, isFalse);
      },
    );
  });
}
