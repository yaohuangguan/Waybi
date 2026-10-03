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
  NavigationLocationFilter({GeoPoint? anchor, DateTime Function()? clock})
    : this._(anchor, clock ?? DateTime.now);

  NavigationLocationFilter._(this._anchor, this._clock);

  final DateTime Function() _clock;

  GeoPoint? _anchor;
  NavigationLocationFix? _accepted;
  NavigationLocationFix? _candidate;
  int _relocationFixes = 0;
  DateTime? _relocationSince;

  NavigationLocationFix? get accepted => _accepted;

  void reset({GeoPoint? anchor}) {
    _anchor = anchor;
    _accepted = null;
    _candidate = null;
    _relocationFixes = 0;
    _relocationSince = null;
  }

  NavigationLocationFix? accept(NavigationLocationFix fix) {
    final age = _clock().difference(fix.timestamp);
    if (!fix.point.isValid ||
        !fix.accuracyMeters.isFinite ||
        fix.accuracyMeters <= 0 ||
        fix.accuracyMeters > 35 ||
        !fix.speedMetresPerSecond.isFinite ||
        fix.speedMetresPerSecond > 70 ||
        age > const Duration(seconds: 10) ||
        age < const Duration(seconds: -5)) {
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
        if (stationary && fromAnchor > anchorTolerance) {
          if (fromAnchor > 250 || !_confirmedRelocation(fix)) return null;
          _anchor = fix.point;
          return _commit(fix);
        }
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
        if (!fix.timestamp.isAfter(candidate.timestamp)) return null;
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

      return _commit(fix);
    }

    if (!fix.timestamp.isAfter(previous.timestamp)) return null;
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
      if (delta > stationaryTolerance && !muchBetterFix) {
        // Reacquire after a real GPS outage instead of permanently pinning the
        // user to an old fix. Several precise, consistent fixes are required.
        if (elapsed < 10 ||
            (delta > 250 && elapsed < 60) ||
            !_confirmedRelocation(fix)) {
          return null;
        }
        return _commit(fix);
      }
    }

    final plausibleTravel =
        speed * elapsed * 2.75 +
        fix.accuracyMeters * 1.5 +
        previous.accuracyMeters;
    if (delta > math.max(55.0, plausibleTravel)) return null;

    return _commit(fix);
  }

  bool _confirmedRelocation(NavigationLocationFix fix) {
    if (fix.accuracyMeters > 12) {
      _candidate = null;
      _relocationFixes = 0;
      _relocationSince = null;
      return false;
    }
    final previous = _candidate;
    if (previous != null && !fix.timestamp.isAfter(previous.timestamp)) {
      return false;
    }
    final consistent =
        previous != null &&
        fix.timestamp.difference(previous.timestamp) <=
            const Duration(seconds: 5) &&
        distanceMeters(
              previous.point.latitude,
              previous.point.longitude,
              fix.point.latitude,
              fix.point.longitude,
            ) <=
            math.max(10, fix.accuracyMeters * 1.25);
    if (!consistent || _relocationSince == null) {
      _relocationFixes = 0;
      _relocationSince = fix.timestamp;
    }
    _candidate = fix;
    _relocationFixes++;
    return _relocationFixes >= 3 &&
        fix.timestamp.difference(_relocationSince!) >=
            const Duration(seconds: 2);
  }

  NavigationLocationFix _commit(NavigationLocationFix fix) {
    _candidate = null;
    _relocationFixes = 0;
    _relocationSince = null;
    _accepted = fix;
    return fix;
  }
}
