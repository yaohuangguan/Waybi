import 'dart:async';

import '../domain/map_layer_settings.dart';
import '../domain/road_event.dart';
import '../drive/drive_engine.dart';
import '../services/notification_service.dart';
import 'home_sheets.dart' show roadEventLabel;

/// Shows one OS notification; true when the system displayed it.
typedef RoadAlertPresenter = Future<bool> Function({
  required String id,
  required String title,
  required String body,
});

/// Which drive-time notifications the person turned on.
typedef RoadAlertSettings = ({bool cameras, bool incidents, bool community});

/// OS notifications for cameras and road events ahead while driving (for
/// when Waybi is in the background). Each alert is shown once per trip; a
/// failed one is retried after 20 seconds, and [newTrip] forgets them all.
class RoadAlerts {
  RoadAlerts({
    required this._settings,
    required this._language,
    RoadAlertPresenter? present,
    Future<void> Function()? requestPermission,
    DateTime Function()? clock,
  }) : _present = present ?? WaybiNotificationService.instance.showRoadAlert,
       _requestPermission =
           requestPermission ??
           WaybiNotificationService.instance.requestPermission,
       _clock = clock ?? DateTime.now;

  final RoadAlertSettings Function() _settings;
  final String Function() _language;
  final RoadAlertPresenter _present;
  final Future<void> Function() _requestPermission;
  final DateTime Function() _clock;

  final Set<String> _shown = {};
  final Set<String> _pending = {};
  final Map<String, DateTime> _retryAfter = {};
  int _session = 0;

  String _text(String en, String zh) => _language() == 'zh' ? zh : en;

  /// Forgets every alert shown or pending in the last trip.
  void newTrip() {
    ++_session;
    _shown.clear();
    _pending.clear();
    _retryAfter.clear();
  }

  /// Asks for notification permission when any alert type is on.
  Future<void> prepare() async {
    final settings = _settings();
    if (!settings.cameras && !settings.incidents && !settings.community) {
      return;
    }
    try {
      await _requestPermission();
    } catch (_) {
      // OS notifications are optional; navigation and spoken guidance continue.
    }
  }

  /// Notifies the next camera within 800 m and enabled road events within
  /// 1.5 km of [drive].
  Future<void> check(DriveEngine drive) async {
    if (!drive.active) return;
    final settings = _settings();
    final language = _language();
    final camera = drive.upcomingCamera;
    final cameraDistance = drive.upcomingCameraDistanceMeters;
    if (settings.cameras &&
        camera != null &&
        cameraDistance != null &&
        cameraDistance > 0 &&
        cameraDistance <= 800) {
      final cameraType = CameraKindLabel.fromCamera(camera)
          .cameraLabel(language);
      await show(
        id: 'camera:${camera.id}',
        title: _text('$cameraType ahead', '前方$cameraType'),
        body: _text(
          '${cameraDistance.round()} m · ${camera.location}',
          '${cameraDistance.round()} 米 · ${camera.location}',
        ),
      );
    }

    for (final event in drive.upcomingRoadEvents) {
      final distance = event.distanceAlongRoute ?? event.distanceFromDriver;
      if (distance == null || distance > 1500) continue;
      final community = event.metadata['userReported'] == true;
      final importantOfficial =
          event.severity == RoadEventSeverity.warning ||
          event.severity == RoadEventSeverity.critical;
      final enabled = community
          ? settings.community
          : settings.incidents && importantOfficial;
      if (!enabled || event.type == RoadEventType.safetyCamera) continue;
      final reporter = event.metadata['reporterName']?.toString();
      await show(
        id: event.id,
        title: roadEventLabel(event.type, language),
        body: reporter == null
            ? _text('${distance.round()} m ahead', '前方 ${distance.round()} 米')
            : _text(
                '${distance.round()} m ahead · reported by $reporter',
                '前方 ${distance.round()} 米 · $reporter 报告',
              ),
      );
    }
  }

  /// Shows [id] unless it was shown this trip, is pending or is waiting
  /// to retry.
  Future<void> show({
    required String id,
    required String title,
    required String body,
  }) async {
    if (_shown.contains(id) ||
        _pending.contains(id) ||
        (_retryAfter[id]?.isAfter(_clock()) ?? false)) {
      return;
    }
    _pending.add(id);
    final session = _session;
    try {
      final shown = await _present(id: id, title: title, body: body);
      if (session != _session) return;
      if (shown) {
        _shown.add(id);
      } else {
        _retryAfter[id] = _clock().add(const Duration(seconds: 20));
      }
    } catch (_) {
      if (session == _session) {
        _retryAfter[id] = _clock().add(const Duration(seconds: 20));
      }
    } finally {
      if (session == _session) _pending.remove(id);
    }
  }
}
