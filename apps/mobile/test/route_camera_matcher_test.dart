import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/domain/safety_camera.dart';
import 'package:waybi_mobile/drive/route_camera_matcher.dart';

void main() {
  const matcher = RouteCameraMatcher();
  const route = RouteOption(
    id: 'northbound',
    mode: WaybiTravelMode.drive,
    durationSeconds: 200,
    distanceMeters: 1100,
    points: [GeoPoint(-36.85, 174.76), GeoPoint(-36.84, 174.76)],
    provider: 'test',
    traffic: TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
    trafficIntervals: [],
    steps: [
      RouteStepInfo(
        instruction: 'Continue on Queen Street',
        distanceMeters: 1100,
        location: GeoPoint(-36.849, 174.76),
      ),
    ],
  );
  const onRoute = SafetyCamera(
    id: 'on-route',
    name: 'Queen St camera',
    region: 'Auckland',
    suburb: 'City',
    location: 'Queen Street NB',
    type: 'Spot speed',
    latitude: -36.845,
    longitude: 174.7601,
  );
  const parallel = SafetyCamera(
    id: 'parallel',
    name: 'Parallel road camera',
    region: 'Auckland',
    suburb: 'City',
    location: 'Parallel Road',
    type: 'Spot speed',
    latitude: -36.845,
    longitude: 174.761,
  );
  const opposite = SafetyCamera(
    id: 'opposite',
    name: 'Opposite direction',
    region: 'Auckland',
    suburb: 'City',
    location: 'Queen Street SB',
    type: 'Spot speed',
    latitude: -36.846,
    longitude: 174.76,
  );

  test(
    'matches a route camera while excluding adjacent and opposite roads',
    () {
      final matches = matcher.match(route, [onRoute, parallel, opposite]);
      expect(matches.map((match) => match.camera.id), ['on-route']);
      expect(matches.single.highConfidence, isTrue);
    },
  );

  test('road confidence covers the full step, far from its maneuver', () {
    const roadside = SafetyCamera(
      id: 'roadside',
      name: 'Queen St camera',
      region: 'Auckland',
      suburb: 'City',
      location: 'Queen Street NB',
      type: 'Spot speed',
      latitude: -36.841,
      longitude: 174.76035,
    );
    final match = matcher.match(route, [roadside]).single;
    expect(match.offsetMeters, greaterThan(28));
    expect(match.highConfidence, isTrue);
  });

  test('upcoming is based on distance along the route, not raw radius', () {
    final matches = matcher.match(route, [onRoute]);
    expect(
      matcher
          .upcoming(const GeoPoint(-36.848, 174.76), route.points, matches)
          ?.camera
          .id,
      'on-route',
    );
    expect(
      matcher.upcoming(const GeoPoint(-36.843, 174.76), route.points, matches),
      isNull,
    );
  });

  test('an out-and-back route matches both passes of one camera', () {
    const loop = RouteOption(
      id: 'out-and-back',
      mode: WaybiTravelMode.drive,
      durationSeconds: 300,
      distanceMeters: 2224,
      points: [
        GeoPoint(-36.85, 174.76),
        GeoPoint(-36.84, 174.76),
        GeoPoint(-36.84, 174.76006),
        GeoPoint(-36.85, 174.76006),
      ],
      provider: 'test',
      traffic: TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
      trafficIntervals: [],
    );
    const camera = SafetyCamera(
      id: 'both-ways',
      name: 'Two-way camera',
      region: 'Auckland',
      suburb: 'City',
      location: 'Queen Street',
      type: 'Spot speed',
      latitude: -36.845,
      longitude: 174.76003,
    );
    const far = SafetyCamera(
      id: 'far',
      name: 'Elsewhere',
      region: 'Wellington',
      suburb: 'City',
      location: 'Lambton Quay',
      type: 'Spot speed',
      latitude: -41.28,
      longitude: 174.77,
    );
    final matches = matcher.match(loop, [camera, far]);
    expect(matches, hasLength(2));
    expect(matches.first.alongMeters, closeTo(556, 10));
    expect(matches.last.alongMeters, closeTo(1667, 10));
    expect(matches.map((m) => m.pass), [0, 1]);
    expect(matches.map((m) => m.alertKey), ['both-ways', 'both-ways#2']);
    expect(matches.first.withPass(0), same(matches.first));
  });
}
