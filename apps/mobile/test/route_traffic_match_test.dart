import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_traffic_match.dart';
import 'package:waybi_mobile/domain/traffic_flow.dart';

TrafficFlowSegment traffic({
  required GeoPoint start,
  required GeoPoint end,
  required List<GeoPoint> geometry,
}) => TrafficFlowSegment(
  id: 'flow',
  motorway: 'SH20A',
  name: 'George Bolt Memorial Drive',
  direction: 'southbound',
  congestion: 'free',
  level: TrafficFlowLevel.free,
  start: start,
  end: end,
  geometry: geometry,
  geometryQuality: 'road-matched',
);

void main() {
  const route = MapRoutePath(
    id: 'airport',
    active: true,
    points: [
      GeoPoint(-36.98, 174.79),
      GeoPoint(-36.985, 174.79),
      GeoPoint(-36.99, 174.79),
      GeoPoint(-36.995, 174.79),
      GeoPoint(-37.00, 174.79),
    ],
  );

  test(
    'traffic colours exact active-route geometry, not a parallel ribbon',
    () {
      final segment = traffic(
        start: const GeoPoint(-36.984, 174.7901),
        end: const GeoPoint(-36.996, 174.7901),
        geometry: const [
          GeoPoint(-36.984, 174.7901),
          GeoPoint(-36.996, 174.7901),
        ],
      );
      expect(trafficSegmentMatchesRoute(segment, route), isTrue);
      final painted = trafficGeometryOnRoute(segment, route);
      expect(painted, isNotEmpty);
      expect(
        painted.any((point) => point == const GeoPoint(-36.99, 174.79)),
        isTrue,
      );
      expect(
        painted.every((point) => (point.longitude - 174.79).abs() < .00001),
        isTrue,
      );
    },
  );

  test(
    'parallel or reverse traffic is not painted over the navigation route',
    () {
      final parallel = traffic(
        start: const GeoPoint(-36.985, 174.7925),
        end: const GeoPoint(-36.995, 174.7925),
        geometry: const [
          GeoPoint(-36.985, 174.7925),
          GeoPoint(-36.995, 174.7925),
        ],
      );
      final reverse = traffic(
        start: const GeoPoint(-36.995, 174.7901),
        end: const GeoPoint(-36.985, 174.7901),
        geometry: const [
          GeoPoint(-36.995, 174.7901),
          GeoPoint(-36.985, 174.7901),
        ],
      );
      expect(trafficSegmentMatchesRoute(parallel, route), isFalse);
      expect(trafficGeometryOnRoute(parallel, route), isEmpty);
      expect(trafficSegmentMatchesRoute(reverse, route), isFalse);
      expect(trafficGeometryOnRoute(reverse, route), isEmpty);
    },
  );
}
