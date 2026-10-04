import 'dart:async';

import 'package:geolocator/geolocator.dart';

typedef PositionStreamFactory = Stream<Position> Function(LocationSettings);
typedef PositionRequest = Future<Position> Function(LocationSettings);

/// One owner of the platform stream, with bounded recovery when it goes quiet.
/// Only real OS observations are delivered; timeouts never synthesize movement.
class ReliableLocationFeed {
  ReliableLocationFeed({
    required this.settings,
    required this.onPosition,
    required this.onIssue,
    PositionStreamFactory? stream,
    PositionRequest? request,
    DateTime Function()? clock,
  }) : _stream =
           stream ??
           ((settings) =>
               Geolocator.getPositionStream(locationSettings: settings)),
       _request =
           request ??
           ((settings) =>
               Geolocator.getCurrentPosition(locationSettings: settings)),
       _clock = clock ?? DateTime.now;

  final LocationSettings settings;
  final bool Function(Position) onPosition;
  final void Function(Object?) onIssue;
  final PositionStreamFactory _stream;
  final PositionRequest _request;
  final DateTime Function() _clock;
  StreamSubscription<Position>? _subscription;
  Timer? _watchdog;
  DateTime? _acceptedAt, _lastStreamAt, _lastAttempt;
  Object? _lastIssue;
  bool _running = false, _recovering = false;
  int _generation = 0;

  bool get running => _running;

  void start({Position? initialPosition}) {
    if (_running) return;
    _running = true;
    _acceptedAt = null;
    _lastAttempt = null;
    _lastIssue = null;
    _recovering = false;
    final generation = ++_generation;
    if (initialPosition != null) _deliver(initialPosition, generation);
    _subscribe(generation);
    // An independent request supplies the second stationary observation when
    // Core Location has no reason to emit another stream event.
    unawaited(recover(force: true));
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      final accepted = _acceptedAt;
      if (accepted == null ||
          _clock().difference(accepted) > const Duration(seconds: 10)) {
        _reportIssue(TimeoutException('Waiting for a fresh GPS fix'));
        unawaited(recover());
      }
    });
  }

  void _deliver(Position position, int generation) {
    if (!_running || generation != _generation) return;
    if (onPosition(position)) {
      _acceptedAt = position.timestamp;
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
    if (!_running || _recovering) return;
    final now = _clock();
    if (!force &&
        _lastAttempt != null &&
        now.difference(_lastAttempt!) < const Duration(seconds: 6)) {
      return;
    }
    _lastAttempt = now;
    _recovering = true;
    final generation = _generation;
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
              _clock().difference(_acceptedAt!) >
                  const Duration(seconds: 10))) {
        _reportIssue(error);
      }
    } finally {
      if (generation == _generation) _recovering = false;
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

  Future<void> stop() async {
    _running = false;
    ++_generation;
    _watchdog?.cancel();
    _watchdog = null;
    final previous = _subscription;
    _subscription = null;
    await previous?.cancel();
    // Geolocator caches settings until its broadcast onCancel has completed.
    await Future<void>.delayed(Duration.zero);
  }
}
