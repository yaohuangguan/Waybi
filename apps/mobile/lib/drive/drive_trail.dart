import 'dart:math' as math;

import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import 'navigation_location_filter.dart';

/// Memory-only history for the current Just Drive session.
class DriveTrail {
  DriveTrail({this.maxPoints = 4000});
  final int maxPoints;
  final List<List<GeoPoint>> _segments = [];
  NavigationLocationFix? _last;
  DateTime? _lastObservationAt;
  int _count = 0;

  List<MapRoutePath> get paths => [
    for (var i = 0; i < _segments.length; i++)
      if (_segments[i].length > 1)
        MapRoutePath(
          id: 'drive-trail:$i',
          points: List.unmodifiable(_segments[i]),
          active: true,
          trail: true,
        ),
  ];

  void clear() {
    _segments.clear();
    _last = null;
    _lastObservationAt = null;
    _count = 0;
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
    if (disconnected) _segments.add([]);
    _segments.last.add(fix.point);
    _last = fix;
    _count++;
    while (_count > maxPoints && _segments.isNotEmpty) {
      _segments.first.removeAt(0);
      _count--;
      if (_segments.first.isEmpty) _segments.removeAt(0);
    }
  }
}
