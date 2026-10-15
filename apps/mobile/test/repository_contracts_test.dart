import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/data/route_repository.dart';
import 'package:waybi_mobile/data/speed_limit_repository.dart';
import 'package:waybi_mobile/data/usage_telemetry_repository.dart';
import 'package:waybi_mobile/data/camera_repository.dart';
import 'package:waybi_mobile/data/nzta_road_event_provider.dart';
import 'package:waybi_mobile/domain/country_profile.dart';
import 'package:waybi_mobile/domain/route_option.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const from = LatLng(latitude: -36.8, longitude: 174.7);
  const to = LatLng(latitude: -36.9, longitude: 174.8);
  test(
    'route request preserves coordinate order, stops, mode and Unicode',
    () async {
      final repo = RouteRepository(
        client: MockClient((r) async {
          expect(r.url.queryParameters, {
            'from': '174.7,-36.8',
            'to': '174.8,-36.9',
            'stops': '174.7,-36.8',
            'mode': 'walk',
          });
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'provider': 'waybi',
                'stopsApplied': 1,
                'trafficAvailable': false,
                'options': [
                  {
                    'id': 'walk',
                    'mode': 'walk',
                    'description': '步行',
                    'coordinates': [
                      [174.7, -36.8],
                      [174.8, -36.9],
                    ],
                    'durationSeconds': 60,
                    'distanceMeters': 100,
                  },
                  {'id': 'bad', 'mode': 'drive', 'coordinates': []},
                ],
              }),
            ),
            200,
          );
        }),
      );
      final plan = await repo.fetch(
        origin: from,
        destination: to,
        stops: [from],
        mode: WaybiTravelMode.walk,
      );
      expect(plan.options, hasLength(1));
      expect(plan.options.first.description, '步行');
      expect(plan.options.first.points.first.longitude, 174.7);
      expect(plan.stopsApplied, 1);
      expect(plan.trafficAvailable, isFalse);
    },
  );
  test(
    'transit without road geometry is valid but empty driving results fail',
    () async {
      var mode = 'transit';
      final repo = RouteRepository(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'options': [
                {'id': 'route', 'mode': mode, 'coordinates': []},
              ],
            }),
            200,
          ),
        ),
      );
      expect(
        (await repo.fetch(origin: from, destination: to)).options.single.mode,
        WaybiTravelMode.transit,
      );
      mode = 'drive';
      await expectLater(
        repo.fetch(origin: from, destination: to),
        throwsStateError,
      );
    },
  );
  test('route HTTP and malformed-response failures are surfaced', () async {
    for (final response in [
      http.Response('{}', 503),
      http.Response('{broken', 200),
    ]) {
      final repo = RouteRepository(client: MockClient((_) async => response));
      await expectLater(
        repo.fetch(origin: from, destination: to),
        throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
      );
    }
  });
  test(
    'speed limit preserves unknown values and reports upstream errors',
    () async {
      var status = 200;
      var body = '{"speedLimitKph":49.7,"zoneName":"School"}';
      final repo = SpeedLimitRepository(
        client: MockClient((r) async {
          expect(r.url.queryParameters['at'], '174.7,-36.8');
          return http.Response(body, status);
        }),
      );
      final known = await repo.fetch(latitude: -36.8, longitude: 174.7);
      expect(known.speedLimitKph, 50);
      expect(known.zoneName, 'School');
      body = '{}';
      expect(
        (await repo.fetch(latitude: -36.8, longitude: 174.7)).speedLimitKph,
        isNull,
      );
      status = 503;
      await expectLater(
        repo.fetch(latitude: -36.8, longitude: 174.7),
        throwsStateError,
      );
    },
  );
  test(
    'usage is bounded and a telemetry failure never interrupts navigation',
    () async {
      final units = <int>[];
      final repo = UsageTelemetryRepository(
        client: MockClient((r) async {
          expect(r.url.path, '/api/telemetry/usage');
          expect(r.headers['x-waybi-client'], 'mobile');
          units.add((jsonDecode(r.body) as Map)['units'] as int);
          throw http.ClientException('offline');
        }),
      );
      await repo.record('route', units: 0);
      await repo.record('route', units: 99);
      expect(units, [1, 25]);
      repo.dispose();
    },
  );
  test(
    'NZTA camera events retain provenance and only infer explicit directions',
    () async {
      final repo = CameraRepository(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'syncStatus': 'live',
              'sourceUpdatedAt': '2026-10-01',
              'cameras': [
                for (final d in [
                  'northbound',
                  'EB',
                  'southbound',
                  'WB',
                  'unnamed',
                ])
                  {
                    'id': d,
                    'name': d,
                    'region': 'Auckland',
                    'suburb': 'CBD',
                    'location': 'SH1 $d',
                    'type': 'Fixed speed camera',
                    'latitude': -36.8,
                    'longitude': 174.7,
                  },
              ],
            }),
            200,
          ),
        ),
      );
      final provider = NztaRoadEventProvider(repo);
      expect(provider.supports(CountryProfiles.nz), isTrue);
      expect(provider.supports(CountryProfiles.au), isFalse);
      final events = await provider.load();
      expect(events.map((e) => e.headingDegrees), [0, 90, 180, 270, null]);
      expect(events.first.source.provider, 'NZTA safety cameras');
      expect(events.first.source.sourceId, 'northbound');
      expect(provider.lastSnapshot?.cameras, hasLength(5));
    },
  );
}
