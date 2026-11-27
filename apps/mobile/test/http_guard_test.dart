import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/data/account_repository.dart';
import 'package:waybi_mobile/data/explore_repository.dart';
import 'package:waybi_mobile/data/http_guard.dart';
import 'package:waybi_mobile/data/parking_repository.dart';
import 'package:waybi_mobile/data/place_details_repository.dart';
import 'package:waybi_mobile/data/speed_limit_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';

const _cloudflare502 =
    '<!DOCTYPE html><html><head><title>502 Bad Gateway</title></head></html>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Retry-After', () {
    test('accepts delta seconds and IMF dates, rejects nonsense', () {
      expect(parseRetryAfter('30'), const Duration(seconds: 30));
      expect(parseRetryAfter(' 0 '), Duration.zero);
      expect(parseRetryAfter('-4'), isNull);
      expect(parseRetryAfter(null), isNull);
      expect(parseRetryAfter(''), isNull);
      expect(parseRetryAfter('soon'), isNull);
      expect(parseRetryAfter('Wed, 21 Foo 2026 07:28:00 GMT'), isNull);
      final now = DateTime.utc(2026, 10, 21, 7, 27, 30);
      expect(
        parseRetryAfter('Wed, 21 Oct 2026 07:28:00 GMT', now: now),
        const Duration(seconds: 30),
      );
      expect(
        parseRetryAfter('Wed, 21 Oct 2026 07:00:00 GMT', now: now),
        Duration.zero,
      );
    });

    test('429 and 503 with Retry-After become bounded rate limits', () {
      Never fail(http.Response response) {
        throwIfRateLimited(response);
        throw StateError('not limited');
      }

      expect(
        () => fail(http.Response('', 429, headers: {'retry-after': '12'})),
        throwsA(
          isA<RateLimitedException>()
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 12),
              )
              .having((e) => e.statusCode, 'status', 429),
        ),
      );
      expect(
        () => fail(http.Response('', 429)),
        throwsA(
          isA<RateLimitedException>().having(
            (e) => e.retryAfter,
            'fallback',
            const Duration(seconds: 60),
          ),
        ),
      );
      expect(
        () => fail(http.Response('', 503, headers: {'retry-after': '86400'})),
        throwsA(
          isA<RateLimitedException>()
              .having(
                (e) => e.retryAfter,
                'clamped',
                const Duration(minutes: 15),
              )
              .having((e) => e.toString(), 'text', contains('900s')),
        ),
      );
      // A plain 503 is an outage, not a rate limit.
      expect(() => fail(http.Response('', 503)), throwsStateError);
      expect(
        RateLimitedException(Duration.zero),
        isA<ApiException>(),
        reason: 'Existing StateError handlers keep working',
      );
    });
  });

  group('decodeJsonResponse', () {
    test('checks the status before decoding an HTML error page', () {
      expect(
        () => decodeJsonResponse(
          http.Response(_cloudflare502, 502),
          unavailable: 'Places unavailable',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Places unavailable')
              .having((e) => e.statusCode, 'status', 502)
              .having((e) => e.toString(), 'text', 'Places unavailable'),
        ),
      );
      expect(
        () => decodeJsonResponse(
          http.Response(_cloudflare502, 200),
          unavailable: 'Places unavailable',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => decodeJsonResponse(
          http.Response('{"error":"Place not found"}', 404),
          unavailable: 'Places unavailable',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Place not found',
          ),
        ),
      );
      expect(
        decodeJsonResponse(
          http.Response('{"ok":true}', 202),
          unavailable: 'x',
          accept: const {200, 202},
        ),
        {'ok': true},
      );
      expect(serverErrorMessage(http.Response('{"error":"  "}', 500)), isNull);
      expect(serverErrorMessage(http.Response('[1]', 500)), isNull);
    });
  });

  group('abortableGet', () {
    test('returns responses and forwards headers', () async {
      final client = MockClient((request) async {
        expect(request.headers['accept'], 'application/json');
        return http.Response('ok', 200);
      });
      final response = await abortableGet(
        client,
        Uri.parse('https://example.test/a'),
        headers: const {'accept': 'application/json'},
        timeout: const Duration(seconds: 1),
      );
      expect(response.body, 'ok');
    });

    test('times out a stalled request and aborts its trigger', () async {
      http.BaseRequest? sent;
      final client = MockClient.streaming((request, _) {
        sent = request;
        return Completer<http.StreamedResponse>().future;
      });
      await expectLater(
        abortableGet(
          client,
          Uri.parse('https://example.test/slow'),
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );
      final trigger = (sent! as http.Abortable).abortTrigger!;
      await expectLater(trigger, completes);
    });

    test(
      'a cancel signal abandons the request, a failing one does not',
      () async {
        final cancel = Completer<void>();
        final client = MockClient.streaming(
          (_, _) => Completer<http.StreamedResponse>().future,
        );
        final pending = abortableGet(
          client,
          Uri.parse('https://example.test/slow'),
          timeout: const Duration(seconds: 5),
          cancel: cancel.future,
        );
        cancel.complete();
        await expectLater(pending, throwsA(isA<RequestCancelledException>()));
        expect(
          const RequestCancelledException().toString(),
          'Request cancelled',
        );

        final failing = Completer<void>();
        final ok = abortableGet(
          MockClient((_) async => http.Response('fine', 200)),
          Uri.parse('https://example.test/fast'),
          timeout: const Duration(seconds: 1),
          cancel: failing.future,
        );
        failing.completeError(StateError('ignored'));
        expect((await ok).body, 'fine');
      },
    );

    test('propagates transport errors', () async {
      await expectLater(
        abortableGet(
          MockClient((_) async => throw http.ClientException('offline')),
          Uri.parse('https://example.test/'),
          timeout: const Duration(seconds: 1),
        ),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  group('repositories', () {
    test('speed limit lookups time out and surface 429 back-off', () async {
      final stalled = SpeedLimitRepository(
        client: MockClient.streaming(
          (_, _) => Completer<http.StreamedResponse>().future,
        ),
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        stalled.fetch(latitude: -36.8, longitude: 174.7),
        throwsA(isA<TimeoutException>()),
      );
      final limited = SpeedLimitRepository(
        client: MockClient(
          (_) async => http.Response('', 429, headers: {'retry-after': '45'}),
        ),
      );
      await expectLater(
        limited.fetch(latitude: -36.8, longitude: 174.7),
        throwsA(
          isA<RateLimitedException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(seconds: 45),
          ),
        ),
      );
      final list = SpeedLimitRepository(
        client: MockClient((_) async => http.Response('[]', 200)),
      );
      await expectLater(
        list.fetch(latitude: -36.8, longitude: 174.7),
        throwsA(isA<ApiException>()),
      );
    });

    test(
      'place details and explore turn HTML 502 pages into friendly errors',
      () async {
        final html = MockClient(
          (_) async => http.Response(_cloudflare502, 502),
        );
        final details = PlaceDetailsRepository(client: html);
        await expectLater(
          details.fetch('abc'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Place details unavailable',
            ),
          ),
        );
        await expectLater(
          details.fetchIndependent(
            const PlaceSummary(
              name: 'Cafe',
              location: GeoPoint(-36.85, 174.76),
            ),
          ),
          throwsA(isA<StateError>()),
        );
        final explore = ExploreRepository(client: html);
        await expectLater(
          explore.fetch(
            latitude: -36.85,
            longitude: 174.76,
            category: 'food',
            language: 'en',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Explore places are unavailable',
            ),
          ),
        );
        final wrongShape = MockClient((_) async => http.Response('[]', 200));
        await expectLater(
          PlaceDetailsRepository(client: wrongShape).fetch('abc'),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          PlaceDetailsRepository(client: wrongShape).fetchIndependent(
            const PlaceSummary(
              name: 'Cafe',
              location: GeoPoint(-36.85, 174.76),
            ),
          ),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          ExploreRepository(
            client: MockClient((_) async => http.Response('{}', 200)),
          ).fetch(
            latitude: -36.85,
            longitude: 174.76,
            category: 'food',
            language: 'en',
          ),
          throwsA(isA<ApiException>()),
        );
      },
    );

    test('AT car parks without descriptions never show "null"', () async {
      final repository = ParkingRepository(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'features': [
                {
                  'properties': {
                    'OBJECTID': 7,
                    'SHORTDESCRIPTION': null,
                    'LONGDESCRIPTION': 'null',
                    'STREETNUMBER': null,
                    'STREET': null,
                    'SUBURB': null,
                    'STATUS': 'Open',
                  },
                  'geometry': {
                    'coordinates': [174.7601, -36.8501],
                  },
                },
              ],
            }),
            200,
          ),
        ),
      );
      final places = await repository.nearby(
        destination: const GeoPoint(-36.85, 174.76),
        allowGoogleFallback: false,
      );
      expect(places.single.name, 'AT car park');
      expect(places.single.name, isNot(contains('null')));
    });

    test('an HTML account error page becomes a friendly message', () async {
      final account = AccountRepository(
        client: MockClient((_) async => http.Response(_cloudflare502, 502)),
      );
      await expectLater(
        account.authenticate('a@example.com', 'secret', register: false),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('temporarily unavailable'),
          ),
        ),
      );
    });
  });
}
