import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A large JSON cache stored as a file in the app support directory.
///
/// SharedPreferences rewrites its whole XML/plist on every write and keeps
/// everything in memory, so 60–250 KB catalogues there slow every settings
/// write. A value left in preferences by an older version is migrated once.
/// Where no app directory exists (tests, unsupported platforms) the cache
/// falls back to preferences.
class JsonFileCache {
  JsonFileCache(
    this.fileName, {
    this.legacyPrefsKey,
    Future<Directory?> Function()? directory,
  }) : _directory = directory ?? _supportDirectory;

  final String fileName;
  final String? legacyPrefsKey;
  final Future<Directory?> Function() _directory;
  String? _lastWritten;

  static Future<Directory?> _supportDirectory() async {
    if (kIsWeb) return null;
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return null;
    }
  }

  String get _prefsKey => legacyPrefsKey ?? 'waybi.file_cache.$fileName';

  Future<File?> _file() async {
    final directory = await _directory();
    return directory == null ? null : File('${directory.path}/$fileName');
  }

  Future<String?> read() async {
    final file = await _file();
    if (file == null) return _readPrefs();
    try {
      if (await file.exists()) return _lastWritten = await file.readAsString();
    } catch (_) {
      return null;
    }
    // One-time migration from SharedPreferences.
    String? legacy;
    try {
      legacy = legacyPrefsKey == null
          ? null
          : (await SharedPreferences.getInstance()).getString(legacyPrefsKey!);
    } catch (_) {
      legacy = null;
    }
    if (legacy != null) {
      await write(legacy);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(legacyPrefsKey!);
      } catch (_) {}
    }
    return legacy;
  }

  /// Writes [raw] unless it is what this cache last read or wrote.
  Future<bool> write(String raw) async {
    if (raw == _lastWritten) return false;
    final file = await _file();
    try {
      if (file == null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, raw);
      } else {
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(raw, flush: true);
        await temporary.rename(file.path);
      }
      _lastWritten = raw;
      return true;
    } catch (_) {
      // Caching is best effort.
      return false;
    }
  }

  Future<String?> _readPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _lastWritten = prefs.getString(_prefsKey);
    } catch (_) {
      return null;
    }
  }
}

/// Whether large JSON is decoded on a background isolate. Off under
/// `flutter test`, whose fake clock never delivers isolate results.
bool decodeLargeJsonInIsolate =
    !kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST');

/// Decodes large JSON off the UI isolate (a 242 KB lane snapshot takes tens
/// of milliseconds to parse on a phone).
Future<Object?> decodeJsonOffMain(String raw, {int threshold = 32 * 1024}) {
  if (!decodeLargeJsonInIsolate || raw.length < threshold) {
    return Future.value(jsonDecode(raw));
  }
  return Isolate.run(() => jsonDecode(raw));
}
