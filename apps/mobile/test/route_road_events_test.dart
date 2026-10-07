import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/domain/road_event.dart';
import 'package:waybi_mobile/domain/route_road_events.dart';

void main() {
  final now = DateTime.utc(2026, 10, 6, 8, 20);
  const route = RouteOption(
    id: 'south',
    mode: WaybiTravelMode.drive,
    durationSeconds: 600,
    distanceMeters: 5550,
    points: [GeoPoint(-36.85, 174.76), GeoPoint(-36.9, 174.76)],
    provider: 'independent',
    traffic: TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
    trafficIntervals: [],
  );
  RoadEvent closure({
    String id = 'closed',
    double lat = -36.88,
    double lon = 174.76,
    double? heading,
    DateTime? from,
    DateTime? until,
    RoadEventObservation observation = RoadEventObservation.official,
  }) => RoadEvent(
    id: id,
    type: RoadEventType.roadClosure,
    location: GeoPoint(lat, lon),
    headingDegrees: heading,
    validFrom: from,
    validUntil: until,
    observation: observation,
    source: const RoadEventSource(
      provider: 'NZTA Traffic and Travel',
      country: 'NZ',
      sourceId: '1',
    ),
  );
  test(
    'closure beyond the announcement window is shown during route preview',
    () {
      final result = routeClosures(route, [closure(), closure()], now: now);
      expect(result, hasLength(1));
      expect(result.single.distanceAlongRoute, greaterThan(3000));
    },
  );
  test('exclude parallel roads, opposite direction, past incidents and inferred closures', () {
    final result = routeClosures(route, [
      closure(lon: 174.762),
      closure(heading: 0),
      closure(until: now),
      closure(observation: RoadEventObservation.inferred),
    ], now: now);
    expect(result, isEmpty);
    expect(
      routeClosures(route, [closure(heading: 180)], now: now),
      hasLength(1),
    );
    expect(
      routeClosures(
        route,
        [closure(lat: -36.855)],
        progressMeters: 2000,
        now: now,
      ),
      isEmpty,
    );
  });
  test('closure starting before arrival matches, closure starting afterwards does not', () {
    expect(
      routeClosures(route, [
        closure(from: now.add(const Duration(minutes: 2))),
      ], now: now),
      hasLength(1),
    );
    expect(
      routeClosures(route, [
        closure(from: now.add(const Duration(hours: 1))),
      ], now: now),
      isEmpty,
    );
  });
}
