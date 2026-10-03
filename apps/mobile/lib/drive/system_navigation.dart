import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lock Screen / Dynamic Island on iOS; a location foreground service on Android.
/// Serialize native updates so ending a trip cannot race with an old GPS update.
class SystemNavigation {
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

  Future<void> start(Map<String, Object?> state) {
    final session = ++_session;
    _active = true;
    _lastUpdate = null;
    _lastInstruction = null;
    _lastOffRoute = null;
    return _enqueue('start', state, session);
  }

  Future<void> update(Map<String, Object?> state, {bool force = false}) {
    if (!_active) return Future<void>.value();
    final now = _clock();
    final instruction = state['instruction'] as String?;
    final offRoute = state['offRoute'] == true;
    if (!force &&
        instruction == _lastInstruction &&
        offRoute == _lastOffRoute &&
        _lastUpdate != null &&
        now.difference(_lastUpdate!) < const Duration(seconds: 3)) {
      return Future<void>.value();
    }
    _lastUpdate = now;
    _lastInstruction = instruction;
    _lastOffRoute = offRoute;
    return _enqueue('update', state, _session);
  }

  Future<void> stop() {
    _active = false;
    return _enqueue('stop', const {}, ++_session);
  }

  Future<void> _enqueue(
    String method,
    Map<String, Object?> state,
    int session,
  ) {
    final task = _queue.then((_) async {
      if (session != _session) return;
      try {
        await _channel.invokeMethod<bool>(method, state);
      } on MissingPluginException {
        // Web previews and platforms without the native navigation surface.
      } on PlatformException catch (error) {
        debugPrint('System navigation: ${error.code}');
      }
    });
    _queue = task.catchError((Object _) {});
    return _queue;
  }
}
