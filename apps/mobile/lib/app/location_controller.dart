import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/map_provider.dart';
import '../drive/device_heading.dart';
import '../drive/location_permission_gate.dart';
import '../drive/navigation_location_filter.dart';
import '../drive/navigation_motion.dart';
import '../drive/reliable_location_feed.dart';
import '../drive/route_origin_location.dart';

/// What the location banner's button does.
enum LocationNoticeAction { retry, appSettings, locationSettings }

/// Creates the browse-profile feed. Tests replace it.
typedef BrowseFeedFactory = ReliableLocationFeed Function(
  bool Function(Position) onPosition,
  void Function(Object?) onIssue,
);

/// The phone's position while browsing: permission, the browse GPS feed,
/// the compass, and filtering of indoor jumps.
///
/// Fixes reach the page twice: [locationListenable] (and the compass in
/// [deviceHeadingListenable]) for things that redraw, and [onFix] for
/// decisions (arrival, ETAs). While Drive or navigation runs, the page feeds
/// the drive engine's fixes through [handlePosition] instead of the browse
/// feed, which is stopped.
class LocationController {
  LocationController({
    required this._driveActive,
    required this._driveSpeedKph,
    required this._language,
    LocationPermissionGate? permission,
    BrowseFeedFactory? feedFactory,
    Stream<double> Function()? headings,
    Future<bool> Function()? appSettings,
    Future<bool> Function()? locationSettings,
    DateTime Function()? clock,
  }) : _permission = permission ?? LocationPermissionGate(),
       _feedFactory =
           feedFactory ??
           ((onPosition, onIssue) => ReliableLocationFeed.profile(
             LocationFeedProfile.browse,
             onPosition: onPosition,
             onIssue: onIssue,
           )),
       _headings = headings ?? (() => DeviceHeading.readings),
       _openAppSettings = appSettings ?? openAppSettings,
       _openLocationSettings =
           locationSettings ?? Geolocator.openLocationSettings,
       _clock = clock ?? DateTime.now;

  final bool Function() _driveActive;
  final double Function() _driveSpeedKph;
  final String Function() _language;
  final LocationPermissionGate _permission;
  final BrowseFeedFactory _feedFactory;
  final Stream<double> Function() _headings;
  final Future<bool> Function() _openAppSettings;
  final Future<bool> Function() _openLocationSettings;
  final DateTime Function() _clock;
  bool _disposed = false;

  String _text(String en, String zh) => _language() == 'zh' ? zh : en;

  ReliableLocationFeed? _feed;
  StreamSubscription<double>? _headingSubscription;
  final _filter = NavigationLocationFilter();
  final _motion = NavigationMotionEstimator();
  final _routeOrigin = RouteOriginLocation();

  final ValueNotifier<GeoPoint?> _location = ValueNotifier(null);
  final ValueNotifier<double?> _deviceHeading = ValueNotifier(null);

  /// The last reliable position: changes only when the filter accepts a fix.
  ValueListenable<GeoPoint?> get locationListenable => _location;
  GeoPoint? get location => _location.value;

  /// The compass, when the platform has one.
  ValueListenable<double?> get deviceHeadingListenable => _deviceHeading;
  double? get deviceHeading => _deviceHeading.value;

  /// Accuracy of the latest fix, accepted or not.
  double? accuracy;

  /// Course over ground while moving (≥ 0.8 m/s), otherwise null.
  double? travelHeading;

  /// The raw position of the last accepted fix.
  Position? lastReliablePosition;

  /// Where a route starts: a fresh precise fix may be used before the puck
  /// confirms it.
  GeoPoint? get routeOrigin => _routeOrigin.point;

  bool get running => _feed?.running == true;

  /// The current location problem, if any.
  String? issueMessage;
  LocationNoticeAction? issueAction;

  /// Every processed fix: [accepted] is null when the filter held the last
  /// reliable position (an indoor jump).
  void Function(NavigationLocationFix? accepted, Position raw)? onFix;

  /// The problem shown to the user changed (null: resolved).
  void Function(String? message)? onIssue;

  /// Whether transient GPS trouble must be reported even though a route
  /// origin is known (a route is waiting for location).
  bool Function() reportTransientIssues = () => false;

  /// Asks for (or checks) permission; reports why location is unavailable.
  Future<bool> ensurePermission({bool request = true}) async {
    try {
      final access = await _permission.ensure(requestPermission: request);
      if (access.isGranted || access.isLimited) return true;
      if (_disposed) return false;
      final settings = access.isPermanentlyDenied || access.isRestricted;
      reportIssue(
        settings
            ? _text(
                'Location is disabled for Waybi. Enable it in system settings.',
                'Waybi 的定位权限已关闭，请在系统设置中开启。',
              )
            : _text(
                'Allow location access to find your position and navigate.',
                '允许定位权限后，即可获取当前位置并开始导航。',
              ),
        settings
            ? LocationNoticeAction.appSettings
            : LocationNoticeAction.retry,
      );
    } catch (_) {
      if (!_disposed) {
        reportIssue(
          _text(
            'Location is temporarily unavailable. Try again.',
            '定位暂不可用，请重试。',
          ),
          LocationNoticeAction.retry,
        );
      }
    }
    return false;
  }

  void reportIssue(String message, LocationNoticeAction action) {
    if (_disposed) return;
    issueMessage = message;
    issueAction = action;
    onIssue?.call(message);
  }

  /// Starts the browse feed and compass unless Drive owns location.
  Future<void> start({bool requestPermission = false}) async {
    if (_driveActive() ||
        running ||
        !await ensurePermission(request: requestPermission)) {
      return;
    }
    if (_disposed || _driveActive() || running) return;
    _headingSubscription ??= _headings().listen(
      (heading) => _deviceHeading.value = heading,
      onError: (_) {
        /* iOS simulator and non-iOS use GPS course. */
      },
    );
    _feed = _feedFactory(handlePosition, _onFeedIssue)..start();
  }

  void _onFeedIssue(Object? error) {
    if (_disposed || _driveActive()) return;
    if (error == null) {
      final shown = issueMessage;
      issueMessage = null;
      issueAction = null;
      if (shown != null) onIssue?.call(null);
      return;
    }
    if (!reportTransientIssues() &&
        routeOrigin != null &&
        error is! PermissionDeniedException &&
        error is! LocationServiceDisabledException) {
      return;
    }
    final message = error is LocationServiceDisabledException
        ? _text(
            'Location services are off. Enable them in Settings.',
            '系统定位已关闭，请在系统设置中打开定位。',
          )
        : error is PermissionDeniedException
        ? _text(
            'Location access is disabled. Allow Waybi to use your location in Settings.',
            '定位权限已关闭，请在系统设置中允许 Waybi 使用定位。',
          )
        : _text(
            'Waiting for a reliable location. Retrying automatically…',
            '暂时未获取到可靠定位，正在自动重试…',
          );
    reportIssue(
      message,
      error is LocationServiceDisabledException
          ? LocationNoticeAction.locationSettings
          : error is PermissionDeniedException
          ? LocationNoticeAction.appSettings
          : LocationNoticeAction.retry,
    );
  }

  /// Filters one fix (from the browse feed, or the drive engine while it
  /// runs). Returns whether the feed may treat it as a fresh, usable fix.
  bool handlePosition(Position position) {
    if (_disposed) return false;
    accuracy = position.accuracy.isFinite ? position.accuracy : null;
    final point = GeoPoint(position.latitude, position.longitude);
    final motion = _motion.update(
      NavigationLocationFix(
        point: point,
        accuracyMeters: position.accuracy,
        speedMetresPerSecond: position.speed.isFinite && position.speed > 0
            ? position.speed
            : 0,
        timestamp: position.timestamp,
      ),
      heading: position.heading,
      headingAccuracy: position.headingAccuracy,
    );
    final speed = _driveActive()
        ? _driveSpeedKph() / 3.6
        : motion.speedMetresPerSecond;
    final fix = NavigationLocationFix(
      point: point,
      accuracyMeters: position.accuracy,
      speedMetresPerSecond: speed,
      timestamp: position.timestamp,
    );
    final accepted = _filter.accept(fix);
    _routeOrigin.update(fix, confirmed: accepted != null);
    // Keep the last reliable fix instead of letting a single indoor GPS
    // jump move route origins, arrival checks and the map by 50–100 m.
    if (accepted == null) {
      onFix?.call(null, position);
      return _filter.accepted?.timestamp == position.timestamp &&
          _clock().difference(position.timestamp) <=
              const Duration(seconds: 10);
    }
    lastReliablePosition = position;
    travelHeading = speed >= .8 && motion.heading != null
        ? motion.heading
        : null;
    _location.value = accepted.point;
    onFix?.call(accepted, position);
    return true;
  }

  /// Hands location to Drive: stops the browse feed and, on iOS, asks for
  /// temporary full accuracy.
  Future<void> pauseForDrive() async {
    final feed = _feed;
    _feed = null;
    await feed?.stop();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        if (await Geolocator.getLocationAccuracy() ==
            LocationAccuracyStatus.reduced) {
          await Geolocator.requestTemporaryFullAccuracy(
            purposeKey: 'WaybiNavigation',
          );
        }
      } catch (_) {
        /* Navigation can still wait for a usable GPS fix. */
      }
    }
  }

  /// The app went to the background: browsing needs no GPS there.
  Future<void> pauseInBackground() async => _feed?.pause();

  /// Back in the foreground: restart and ask for a fresh fix at once.
  Future<void> resume() async {
    _feed?.resume();
    await start();
    await _feed?.recover(force: true);
  }

  /// Starts (asking for permission) and requests a fresh fix now.
  Future<void> recover() async {
    await start(requestPermission: true);
    await _feed?.recover(force: true);
  }

  /// Runs the banner's action: opens settings, or retries location through
  /// [recoverDrive] while Drive owns GPS and [recoverBrowse] otherwise.
  Future<void> resolveIssue({
    required Future<void> Function() recoverDrive,
    required Future<void> Function() recoverBrowse,
  }) async {
    try {
      switch (issueAction) {
        case LocationNoticeAction.appSettings:
          await _openAppSettings();
        case LocationNoticeAction.locationSettings:
          await _openLocationSettings();
        case LocationNoticeAction.retry:
        case null:
          if (_driveActive()) {
            await recoverDrive();
          } else {
            await recoverBrowse();
          }
      }
    } catch (_) {
      reportIssue(
        _text(
          'Could not recover location. Check system location settings.',
          '暂时无法恢复定位，请检查系统定位设置。',
        ),
        LocationNoticeAction.appSettings,
      );
    }
  }

  void dispose() {
    _disposed = true;
    unawaited(_feed?.stop());
    _feed = null;
    unawaited(_headingSubscription?.cancel());
    _location.dispose();
    _deviceHeading.dispose();
  }
}
