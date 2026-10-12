import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/domain/route_preference.dart';
import 'package:waybi_mobile/domain/routing_origin.dart';
import 'package:waybi_mobile/providers/independent_routing_provider.dart';

RouteOption candidate(
  String id,
  int seconds, {
  bool reversal = false,
  WaybiTravelMode mode = WaybiTravelMode.drive,
}) => RouteOption(
  id: id,
  mode: mode,
  durationSeconds: seconds,
  distanceMeters: 20000,
  points: const [GeoPoint(-36.99, 174.79), GeoPoint(-36.85, 174.76)],
  provider: 'independent',
  traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
  trafficIntervals: const [],
  steps: [
    if (reversal)
      const RouteStepInfo(
        instruction: '',
        distanceMeters: 500,
        location: GeoPoint(-36.99, 174.79),
        maneuverType: 'continue',
        maneuverModifier: 'uturn',
      ),
  ],
);

void main() {
  test('a comparable legal alternative beats a marginally faster U-turn', () {
    final routes = [
      candidate('reverse', 1400, reversal: true),
      candidate('direct', 1430),
    ];
    expect(recommendedRoute(routes, const {})?.id, 'direct');
    expect(assessRoutePreferences(routes, const {})['reverse']!.fastest, true);
  });
  test(
    'necessary reversals remain available and do not justify long detours',
    () {
      final only = candidate('only-legal', 1400, reversal: true);
      expect(recommendedRoute([only], const {})?.id, only.id);
      expect(
        recommendedRoute([only, candidate('long-detour', 1650)], const {})?.id,
        only.id,
      );
      expect(
        recommendedRoute([
          candidate('walk', 100, reversal: true, mode: WaybiTravelMode.walk),
          candidate('other-walk', 110, mode: WaybiTravelMode.walk),
        ], const {})?.id,
        'walk',
      );
    },
  );
  for (final entry in {
    'NZ': const GeoPoint(-36.9910531, 174.7907113),
    'AU': const GeoPoint(-33.9461, 151.1772),
  }.entries) {
    test(
      '${entry.key} preview and reroute choose from engine alternatives and preserve heading',
      () async {
        final requests = <Uri>[];
        final p = entry.value;
        final provider = IndependentRoutingProvider(
          client: MockClient((request) async {
            requests.add(request.url);
            return http.Response(
              jsonEncode({
                'code': 'Ok',
                'routes': [
                  for (final reverse in [true, false])
                    {
                      'distance': 20000,
                      'duration': reverse ? 1400 : 1430,
                      'geometry': {
                        'coordinates': [
                          [p.longitude, p.latitude],
                          [p.longitude + .1, p.latitude + .1],
                        ],
                      },
                      'legs': [
                        {
                          'steps': [
                            {
                              'distance': 100,
                              'maneuver': {
                                'type': 'depart',
                                'location': [p.longitude, p.latitude],
                              },
                            },
                            {
                              'distance': 19900,
                              'maneuver': {
                                'type': reverse ? 'continue' : 'turn',
                                'modifier': reverse ? 'uturn' : 'right',
                                'location': [p.longitude, p.latitude + .001],
                              },
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
        addTearDown(provider.dispose);
        final destination = GeoPoint(p.latitude + .1, p.longitude + .1);
        final plan = await provider.route(
          origin: p,
          destination: destination,
          language: 'en',
          mode: WaybiTravelMode.drive,
          headingDegrees: -45,
        );
        expect(plan.options.first.id, 'independent-drive-1');
        expect(plan.options, hasLength(2));
        final reroute = await provider.reroute(
          origin: GeoPoint(p.latitude + .001, p.longitude),
          destination: destination,
          language: 'en',
          mode: WaybiTravelMode.drive,
          headingDegrees: -45,
        );
        expect(reroute.id, 'independent-drive-1');
        expect(requests, hasLength(2));
        expect(
          requests.every((uri) => uri.queryParameters['bearings'] == '315,60;'),
          true,
        );
        expect(
          requests.every((uri) => uri.queryParameters['alternatives'] == '3'),
          true,
        );
      },
    );
  }
  test('origin direction requires a recent accurate moving fix, never compass or manual origin', () {
    final now = DateTime(2026, 10, 12, 10);
    double? course({
      double? heading = -45,
      double speed = 15,
      double accuracy = 8,
      int age = 0,
      bool manual = false,
    }) => routingOriginHeading(
      heading: heading,
      speedMetresPerSecond: speed,
      accuracyMeters: accuracy,
      timestamp: now.subtract(Duration(seconds: age)),
      now: now,
      manualOrigin: manual,
    );
    expect(course(), 315);
    expect(course(speed: 0), null);
    expect(course(accuracy: 60), null);
    expect(course(accuracy: double.nan), null);
    expect(course(heading: double.nan), null);
    expect(course(age: 20), null);
    expect(course(age: -20), null);
    expect(course(manual: true), null);
  });
}
