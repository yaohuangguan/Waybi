import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeMapLanguage {
  static const _channel = MethodChannel('waybi/map_language');

  /// iOS exposes map language through the system's per-app language setting.
  /// Android can update its application resource locale before recreating views.
  static Future<bool> apply(String language) async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>('setLanguage', language) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> openSettings() =>
      _channel.invokeMethod<void>('openSettings');
}
