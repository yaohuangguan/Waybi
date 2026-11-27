import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_geometry.dart';
import 'package:waybi_mobile/domain/route_option.dart';

// Out 556 m north, U-turn, and back on the same road to a point 222 m north
// of the start. "Turn left" happens on the return leg at the same place the
// outward leg passed first.
const a = GeoPoint(-36.86, 174.76);
const c = GeoPoint(-36.858, 174.76);
const tip = GeoPoint(-36.855, 174.76);
const back = GeoPoint(-36.858, 174.76001);
const end = GeoPoint(-36.858, 174.759);

RouteOption outAndBack({
  bool along = false,
  List<GeoPoint> waypoints = const [],
  bool arrivals = true,
}) {
  final steps = <RouteStepInfo>[
    RouteStepInfo(
      instruction: 'Head north',
      distanceMeters: 556,
      location: a,
      alongRouteMeters: along ? 0 : null,
      maneuverType: 'depart',
    ),
    if (arrivals && waypoints.length > 2)
      RouteStepInfo(
        instruction: 'Arrive at stop',
        distanceMeters: 0,
        location: tip,
        alongRouteMeters: along ? 556 : null,
        maneuverType: 'arrive',
      ),
    RouteStepInfo(
      instruction: 'Make a U-turn',
      distanceMeters: 334,
      location: tip,
      alongRouteMeters: along ? 556 : null,
      maneuverType: 'continue',
      maneuverModifier: 'uturn',
    ),
    if (arrivals && waypoints.length > 2)
      RouteStepInfo(
        instruction: 'Arrive at second stop',
        distanceMeters: 0,
        location: back,
        alongRouteMeters: along ? 890 : null,
        maneuverType: 'arrive',
      ),
    RouteStepInfo(
      instruction: 'Turn left',
      distanceMeters: 89,
      location: back,
      alongRouteMeters: along ? 890 : null,
      maneuverType: 'turn',
      maneuverModifier: 'left',
    ),
    RouteStepInfo(
      instruction: 'Arrive',
      distanceMeters: 0,
      location: end,
      alongRouteMeters: along ? 979 : null,
      maneuverType: 'arrive',
    ),
  ];
  return RouteOption(
    id: 'out-and-back',
    mode: WaybiTravelMode.drive,
    durationSeconds: 120,
    distanceMeters: 979,
    points: const [a, c, tip, back, end],
    provider: 'independent',
    traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
    trafficIntervals: const [],
    steps: steps,
    waypoints: waypoints,
  );
}

void main() {
  test('geometry is measured once per points list and sliced exactly', () {
    final points = [a, c, tip];
    final geometry = RouteGeometry.of(points);
    expect(identical(RouteGeometry.of(points), geometry), isTrue);
    expect(geometry.totalMeters, closeTo(556, 2));
    expect(geometry.segmentAt(0), 0);
    expect(geometry.segmentAt(300), 1);
    expect(geometry.segmentAt(10000), 1);
    expect(geometry.pointAt(-5), a);
    expect(geometry.pointAt(1e6), tip);
    expect(geometry.pointAt(111).latitude, closeTo(-36.859, .00002));
    final slice = geometry.slice(100, 300);
    expect(slice.first.latitude, closeTo(-36.8591, .00002));
    expect(slice, contains(c));
    expect(slice.last.latitude, closeTo(-36.8573, .00003));
    expect(geometry.slice(300, 100), isEmpty);
    expect(RouteGeometry.of(const [a]).slice(0, 10), isEmpty);
    expect(RouteGeometry.of(const [a]).pointAt(5), a);
    expect(RouteGeometry.of(const [a]).segmentAt(5), 0);
    expect(
      () => RouteGeometry.of(const <GeoPoint>[]).pointAt(0),
      throwsStateError,
    );
    // A growable list extended after measurement is re-measured.
    points.add(end);
    expect(RouteGeometry.of(points).cumulative, hasLength(4));
    expect(geometry.project(tip)!.alongMeters, closeTo(556, 2));
  });

  test('step positions on a road used twice stay in route order', () {
    for (final along in [false, true]) {
      final positions = routeStepPositions(outAndBack(along: along));
      expect(positions, hasLength(4));
      expect(positions[1], closeTo(556, 15), reason: 'U-turn (along=$along)');
      expect(
        positions[2],
        closeTo(890, 20),
        reason: 'Left turn is on the return leg, not the outward pass',
      );
      for (var i = 1; i < positions.length; i++) {
        expect(positions[i], greaterThanOrEqualTo(positions[i - 1]));
      }
    }
  });

  test(
    'a step far from its geometry falls back to its cumulative distance',
    () {
      final route = RouteOption(
        id: 'odd',
        mode: WaybiTravelMode.drive,
        durationSeconds: 60,
        distanceMeters: 556,
        points: const [a, c, tip],
        provider: 'independent',
        traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
        trafficIntervals: const [],
        steps: const [
          RouteStepInfo(
            instruction: 'Depart',
            distanceMeters: 300,
            location: a,
          ),
          RouteStepInfo(
            instruction: 'Somewhere else',
            distanceMeters: 256,
            location: GeoPoint(-36.7, 174.9),
          ),
          RouteStepInfo(
            instruction: 'Beyond',
            distanceMeters: 0,
            location: tip,
            alongRouteMeters: 1e9,
          ),
        ],
      );
      final positions = routeStepPositions(route);
      expect(positions[1], closeTo(300, 5));
      expect(positions[2], closeTo(556, 2), reason: 'Clamped to the geometry');
    },
  );

  test('a stop passed earlier on the outward leg is visited on the return', () {
    // The stop at `back` lies next to where the outward leg already passed.
    const waypoints = [a, tip, back, end];
    for (final arrivals in [true, false]) {
      final route = outAndBack(waypoints: waypoints, arrivals: arrivals);
      final stops = routeStopPositions(route);
      expect(stops, hasLength(2));
      expect(stops[0], closeTo(556, 15), reason: 'arrivals=$arrivals');
      expect(stops[1], greaterThan(800), reason: 'arrivals=$arrivals');
    }
    expect(routeStopPositions(outAndBack()), isEmpty);
  });

  test('server routes carry cumulative step positions', () {
    final route = RouteOption.fromJson({
      'id': 'json',
      'mode': 'drive',
      'distanceMeters': 979,
      'coordinates': [
        for (final p in const [a, c, tip, back, end]) [p.longitude, p.latitude],
      ],
      'steps': [
        {
          'distance': 556.4,
          'maneuver': 'depart',
          'location': [174.76, -36.86],
        },
        {
          'distance': 333.6,
          'maneuver': 'continue',
          'modifier': 'uturn',
          'location': [174.76, -36.855],
        },
        {
          'distance': 89,
          'maneuver': 'turn',
          'location': [174.76001, -36.858],
          'along': 890,
        },
        {
          'distance': -3,
          'maneuver': 'arrive',
          'location': [174.759, -36.858],
        },
      ],
    });
    expect(route.steps.map((s) => s.alongRouteMeters), [0, 556.4, 890, 979]);
  });
}
