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
