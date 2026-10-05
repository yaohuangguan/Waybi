import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/domain/route_preference.dart';

RouteOption route(String id, {required int seconds, required int metres}) =>
    RouteOption(
      id: id,
      mode: WaybiTravelMode.drive,
      durationSeconds: seconds,
      distanceMeters: metres,
      points: const [GeoPoint(-36.85, 174.76), GeoPoint(-36.86, 174.77)],
      provider: 'independent',
      traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
      trafficIntervals: const [],
    );

void main() {
  test('route preferences prioritize ETA while preserving route badges', () {
    final routes = [
      route('fast', seconds: 600, metres: 10000),
      route('balanced', seconds: 640, metres: 9000),
      route('short', seconds: 700, metres: 8000),
    ];
    const summaries = {
      'fast': RoutePreferenceSummary(cameraCount: 2, congestionScore: 400),
      'balanced': RoutePreferenceSummary(cameraCount: 0, congestionScore: 0),
      'short': RoutePreferenceSummary(cameraCount: 1, congestionScore: 200),
    };

    final result = assessRoutePreferences(routes, summaries);

    expect(result['fast']!.fastest, isTrue);
    expect(result['short']!.shortest, isTrue);
    expect(result['balanced']!.leastTraffic, isTrue);
    expect(result['balanced']!.zeroCameras, isTrue);
    expect(result['fast']!.recommended, isTrue);
    expect(recommendedRoute(routes, summaries)?.id, 'fast');
  });

  test(
    'camera-free detour outside the ETA guardrail never becomes default',
    () {
      final routes = [
        route('fast', seconds: 600, metres: 10000),
        route('detour', seconds: 780, metres: 9300),
      ];
      const summaries = {
        'fast': RoutePreferenceSummary(cameraCount: 4, congestionScore: 80),
        'detour': RoutePreferenceSummary(cameraCount: 0, congestionScore: 0),
      };
      expect(recommendedRoute(routes, summaries)?.id, 'fast');
    },
  );
}
