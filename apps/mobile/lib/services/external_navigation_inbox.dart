import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Owns the cold-start handoff independently of the splash/onboarding routes.
/// The latest request wins while the map is still becoming ready.
class ExternalNavigationInbox extends ChangeNotifier {
  ExternalNavigationInbox([
    this._channel = const MethodChannel('waybi/external_navigation'),
  ]);

  static final instance = ExternalNavigationInbox();
  final MethodChannel _channel;
  String? _pending;
  bool _draining = false;
  bool _drainAgain = false;
  bool _disposed = false;

  bool get hasPending => _pending != null;

  String? takePending() {
    final result = _pending;
    _pending = null;
    return result;
  }

  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pending') await _drain();
    });
    await _drain();
  }

  Future<void> _drain() async {
    if (_disposed) return;
    if (_draining) {
      _drainAgain = true;
      return;
    }
    _draining = true;
    try {
      do {
        _drainAgain = false;
        final value = await _channel.invokeMethod<String>('takePending');
        if (!_disposed && value != null) {
          _pending = value;
          notifyListeners();
        }
      } while (!_disposed && _drainAgain);
    } on MissingPluginException {
      // The native receiver is currently iOS-only.
    } on PlatformException {
      // A failed handoff must not prevent normal app startup.
    } finally {
      _draining = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
