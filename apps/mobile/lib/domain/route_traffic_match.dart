import 'geo_math.dart';
import 'map_provider.dart';
import 'traffic_flow.dart';
import '../drive/route_camera_matcher.dart';

({RouteProjection start, RouteProjection end})? _matchProjections(
  TrafficFlowSegment segment,
  MapRoutePath route, {
  double maxOffsetMeters = 90,
}) {
  if (!segment.hasRoadGeometry || route.points.length < 2) return null;
  const matcher = RouteCameraMatcher();
  final start = matcher.project(segment.start, route.points);
  final end = matcher.project(segment.end, route.points);
  if (start == null || end == null) return null;
  if (start.offsetMeters > maxOffsetMeters ||
      end.offsetMeters > maxOffsetMeters) {
    return null;
  }
  final flowBearing = bearingDegrees(
    segment.start.latitude,
    segment.start.longitude,
    segment.end.latitude,
    segment.end.longitude,
  );
  final routeBearing = start.bearingDegrees;
  if (angleDifference(flowBearing, routeBearing) > 75) return null;
  // A matching flow section should progress in the same route direction.
  if (end.alongMeters <= start.alongMeters + 5) return null;
  return (start: start, end: end);
}

bool trafficSegmentMatchesRoute(
  TrafficFlowSegment segment,
  MapRoutePath route, {
  double maxOffsetMeters = 90,
}) =>
    _matchProjections(segment, route, maxOffsetMeters: maxOffsetMeters) != null;

/// Returns the navigation route geometry covered by this official traffic
/// section. This deliberately colors the route itself rather than drawing the
/// traffic provider's nearby carriageway geometry as a second competing line.
List<GeoPoint> trafficGeometryOnRoute(
  TrafficFlowSegment segment,
  MapRoutePath route, {
  double maxOffsetMeters = 90,
}) {
  final match = _matchProjections(
    segment,
    route,
    maxOffsetMeters: maxOffsetMeters,
  );
  if (match == null || match.start.point == null || match.end.point == null) {
    return const [];
  }
  final points = <GeoPoint>[match.start.point!];
  var along = 0.0;
  for (var index = 0; index < route.points.length; index++) {
    if (index > 0) {
      final previous = route.points[index - 1];
      final current = route.points[index];
      along += distanceMeters(
        previous.latitude,
        previous.longitude,
        current.latitude,
        current.longitude,
      );
    }
    if (along > match.start.alongMeters + 1 &&
        along < match.end.alongMeters - 1) {
      points.add(route.points[index]);
    }
  }
  points.add(match.end.point!);
  return points.length >= 2 ? List.unmodifiable(points) : const [];
}

/// One official traffic section matched onto a route, by along-route metres.
class RouteTrafficSpan {
  const RouteTrafficSpan(this.segment, this.startMeters, this.endMeters);
  final TrafficFlowSegment segment;
  final double startMeters, endMeters;
}

/// Matches every traffic section to [route] once, skipping sections outside
/// the route's bounding box. Renderers then only clip the spans at the car
/// instead of re-projecting all traffic onto the whole route on each update.
List<RouteTrafficSpan> routeTrafficSpans(
  List<TrafficFlowSegment> segments,
  List<GeoPoint> route, {
  double maxOffsetMeters = 90,
}) {
  if (route.length < 2 || segments.isEmpty) return const [];
  var south = 90.0, north = -90.0, west = 180.0, east = -180.0;
  for (final p in route) {
    if (p.latitude < south) south = p.latitude;
    if (p.latitude > north) north = p.latitude;
    if (p.longitude < west) west = p.longitude;
    if (p.longitude > east) east = p.longitude;
  }
  const margin = .0015;
  bool inside(GeoPoint p) =>
      p.latitude >= south - margin &&
      p.latitude <= north + margin &&
      p.longitude >= west - margin * 1.3 &&
      p.longitude <= east + margin * 1.3;
  final path = MapRoutePath(id: 'route', points: route);
  final spans = <RouteTrafficSpan>[];
  for (final segment in segments) {
    if (!inside(segment.start) || !inside(segment.end)) continue;
    final match = _matchProjections(
      segment,
      path,
      maxOffsetMeters: maxOffsetMeters,
    );
    if (match == null) continue;
    spans.add(
      RouteTrafficSpan(segment, match.start.alongMeters, match.end.alongMeters),
    );
  }
  spans.sort((a, b) => a.startMeters.compareTo(b.startMeters));
  return List.unmodifiable(spans);
}
