import 'dart:math' as math;

import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import 'navigation_location_filter.dart';

/// Memory-only history for the current Just Drive session.
///
/// The trail is published as immutable chunks of up to [chunkPoints] points
/// plus one small live tail ([MapRoutePath.live]). A renderer re-sends the
/// frozen chunks only when one is added or dropped (every [chunkPoints]
/// points), never the whole trail on every GPS fix.
class DriveTrail {
  DriveTrail({this.maxPoints = 4000, this.chunkPoints = 200});
  final int maxPoints;
  final int chunkPoints;
  final List<MapRoutePath> _frozen = [];
  List<GeoPoint> _tail = [];
  int _frozenPoints = 0;
  int _nextChunk = 0;
  int _revision = 0;
  List<MapRoutePath>? _paths;
  NavigationLocationFix? _last;
  DateTime? _lastObservationAt;

  /// Increases whenever [paths] changes.
  int get revision => _revision;

  /// Stable between changes, so renderers can compare by identity.
  List<MapRoutePath> get paths => _paths ??= List.unmodifiable([
    ..._frozen,
    if (_tail.length > 1)
      MapRoutePath(
        id: 'drive-trail:live',
        points: List.unmodifiable(_tail),
        active: true,
        trail: true,
        live: true,
        revision: _revision,
      ),
  ]);

  void clear() {
    _frozen.clear();
    _tail = [];
    _frozenPoints = 0;
    _last = null;
    _lastObservationAt = null;
    _changed();
  }

  void _changed() {
    _revision++;
    _paths = null;
  }

  /// Freezes the tail as an immutable chunk; a continuing line starts its
  /// next chunk at the same point so the drawn trail has no gap.
  void _freeze({required bool continueLine}) {
    if (_tail.length > 1) {
      final id = _nextChunk++;
      _frozen.add(
        MapRoutePath(
          id: 'drive-trail:$id',
          points: List.unmodifiable(_tail),
          active: true,
          trail: true,
          revision: id,
        ),
      );
      _frozenPoints += _tail.length;
    }
    _tail = continueLine && _tail.isNotEmpty ? [_tail.last] : [];
  }

  void add(NavigationLocationFix fix) {
    if (!fix.point.isValid ||
        !fix.accuracyMeters.isFinite ||
        fix.accuracyMeters <= 0 ||
        fix.accuracyMeters > 35 ||
        !fix.speedMetresPerSecond.isFinite) {
      return;
    }
    final previous = _last;
    final lastObservation = _lastObservationAt;
    if (lastObservation != null && !fix.timestamp.isAfter(lastObservation)) {
      return;
    }
    _lastObservationAt = fix.timestamp;
    final elapsed = previous == null
        ? 0.0
        : fix.timestamp.difference(previous.timestamp).inMilliseconds / 1000;
    final moved = previous == null
        ? 0.0
        : distanceMeters(
            previous.point.latitude,
            previous.point.longitude,
            fix.point.latitude,
            fix.point.longitude,
          );
    final disconnected =
        previous == null ||
        (lastObservation != null &&
            fix.timestamp.difference(lastObservation) >
                const Duration(seconds: 15)) ||
        moved >
            math.max(
              60,
              math.max(
                        previous.speedMetresPerSecond,
                        fix.speedMetresPerSecond,
                      ) *
                      elapsed *
                      1.5 +
                  previous.accuracyMeters +
                  fix.accuracyMeters,
            );
    // Do not turn stationary GPS jitter into a scribble.
    if (!disconnected && moved < math.max(5, fix.accuracyMeters * .5)) return;
    if (disconnected) _freeze(continueLine: false);
    _tail.add(fix.point);
    _last = fix;
    if (_tail.length >= chunkPoints) _freeze(continueLine: true);
    while (_frozenPoints + _tail.length > maxPoints) {
      if (_frozen.isNotEmpty) {
        _frozenPoints -= _frozen.removeAt(0).points.length;
      } else {
        _tail.removeAt(0);
      }
    }
    _changed();
  }
}
