import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

typedef PositionStreamFactory = Stream<Position> Function(LocationSettings);
typedef PositionRequest = Future<Position> Function(LocationSettings);

/// How much GPS a feed asks for.
enum LocationFeedProfile {
  /// Turn-by-turn and Just Drive: every fix, best accuracy.
  navigation,

  /// The map in the foreground: accurate, but only after real movement.
  browse,

  /// Background-friendly or battery saver: coarse and infrequent.
  lowPower,
}

/// One owner of the platform stream, with bounded recovery when it goes quiet.
/// Only real OS observations are delivered; timeouts never synthesize movement.
///
/// Recovery requests back off (6 s three times, then 12, 24, 48 and 60 s)
/// while no fix arrives, so a car park or tunnel does not keep the GPS radio
/// on a one-shot request every few seconds. [pause] releases the platform
/// stream (for example while the app is in the background) and [resume]
/// restores it.
class ReliableLocationFeed {
  ReliableLocationFeed({
    required this.settings,
    required this.onPosition,
    required this.onIssue,
    PositionStreamFactory? stream,
    PositionRequest? request,
    DateTime Function()? clock,
    this.staleAfter = const Duration(seconds: 10),
  }) : _stream =
           stream ??
           ((settings) =>
               Geolocator.getPositionStream(locationSettings: settings)),
       _request =
           request ??
           ((settings) =>
               Geolocator.getCurrentPosition(locationSettings: settings)),
       _clock = clock ?? DateTime.now;

  /// A feed configured for [profile] on the current platform.
  factory ReliableLocationFeed.profile(
    LocationFeedProfile profile, {
    required bool Function(Position) onPosition,
    required void Function(Object?) onIssue,
    PositionStreamFactory? stream,
    PositionRequest? request,
    DateTime Function()? clock,
  }) => ReliableLocationFeed(
    settings: settingsFor(profile),
    staleAfter: staleAfterFor(profile),
    onPosition: onPosition,
    onIssue: onIssue,
    stream: stream,
    request: request,
    clock: clock,
  ).._profile = profile;

  /// Platform settings for [profile]. Browsing never asks for
  /// `bestForNavigation` with no distance filter, and never runs in the
  /// background.
  static LocationSettings settingsFor(
    LocationFeedProfile profile, {
    TargetPlatform? platform,
  }) {
    final target = platform ?? defaultTargetPlatform;
    final (accuracy, distance, interval) = switch (profile) {
      LocationFeedProfile.navigation => (
        LocationAccuracy.bestForNavigation,
        0,
        const Duration(seconds: 1),
      ),
      LocationFeedProfile.browse => (
        LocationAccuracy.high,
        5,
        const Duration(seconds: 2),
      ),
      LocationFeedProfile.lowPower => (
        LocationAccuracy.medium,
        50,
        const Duration(seconds: 15),
      ),
    };
    return switch (target) {
      TargetPlatform.iOS => AppleSettings(
        accuracy: accuracy,
        distanceFilter: distance,
        activityType: profile == LocationFeedProfile.navigation
            ? ActivityType.automotiveNavigation
            : ActivityType.other,
        pauseLocationUpdatesAutomatically:
            profile != LocationFeedProfile.navigation,
        allowBackgroundLocationUpdates:
            profile == LocationFeedProfile.navigation,
        showBackgroundLocationIndicator:
            profile == LocationFeedProfile.navigation,
      ),
      TargetPlatform.android => AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distance,
        intervalDuration: interval,
      ),
      _ => LocationSettings(accuracy: accuracy, distanceFilter: distance),
    };
  }

  /// With a distance filter a parked phone legitimately goes quiet.
  static Duration staleAfterFor(LocationFeedProfile profile) =>
      switch (profile) {
        LocationFeedProfile.navigation => const Duration(seconds: 10),
        LocationFeedProfile.browse => const Duration(seconds: 30),
        LocationFeedProfile.lowPower => const Duration(minutes: 2),
      };

  /// Current platform settings; see [updateProfile].
  LocationSettings settings;
  LocationFeedProfile? _profile;

  /// The profile this feed was created with or switched to, if any.
  LocationFeedProfile? get profile => _profile;

  /// No accepted fix for this long counts as stale and starts recovery.
  Duration staleAfter;
  final bool Function(Position) onPosition;
  final void Function(Object?) onIssue;
  final PositionStreamFactory _stream;
  final PositionRequest _request;
  final DateTime Function() _clock;
  StreamSubscription<Position>? _subscription;
  Timer? _watchdog;
  DateTime? _acceptedAt, _lastStreamAt, _lastAttempt;
  Object? _lastIssue;
  bool _running = false, _recovering = false, _paused = false;
  int _generation = 0;
  int _failedRecoveries = 0;

  bool get running => _running;
  bool get paused => _paused;

  /// Delay before the next unforced recovery attempt.
  Duration get recoveryInterval {
    if (_failedRecoveries < 3) return const Duration(seconds: 6);
    final seconds = 6 * math.pow(2, _failedRecoveries - 2);
    return Duration(seconds: math.min(60, seconds).round());
  }

  void start({Position? initialPosition}) {
    if (_running) return;
    _running = true;
    _paused = false;
    _acceptedAt = null;
    _lastAttempt = null;
    _lastIssue = null;
    _recovering = false;
    _failedRecoveries = 0;
    final generation = ++_generation;
    if (initialPosition != null) _deliver(initialPosition, generation);
    _activate(generation);
  }

  void _activate(int generation) {
    _subscribe(generation);
    // An independent request supplies the second stationary observation when
    // Core Location has no reason to emit another stream event.
    unawaited(recover(force: true));
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      final accepted = _acceptedAt;
      if (accepted == null || _clock().difference(accepted) > staleAfter) {
        _reportIssue(TimeoutException('Waiting for a fresh GPS fix'));
        unawaited(recover());
      }
    });
  }

  /// Releases the platform stream and watchdog, keeping the feed owned.
  Future<void> pause() async {
    if (!_running || _paused) return;
    _paused = true;
    ++_generation;
    _recovering = false;
    await _release();
  }

  /// Re-subscribes after [pause] and asks for a fresh fix at once.
  void resume() {
    if (!_running || !_paused) return;
    _paused = false;
    _failedRecoveries = 0;
    _lastAttempt = null;
    _activate(++_generation);
  }

  /// Switches settings, restarting the platform stream when running.
  Future<void> updateProfile(LocationFeedProfile profile) async {
    if (profile == _profile) return;
    _profile = profile;
    settings = settingsFor(profile);
    staleAfter = staleAfterFor(profile);
    if (!_running || _paused) return;
    final generation = ++_generation;
    _recovering = false;
    await _release();
    if (_running && !_paused && generation == _generation) {
      _activate(generation);
    }
  }

  void _deliver(Position position, int generation) {
    if (!_running || generation != _generation) return;
    if (onPosition(position)) {
      _acceptedAt = position.timestamp;
      _failedRecoveries = 0;
      _reportIssue(null);
    }
  }

  void _subscribe(int generation) {
    if (!_running || generation != _generation) return;
    _lastStreamAt = _clock();
    try {
      _subscription = _stream(settings).listen(
        (position) {
          if (!_running || generation != _generation) return;
          _lastStreamAt = _clock();
          _deliver(position, generation);
        },
        onError: (Object error) {
          if (!_running || generation != _generation) return;
          _reportIssue(error);
          _lastStreamAt = null;
          unawaited(recover());
        },
        onDone: () {
          if (!_running || generation != _generation) return;
          _lastStreamAt = null;
          unawaited(recover());
        },
      );
    } catch (error) {
      _reportIssue(error);
      _lastStreamAt = null;
    }
  }

  Future<void> recover({bool force = false}) async {
    if (!_running || _paused || _recovering) return;
    final now = _clock();
    if (!force &&
        _lastAttempt != null &&
        now.difference(_lastAttempt!) < recoveryInterval) {
      return;
    }
    _lastAttempt = now;
    _recovering = true;
    final generation = _generation;
    final acceptedBefore = _acceptedAt;
    try {
      if (_lastStreamAt == null ||
          now.difference(_lastStreamAt!) > const Duration(seconds: 10)) {
        final previous = _subscription;
        _subscription = null;
        await previous?.cancel();
        await Future<void>.delayed(Duration.zero);
        _subscribe(generation);
      }
      final position = await _request(
        LocationSettings(
          accuracy: settings.accuracy,
          distanceFilter: 0,
          timeLimit: const Duration(seconds: 5),
        ),
      ).timeout(const Duration(seconds: 5));
      _deliver(position, generation);
    } catch (error) {
      if (_running &&
          generation == _generation &&
          (_acceptedAt == null ||
              _clock().difference(_acceptedAt!) > staleAfter)) {
        _reportIssue(error);
      }
    } finally {
      if (generation == _generation) {
        _recovering = false;
        if (identical(_acceptedAt, acceptedBefore)) _failedRecoveries++;
      }
    }
  }

  void _reportIssue(Object? issue) {
    // A timeout does not explain a disabled permission or service. Keep the
    // actionable cause until an actual OS observation confirms recovery.
    if (issue is TimeoutException &&
        (_lastIssue is PermissionDeniedException ||
            _lastIssue is LocationServiceDisabledException)) {
      return;
    }
    if (_lastIssue?.toString() == issue?.toString()) return;
    _lastIssue = issue;
    onIssue(issue);
  }

  Future<void> _release() async {
    _watchdog?.cancel();
    _watchdog = null;
    final previous = _subscription;
    _subscription = null;
    await previous?.cancel();
    // Geolocator caches settings until its broadcast onCancel has completed.
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> stop() async {
    _running = false;
    _paused = false;
    ++_generation;
    await _release();
  }
}
