import 'camera_matcher.dart';

enum CameraAlertPhase { idle, approaching, passed }

class CameraAlertState {
  const CameraAlertState(
    this.phase, {
    this.cameraId,
    this.distanceMeters,
    this.passKey,
  });
  const CameraAlertState.idle()
    : phase = CameraAlertPhase.idle,
      cameraId = null,
      distanceMeters = null,
      passKey = null;

  final CameraAlertPhase phase;
  final String? cameraId;
  final double? distanceMeters;

  /// Set for a later pass of the same camera on one route.
  final String? passKey;

  /// The pass being tracked (see [CameraMatch.alertKey]).
  String? get alertKey => passKey ?? cameraId;
}

/// Tracks one camera pass at a time and suppresses repeated alerts after
/// passage for [cooldown]. A route passing the same camera twice tracks each
/// pass separately ([CameraMatch.alertKey]).
class CameraAlertLifecycle {
  CameraAlertLifecycle({
    this.passDistanceMeters = 120,
    this.passedDisplay = const Duration(seconds: 8),
    this.cooldown = const Duration(minutes: 5),
  });

  final double passDistanceMeters;
  final Duration passedDisplay;
  final Duration cooldown;
  final Map<String, DateTime> _completedAt = {};
  String? _trackingKey, _trackingCamera;
  double? _lastDistance;
  DateTime? _passedAt;
  String? _passedKey, _passedCamera;

  CameraAlertState update(CameraMatch? match, DateTime now) {
    _completedAt.removeWhere((_, at) => now.difference(at) >= cooldown);
    if (_trackingKey != null &&
        (match == null || match.alertKey != _trackingKey)) {
      if (_lastDistance != null && _lastDistance! <= passDistanceMeters) {
        _completedAt[_trackingKey!] = now;
        _passedKey = _trackingKey;
        _passedCamera = _trackingCamera;
        _passedAt = now;
      }
      _trackingKey = null;
      _trackingCamera = null;
      _lastDistance = null;
    }
    if (_passedAt != null && now.difference(_passedAt!) >= passedDisplay) {
      _passedAt = null;
      _passedKey = null;
      _passedCamera = null;
    }
    if (match != null && !_completedAt.containsKey(match.alertKey)) {
      _trackingKey = match.alertKey;
      _trackingCamera = match.camera.id;
      _lastDistance = match.distanceMeters;
      _passedAt = null;
      _passedKey = null;
      _passedCamera = null;
      return CameraAlertState(
        CameraAlertPhase.approaching,
        cameraId: match.camera.id,
        distanceMeters: match.distanceMeters,
        passKey: match.passKey,
      );
    }
    if (_passedKey != null) {
      return CameraAlertState(
        CameraAlertPhase.passed,
        cameraId: _passedCamera,
        passKey: _passedKey == _passedCamera ? null : _passedKey,
      );
    }
    return const CameraAlertState.idle();
  }

  void reset() {
    _trackingKey = null;
    _trackingCamera = null;
    _lastDistance = null;
    _passedAt = null;
    _passedKey = null;
    _passedCamera = null;
    _completedAt.clear();
  }
}

/// Which camera reminders have been spoken, by pass and distance threshold.
///
/// Entries expire after [lifetime] (the lifecycle cooldown) and are cleared
/// when their pass is completed, so passing the same camera again later is
/// announced again rather than only showing a silent card.
class SpokenCameraAlerts {
  SpokenCameraAlerts({this.lifetime = const Duration(minutes: 5)});
  final Duration lifetime;
  final Map<String, DateTime> _spoken = {};

  bool contains(String alertKey, int threshold) =>
      _spoken.containsKey('$alertKey:$threshold');

  /// The 300 m reminder also covers the 800 m one.
  void record(String alertKey, int threshold, DateTime at) {
    _spoken['$alertKey:$threshold'] = at;
    if (threshold == 300) _spoken['$alertKey:800'] = at;
  }

  void passed(String? alertKey) {
    if (alertKey == null) return;
    _spoken.removeWhere((key, _) => key.startsWith('$alertKey:'));
  }

  void expire(DateTime now) =>
      _spoken.removeWhere((_, at) => now.difference(at) >= lifetime);

  void clear() => _spoken.clear();
}
