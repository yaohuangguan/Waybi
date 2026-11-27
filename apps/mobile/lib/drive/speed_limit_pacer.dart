import 'dart:math' as math;

import '../domain/geo_math.dart';
import '../domain/map_provider.dart';

/// When to look up the posted speed limit, and when a shown limit is stale.
///
/// Each lookup costs the Worker an ArcGIS query, so requests are spaced by
/// distance scaled to speed (about one every 20 s at any cruising speed,
/// rather than every 75 m — every 2.7 s at 100 km/h) and never sent while
/// parked. A stalled request cannot freeze the limit, and a server
/// `Retry-After` is honoured.
class SpeedLimitPacer {
  static const minimumInterval = Duration(seconds: 5);
  static const idleInterval = Duration(seconds: 30);
  static const lookupHorizon = Duration(seconds: 20);
  static const stuckRequest = Duration(seconds: 10);
  static const staleAge = Duration(minutes: 3);
  static const staleDistanceMeters = 1500.0;

  DateTime? _lookupAt, _pendingSince, _retryAfter, _successAt;
  GeoPoint? _lookupPoint, _successPoint;

  /// Distance to travel between lookups at [speedKph].
  static double distanceFor(double speedKph) =>
      math.max(150, math.max(0, speedKph) / 3.6 * lookupHorizon.inSeconds);

  bool shouldLookUp(DateTime now, GeoPoint at, double speedKph) {
    final pending = _pendingSince;
    if (pending != null && now.difference(pending) < stuckRequest) {
      return false;
    }
    if (_retryAfter != null && now.isBefore(_retryAfter!)) return false;
    final last = _lookupAt, point = _lookupPoint;
    if (last == null || point == null) return true;
    final elapsed = now.difference(last);
    if (elapsed < minimumInterval) return false;
    final moved = _distance(point, at);
    return moved >= distanceFor(speedKph) ||
        (elapsed >= idleInterval && moved >= 30);
  }

  void started(DateTime now, GeoPoint at) {
    _pendingSince = now;
    _lookupAt = now;
    _lookupPoint = at;
  }

  /// Records the end of a lookup. A rate limit delays the next one.
  void finished(DateTime now, {bool success = false, Duration? retryAfter}) {
    _pendingSince = null;
    if (retryAfter != null) _retryAfter = now.add(retryAfter);
    if (success) {
      _successAt = now;
      _successPoint = _lookupPoint;
    }
  }

  /// A result is applied only while the car is still near where it asked.
  static bool stillApplies(GeoPoint requested, GeoPoint latest, double kph) =>
      _distance(requested, latest) <= math.max(100, math.max(0, kph) / 3.6 * 8);

  /// The shown limit belongs to a road the car has probably left.
  bool isStale(DateTime now, GeoPoint at) {
    final when = _successAt, where = _successPoint;
    if (when == null || where == null) return false;
    final moved = _distance(where, at);
    return moved > staleDistanceMeters ||
        (now.difference(when) > staleAge && moved > 200);
  }

  void reset() {
    _lookupAt = null;
    _pendingSince = null;
    _successAt = null;
    _lookupPoint = null;
    _successPoint = null;
    // A server rate limit outlives one trip.
  }

  static double _distance(GeoPoint a, GeoPoint b) =>
      distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude);
}
