import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lock Screen / Dynamic Island on iOS; a location foreground service on Android.
/// Serialize native updates so ending a trip cannot race with an old GPS update.
class SystemNavigation extends ChangeNotifier {
  SystemNavigation({MethodChannel? channel, DateTime Function()? clock})
    : _channel = channel ?? const MethodChannel('waybi/system_navigation'),
      _clock = clock ?? DateTime.now;
  final MethodChannel _channel;
  final DateTime Function() _clock;
  Future<void> _queue = Future<void>.value();
  int _session = 0;
  bool _active = false;
  DateTime? _lastUpdate;
  String? _lastInstruction;
  bool? _lastOffRoute;
  bool? _lastGpsReliable;
  bool? supported;
  bool enabled = true;
  bool surfaceActive = false;
  String? failureReason;
  Map<String, Object?>? _latestState;
  bool _disposed = false;

  Future<void> start(Map<String, Object?> state) {
    final session = ++_session;
    _active = true;
    _lastUpdate = null;
    _lastInstruction = null;
    _lastOffRoute = null;
    _lastGpsReliable = null;
    _latestState = Map.of(state);
    return _enqueue('start', state, session);
  }

  Future<void> update(Map<String, Object?> state, {bool force = false}) {
    if (!_active) return Future<void>.value();
    final now = _clock();
    final instruction = state['instruction'] as String?;
    final offRoute = state['offRoute'] == true;
    final gpsReliable = state['gpsReliable'] != false;
    _latestState = Map.of(state);
    if (!force &&
        instruction == _lastInstruction &&
        offRoute == _lastOffRoute &&
        gpsReliable == _lastGpsReliable &&
        _lastUpdate != null &&
        now.difference(_lastUpdate!) < const Duration(seconds: 3)) {
      return Future<void>.value();
    }
    _lastUpdate = now;
    _lastInstruction = instruction;
    _lastOffRoute = offRoute;
    _lastGpsReliable = gpsReliable;
    return _enqueue('update', state, _session);
  }

  Future<void> stop() {
    _active = false;
    _latestState = null;
    return _enqueue('stop', const {}, ++_session);
  }

  Future<void> retry() => !_active || _latestState == null
      ? Future<void>.value()
      : start(_latestState!);

  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<Object?>('openSettings');
    } on PlatformException {
      /* Settings may not be available in a preview. */
    } on MissingPluginException {
      /* Unsupported platform. */
    }
  }

  void _status(Object? value) {
    if (value is Map) {
      supported = value['supported'] == true;
      enabled = value['enabled'] == true;
      surfaceActive = value['active'] == true;
      failureReason = value['errorCode'] as String?;
    } else if (value is bool) {
      supported = true;
      surfaceActive = value && _active;
      failureReason = value ? null : 'unavailable';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _enqueue(
    String method,
    Map<String, Object?> state,
    int session,
  ) {
    final task = _queue.then((_) async {
      if (session != _session) return;
      try {
        final value = await _channel.invokeMethod<Object?>(method, state);
        if (session == _session) _status(value);
      } on MissingPluginException {
        // Web previews and platforms without the native navigation surface.
        supported = false;
      } on PlatformException catch (error) {
        failureReason = error.code;
        surfaceActive = false;
        if (!_disposed) notifyListeners();
        debugPrint('System navigation: ${error.code}');
      }
    });
    _queue = task.catchError((Object _) {});
    return _queue;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
