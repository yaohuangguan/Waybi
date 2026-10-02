import 'dart:math' as math;

import '../domain/geo_math.dart';
import '../domain/map_provider.dart';

class NavigationLocationFix {
  const NavigationLocationFix({
    required this.point,
    required this.accuracyMeters,
    required this.speedMetresPerSecond,
    required this.timestamp,
  });

  final GeoPoint point;
  final double accuracyMeters;
  final double speedMetresPerSecond;
  final DateTime timestamp;
}

/// Rejects low-confidence GPS jumps before they can move the navigation puck
/// or advance route progress. The filter is intentionally conservative while
/// stationary and relaxes naturally once the device reports real movement.
class NavigationLocationFilter {
  NavigationLocationFilter({GeoPoint? anchor}) : this._(anchor);

  NavigationLocationFilter._(this._anchor);

  GeoPoint? _anchor;
  NavigationLocationFix? _accepted;
  NavigationLocationFix? _candidate;

  NavigationLocationFix? get accepted => _accepted;

  void reset({GeoPoint? anchor}) {
    _anchor = anchor;
    _accepted = null;
    _candidate = null;
  }

  NavigationLocationFix? accept(NavigationLocationFix fix) {
    if (!fix.point.isValid ||
        !fix.accuracyMeters.isFinite ||
        fix.accuracyMeters <= 0 ||
        fix.accuracyMeters > 35 ||
        !fix.speedMetresPerSecond.isFinite) {
      return null;
    }

    final speed = math.max(0, fix.speedMetresPerSecond);
    final previous = _accepted;
    if (previous == null) {
      final anchor = _anchor;
      if (anchor != null) {
        final fromAnchor = distanceMeters(
          anchor.latitude,
          anchor.longitude,
          fix.point.latitude,
          fix.point.longitude,
        );
        final stationary = speed < 1.5;
        final anchorTolerance = math.max(28.0, fix.accuracyMeters * 1.35);
        if (stationary && fromAnchor > anchorTolerance) return null;
      } else if (fix.accuracyMeters > 25) {
        return null;
      }

      // A single indoor fix can look deceptively accurate. While stationary,
      // require a second consistent fix before releasing the puck. Navigation
      // with a real moving course is allowed to start immediately.
      if (speed < 1.5) {
        final candidate = _candidate;
        if (candidate == null) {
          _candidate = fix;
          return null;
        }
        final separation = distanceMeters(
          candidate.point.latitude,
          candidate.point.longitude,
          fix.point.latitude,
          fix.point.longitude,
        );
        final consistencyTolerance = math.max(
          12.0,
          math.max(candidate.accuracyMeters, fix.accuracyMeters) * 1.25,
        );
        final elapsed = fix.timestamp.difference(candidate.timestamp).abs();
        if (elapsed > const Duration(seconds: 10) ||
            separation > consistencyTolerance) {
          _candidate = fix;
          return null;
        }
      }

      _candidate = null;
      _accepted = fix;
      return fix;
    }

    final delta = distanceMeters(
      previous.point.latitude,
      previous.point.longitude,
      fix.point.latitude,
      fix.point.longitude,
    );
    final elapsed = math.max(
      .2,
      fix.timestamp.difference(previous.timestamp).inMilliseconds / 1000,
    );

    if (speed < 1.5) {
      final stationaryTolerance = math.max(
        14.0,
        math.max(previous.accuracyMeters, fix.accuracyMeters) * 1.35,
      );
      final muchBetterFix =
          fix.accuracyMeters + 8 < previous.accuracyMeters && delta <= 40;
      if (delta > stationaryTolerance && !muchBetterFix) return null;
    }

    final plausibleTravel =
        speed * elapsed * 2.75 +
        fix.accuracyMeters * 1.5 +
        previous.accuracyMeters;
    if (delta > math.max(55.0, plausibleTravel)) return null;

    _accepted = fix;
    return fix;
  }
}
