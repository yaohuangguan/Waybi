import 'dart:math' as math;

import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import '../domain/route_geometry.dart';
import 'route_camera_matcher.dart';

/// Tracks the local route corridor so a crossing or GPS jitter cannot jump
/// straight to a later occurrence of the same road.
class RouteProgressTracker {
  RouteProgressTracker(this.points) : geometry = RouteGeometry.of(points);
  final List<GeoPoint> points;

  /// Shared cumulative distances; other route consumers reuse the same array.
  final RouteGeometry geometry;
  double get totalMeters => geometry.totalMeters;
  RouteProjection? _previous;
  GeoPoint? _lastPoint;
  DateTime? _lastTime, _firstAttemptAt;

  /// The last committed (on-route) progress, if any.
  RouteProjection? get committed => _previous;

  static double geometryLength(List<GeoPoint> points) =>
      RouteGeometry.of(points).totalMeters;

  RouteProjection? update(
    GeoPoint point, {
    required DateTime time,
    double accuracyMeters = 10,
    double speedKph = 0,
    double? headingDegrees,
  }) {
    if (!point.isValid ||
        !accuracyMeters.isFinite ||
        accuracyMeters <= 0 ||
        accuracyMeters > 35 ||
        (_lastTime != null && !time.isAfter(_lastTime!))) {
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
    } else {
      // A new route starts where the car is. Without history, a full-route
      // search could snap 5–10 m of noise onto the return leg of an
      // out-and-back (skipping the U-turn), and progress never moves back.
      // Widen the window only as fast as the car could have travelled.
      _firstAttemptAt ??= time;
      final elapsed = math.max(
        0,
        time.difference(_firstAttemptAt!).inMilliseconds / 1000,
      );
      maxAlong =
          150 + accuracyMeters * 2 + elapsed * math.max(3, speedKph / 3.6);
    }
    final projected = geometry.project(
      point,
      minAlongMeters: minAlong,
      maxAlongMeters: maxAlong,
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
