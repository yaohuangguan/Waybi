import '../domain/geo_math.dart';
import '../domain/map_provider.dart';

class JourneySummary {
  const JourneySummary({
    required this.destination,
    required this.startedAt,
    required this.finishedAt,
    required this.distanceMeters,
    required this.points,
    required this.cameraCount,
    required this.arrived,
  });
  final String destination;
  final DateTime startedAt, finishedAt;
  final double distanceMeters;
  final List<GeoPoint> points;
  final int cameraCount;
  final bool arrived;
  Duration get elapsed => finishedAt.difference(startedAt);
}

/// Arrival uses the requested destination and fresh raw GPS, never the
/// road-snapped endpoint or the SDK's more generous arrival radius.
class JourneyTracker {
  JourneyTracker({
    required this.target,
    required this.destination,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();
  final GeoPoint target;
  final String destination;
  final DateTime startedAt;
  final List<GeoPoint> _points = [];
  final Set<String> _cameras = {};
  double _distance = 0;
  DateTime? _lastFix, _withinRadiusAt;
  bool _finished = false;

  void cameraPassed(String? id) {
    if (id != null) _cameras.add(id);
  }

  bool update(
    GeoPoint point, {
    required double accuracyMeters,
    required DateTime time,
  }) {
    if (_finished ||
        !point.isValid ||
        time.isBefore(startedAt) ||
        !accuracyMeters.isFinite ||
        accuracyMeters < 0 ||
        accuracyMeters > 25 ||
        (_lastFix != null && !time.isAfter(_lastFix!))) {
      _withinRadiusAt = null;
      return false;
    }
    if (_points.isNotEmpty) {
      final last = _points.last;
      final moved = distanceMeters(
        last.latitude,
        last.longitude,
        point.latitude,
        point.longitude,
      );
      final seconds = time.difference(_lastFix!).inMilliseconds / 1000;
      if (moved > 2 && moved <= seconds * 60 + accuracyMeters) {
        _distance += moved;
      }
    }
    _lastFix = time;
    _points.add(point);
    final near =
        distanceMeters(
          point.latitude,
          point.longitude,
          target.latitude,
          target.longitude,
        ) <=
        10;
    if (!near) {
      _withinRadiusAt = null;
      return false;
    }
    _withinRadiusAt ??= time;
    return time.difference(_withinRadiusAt!).inMilliseconds >= 750;
  }

  JourneySummary finish({required bool arrived, DateTime? time}) {
    _finished = true;
    return JourneySummary(
      destination: destination,
      startedAt: startedAt,
      finishedAt: time ?? DateTime.now(),
      distanceMeters: _distance,
      points: List.unmodifiable(_points),
      cameraCount: _cameras.length,
      arrived: arrived,
    );
  }
}
