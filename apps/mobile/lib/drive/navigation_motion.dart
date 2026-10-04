import 'dart:math' as math;

import '../domain/geo_math.dart';
import 'navigation_location_filter.dart';

class NavigationMotion {
  const NavigationMotion(this.speedMetresPerSecond, this.heading);
  final double speedMetresPerSecond;
  final double? heading;
}

/// Course/speed fallback for OS fixes without usable motion metadata.
/// Requires consecutive, directionally consistent real observations, not a
/// camera animation or elapsed time along an assumed route.
class NavigationMotionEstimator {
  NavigationLocationFix? _previous;
  DateTime? _latestAt, _estimatedAt;
  NavigationMotion? _estimated;
  double? _candidateHeading;
  int _consistent = 0;

  void reset() {
    _previous = null;
    _latestAt = null;
    _estimatedAt = null;
    _estimated = null;
    _candidateHeading = null;
    _consistent = 0;
  }

  NavigationMotion update(NavigationLocationFix fix, {double? heading}) {
    final reported = fix.speedMetresPerSecond;
    if (!fix.point.isValid ||
        !fix.accuracyMeters.isFinite ||
        fix.accuracyMeters <= 0 ||
        fix.accuracyMeters > 35) {
      reset();
      return const NavigationMotion(0, null);
    }
    final previous = _previous;
    if (_latestAt != null && !fix.timestamp.isAfter(_latestAt!)) {
      return NavigationMotion(
        reported.isFinite && reported > 0 ? reported : 0,
        null,
      );
    }
    _latestAt = fix.timestamp;
    if (reported.isFinite && reported >= .8 && reported <= 70) {
      _previous = fix;
      _estimated = null;
      _estimatedAt = null;
      _consistent = 0;
      _candidateHeading = null;
      return NavigationMotion(
        reported,
        heading != null && heading.isFinite && heading >= 0
            ? heading % 360
            : null,
      );
    }
    if (previous == null) {
      _previous = fix;
      return const NavigationMotion(0, null);
    }
    final dt =
        fix.timestamp.difference(previous.timestamp).inMilliseconds / 1000;
    final distance = distanceMeters(
      previous.point.latitude,
      previous.point.longitude,
      fix.point.latitude,
      fix.point.longitude,
    );
    final minimumTravel = math.max(
      8.0,
      math.max(previous.accuracyMeters, fix.accuracyMeters) * 1.2,
    );
    if (dt > 5 || fix.accuracyMeters > 25 || (dt >= .2 && distance / dt > 70)) {
      _previous = fix;
      _estimated = null;
      _estimatedAt = null;
      _consistent = 0;
      _candidateHeading = null;
      return const NavigationMotion(0, null);
    }
    // Accumulate displacement instead of requiring eight metres per callback.
    // Core Location may emit several times per second, even at city speeds.
    if (dt < .2 || distance < minimumTravel) {
      return _estimated != null &&
              fix.timestamp.difference(_estimatedAt!) <=
                  const Duration(seconds: 2)
          ? _estimated!
          : const NavigationMotion(0, null);
    }
    _previous = fix;
    final course = bearingDegrees(
      previous.point.latitude,
      previous.point.longitude,
      fix.point.latitude,
      fix.point.longitude,
    );
    _consistent =
        _candidateHeading != null &&
            angleDifference(course, _candidateHeading!) <= 60
        ? _consistent + 1
        : 1;
    _candidateHeading = course;
    _estimated = _consistent >= 2
        ? NavigationMotion(distance / dt, course)
        : null;
    _estimatedAt = _estimated == null ? null : fix.timestamp;
    return _estimated ?? const NavigationMotion(0, null);
  }
}
