import 'dart:typed_data';

import '../drive/route_camera_matcher.dart';
import 'geo_math.dart';
import 'map_provider.dart';
import 'route_option.dart';

/// Cumulative distances for one route polyline, computed once and shared by
/// progress tracking, step positions, camera matching, closures and display.
///
/// Instances are cached per [points] list identity, so every consumer of the
/// same [RouteOption] reuses one array instead of re-measuring the route.
class RouteGeometry {
  RouteGeometry._(List<GeoPoint> source, this.cumulative)
    : points = List.unmodifiable(source),
      _last = source.isEmpty ? null : source.last;

  factory RouteGeometry.of(List<GeoPoint> points) {
    final cached = _cache[points];
    // A growable list may have been extended since it was measured.
    if (cached != null &&
        cached.cumulative.length == points.length &&
        (points.isEmpty || identical(cached._last, points.last))) {
      return cached;
    }
    return _cache[points] = RouteGeometry._(points, _measure(points));
  }

  static final Expando<RouteGeometry> _cache = Expando('RouteGeometry');
  static const _matcher = RouteCameraMatcher();

  final List<GeoPoint> points;
  final GeoPoint? _last;

  /// `cumulative[i]` is the distance from the first point to `points[i]`.
  final Float64List cumulative;

  double get totalMeters => cumulative.isEmpty ? 0 : cumulative.last;

  static Float64List _measure(List<GeoPoint> points) {
    final cumulative = Float64List(points.length);
    for (var i = 1; i < points.length; i++) {
      cumulative[i] =
          cumulative[i - 1] +
          distanceMeters(
            points[i - 1].latitude,
            points[i - 1].longitude,
            points[i].latitude,
            points[i].longitude,
          );
    }
    return cumulative;
  }

  /// Nearest point within the optional along-route window.
  RouteProjection? project(
    GeoPoint point, {
    double minAlongMeters = 0,
    double maxAlongMeters = double.infinity,
    double? headingDegrees,
  }) => _matcher.project(
    point,
    points,
    minAlongMeters: minAlongMeters,
    maxAlongMeters: maxAlongMeters,
    cumulativeMeters: cumulative,
    headingDegrees: headingDegrees,
  );

  /// Index `i` of the segment `points[i]..points[i + 1]` containing [along].
  int segmentAt(double along) {
    if (points.length < 2) return 0;
    var low = 0, high = points.length - 2;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (cumulative[middle] <= along) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  /// The interpolated position [along] metres from the start.
  GeoPoint pointAt(double along) {
    if (points.isEmpty) throw StateError('Empty route');
    if (points.length == 1 || along <= 0) return points.first;
    if (along >= totalMeters) return points.last;
    final index = segmentAt(along);
    final start = points[index], end = points[index + 1];
    final length = cumulative[index + 1] - cumulative[index];
    final fraction = length <= 0
        ? 0.0
        : ((along - cumulative[index]) / length).clamp(0.0, 1.0);
    final longitudeDelta = (end.longitude - start.longitude + 540) % 360 - 180;
    return GeoPoint(
      start.latitude + (end.latitude - start.latitude) * fraction,
      (start.longitude + longitudeDelta * fraction + 540) % 360 - 180,
    );
  }

  /// The sub-polyline between two along-route positions, with exact ends.
  List<GeoPoint> slice(double from, double to) {
    if (points.length < 2) return const [];
    final start = from.clamp(0.0, totalMeters),
        end = to.clamp(0.0, totalMeters);
    if (end <= start) return const [];
    final output = <GeoPoint>[pointAt(start)];
    for (var i = segmentAt(start) + 1; i < points.length; i++) {
      if (cumulative[i] >= end) break;
      if (cumulative[i] > start) output.add(points[i]);
    }
    output.add(pointAt(end));
    return output;
  }
}

/// Along-route geometry position of every step, in route order.
///
/// Provider step distances are scaled to the drawn geometry. Positions never
/// decrease, so a route that reuses a road (an out-and-back or a loop) cannot
/// place a later maneuver at the earlier pass of the same location.
List<double> routeStepPositions(RouteOption route, [RouteGeometry? geometry]) {
  final shape = geometry ?? RouteGeometry.of(route.points);
  final total = shape.totalMeters;
  final scale = route.distanceMeters > 0 ? total / route.distanceMeters : 1.0;
  final positions = <double>[];
  var previous = 0.0, expected = 0.0;
  for (final step in route.steps) {
    double position;
    if (step.alongRouteMeters != null) {
      position = step.alongRouteMeters! * scale;
    } else {
      // Search forward from the previous maneuver, near where the cumulative
      // step distances say this one should be.
      final estimate = expected * scale;
      final projection = shape.project(
        step.location,
        minAlongMeters: previous,
        maxAlongMeters: estimate + 250 + total * .05,
      );
      position = projection != null && projection.offsetMeters <= 60
          ? projection.alongMeters
          : estimate;
    }
    if (!position.isFinite || position < previous) position = previous;
    if (position > total) position = total;
    positions.add(position);
    previous = position;
    expected += step.distanceMeters;
  }
  return positions;
}

/// Along-route position of each intermediate waypoint, in visiting order.
///
/// Leg boundaries (`arrive` maneuvers) are authoritative. Otherwise each stop
/// is projected forward from the previous one, never onto an earlier pass.
List<double> routeStopPositions(
  RouteOption route, {
  RouteGeometry? geometry,
  List<double>? stepPositions,
}) {
  final stops = route.waypoints.length > 2
      ? route.waypoints.sublist(1, route.waypoints.length - 1)
      : const <GeoPoint>[];
  if (stops.isEmpty) return const [];
  final shape = geometry ?? RouteGeometry.of(route.points);
  final steps = stepPositions ?? routeStepPositions(route, shape);
  final arrivals = [
    for (var i = 0; i < route.steps.length && i < steps.length; i++)
      if (route.steps[i].maneuverType == 'arrive') steps[i],
  ];
  if (arrivals.length == stops.length + 1) {
    return arrivals.take(stops.length).toList(growable: false);
  }
  final positions = <double>[];
  var previous = 0.0;
  for (final stop in stops) {
    final projection = shape.project(stop, minAlongMeters: previous);
    final position = projection?.alongMeters ?? previous;
    positions.add(position);
    previous = position;
  }
  return positions;
}
