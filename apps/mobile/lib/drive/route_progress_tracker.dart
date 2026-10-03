import 'dart:math' as math;

import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import 'route_camera_matcher.dart';

/// Tracks the local route corridor so a crossing or GPS jitter cannot jump
/// straight to a later occurrence of the same road.
class RouteProgressTracker {
  RouteProgressTracker(this.points) : _cumulative = [0] {
    for (var i = 1; i < points.length; i++) {
      _cumulative.add(
        _cumulative.last +
            distanceMeters(
              points[i - 1].latitude,
              points[i - 1].longitude,
              points[i].latitude,
              points[i].longitude,
            ),
      );
    }
  }
  final List<GeoPoint> points;
  final List<double> _cumulative;
  double get totalMeters => _cumulative.last;
  final RouteCameraMatcher _matcher = const RouteCameraMatcher();
  RouteProjection? _previous;
  GeoPoint? _lastPoint;
  DateTime? _lastTime;

  static double geometryLength(List<GeoPoint> points) {
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      length += distanceMeters(
        points[i - 1].latitude,
        points[i - 1].longitude,
        points[i].latitude,
        points[i].longitude,
      );
    }
    return length;
  }

  RouteProjection? update(
    GeoPoint point, {
    required DateTime time,
    double accuracyMeters = 10,
    double speedKph = 0,
    double? headingDegrees,
  }) {
    if (!point.isValid || !accuracyMeters.isFinite || accuracyMeters > 65) {
      return null;
    }
    final previous = _previous;
    var maxAlong = double.infinity;
    var minAlong = 0.0;
    if (previous != null && _lastPoint != null && _lastTime != null) {
      final elapsed = time.difference(_lastTime!).inMilliseconds / 1000;
      final moved = distanceMeters(
        _lastPoint!.latitude,
        _lastPoint!.longitude,
        point.latitude,
        point.longitude,
      );
      minAlong = math.max(0, previous.alongMeters - 35);
      maxAlong =
          previous.alongMeters +
          math.max(
            80,
            moved * 2 +
                math.max(0, elapsed) * math.max(3, speedKph / 3.6) +
                accuracyMeters * 2,
          );
    }
    final projected = _matcher.project(
      point,
      points,
      minAlongMeters: minAlong,
      maxAlongMeters: maxAlong,
      cumulativeMeters: _cumulative,
      headingDegrees: speedKph >= 15 ? headingDegrees : null,
    );
    if (projected == null) return null;
    if (projected.offsetMeters > math.max(35, accuracyMeters * 1.5)) {
      return projected;
    }
    final progress = RouteProjection(
      alongMeters: math.max(previous?.alongMeters ?? 0, projected.alongMeters),
      offsetMeters: projected.offsetMeters,
      bearingDegrees: projected.bearingDegrees,
      point: projected.alongMeters < (previous?.alongMeters ?? 0)
          ? previous?.point
          : projected.point,
    );
    _previous = progress;
    _lastPoint = point;
    _lastTime = time;
    return progress;
  }
}
