import 'dart:math' as math;

import '../domain/geo_math.dart';
import '../domain/map_provider.dart';

/// Paces automatic route recalculation so one stuck phone cannot exhaust the
/// shared routing budget, and a car parked beside the road does not reroute
/// every few seconds.
///
/// * One request at a time, including after the engine stopped waiting.
/// * Deviation reroutes back off 5 → 10 → 20 → 40 → 60 s (plus 0–20 %
///   jitter), timed from completion, until the car follows a route again.
/// * Between deviation reroutes the car must move [minimumMoveMeters] or be
///   faster than [movingSpeedKph].
/// * Closure reroutes retry 60 → 120 → 240 → 300 s, at most
///   [maxClosureAttempts] times for the same set of closures.
/// * A server `Retry-After` is always honoured.
class RerouteScheduler {
  RerouteScheduler({math.Random? random}) : _random = random ?? math.Random();

  static const deviationDelays = [5, 10, 20, 40, 60];
  static const closureDelays = [60, 120, 240, 300];
  static const maxClosureAttempts = 5;
  static const minimumMoveMeters = 40.0;
  static const movingSpeedKph = 10.0;

  /// A provider future that never settles must not block rerouting forever.
  static const maxInFlight = Duration(seconds: 60);

  /// Time on route after which the next deviation starts a fresh back-off.
  static const recovery = Duration(seconds: 30);

  final math.Random _random;
  Object? _inFlight;
  DateTime? _startedAt, _completedAt, _deviationNotBefore, _rateLimitedUntil;
  DateTime? _closureNotBefore;
  GeoPoint? _anchor;
  int _streak = 0;
  String? _closureFingerprint;
  int _closureAttempts = 0;

  bool inFlightAt(DateTime now) =>
      _inFlight != null &&
      (_startedAt == null || now.difference(_startedAt!) < maxInFlight);

  /// Consecutive deviation reroutes without the car settling on a route.
  int get streak => _streak;

  /// The earliest time any reroute may start (rate limit or back-off).
  DateTime? get deviationNotBefore =>
      _latest(_deviationNotBefore, _rateLimitedUntil);

  /// Where movement is measured from; set by the first usable fix on a route.
  void anchorIfUnset(GeoPoint point) => _anchor ??= point;

  bool canRerouteForDeviation(
    DateTime now, {
    required GeoPoint at,
    required double speedKph,
  }) {
    if (inFlightAt(now)) return false;
    final notBefore = deviationNotBefore;
    if (notBefore != null && now.isBefore(notBefore)) return false;
    final anchor = _anchor;
    if (anchor != null &&
        speedKph <= movingSpeedKph &&
        distanceMeters(
              anchor.latitude,
              anchor.longitude,
              at.latitude,
              at.longitude,
            ) <
            minimumMoveMeters) {
      return false;
    }
    return true;
  }

  bool canRerouteForClosure(DateTime now, String fingerprint) {
    if (inFlightAt(now)) return false;
    if (_rateLimitedUntil != null && now.isBefore(_rateLimitedUntil!)) {
      return false;
    }
    if (fingerprint != _closureFingerprint) return true;
    if (_closureAttempts >= maxClosureAttempts) return false;
    return _closureNotBefore == null || !now.isBefore(_closureNotBefore!);
  }

  /// Returns a token that [settled] must receive when the request's future
  /// completes, even after the caller stopped waiting for it.
  Object start(DateTime now, GeoPoint at, {String? closureFingerprint}) {
    final token = Object();
    _inFlight = token;
    _startedAt = now;
    _anchor = at;
    if (closureFingerprint != null) {
      if (closureFingerprint != _closureFingerprint) {
        _closureFingerprint = closureFingerprint;
        _closureAttempts = 0;
      }
      _closureAttempts++;
    } else {
      _streak++;
    }
    return token;
  }

  void settled(Object token) {
    if (identical(_inFlight, token)) _inFlight = null;
  }

  /// Records the end of an attempt (success, failure or engine timeout).
  void finish(DateTime now, {bool closure = false, Duration? retryAfter}) {
    _completedAt = now;
    if (retryAfter != null) {
      _rateLimitedUntil = _latest(_rateLimitedUntil, now.add(retryAfter));
    }
    if (closure) {
      final index = math.min(_closureAttempts, closureDelays.length) - 1;
      _closureNotBefore = now.add(_jittered(closureDelays[math.max(0, index)]));
    } else {
      final index = math.min(_streak, deviationDelays.length) - 1;
      _deviationNotBefore = now.add(
        _jittered(deviationDelays[math.max(0, index)]),
      );
    }
  }

  /// The car is following a route; after [recovery] the back-off resets.
  void confirmOnRoute(DateTime now) {
    final completed = _completedAt;
    if (_streak > 0 &&
        completed != null &&
        now.difference(completed) >= recovery) {
      _streak = 0;
    }
  }

  /// The closures ahead have cleared.
  void clearClosure() {
    _closureFingerprint = null;
    _closureAttempts = 0;
    _closureNotBefore = null;
  }

  /// A new trip. An earlier request still in flight keeps blocking a second
  /// overlapping request, and a server rate limit stays in force.
  void reset() {
    _completedAt = null;
    _deviationNotBefore = null;
    _anchor = null;
    _streak = 0;
    clearClosure();
  }

  Duration _jittered(int seconds) => Duration(
    milliseconds: (seconds * 1000 * (1 + .2 * _random.nextDouble())).round(),
  );

  static DateTime? _latest(DateTime? a, DateTime? b) =>
      a == null ? b : (b == null || a.isAfter(b) ? a : b);
}
